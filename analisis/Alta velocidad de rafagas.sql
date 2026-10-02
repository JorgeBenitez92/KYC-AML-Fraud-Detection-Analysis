-- ============================================================
-- SECCION 4: VELOCIDAD ALTA / RAFAGAS DE TRANSACCIONES
-- ============================================================

-- Pregunta de negocio: ¿Que cuentas presentan un volumen inusual
-- de retiros (Efectivo y Cajero) en una ventana de tiempo muy
-- corta, un patron caracteristico de robo/hackeo de cuenta (toma
-- de control) mas que de comportamiento normal del titular?

-- Ver archivo de Seccion 1 (Estructuracion) para el mandato
-- completo del proyecto.
-- ============================================================

-- Query 1: Numero total de retiros por cuenta, para ver quien se sale del volumen normal

SELECT cuenta_id, 
COUNT(*) AS numero_retiros
FROM transacciones 
WHERE tipo_transaccion = 'Retiro Efectivo'
GROUP BY cuenta_id
ORDER BY numero_retiros DESC;

-- Query 2: Rango de fechas (primer y ultimo retiro) por cuenta, para saber si esos retiros estan repartidos en el tiempo o concentrados

SELECT cuenta_id, 
COUNT(*) AS numero_retiros,
MIN(fecha_hora) AS primer_retiro, 
MAX(fecha_hora) AS ultimo_retiro
FROM transacciones 
WHERE tipo_transaccion = 'Retiro Efectivo'
GROUP BY cuenta_id 
ORDER BY numero_retiros DESC;

-- Query 3: Retiros concentrados en pocos dias (rafaga), con fechas en español y filtro de las que se salen de lo normal

SET lc_time_names = 'es_MX';
SELECT cuenta_id, 
COUNT(*) AS numero_retiros, 
DATE_FORMAT(MIN(fecha_hora), '%W %d de %M de %Y') AS primer_retiro,
DATE_FORMAT(MAX(fecha_hora), '%W %d de %M de %Y') AS ultimo_retiro,
DATEDIFF(MAX(fecha_hora), MIN(fecha_hora)) AS dias_diferencia 
FROM transacciones
WHERE tipo_transaccion = 'Retiro Efectivo'
GROUP BY cuenta_id
HAVING numero_retiros >= 3 AND dias_diferencia <= 7 
ORDER BY dias_diferencia ASC;

-- Query 4: Detalle completo de transacciones (todos los tipos y canales) de las cuentas con rafaga de retiros detectada

SELECT cl.nombre_completo, cl.nivel_riesgo_kyc_onboarding, t.cuenta_id, t.fecha_hora, t.monto_mxn, t.tipo_transaccion, t.canal
FROM transacciones t
JOIN cuentas c ON c.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = c.cliente_id
WHERE t.cuenta_id IN (117, 313, 1051, 207, 67, 506, 384, 703)
ORDER BY t.cuenta_id, t.fecha_hora; 

-- Verificacion: que canales existen realmente para Retiro Efectivo en toda la base
SELECT DISTINCT canal
FROM transacciones
WHERE tipo_transaccion = 'Retiro Efectivo';

-- Query 5: Detalle de RETIROS unicamente (con canal) de las cuentas con rafaga detectada

SELECT cl.nombre_completo, cl.nivel_riesgo_kyc_onboarding, t.cuenta_id, t.fecha_hora, t.monto_mxn, t.canal
FROM transacciones t 
JOIN cuentas c ON c.cuenta_id = t.cuenta_id 
JOIN clientes cl ON cl.cliente_id = c.cliente_id
WHERE t.cuenta_id IN (117, 313, 1051, 207, 67, 506, 384, 703)
AND t.tipo_transaccion = 'Retiro Efectivo'
ORDER BY t.cuenta_id, t.fecha_hora;

-- Query 6: Cruce de las 8 cuentas con rafaga contra casos_revision_kyc (via subconsulta cuenta -> cliente)

SELECT cr.caso_id, cr.cliente_id, cl.nombre_completo, cr.tipo_alerta, cr.detalle_alerta, cr.fecha_generacion, cr.fecha_cierre, cr.resultado, cr.es_caso_verdadero_ground_truth
FROM casos_revision_kyc cr
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.cliente_id IN (
SELECT c.cliente_id
FROM cuentas c 
WHERE c.cuenta_id IN (67, 117, 207, 313, 384, 506, 703, 1051)

)
ORDER BY cr.cliente_id;

-- ============================================================
-- RESUMEN EJECUTIVO — SECCION 4: VELOCIDAD ALTA / RAFAGAS DE RETIROS
-- ============================================================

-- HALLAZGOS:

-- De 1191 cuentas, se detectaron 8 con un patron de rafaga real:
-- 3 o mas retiros de efectivo concentrados en 7 dias o menos
-- (cuentas 117, 313, 1051, 207, 67, 506, 384, 703). Las dos mas
-- extremas (117 y 313) tuvieron 4 retiros el mismo dia calendario
-- (dias_diferencia = 0).
--
-- Se confirmo, sobre TODA la base de transacciones (no solo estas
-- 8 cuentas), que "Retiro Efectivo" unicamente ocurre por canal
-- Cajero o Sucursal — nunca por App ni Web. Esto es un modelado
-- realista del dataset (no se puede entregar efectivo fisico a
-- traves de una app), y descarta de raiz el "hackeo remoto de
-- usuario y contrasena" como explicacion directa de estos retiros:
-- en los 8 casos, alguien tuvo que estar fisicamente presente con
-- tarjeta y/o identificacion.
--
-- La revision caso por caso (con criterio de operacion bancaria
-- real: topes de retiro en cajero, politica de cheque de caja
-- para montos mayores a $50,000 MXN, verificacion de INE/firma/
-- rostro en ventanilla) explica razonablemente la mayoria de estos
-- patrones como actividad legitima del titular. Unicamente la
-- cuenta 313 (combinacion de Cajero + Sucursal el mismo dia)
-- genera algo mas de duda, aunque tambien es consistente con
-- comportamiento normal de un cliente.
--
-- Al cruzar las 8 cuentas contra casos_revision_kyc, SOLO 1 tiene
-- algun caso registrado: la cuenta 207 (Laura Ortiz Vazquez) — y
-- NO es por la rafaga de retiros, sino por un tipo de alerta
-- distinto, "Credential Stuffing / Fuerza Bruta": 18 intentos de
-- login fallidos desde 18 IPs distintas en 20 minutos, seguidos de
-- un acceso exitoso ("posible cuenta comprometida"), fechado casi
-- un mes despues de la rafaga de retiros de julio. Este dato viene
-- de una tabla distinta (intentos_acceso, por IP de acceso digital)
-- y no del canal fisico de los retiros — son dos anomalias
-- separadas de la misma clienta, no el mismo evento.
--
-- El hallazgo mas serio de la seccion: aunque este caso esta
-- marcado como es_caso_verdadero_ground_truth = 1 (caso real segun
-- el diseño del ejercicio) y el patron tecnico (18 IPs distintas,
-- acceso exitoso posterior) es una firma clasica de ataque
-- automatizado, el caso se cerro simplemente como "Cliente
-- Contactado - Aclarado" — una resolucion superficial frente a la
-- severidad que el propio detalle de la alerta describe. Dos
-- explicaciones son plausibles: (a) la revision no profundizo en
-- el patron tecnico y solo confirmo con el cliente de forma
-- generica, o (b) el atacante ya tenia control de la cuenta y se
-- hizo pasar por el cliente durante la llamada de aclaracion.
--
-- No hubo sobresaturacion de Cumplimiento con este tipo de alerta
-- (solo 1 de 8 cuentas genero caso) — el problema aqui no es
-- exceso de alertas, es la profundidad insuficiente en la unica
-- que si se genero.
--
-- LIMITACIONES DE DATOS:
-- No existe en el dataset una tabla de "reporte de robo o
-- extravio de tarjeta", ni un campo que indique si el cliente
-- contacto proactivamente al Call Center o acudio a sucursal a
-- reportar un cargo no reconocido. No se puede verificar si los
-- titulares afectados ya se dieron cuenta y reportaron, o si
-- siguen sin saberlo.
--
-- RECOMENDACIONES:
--
-- 1. Llevar un registro formal y actualizado de las cuentas cuyos
--    clientes hayan contactado al Call Center o acudido a sucursal
--    para reportar robo o uso no reconocido de su dinero. Hoy esa
--    informacion no existe de forma consultable, lo que impide
--    cruzar patrones de deteccion (como esta rafaga) contra
--    reportes reales de clientes — es un control que se debe
--    implementar para tener mejores practicas y trazabilidad.
--
-- 2. Establecer una regla de escalacion obligatoria para cualquier
--    caso de Credential Stuffing / Fuerza Bruta que combine un
--    numero alto de IPs distintas en poco tiempo CON un acceso
--    exitoso posterior — este patron no deberia poder cerrarse
--    solo con una llamada de "aclaracion", sino requerir bloqueo
--    temporal de la cuenta, restablecimiento forzado de contrasena
--    y revision por un segundo analista antes de cerrar el caso.
--
-- 3. Los controles actuales en ventanilla (INE, firma, verificacion
--    de rostro) y la politica de cheque de caja para montos
--    mayores a $50,000 MXN parecen funcionar correctamente como
--    primer filtro — no se identificaron fallas en ese proceso.
--
-- 4. Monitorear de forma cruzada intentos_acceso y transacciones
--    para la misma cuenta/cliente, en vez de revisarlos como
--    señales aisladas — el caso de la cuenta 207 muestra que una
--    anomalia de acceso digital y una rafaga de retiros fisicos
--    en el mismo cliente, ocurridas semanas aparte, pueden pasar
--    desapercibidas si nadie las conecta.
--
-- 5. La investigacion tecnica mas profunda de patrones de
--    Credential Stuffing / Fuerza Bruta (IPs, dispositivos,
--    horarios de acceso) queda para la Seccion 7, dedicada
--    especificamente a ese tema.
-- ============================================================



