-- ============================================================
-- SECCION 6: POSIBLE PRESTANOMBRES
-- ============================================================

-- Pregunta de negocio: ¿Que grupos de cuentas, aparentemente de
-- distintos titulares, comparten el mismo dispositivo (celular
-- para Banca Movil) o la misma IP de acceso de forma sospechosa,
-- lo cual sugeriria que una sola persona controla varias cuentas
-- a nombre de otros (prestanombres)?

-- Ver archivo de Seccion 1 (Estructuracion) para el mandato
-- completo del proyecto.
-- ============================================================

-- Query 1: Estructura de la tabla intentos_acceso, para confirmar que
-- columnas de dispositivo/IP existen antes de armar la deteccion

DESCRIBE intentos_acceso;

-- Query 2: Dispositivos (dispositivo_id) usados para acceder a mas de
-- un cliente distinto, señal de que una sola persona/telefono controla
-- varias cuentas a nombre de otros titulares

SELECT dispositivo_id, 
COUNT(DISTINCT cliente_id) AS numero_clientes
FROM intentos_acceso
GROUP BY dispositivo_id 
HAVING numero_clientes >= 2 
ORDER BY numero_clientes DESC;

-- Query 3: Identificar los clientes distintos detras de los 4 dispositivos
-- compartidos, para empezar a investigar si estan relacionados entre si

SELECT DISTINCT ia.dispositivo_id, ia.cliente_id, cl.nombre_completo, cl.nivel_riesgo_kyc_onboarding
FROM intentos_acceso ia
JOIN clientes cl ON cl.cliente_id = ia.cliente_id
WHERE ia.dispositivo_id IN ('DEV-67FB306831', 'DEV-917C07F483', 'DEV-F6032BE7C2', 'DEV-FC8DB4B3C9')
ORDER BY ia.dispositivo_id, ia.cliente_id;

-- Query 4: Estructura de la tabla clientes, para confirmar si existe
-- columna de lista negra, OFAC o nacionalidad a nivel de persona fisica

DESCRIBE clientes;

-- Query 5: Perfil de onboarding (fecha de alta, canal, bandera PEP,
-- ingreso declarado y pais) de los 12 clientes que comparten dispositivo,
-- ordenado por fecha de alta para buscar patrones de reclutamiento

SELECT cliente_id, nombre_completo, fecha_alta, canal_alta, es_pep, ingreso_mensual_declarado_mxn, pais_id
FROM clientes
WHERE cliente_id IN (6, 483, 554, 196, 368, 460, 377, 529, 535, 118, 197, 741)
ORDER BY fecha_alta;

-- Query 6: IPs de origen usadas por los mismos 12 clientes, para
-- verificar con datos quien realmente comparte IP

SELECT DISTINCT cliente_id, ip_origen
FROM intentos_acceso
WHERE cliente_id IN (6, 483, 554, 196, 368, 460, 377, 529, 535, 118, 197, 741)
ORDER BY ip_origen, cliente_id;

-- Query 7: Estructura de la tabla cuentas, para confirmar si existe
-- un campo de beneficiario (por fallecimiento) a nivel de cuenta

DESCRIBE cuentas;

-- Query 8: Listado de todas las tablas de la base de datos, para
-- confirmar si existe una tabla dedicada a beneficiarios de cuenta
-- (por fallecimiento) que no haya explorado todavia

SHOW TABLES;

-- Query 9: Estructura de la tabla contacto_dispositivo_cliente, tabla
-- nueva que no habia explorado y que podria explicar la relacion
-- real entre cliente y dispositivo compartido

DESCRIBE contacto_dispositivo_cliente;

-- Query 10: Telefono, correo y dispositivo/IP de registro de los
-- mismos 12 clientes, para probar si comparten datos de contacto
-- (indicio de familia) o solo dispositivo/IP (indicio de prestanombres)

SELECT cliente_id, telefono, correo, dispositivo_id, ip_registro
FROM contacto_dispositivo_cliente
WHERE cliente_id IN (6, 483, 554, 196, 368, 460, 377, 529, 535, 118, 197, 741)
ORDER BY dispositivo_id, cliente_id;

-- Query 11: Edad de los 12 clientes que comparten dispositivo/IP/telefono,
-- para probar si el titular de mayor edad en cada grupo podria estar
-- recibiendo ayuda de un familiar mas joven para usar Banca Movil

SELECT cliente_id, nombre_completo, fecha_nacimiento_constitucion, TIMESTAMPDIFF(YEAR, fecha_nacimiento_constitucion, CURDATE()) AS edad
FROM clientes
WHERE cliente_id IN (6, 483, 554, 196, 368, 460, 377, 529, 535, 118, 197, 741)
ORDER BY edad DESC;

-- Query 12: Cruce de los 12 clientes que comparten dispositivo/IP/telefono
-- contra casos_revision_kyc, para ver que alertas generaron y como se
-- resolvieron

SELECT cr.caso_id, cr.cliente_id, cl.nombre_completo, cr.tipo_alerta, cr.detalle_alerta, cr.fecha_generacion, cr.fecha_cierre, cr.resultado, cr.es_caso_verdadero_ground_truth
FROM casos_revision_kyc cr
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.cliente_id IN (6, 483, 554, 196, 368, 460, 377, 529, 535, 118, 197, 741)
ORDER BY cr.cliente_id;

-- ============================================================
-- RESUMEN EJECUTIVO -- SECCION 6: POSIBLE PRESTANOMBRES
-- ============================================================

-- METODOLOGIA:
-- Via intentos_acceso y contacto_dispositivo_cliente se detectaron 4
-- dispositivos, cada uno usado por 3 clientes distintos (12 clientes
-- en total). Los mismos 4 grupos comparten ademas la misma IP de
-- registro y el mismo numero de telefono (con correos distintos),
-- lo cual descarta coincidencia -- es un patron consistente, no
-- aleatorio.
--
-- HIPOTESIS ALTERNATIVAS CONSIDERADAS (no se fuerza conclusion):
-- - Relacion familiar/hogar compartido: plausible para Daniela Ortiz
--   Vargas (66 anios) y Paola Martinez Ramos (58 anios), posible
--   ayuda de un familiar mas joven con Banca Movil; el resto tiene
--   edades similares dentro de cada grupo, compatible con pareja.
-- - Cuenta comprometida/hackeo (patron ya visto en Seccion 4).
-- - Prestanombres/cuenta puente -- reforzado por el cruce siguiente.
--
-- CRUCE CONTRA CASOS_REVISION_KYC:
-- Los 12 clientes generaron caso "Posible Prestanombres" el mismo
-- dia (generacion en lote), con es_caso_verdadero_ground_truth = 1
-- en los 12. El detalle_alerta trae un ratio de "flujo vs ingreso
-- anual declarado" por cliente. Resultado: 11 de 12 Falso Positivo;
-- solo 1 (Daniela Ortiz Vargas, 118) escalo a Confirmado-Aviso a UIF.
--
-- HALLAZGO 1 -- La escalacion no sigue la severidad de la propia
-- alerta: Daniela Ortiz Vargas, con el flujo MAS BAJO del grupo
-- (0.91x su ingreso anual), fue la UNICA escalada a UIF. Clientes
-- con flujo de 4.76x (Juan Diaz Gonzalez), 7.08x (Paola Martinez
-- Ramos), 9.91x (Ricardo Ramos Gomez) y hasta 14.94x (Veronica
-- Garcia Morales) cerraron TODOS como Falso Positivo. La decision de
-- escalar no correlaciona con el indicador cuantitativo que la
-- propia alerta ya trae calculado -- evidencia de proceso
-- inconsistente, no de criterio de riesgo aplicado.
--
-- HALLAZGO 2 -- Cliente recurrente sin recalificacion de riesgo:
-- Ricardo Diaz Aguilar (554) acumula TRES alertas de tipo distinto
-- en menos de un anio: Estructuracion (nov 2025, Cliente Contactado
-- - Aclarado), Monto Inusual (ago 2026, caso ancla de la Seccion 3,
-- Confirmado-Aviso a UIF por $2,114,211 MXN) y ahora Posible
-- Prestanombres (flujo 4.29x, Falso Positivo). Pese a tener ya un
-- aviso a UIF confirmado, su nivel_riesgo_kyc_onboarding nunca se
-- actualiza -- el riesgo del cliente no se recalifica con base en
-- su comportamiento real posterior al onboarding.
--
-- LIMITACION DE DATOS (patron que se repite en TODAS las secciones
-- del proyecto):
-- casos_revision_kyc no tiene columna de motivo/detalle de
-- resolucion -- no se puede auditar con que evidencia se determino
-- cada Falso Positivo. Tampoco existe tabla de robo/extravio ni de
-- beneficiario por fallecimiento (confirmado con SHOW TABLES).
--
-- RECOMENDACIONES:
-- 1. Para casos con flujo >= 3x el ingreso anual declarado Y
--    dispositivo/IP/telefono compartido con otros clientes, no basta
--    actualizar segmento o citar a sucursal -- se requiere aviso
--    formal a UIF y recalificacion de riesgo KYC (Bajo a Medio,
--    Medio a Alto), dado que IP + dispositivo compartido + correos
--    distintos es indicio razonable de prestanombres.
--
-- 2. Recalificacion de riesgo obligatoria cuando un cliente acumula
--    multiples alertas confirmadas (ground_truth=1) en categorias
--    distintas como el caso de Ricardo Diaz Aguilar muestra que el
--    riesgo de onboarding nunca se actualiza pese a historial
--    creciente de alertas reales.
--
-- 3. Agregar trazabilidad obligatoria (motivo/detalle) al cierre de
--    casos en casos_revision_kyc esto es el mismo hueco senalado en las
--    Secciones 3, 4 y 5 -- para que EDD/PLD/KYC puedan auditar sus
--    propias decisiones y facilitar auditoria interna y externa.
--
-- 4. Investigar (con datos historicos mas amplios de los disponibles
--    aqui) si los cierres inconsistentes como Falso Positivo estan
--    generando reactivacion de alertas recurrentes sobre el mismo
--    cliente, sobrecargando innecesariamente a Cumplimiento
--    hipotesis razonable a partir del patron observado, no probada
--    con este dataset.
-- ============================================================


