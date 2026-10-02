-- =====================================================================
-- 07_generar_casos_revision.sql (MySQL)
--
-- Este script simula UN AÑO de historial de trabajo del equipo
-- KYC/PLD: convierte cada alerta detectada en un "caso" con analista
-- asignado, horas invertidas, prioridad y resultado de la
-- investigacion. Es la fuente para tus KPIs de Power BI de carga de
-- trabajo (en que gasta el tiempo el analista, cuantas horas por tipo
-- de alerta, embudo de resultados, etc.).
--
-- IMPORTANTE -- este script usa 7 vistas de deteccion "de andamiaje"
-- (scaffolding) SOLO para poder generar esta tabla historica de forma
-- realista. NO son las queries finales de tu proyecto: esas las vas a
-- escribir TU, desde cero, paso a paso, mas adelante -- ese es el
-- contenido que de verdad se evalua en una entrevista. Por eso, al
-- final de este script, las 7 vistas + la vista consolidada se
-- BORRAN (DROP VIEW), para que tu base de datos quede limpia y cuando
-- construyas tus propias vistas de deteccion no encuentres nombres ya
-- ocupados ni "la respuesta" ya escrita.
-- =====================================================================
USE kyc_aml_portafolio;

-- ---------------------------------------------------------------------
-- Vistas de andamiaje (temporales) -- una por cada signal de riesgo
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_andamio_estructuracion AS
WITH candidatas AS (
    SELECT transaccion_id, cuenta_id, fecha_hora, monto_mxn
    FROM transacciones
    WHERE tipo_transaccion = 'Deposito Efectivo' AND monto_mxn BETWEEN 100000 AND 149999
),
ventanas AS (
    SELECT c1.cuenta_id, c1.transaccion_id, c1.fecha_hora,
           COUNT(*) AS depositos_en_ventana,
           SUM(c2.monto_mxn) AS monto_total_ventana
    FROM candidatas c1
    JOIN candidatas c2
      ON c2.cuenta_id = c1.cuenta_id
     AND c2.fecha_hora BETWEEN c1.fecha_hora - INTERVAL 10 DAY AND c1.fecha_hora + INTERVAL 10 DAY
    GROUP BY c1.cuenta_id, c1.transaccion_id, c1.fecha_hora
)
SELECT
    cl.cliente_id, cl.nombre_completo, cl.ciudad, v.cuenta_id,
    MAX(v.depositos_en_ventana) AS max_depositos_ventana_10d,
    MAX(v.monto_total_ventana) AS monto_max_acumulado,
    MIN(v.fecha_hora) AS primera_deteccion
FROM ventanas v
JOIN cuentas cu ON cu.cuenta_id = v.cuenta_id
JOIN clientes cl ON cl.cliente_id = cu.cliente_id
WHERE v.depositos_en_ventana >= 5
GROUP BY cl.cliente_id, cl.nombre_completo, cl.ciudad, v.cuenta_id;

CREATE OR REPLACE VIEW vw_andamio_pais_sancionado AS
SELECT
    cl.cliente_id, cl.nombre_completo, cl.ciudad, t.cuenta_id, t.transaccion_id,
    t.fecha_hora, t.monto_mxn, po.nombre_pais AS pais_origen, pd.nombre_pais AS pais_destino
FROM transacciones t
JOIN paises po ON po.pais_id = t.pais_origen_id
JOIN paises pd ON pd.pais_id = t.pais_destino_id
JOIN cuentas cu ON cu.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = cu.cliente_id
WHERE po.es_sancionado_ofac = 1 OR pd.es_sancionado_ofac = 1;

CREATE OR REPLACE VIEW vw_andamio_monto_inusual AS
WITH stats AS (
    SELECT cuenta_id, AVG(monto_mxn) AS promedio, STDDEV_POP(monto_mxn) AS desviacion, COUNT(*) AS n_transacciones
    FROM transacciones
    GROUP BY cuenta_id
    HAVING COUNT(*) >= 5
)
SELECT
    cl.cliente_id, cl.nombre_completo, t.cuenta_id, t.transaccion_id, t.fecha_hora, t.monto_mxn,
    ROUND(s.promedio, 2) AS promedio_historico_cuenta,
    ROUND((t.monto_mxn - s.promedio) / NULLIF(s.desviacion, 0), 2) AS z_score
FROM transacciones t
JOIN stats s ON s.cuenta_id = t.cuenta_id
JOIN cuentas cu ON cu.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = cu.cliente_id
WHERE s.desviacion > 0 AND (t.monto_mxn - s.promedio) / s.desviacion > 4.5;

CREATE OR REPLACE VIEW vw_andamio_velocidad AS
WITH ventanas AS (
    SELECT t1.cuenta_id, t1.transaccion_id, t1.fecha_hora,
           COUNT(*) AS transacciones_en_ventana
    FROM transacciones t1
    JOIN transacciones t2
      ON t2.cuenta_id = t1.cuenta_id
     AND t2.fecha_hora BETWEEN t1.fecha_hora - INTERVAL 15 MINUTE AND t1.fecha_hora + INTERVAL 15 MINUTE
    GROUP BY t1.cuenta_id, t1.transaccion_id, t1.fecha_hora
)
SELECT
    cl.cliente_id, cl.nombre_completo, v.cuenta_id,
    MAX(v.transacciones_en_ventana) AS max_transacciones_ventana_15min,
    MIN(v.fecha_hora) AS primera_deteccion
FROM ventanas v
JOIN cuentas cu ON cu.cuenta_id = v.cuenta_id
JOIN clientes cl ON cl.cliente_id = cu.cliente_id
WHERE v.transacciones_en_ventana >= 5
GROUP BY cl.cliente_id, cl.nombre_completo, v.cuenta_id;

CREATE OR REPLACE VIEW vw_andamio_ubo_lista_negra AS
SELECT
    cl.cliente_id, cl.nombre_completo AS razon_social, s.socio_id, s.nombre_socio,
    s.porcentaje_participacion, s.es_beneficiario_final_ubo, p.nombre_pais AS nacionalidad_socio
FROM personas_morales_socios s
JOIN clientes cl ON cl.cliente_id = s.cliente_id
JOIN paises p ON p.pais_id = s.pais_nacionalidad_id
WHERE s.en_lista_negra = 1;

CREATE OR REPLACE VIEW vw_andamio_prestanombres AS
WITH dispositivos_compartidos AS (
    SELECT dispositivo_id, COUNT(DISTINCT cliente_id) AS clientes_compartiendo
    FROM contacto_dispositivo_cliente
    GROUP BY dispositivo_id
    HAVING COUNT(DISTINCT cliente_id) > 1
),
flujo_cliente AS (
    SELECT cu.cliente_id, SUM(t.monto_mxn) AS flujo_total_12m
    FROM transacciones t JOIN cuentas cu ON cu.cuenta_id = t.cuenta_id
    WHERE t.fecha_hora > DATE_SUB(NOW(), INTERVAL 365 DAY)
    GROUP BY cu.cliente_id
)
SELECT
    cl.cliente_id, cl.nombre_completo, cl.ingreso_mensual_declarado_mxn,
    cdc.dispositivo_id, dc.clientes_compartiendo,
    ROUND(f.flujo_total_12m, 2) AS flujo_transaccional_12m,
    ROUND(f.flujo_total_12m / NULLIF(cl.ingreso_mensual_declarado_mxn * 12, 0), 2) AS veces_ingreso_anual_declarado
FROM contacto_dispositivo_cliente cdc
JOIN dispositivos_compartidos dc ON dc.dispositivo_id = cdc.dispositivo_id
JOIN clientes cl ON cl.cliente_id = cdc.cliente_id
LEFT JOIN flujo_cliente f ON f.cliente_id = cl.cliente_id;

CREATE OR REPLACE VIEW vw_andamio_credential_stuffing AS
WITH fallidos AS (
    SELECT * FROM intentos_acceso WHERE exitoso = 0
),
ventanas AS (
    SELECT f1.cliente_id, f1.intento_id, f1.fecha_hora,
           COUNT(*) AS intentos_en_ventana,
           COUNT(DISTINCT f2.ip_origen) AS ips_distintas
    FROM fallidos f1
    JOIN fallidos f2
      ON f2.cliente_id = f1.cliente_id
     AND f2.fecha_hora BETWEEN f1.fecha_hora - INTERVAL 20 MINUTE AND f1.fecha_hora + INTERVAL 20 MINUTE
    GROUP BY f1.cliente_id, f1.intento_id, f1.fecha_hora
),
resumen AS (
    SELECT cl.cliente_id, cl.nombre_completo,
           MAX(v.intentos_en_ventana) AS max_intentos_fallidos_ventana_20min,
           MAX(v.ips_distintas) AS max_ips_distintas,
           MIN(v.fecha_hora) AS primera_deteccion
    FROM ventanas v
    JOIN clientes cl ON cl.cliente_id = v.cliente_id
    WHERE v.intentos_en_ventana >= 8 AND v.ips_distintas >= 3
    GROUP BY cl.cliente_id, cl.nombre_completo
)
SELECT
    r.*,
    EXISTS (
        SELECT 1 FROM intentos_acceso ia
        WHERE ia.cliente_id = r.cliente_id AND ia.exitoso = 1
          AND ia.fecha_hora BETWEEN r.primera_deteccion AND r.primera_deteccion + INTERVAL 1 DAY
    ) AS hubo_acceso_exitoso_posterior
FROM resumen r;

CREATE OR REPLACE VIEW vw_andamio_alertas_consolidadas AS
SELECT 'Cliente' AS tipo_entidad, cliente_id AS entidad_id, cliente_id,
       'Estructuracion' AS tipo_alerta,
       CONCAT('Cuenta ', cuenta_id, ': ', max_depositos_ventana_10d, ' depositos en efectivo en ventana de 10 dias, $', monto_max_acumulado, ' MXN acumulados') AS detalle,
       primera_deteccion AS fecha_deteccion, 'Alta' AS severidad_sugerida
FROM vw_andamio_estructuracion
UNION ALL
SELECT 'Cliente', cliente_id, cliente_id, 'Pais Sancionado OFAC',
       CONCAT('Transaccion ', transaccion_id, ' de $', monto_mxn, ' MXN con ', pais_destino),
       fecha_hora, 'Critica'
FROM vw_andamio_pais_sancionado
UNION ALL
SELECT 'Cliente', cliente_id, cliente_id, 'Monto Inusual',
       CONCAT('Transaccion ', transaccion_id, ' de $', monto_mxn, ' MXN (z-score ', z_score, ' vs promedio $', promedio_historico_cuenta, ')'),
       fecha_hora, 'Media'
FROM vw_andamio_monto_inusual
UNION ALL
SELECT 'Cliente', cliente_id, cliente_id, 'Velocidad Alta',
       CONCAT('Cuenta ', cuenta_id, ': ', max_transacciones_ventana_15min, ' transacciones en 15 minutos'),
       primera_deteccion, 'Media'
FROM vw_andamio_velocidad
UNION ALL
SELECT 'Socio', socio_id, cliente_id, 'UBO en Lista Negra',
       CONCAT('Socio "', nombre_socio, '" (', porcentaje_participacion, '%) nacionalidad ', nacionalidad_socio),
       NOW(), 'Critica'
FROM vw_andamio_ubo_lista_negra
UNION ALL
SELECT 'Cliente', cliente_id, cliente_id, 'Posible Prestanombres',
       CONCAT('Dispositivo ', dispositivo_id, ' compartido con ', (clientes_compartiendo - 1), ' cliente(s) mas; flujo = ', COALESCE(CAST(veces_ingreso_anual_declarado AS CHAR), 'N/D'), 'x el ingreso anual declarado'),
       NOW(), 'Alta'
FROM vw_andamio_prestanombres
UNION ALL
SELECT 'Cliente', cliente_id, cliente_id, 'Credential Stuffing / Fuerza Bruta',
       CONCAT(max_intentos_fallidos_ventana_20min, ' intentos fallidos desde ', max_ips_distintas, ' IPs en 20 min',
              CASE WHEN hubo_acceso_exitoso_posterior THEN ' -- HUBO acceso exitoso despues (posible cuenta comprometida)' ELSE '' END),
       primera_deteccion, CASE WHEN hubo_acceso_exitoso_posterior THEN 'Critica' ELSE 'Alta' END
FROM vw_andamio_credential_stuffing;

-- ---------------------------------------------------------------------
-- Generacion de casos_revision_kyc a partir de las alertas de andamiaje
--
-- Nota tecnica: r_resultado y r_horas se leen VARIAS veces mas abajo
-- (r_resultado en un CASE de 8 ramas, r_horas tanto para horas
-- invertidas como para la fecha de cierre), asi que se materializan
-- primero como columnas de una tabla temporal REAL: MySQL puede
-- "aplanar" una subconsulta simple y recalcular el mismo RAND() en
-- cada referencia si no se materializa en una tabla real.
--
-- Nota de negocio: es_verdadero (si la alerta coincide con un riesgo
-- sembrado a proposito en ground_truth_casos_riesgo) es SOLO la llave
-- de validacion para medir recall/precision de las queries de
-- deteccion -- un analista real nunca sabe de antemano cual alerta es
-- "de prueba". Por eso el resultado de la investigacion no depende
-- fuerte de es_verdadero: incluso un patron sembrado obvio se cierra
-- casi siempre como Falso Positivo tras revisarlo (tasas de falso
-- positivo de 70-90% son estandar en la industria de PLD), con solo
-- una probabilidad modestamente mayor de escalar/confirmar frente al
-- ruido puro.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_casos_calc;
CREATE TABLE tmp_casos_calc (
    fila_id             INT AUTO_INCREMENT PRIMARY KEY,
    tipo_entidad        VARCHAR(15),
    entidad_id          INT,
    cliente_id          INT,
    tipo_alerta         VARCHAR(40),
    detalle             VARCHAR(300),
    fecha_deteccion     DATETIME,
    severidad_sugerida  VARCHAR(10),
    es_verdadero        TINYINT(1),
    analista            VARCHAR(60),
    fecha_asignacion    DATETIME,
    r_resultado         DOUBLE,
    r_horas             DOUBLE
);

INSERT INTO tmp_casos_calc (
    tipo_entidad, entidad_id, cliente_id, tipo_alerta, detalle, fecha_deteccion, severidad_sugerida,
    es_verdadero, analista, fecha_asignacion, r_resultado, r_horas
)
SELECT
    ac.tipo_entidad, ac.entidad_id, ac.cliente_id, ac.tipo_alerta, ac.detalle, ac.fecha_deteccion, ac.severidad_sugerida,
    EXISTS (
        SELECT 1 FROM ground_truth_casos_riesgo gt
        WHERE gt.tipo_entidad = ac.tipo_entidad AND gt.entidad_id = ac.entidad_id AND gt.tipo_riesgo = ac.tipo_alerta
    ),
    ELT(1 + FLOOR(RAND()*6), 'Ana Beltran', 'Diego Cazares', 'Fernanda Ibarra', 'Roberto Quintana', 'Karina Solis', 'Luis Pantoja'),
    ac.fecha_deteccion + INTERVAL FLOOR(2 + RAND()*46) HOUR,
    RAND(),
    RAND()
FROM vw_andamio_alertas_consolidadas ac;

DROP TABLE IF EXISTS tmp_casos_calc2;
CREATE TABLE tmp_casos_calc2 (
    fila_id             INT PRIMARY KEY,
    tipo_entidad        VARCHAR(15),
    entidad_id          INT,
    cliente_id          INT,
    tipo_alerta         VARCHAR(40),
    detalle             VARCHAR(300),
    fecha_deteccion     DATETIME,
    severidad_sugerida  VARCHAR(10),
    es_verdadero        TINYINT(1),
    analista            VARCHAR(60),
    fecha_asignacion    DATETIME,
    r_horas             DOUBLE,
    resultado           VARCHAR(35)
);

INSERT INTO tmp_casos_calc2
SELECT
    fila_id, tipo_entidad, entidad_id, cliente_id, tipo_alerta, detalle, fecha_deteccion, severidad_sugerida,
    es_verdadero, analista, fecha_asignacion, r_horas,
    CASE
        WHEN es_verdadero = 1 AND r_resultado < 0.06 THEN 'Confirmado - Aviso a UIF'
        WHEN es_verdadero = 1 AND r_resultado < 0.14 THEN 'Escalado a EDD'
        WHEN es_verdadero = 1 AND r_resultado < 0.28 THEN 'Cliente Contactado - Aclarado'
        WHEN es_verdadero = 1 THEN 'Falso Positivo'
        WHEN es_verdadero = 0 AND r_resultado < 0.01 THEN 'Confirmado - Aviso a UIF'
        WHEN es_verdadero = 0 AND r_resultado < 0.04 THEN 'Escalado a EDD'
        WHEN es_verdadero = 0 AND r_resultado < 0.12 THEN 'Cliente Contactado - Aclarado'
        ELSE 'Falso Positivo'
    END
FROM tmp_casos_calc;

INSERT INTO casos_revision_kyc (
    tipo_entidad, entidad_id, cliente_id, tipo_alerta, detalle_alerta, fecha_generacion,
    analista_asignado, fecha_asignacion, fecha_cierre, horas_invertidas, prioridad, resultado,
    es_caso_verdadero_ground_truth
)
SELECT
    c.tipo_entidad, c.entidad_id, c.cliente_id, c.tipo_alerta, c.detalle, c.fecha_deteccion,
    c.analista, c.fecha_asignacion,
    c.fecha_asignacion + INTERVAL (
        CASE c.resultado
            WHEN 'Falso Positivo' THEN FLOOR(2 + c.r_horas*10) * 60
            WHEN 'Cliente Contactado - Aclarado' THEN FLOOR(8 + c.r_horas*40) * 60
            WHEN 'Escalado a EDD' THEN FLOOR(3 + c.r_horas*10) * 1440
            WHEN 'Confirmado - Aviso a UIF' THEN FLOOR(5 + c.r_horas*15) * 1440
            ELSE 0
        END
    ) MINUTE,
    ROUND((
        CASE c.tipo_alerta
            WHEN 'Estructuracion' THEN 3 + c.r_horas*5
            WHEN 'Pais Sancionado OFAC' THEN 2 + c.r_horas*4
            WHEN 'Monto Inusual' THEN 1 + c.r_horas*2
            WHEN 'Velocidad Alta' THEN 1 + c.r_horas*3
            WHEN 'UBO en Lista Negra' THEN 4 + c.r_horas*6
            WHEN 'Posible Prestanombres' THEN 5 + c.r_horas*7
            WHEN 'Credential Stuffing / Fuerza Bruta' THEN 1 + c.r_horas*2
            ELSE 2 + c.r_horas*3
        END
    ), 2),
    c.severidad_sugerida,
    c.resultado,
    c.es_verdadero
FROM tmp_casos_calc2 c;

DROP TABLE IF EXISTS tmp_casos_calc, tmp_casos_calc2;

-- ---------------------------------------------------------------------
-- Limpieza: se borran las vistas de andamiaje. Tu base de datos queda
-- solo con las 9 tablas del esquema, ya con datos historicos de un
-- año completo. Las vistas de deteccion "de verdad" las construyes tu
-- mas adelante, con otros nombres, paso a paso.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS
    vw_andamio_alertas_consolidadas,
    vw_andamio_estructuracion,
    vw_andamio_pais_sancionado,
    vw_andamio_monto_inusual,
    vw_andamio_velocidad,
    vw_andamio_ubo_lista_negra,
    vw_andamio_prestanombres,
    vw_andamio_credential_stuffing;
