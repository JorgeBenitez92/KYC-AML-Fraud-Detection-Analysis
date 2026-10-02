-- =====================================================================
-- 04_generar_transacciones_normales.sql (MySQL)
-- Genera la actividad transaccional "normal" (linea base) de todas las
-- cuentas durante los ultimos 12 meses. El monto se escala respecto al
-- ingreso declarado del cliente, para que despues los signals de
-- "monto inusual vs historico" tengan sentido real (comparan contra
-- ESTA linea base).
--
-- Nota tecnica: cualquier valor RAND() que se vaya a leer MAS DE UNA VEZ
-- mas adelante (aqui, r_intl decide tanto pais_destino_id como
-- es_internacional) se materializa primero en una TABLA temporal real
-- (no una subconsulta derivada). MySQL puede "aplanar" (merge) una
-- subconsulta derivada simple y re-evaluar el mismo RAND() por separado
-- en cada referencia, dando resultados inconsistentes entre columnas.
-- Una tabla real siempre queda materializada, así que el valor guardado
-- es el mismo sin importar cuantas veces se lea.
-- =====================================================================
USE kyc_aml_portafolio;

-- Helper: secuencia 1..35 (hasta 35 "intentos" de transaccion por cuenta,
-- filtrados despues con RAND()<0.65 para dejar ~15-28 transacciones reales)
DROP TABLE IF EXISTS tmp_35;
CREATE TABLE tmp_35 (n INT PRIMARY KEY);
INSERT INTO tmp_35
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 35
)
SELECT n FROM seq;

-- Cuentas + datos del cliente dueño, con r_intl YA fijo por fila (tabla real)
DROP TABLE IF EXISTS tmp_cuentas_calc;
CREATE TABLE tmp_cuentas_calc (
    fila_id           INT AUTO_INCREMENT PRIMARY KEY,
    cuenta_id         INT,
    ingreso_mensual   DECIMAL(14,2),
    fecha_alta        DATETIME,
    dias_disponibles  INT,
    r_intl            DOUBLE
);
INSERT INTO tmp_cuentas_calc (cuenta_id, ingreso_mensual, fecha_alta, dias_disponibles, r_intl)
SELECT cc.cuenta_id, cc.ingreso_mensual, cc.fecha_alta, cc.dias_disponibles, RAND()
FROM (
    SELECT cu.cuenta_id, cl.ingreso_mensual_declarado_mxn AS ingreso_mensual, cl.fecha_alta,
           LEAST(365, GREATEST(1, DATEDIFF(NOW(), cl.fecha_alta))) AS dias_disponibles
    FROM cuentas cu
    JOIN clientes cl ON cl.cliente_id = cu.cliente_id
) cc
JOIN tmp_35 s ON s.n <= 35
WHERE RAND() < 0.65;

SET @mex_pais_id = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'MEX');
SET @usa_pais_id = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'USA');
SET @can_pais_id = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'CAN');
SET @esp_pais_id = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'ESP');
SET @col_pais_id = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'COL');

INSERT INTO transacciones (
    cuenta_id, fecha_hora, monto_mxn, tipo_transaccion, canal,
    pais_origen_id, pais_destino_id, es_internacional, ip_origen
)
SELECT
    c.cuenta_id,
    GREATEST(c.fecha_alta, DATE_SUB(NOW(), INTERVAL 365 DAY))
        + INTERVAL FLOOR(RAND() * c.dias_disponibles) DAY
        + INTERVAL FLOOR(RAND() * 1440) MINUTE,
    GREATEST(150, ROUND(c.ingreso_mensual * (0.01 + RAND() * 0.35), 2)),
    ELT(1 + FLOOR(RAND() * 5), 'Deposito Efectivo', 'Retiro Efectivo', 'Transferencia SPEI', 'Pago Tarjeta', 'Deposito Cheque'),
    ELT(1 + FLOOR(RAND() * 4), 'App', 'Sucursal', 'Cajero', 'Web'),
    @mex_pais_id,
    CASE WHEN c.r_intl < 0.08
         THEN ELT(1 + FLOOR(RAND() * 4), @usa_pais_id, @can_pais_id, @esp_pais_id, @col_pais_id)
         ELSE @mex_pais_id
    END,
    (c.r_intl < 0.08),
    CONCAT(FLOOR(RAND()*180)+10, '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255))
FROM tmp_cuentas_calc c;

DROP TABLE IF EXISTS tmp_35;
DROP TABLE IF EXISTS tmp_cuentas_calc;
