USE kyc_aml_portafolio;
SET SESSION cte_max_recursion_depth = 5000;

-- ---------------------------------------------------------------------
-- Tabla auxiliar de numeros 1..800 (se borra al final del script)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_seq;
CREATE TABLE tmp_seq (n INT PRIMARY KEY);
INSERT INTO tmp_seq
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 800
)
SELECT n FROM seq;

-- ---------------------------------------------------------------------
-- Catalogos auxiliares para generar nombres/ciudades/ocupaciones
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_nombres;
CREATE TABLE tmp_nombres (nombre VARCHAR(30));
INSERT INTO tmp_nombres VALUES ('Jose'),('Maria'),('Juan'),('Ana'),('Luis'),('Laura'),
('Carlos'),('Karla'),('Miguel'),('Fernanda'),('Ricardo'),('Daniela'),('Jorge'),('Paola'),
('Alejandro'),('Monica'),('Roberto'),('Claudia'),('Eduardo'),('Sofia'),('Francisco'),('Andrea'),
('Raul'),('Patricia'),('Sergio'),('Gabriela'),('Arturo'),('Veronica'),('Hector'),('Lucia');

DROP TABLE IF EXISTS tmp_apellidos;
CREATE TABLE tmp_apellidos (apellido VARCHAR(30));
INSERT INTO tmp_apellidos VALUES ('Garcia'),('Hernandez'),('Martinez'),('Lopez'),('Gonzalez'),
('Perez'),('Sanchez'),('Ramirez'),('Torres'),('Flores'),('Rivera'),('Gomez'),('Diaz'),('Reyes'),
('Cruz'),('Morales'),('Ortiz'),('Gutierrez'),('Chavez'),('Ramos'),('Vazquez'),('Castillo'),
('Jimenez'),('Mendoza'),('Ruiz'),('Aguilar'),('Vargas'),('Contreras'),('Salazar'),('Benitez');

DROP TABLE IF EXISTS tmp_giros_morales;
CREATE TABLE tmp_giros_morales (giro VARCHAR(80));
INSERT INTO tmp_giros_morales VALUES
('Comercio al por menor'),('Restaurantero'),('Construccion'),('Servicios Profesionales'),
('Transporte y Logistica'),('Tecnologia'),('Casa de Cambio'),('Bienes Raices'),
('Importacion y Exportacion'),('Joyeria');

DROP TABLE IF EXISTS tmp_palabras_empresa;
CREATE TABLE tmp_palabras_empresa (palabra VARCHAR(30));
INSERT INTO tmp_palabras_empresa VALUES ('Grupo'),('Comercializadora'),('Constructora'),
('Consultores'),('Distribuidora'),('Soluciones'),('Servicios'),('Industrias'),('Corporativo'),('Logistica');

-- Ciudades ponderadas: 4 "de riesgo" pesan mas que el resto, pero no son mayoria.
DROP TABLE IF EXISTS tmp_ciudades_pool;
CREATE TABLE tmp_ciudades_pool (idx INT AUTO_INCREMENT PRIMARY KEY, ciudad VARCHAR(60));
INSERT INTO tmp_ciudades_pool (ciudad)
SELECT 'Culiacan' FROM tmp_seq WHERE n <= 3
UNION ALL SELECT 'Ecatepec de Morelos' FROM tmp_seq WHERE n <= 3
UNION ALL SELECT 'Reynosa' FROM tmp_seq WHERE n <= 3
UNION ALL SELECT 'Tijuana' FROM tmp_seq WHERE n <= 3
UNION ALL SELECT 'Ciudad de Mexico' FROM tmp_seq WHERE n <= 12
UNION ALL SELECT 'Guadalajara' FROM tmp_seq WHERE n <= 8
UNION ALL SELECT 'Monterrey' FROM tmp_seq WHERE n <= 8
UNION ALL SELECT 'Puebla' FROM tmp_seq WHERE n <= 5
UNION ALL SELECT 'Queretaro' FROM tmp_seq WHERE n <= 5
UNION ALL SELECT 'Merida' FROM tmp_seq WHERE n <= 4
UNION ALL SELECT 'Leon' FROM tmp_seq WHERE n <= 4
UNION ALL SELECT 'Toluca' FROM tmp_seq WHERE n <= 4
UNION ALL SELECT 'Chihuahua' FROM tmp_seq WHERE n <= 3
UNION ALL SELECT 'Cancun' FROM tmp_seq WHERE n <= 4
UNION ALL SELECT 'Aguascalientes' FROM tmp_seq WHERE n <= 3;

DROP TABLE IF EXISTS tmp_ocupaciones;
CREATE TABLE tmp_ocupaciones (ocupacion VARCHAR(80), ingreso_min DECIMAL(12,2), ingreso_max DECIMAL(12,2));
INSERT INTO tmp_ocupaciones VALUES
('Empleado', 9000, 45000),
('Comerciante', 12000, 80000),
('Profesionista Independiente', 15000, 120000),
('Empresario', 40000, 350000),
('Jubilado', 8000, 30000),
('Servidor Publico', 12000, 60000),
('Estudiante', 0, 8000);

-- ---------------------------------------------------------------------
-- CLIENTES: 800 filas (~12% persona moral)
-- ---------------------------------------------------------------------
INSERT INTO clientes (
    tipo_persona, nombre_completo, fecha_nacimiento_constitucion, fecha_alta, canal_alta,
    ciudad, estado_republica, pais_id, ocupacion_giro, ingreso_mensual_declarado_mxn,
    es_pep, nivel_riesgo_kyc_onboarding, estatus_cliente
)
SELECT
    g.tipo_persona,
    CASE WHEN g.tipo_persona = 'Fisica'
         THEN CONCAT(g.nombre, ' ', g.apellido1, ' ', g.apellido2)
         ELSE CONCAT(g.palabra_empresa, ' ', g.giro_moral, ' ', g.apellido1, ' S.A. de C.V.')
    END,
    CASE WHEN g.tipo_persona = 'Fisica'
         THEN DATE_SUB(CURDATE(), INTERVAL (22 + FLOOR(g.r_edad*48)) YEAR)
         ELSE DATE_SUB(CURDATE(), INTERVAL (1 + FLOOR(g.r_edad*20)) YEAR)
    END,
    DATE_SUB(NOW(), INTERVAL FLOOR(g.r_alta*1095) DAY),
    CASE WHEN g.r_canal < 0.55 THEN 'Digital' WHEN g.r_canal < 0.85 THEN 'Sucursal' ELSE 'Ejecutivo' END,
    g.ciudad,
    CASE g.ciudad
        WHEN 'Culiacan' THEN 'Sinaloa'
        WHEN 'Ecatepec de Morelos' THEN 'Estado de Mexico'
        WHEN 'Reynosa' THEN 'Tamaulipas'
        WHEN 'Tijuana' THEN 'Baja California'
        WHEN 'Ciudad de Mexico' THEN 'Ciudad de Mexico'
        WHEN 'Guadalajara' THEN 'Jalisco'
        WHEN 'Monterrey' THEN 'Nuevo Leon'
        WHEN 'Puebla' THEN 'Puebla'
        WHEN 'Queretaro' THEN 'Queretaro'
        WHEN 'Merida' THEN 'Yucatan'
        WHEN 'Leon' THEN 'Guanajuato'
        WHEN 'Toluca' THEN 'Estado de Mexico'
        WHEN 'Chihuahua' THEN 'Chihuahua'
        WHEN 'Cancun' THEN 'Quintana Roo'
        WHEN 'Aguascalientes' THEN 'Aguascalientes'
    END,
    (SELECT pais_id FROM paises WHERE codigo_iso3='MEX'),
    CASE WHEN g.tipo_persona='Fisica' THEN g.ocupacion ELSE g.giro_moral END,
    CASE WHEN g.tipo_persona = 'Fisica' THEN
        CASE g.ocupacion
            WHEN 'Empleado' THEN ROUND(9000 + g.r_ingreso1*36000, 2)
            WHEN 'Comerciante' THEN ROUND(12000 + g.r_ingreso1*68000, 2)
            WHEN 'Profesionista Independiente' THEN ROUND(15000 + g.r_ingreso1*105000, 2)
            WHEN 'Empresario' THEN ROUND(40000 + g.r_ingreso1*310000, 2)
            WHEN 'Jubilado' THEN ROUND(8000 + g.r_ingreso1*22000, 2)
            WHEN 'Servidor Publico' THEN ROUND(12000 + g.r_ingreso1*48000, 2)
            ELSE ROUND(g.r_ingreso1*8000, 2)
        END
    ELSE ROUND(50000 + g.r_ingreso1*g.r_ingreso2*4950000, 2)
    END,
    (g.r_pep < 0.015),
    CASE WHEN g.r_riesgo < 0.70 THEN 'Bajo' WHEN g.r_riesgo < 0.95 THEN 'Medio' ELSE 'Alto' END,
    'Activo'
FROM (
    SELECT
        s.n,
        CASE WHEN RAND() < 0.12 THEN 'Moral' ELSE 'Fisica' END AS tipo_persona,
        (SELECT ciudad FROM tmp_ciudades_pool ORDER BY RAND() LIMIT 1) AS ciudad,
        (SELECT nombre FROM tmp_nombres ORDER BY RAND() LIMIT 1) AS nombre,
        (SELECT apellido FROM tmp_apellidos ORDER BY RAND() LIMIT 1) AS apellido1,
        (SELECT apellido FROM tmp_apellidos ORDER BY RAND() LIMIT 1) AS apellido2,
        (SELECT giro FROM tmp_giros_morales ORDER BY RAND() LIMIT 1) AS giro_moral,
        (SELECT palabra FROM tmp_palabras_empresa ORDER BY RAND() LIMIT 1) AS palabra_empresa,
        (SELECT ocupacion FROM tmp_ocupaciones ORDER BY RAND() LIMIT 1) AS ocupacion,
        RAND() AS r_edad, RAND() AS r_alta, RAND() AS r_canal, RAND() AS r_ingreso1,
        RAND() AS r_ingreso2, RAND() AS r_pep, RAND() AS r_riesgo
    FROM tmp_seq s
) g;

-- ---------------------------------------------------------------------
-- CUENTAS: 1 garantizada por cliente + una 2a para ~25%
-- ---------------------------------------------------------------------
INSERT INTO cuentas (cliente_id, numero_cuenta, tipo_cuenta, fecha_apertura, sucursal, estado_cuenta)
SELECT
    cl.cliente_id,
    CONCAT('MX', LPAD(cl.cliente_id, 10, '0')),
    CASE WHEN cl.tipo_persona = 'Moral' THEN 'Empresarial'
         ELSE ELT(1 + FLOOR(RAND()*3), 'Ahorro','Cheques','Inversion')
    END,
    DATE_ADD(cl.fecha_alta, INTERVAL FLOOR(RAND()*5) DAY),
    ELT(1 + FLOOR(RAND()*6), 'Sucursal Centro','Sucursal Polanco','Sucursal Santa Fe','Sucursal Norte','Sucursal Sur','Banca Digital'),
    'Activa'
FROM clientes cl;

INSERT INTO cuentas (cliente_id, numero_cuenta, tipo_cuenta, fecha_apertura, sucursal, estado_cuenta)
SELECT
    cl.cliente_id,
    CONCAT('MX', LPAD(90000 + cl.cliente_id, 10, '0')),
    ELT(1 + FLOOR(RAND()*3), 'Ahorro','Cheques','Inversion'),
    DATE_ADD(cl.fecha_alta, INTERVAL (30 + FLOOR(RAND()*300)) DAY),
    ELT(1 + FLOOR(RAND()*6), 'Sucursal Centro','Sucursal Polanco','Sucursal Santa Fe','Sucursal Norte','Sucursal Sur','Banca Digital'),
    'Activa'
FROM clientes cl
WHERE RAND() < 0.25;

-- ---------------------------------------------------------------------
-- SOCIOS / UBO de personas morales (2 a 3 por empresa)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_morales;
CREATE TABLE tmp_morales (cliente_id INT, rn INT);
INSERT INTO tmp_morales
SELECT cliente_id, ROW_NUMBER() OVER (ORDER BY cliente_id)
FROM clientes WHERE tipo_persona='Moral';

DROP TABLE IF EXISTS tmp_socios_base;
CREATE TABLE tmp_socios_base (cliente_id INT, k INT);
INSERT INTO tmp_socios_base
SELECT m.cliente_id, s.n
FROM tmp_morales m
JOIN tmp_seq s ON s.n <= 2 + (m.rn % 2);

INSERT INTO personas_morales_socios (cliente_id, nombre_socio, porcentaje_participacion, es_beneficiario_final_ubo, pais_nacionalidad_id, en_lista_negra)
SELECT
    b.cliente_id,
    CONCAT((SELECT nombre FROM tmp_nombres ORDER BY RAND() LIMIT 1), ' ', (SELECT apellido FROM tmp_apellidos ORDER BY RAND() LIMIT 1)),
    pct,
    pct > 25,
    CASE WHEN r_pais < 0.06 THEN (SELECT pais_id FROM paises WHERE es_sancionado_ofac ORDER BY RAND() LIMIT 1)
         ELSE (SELECT pais_id FROM paises WHERE codigo_iso3='MEX')
    END,
    FALSE
FROM (
    SELECT cliente_id, ROUND(10 + RAND()*70, 2) AS pct, RAND() AS r_pais
    FROM tmp_socios_base
) b;

-- ---------------------------------------------------------------------
-- CONTACTO / DISPOSITIVO (1 por cliente)
-- ---------------------------------------------------------------------
INSERT INTO contacto_dispositivo_cliente (cliente_id, telefono, correo, dispositivo_id, ip_registro)
SELECT
    cliente_id,
    CONCAT('55', LPAD(FLOOR(RAND()*100000000), 8, '0')),
    CONCAT('cliente', cliente_id, '@correo-demo.mx'),
    CONCAT('DEV-', UPPER(SUBSTRING(MD5(RAND()), 1, 10))),
    CONCAT(FLOOR(1+RAND()*223), '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255))
FROM clientes;

-- Limpieza de tablas auxiliares
DROP TABLE tmp_seq, tmp_nombres, tmp_apellidos, tmp_giros_morales, tmp_palabras_empresa,
           tmp_ciudades_pool, tmp_ocupaciones, tmp_morales, tmp_socios_base;
