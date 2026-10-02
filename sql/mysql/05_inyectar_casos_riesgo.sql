-- =====================================================================
-- 05_inyectar_casos_riesgo.sql (MySQL)
-- Aqui "sembramos" a proposito los patrones de riesgo que un analista
-- KYC/PLD busca en una revision periodica. Cada patron queda
-- registrado en ground_truth_casos_riesgo para poder VALIDAR despues
-- que tan bien las queries de KPIs los detectan (precision / recall).
--
-- Regla seguida en todo el archivo: cualquier valor aleatorio que se
-- vaya a usar en MAS DE UN LUGAR (p.ej. una fecha_base compartida por
-- varias transacciones de la misma rafaga) se guarda primero en una
-- TABLA temporal real (no una subconsulta), porque MySQL puede
-- "aplanar" una subconsulta simple y recalcular el mismo RAND() cada
-- vez que se lee, dando resultados inconsistentes entre filas.
-- =====================================================================
USE kyc_aml_portafolio;

SET @mex_pais_id = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'MEX');
SET @ofac1 = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'PRK');
SET @ofac2 = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'IRN');
SET @ofac3 = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'SYR');
SET @ofac4 = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'CUB');
SET @ofac5 = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'VEN');
SET @ofac6 = (SELECT pais_id FROM paises WHERE codigo_iso3 = 'RUS');

-- Helpers de secuencias pequeñas reutilizados en varios bloques
DROP TABLE IF EXISTS tmp_burst2; CREATE TABLE tmp_burst2 (b INT); INSERT INTO tmp_burst2 VALUES (1),(2);
DROP TABLE IF EXISTS tmp_dia8;   CREATE TABLE tmp_dia8   (d INT); INSERT INTO tmp_dia8   VALUES (0),(1),(2),(3),(4),(5),(6),(7);
DROP TABLE IF EXISTS tmp_n9;     CREATE TABLE tmp_n9     (n INT); INSERT INTO tmp_n9     VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8);
DROP TABLE IF EXISTS tmp_n3;     CREATE TABLE tmp_n3     (n INT); INSERT INTO tmp_n3     VALUES (1),(2),(3);

-- =====================================================================
-- 1) ESTRUCTURACION (smurfing): depositos en efectivo, muchos y justo
--    debajo de un umbral ilustrativo de aviso ($150,000 MXN), en
--    rafagas de dias consecutivos.
-- =====================================================================
DROP TABLE IF EXISTS tmp_estructuracion;
CREATE TABLE tmp_estructuracion (cliente_id INT PRIMARY KEY, cuenta_id INT);
INSERT INTO tmp_estructuracion
SELECT cliente_id, MIN(cuenta_id) FROM cuentas GROUP BY cliente_id ORDER BY RAND() LIMIT 16;

INSERT INTO ground_truth_casos_riesgo (tipo_entidad, entidad_id, tipo_riesgo, descripcion)
SELECT 'Cliente', cliente_id, 'Estructuracion', 'Rafagas de depositos en efectivo justo debajo del umbral de aviso ($150,000 MXN)'
FROM tmp_estructuracion;

DROP TABLE IF EXISTS tmp_rafagas_estruct;
CREATE TABLE tmp_rafagas_estruct (cliente_id INT, cuenta_id INT, burst_num INT, fecha_base DATETIME);
INSERT INTO tmp_rafagas_estruct (cliente_id, cuenta_id, burst_num, fecha_base)
SELECT e.cliente_id, e.cuenta_id, b.b, DATE_SUB(NOW(), INTERVAL (10 + FLOOR(RAND()*330)) DAY)
FROM tmp_estructuracion e CROSS JOIN tmp_burst2 b;

INSERT INTO transacciones (cuenta_id, fecha_hora, monto_mxn, tipo_transaccion, canal, pais_origen_id, pais_destino_id, es_internacional, ip_origen)
SELECT r.cuenta_id,
       r.fecha_base + INTERVAL d.d DAY + INTERVAL FLOOR(RAND()*8) HOUR,
       ROUND(122000 + RAND()*27000, 2),
       'Deposito Efectivo', 'Sucursal',
       @mex_pais_id, @mex_pais_id, FALSE, NULL
FROM tmp_rafagas_estruct r
CROSS JOIN tmp_dia8 d
WHERE RAND() < 0.9;

-- =====================================================================
-- 2) TRANSACCIONES CON PAISES SANCIONADOS (OFAC)
-- =====================================================================
DROP TABLE IF EXISTS tmp_sancionados;
CREATE TABLE tmp_sancionados (cliente_id INT PRIMARY KEY, cuenta_id INT);
INSERT INTO tmp_sancionados
SELECT cliente_id, MIN(cuenta_id) FROM cuentas GROUP BY cliente_id ORDER BY RAND() LIMIT 14;

INSERT INTO ground_truth_casos_riesgo (tipo_entidad, entidad_id, tipo_riesgo, descripcion)
SELECT 'Cliente', cliente_id, 'Pais Sancionado OFAC', 'Transferencia internacional hacia/desde un pais en la lista de sancionados'
FROM tmp_sancionados;

INSERT INTO transacciones (cuenta_id, fecha_hora, monto_mxn, tipo_transaccion, canal, pais_origen_id, pais_destino_id, es_internacional, ip_origen)
SELECT e.cuenta_id,
       DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*300) DAY),
       ROUND(25000 + RAND()*450000, 2),
       'Transferencia Internacional', 'Web',
       @mex_pais_id,
       ELT(1 + FLOOR(RAND()*6), @ofac1, @ofac2, @ofac3, @ofac4, @ofac5, @ofac6),
       TRUE, NULL
FROM tmp_sancionados e
CROSS JOIN tmp_burst2 b
WHERE b.b = 1 OR RAND() < 0.4;

-- =====================================================================
-- 3) MONTO INUSUAL VS. HISTORICO DEL CLIENTE
-- =====================================================================
DROP TABLE IF EXISTS tmp_monto_inusual;
CREATE TABLE tmp_monto_inusual (cliente_id INT PRIMARY KEY, cuenta_id INT);
INSERT INTO tmp_monto_inusual
SELECT cliente_id, MIN(cuenta_id) FROM cuentas GROUP BY cliente_id ORDER BY RAND() LIMIT 12;

INSERT INTO ground_truth_casos_riesgo (tipo_entidad, entidad_id, tipo_riesgo, descripcion)
SELECT 'Cliente', cliente_id, 'Monto Inusual', 'Transaccion 12x-40x superior al promedio historico del cliente'
FROM tmp_monto_inusual;

DROP TABLE IF EXISTS tmp_historico_montos;
CREATE TABLE tmp_historico_montos (cuenta_id INT PRIMARY KEY, promedio DECIMAL(14,2));
INSERT INTO tmp_historico_montos
SELECT m.cuenta_id, GREATEST(500, AVG(t.monto_mxn))
FROM tmp_monto_inusual m JOIN transacciones t ON t.cuenta_id = m.cuenta_id
GROUP BY m.cuenta_id;

INSERT INTO transacciones (cuenta_id, fecha_hora, monto_mxn, tipo_transaccion, canal, pais_origen_id, pais_destino_id, es_internacional, ip_origen)
SELECT h.cuenta_id,
       DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*120) DAY),
       ROUND(h.promedio * (12 + RAND()*28), 2),
       'Transferencia SPEI', 'App',
       @mex_pais_id, @mex_pais_id, FALSE, NULL
FROM tmp_historico_montos h;

-- =====================================================================
-- 4) VELOCIDAD: multiples transacciones en pocos minutos (posible
--    prueba de tarjeta / cuenta comprometida, o fraccionamiento fino)
-- =====================================================================
DROP TABLE IF EXISTS tmp_velocidad;
CREATE TABLE tmp_velocidad (cliente_id INT PRIMARY KEY, cuenta_id INT);
INSERT INTO tmp_velocidad
SELECT cliente_id, MIN(cuenta_id) FROM cuentas GROUP BY cliente_id ORDER BY RAND() LIMIT 13;

INSERT INTO ground_truth_casos_riesgo (tipo_entidad, entidad_id, tipo_riesgo, descripcion)
SELECT 'Cliente', cliente_id, 'Velocidad Alta', '6 a 10 transacciones concentradas en menos de 15 minutos'
FROM tmp_velocidad;

DROP TABLE IF EXISTS tmp_velocidad_base;
CREATE TABLE tmp_velocidad_base (cliente_id INT, cuenta_id INT, fecha_base DATETIME);
INSERT INTO tmp_velocidad_base
SELECT cliente_id, cuenta_id, DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*200) DAY)
FROM tmp_velocidad;

INSERT INTO transacciones (cuenta_id, fecha_hora, monto_mxn, tipo_transaccion, canal, pais_origen_id, pais_destino_id, es_internacional, ip_origen)
SELECT b.cuenta_id,
       b.fecha_base + INTERVAL FLOOR(s.n * (1 + RAND())) MINUTE,
       ROUND(300 + RAND()*4500, 2),
       'Pago Tarjeta', 'Web',
       @mex_pais_id, @mex_pais_id, FALSE, NULL
FROM tmp_velocidad_base b
CROSS JOIN tmp_n9 s
WHERE RAND() < 0.9;

-- =====================================================================
-- 5) SOCIOS / UBO EN LISTA NEGRA (personas morales)
-- =====================================================================
DROP TABLE IF EXISTS tmp_elegidos_ubo;
CREATE TABLE tmp_elegidos_ubo (socio_id INT PRIMARY KEY);
INSERT INTO tmp_elegidos_ubo
SELECT socio_id FROM personas_morales_socios ORDER BY RAND() LIMIT 9;

UPDATE personas_morales_socios s
JOIN tmp_elegidos_ubo e ON e.socio_id = s.socio_id
SET s.en_lista_negra = TRUE;

INSERT INTO ground_truth_casos_riesgo (tipo_entidad, entidad_id, tipo_riesgo, descripcion)
SELECT 'Socio', socio_id, 'UBO en Lista Negra', 'Beneficiario final / socio coincide con lista restrictiva (PEP/sancionados)'
FROM personas_morales_socios WHERE en_lista_negra = TRUE;

-- =====================================================================
-- 6) PRESTANOMBRES: 4 grupos de 3 clientes que comparten el mismo
--    dispositivo/telefono/IP de registro, con ingreso declarado bajo
--    pero recibiendo transferencias grandes (perfil de "mula")
-- =====================================================================
DROP TABLE IF EXISTS tmp_grupos_prestanombres;
CREATE TABLE tmp_grupos_prestanombres (cliente_id INT PRIMARY KEY, grupo INT);
INSERT INTO tmp_grupos_prestanombres
SELECT cliente_id, NTILE(4) OVER (ORDER BY RAND())
FROM (SELECT cliente_id FROM clientes WHERE tipo_persona = 'Fisica' ORDER BY RAND() LIMIT 12) x;

DROP TABLE IF EXISTS tmp_huella_grupo;
CREATE TABLE tmp_huella_grupo (grupo INT PRIMARY KEY, dispositivo_id VARCHAR(40), telefono VARCHAR(15), ip_registro VARCHAR(45));
INSERT INTO tmp_huella_grupo (grupo, dispositivo_id, telefono, ip_registro)
SELECT g.grupo,
       CONCAT('DEV-', UPPER(SUBSTRING(MD5(CONCAT(RAND(), '-', g.grupo)), 1, 10))),
       CONCAT('55', LPAD(FLOOR(RAND()*100000000), 8, '0')),
       CONCAT(FLOOR(RAND()*223)+1, '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255))
FROM (SELECT DISTINCT grupo FROM tmp_grupos_prestanombres) g;

UPDATE contacto_dispositivo_cliente c
JOIN tmp_grupos_prestanombres tg ON tg.cliente_id = c.cliente_id
JOIN tmp_huella_grupo h ON h.grupo = tg.grupo
SET c.dispositivo_id = h.dispositivo_id,
    c.telefono = h.telefono,
    c.ip_registro = h.ip_registro;

INSERT INTO ground_truth_casos_riesgo (tipo_entidad, entidad_id, tipo_riesgo, descripcion)
SELECT 'Cliente', cliente_id, 'Posible Prestanombres', 'Comparte dispositivo/telefono/IP de registro con otros clientes distintos; perfil de ingreso bajo con flujos altos'
FROM tmp_grupos_prestanombres;

DROP TABLE IF EXISTS tmp_cta_prestanombres;
CREATE TABLE tmp_cta_prestanombres (cliente_id INT PRIMARY KEY, cuenta_id INT);
INSERT INTO tmp_cta_prestanombres
SELECT tg.cliente_id, MIN(cu.cuenta_id)
FROM tmp_grupos_prestanombres tg JOIN cuentas cu ON cu.cliente_id = tg.cliente_id
GROUP BY tg.cliente_id;

INSERT INTO transacciones (cuenta_id, fecha_hora, monto_mxn, tipo_transaccion, canal, pais_origen_id, pais_destino_id, es_internacional, ip_origen)
SELECT c.cuenta_id,
       DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*250) DAY),
       ROUND(60000 + RAND()*140000, 2),
       'Transferencia SPEI', 'App',
       @mex_pais_id, @mex_pais_id, FALSE, NULL
FROM tmp_cta_prestanombres c
CROSS JOIN tmp_n3;

-- Limpieza de tablas auxiliares
DROP TABLE IF EXISTS tmp_burst2, tmp_dia8, tmp_n9, tmp_n3,
    tmp_estructuracion, tmp_rafagas_estruct,
    tmp_sancionados,
    tmp_monto_inusual, tmp_historico_montos,
    tmp_velocidad, tmp_velocidad_base,
    tmp_elegidos_ubo,
    tmp_grupos_prestanombres, tmp_huella_grupo, tmp_cta_prestanombres;
