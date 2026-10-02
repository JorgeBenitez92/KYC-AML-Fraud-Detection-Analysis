-- =====================================================================
-- 06_generar_intentos_acceso.sql (MySQL)
-- Bitacora de intentos de acceso al home banking / app:
--   (a) actividad normal de login para todos los clientes
--   (b) rafagas de credential stuffing / fuerza bruta inyectadas en
--       ~15 clientes: muchos intentos fallidos desde varias IPs
--       distintas en pocos minutos, con o sin exito final.
-- =====================================================================
USE kyc_aml_portafolio;
SET SESSION cte_max_recursion_depth = 5000;

-- ---------------------------------------------------------------------
-- (a) Actividad normal: cada cliente tiene entre ~5 y ~40 logins en el
--     ultimo año, casi todos exitosos, desde su IP/dispositivo habitual.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_n40;
CREATE TABLE tmp_n40 (n INT PRIMARY KEY);
INSERT INTO tmp_n40
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 40
)
SELECT n FROM seq;

INSERT INTO intentos_acceso (cliente_id, fecha_hora, exitoso, tipo_intento, ip_origen, dispositivo_id)
SELECT
    cl.cliente_id,
    DATE_SUB(DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*365) DAY), INTERVAL FLOOR(RAND()*1440) MINUTE),
    (RAND() < 0.97),
    ELT(1 + FLOOR(RAND()*6), 'Login', 'Login', 'Login', 'Login', 'Cambio Contrasena', 'Transferencia Alto Monto'),
    cdc.ip_registro,
    cdc.dispositivo_id
FROM clientes cl
JOIN contacto_dispositivo_cliente cdc ON cdc.cliente_id = cl.cliente_id
CROSS JOIN tmp_n40 g
WHERE RAND() < 0.55;

-- ---------------------------------------------------------------------
-- (b) Credential stuffing / fuerza bruta: 15 clientes con rafagas de
--     10-25 intentos fallidos en <20 minutos desde IPs distintas a la
--     habitual (y distintas entre si -- clasico de un bot probando
--     contraseñas), con probabilidad de un intento exitoso al final.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_credential_stuffing;
CREATE TABLE tmp_credential_stuffing (cliente_id INT PRIMARY KEY);
INSERT INTO tmp_credential_stuffing
SELECT cliente_id FROM clientes ORDER BY RAND() LIMIT 15;

INSERT INTO ground_truth_casos_riesgo (tipo_entidad, entidad_id, tipo_riesgo, descripcion)
SELECT 'Cliente', cliente_id, 'Credential Stuffing / Fuerza Bruta', 'Rafaga de intentos de acceso fallidos desde multiples IPs distintas en menos de 20 minutos'
FROM tmp_credential_stuffing;

DROP TABLE IF EXISTS tmp_cs_base;
CREATE TABLE tmp_cs_base (cliente_id INT PRIMARY KEY, fecha_base DATETIME);
INSERT INTO tmp_cs_base
SELECT cliente_id, DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*200) DAY)
FROM tmp_credential_stuffing;

DROP TABLE IF EXISTS tmp_n22;
CREATE TABLE tmp_n22 (n INT PRIMARY KEY);
INSERT INTO tmp_n22
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 22
)
SELECT n FROM seq;

INSERT INTO intentos_acceso (cliente_id, fecha_hora, exitoso, tipo_intento, ip_origen, dispositivo_id)
SELECT
    b.cliente_id,
    b.fecha_base + INTERVAL FLOOR(s.n * (0.3 + RAND())) MINUTE,
    (s.n >= 20 AND RAND() < 0.4),
    'Login',
    CONCAT(FLOOR(RAND()*223)+1, '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255)),
    CONCAT('DEV-DESCONOCIDO-', UPPER(SUBSTRING(MD5(RAND()), 1, 6)))
FROM tmp_cs_base b
CROSS JOIN tmp_n22 s
WHERE RAND() < 0.85;

DROP TABLE IF EXISTS tmp_n40, tmp_credential_stuffing, tmp_cs_base, tmp_n22;
