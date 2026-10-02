-- =====================================================================
-- PROYECTO: Revisión Periódica de Riesgo PLD/KYC — Portafolio de
-- Analista de Datos
-- =====================================================================
--
-- CONTEXTO DE NEGOCIO
-- El área de Cumplimiento solicitó una revisión trimestral del
-- histórico transaccional. En el trimestre anterior se registró una
-- tasa de falsos positivos muy alta en las alertas automáticas, lo
-- que hace que el equipo invierta horas revisando ruido en vez de
-- casos reales.
--
-- PREGUNTA DE NEGOCIO RAÍZ
-- ¿Dónde está el riesgo real de PLD en la cartera de clientes, y cómo
-- optimizamos el proceso de revisión para enfocar los recursos del
-- equipo en lo que de verdad importa?
--
-- Esta pregunta se descompone en 7 preguntas técnicas, cada una
-- resuelta con su propio set de queries de detección. Este archivo
-- cubre la primera:
--
-- SECCIÓN 1: ESTRUCTURACIÓN / SMURFING
-- Pregunta técnica: ¿qué clientes están fraccionando montos en
-- depósitos de efectivo para evadir el umbral reportable de aviso a
-- la UIF?
-- =====================================================================

QUERY 1: Depósitos en efectivo (vista exploratoria)
-- Pregunta de negocio: ¿cómo se ve la actividad de depósitos en
-- efectivo en general, antes de aplicar ningún filtro de riesgo?

SELECT cuenta_id, fecha_hora, monto_mxn, tipo_transaccion, canal
FROM transacciones
WHERE tipo_transaccion = 'Deposito Efectivo'
ORDER BY monto_mxn DESC;

QUERY 2: Depósitos en efectivo cercanos al umbral de aviso
-- Pregunta de negocio: ¿qué depósitos en efectivo están justo debajo
-- del umbral ilustrativo de $150,000 MXN (posible estructuración)?

SELECT cuenta_id, fecha_hora, monto_mxn, tipo_transaccion, canal 
FROM transacciones
WHERE tipo_transaccion = 'Deposito Efectivo'
AND monto_mxn BETWEEN 120000 AND 149999
ORDER BY cuenta_id, fecha_hora;

-- LIMPIEZA DE DATOS: verificación de canal inválido por tipo de operación
-- Motivo: se detectó que operaciones físicas (efectivo/cheque) tenían
-- canales digitales imposibles (App/Web). Esta consulta cuenta cuántas
-- filas están mal antes de corregirlas.

SELECT tipo_transaccion, canal, COUNT(*) AS filas
From transacciones
WHERE (tipo_transaccion = 'Deposito Efectivo' AND canal NOT IN ('Sucursal','Cajero'))
OR (tipo_transaccion = 'Retiro Efectivo' AND canal NOT IN ('Sucursal','Cajero'))
OR (tipo_transaccion = 'Deposito Cheque' AND canal <> 'Sucursal')
OR (tipo_transaccion = 'Transferencia SPEI' AND canal NOT IN ('App','Web','Sucursal'))
OR (tipo_transaccion = 'Pago Tarjeta' AND canal NOT IN ('App','Web','Sucursal','Cajero'))
GROUP BY tipo_transaccion, canal
ORDER BY filas DESC;

-- =====================================================================
-- CORRECCIÓN DE DATOS: canal invalido para el tipo de transaccion
-- Motivo: en la generacion de datos, tipo_transaccion y canal se
-- asignaron con dos aleatorios independientes, sin logica de negocio
-- real (ej. "Deposito Efectivo" no puede ocurrir en App o Web).
-- Regla aplicada (confirmada con experiencia bancaria propia):
--   Deposito Efectivo / Retiro Efectivo -> Sucursal, Cajero
--   Deposito Cheque                     -> Sucursal
--   Transferencia SPEI                  -> App, Web, Sucursal
--   Pago Tarjeta                        -> App, Web, Sucursal, Cajero
-- =====================================================================

SET SQL_SAFE_UPDATES = 0;

UPDATE transacciones
SET canal = CASE tipo_transaccion
    WHEN 'Deposito Efectivo' THEN ELT(1 + FLOOR(RAND()*2), 'Sucursal', 'Cajero')
    WHEN 'Retiro Efectivo' THEN ELT(1 + FLOOR(RAND()*2), 'Sucursal', 'Cajero')
    WHEN 'Deposito Cheque' THEN 'Sucursal'
    WHEN 'Transferencia SPEI' THEN ELT(1 + FLOOR(RAND()*3), 'App', 'Web', 'Sucursal')
    WHEN 'Pago Tarjeta' THEN ELT(1 + FLOOR(RAND()*4), 'App', 'Web', 'Sucursal', 'Cajero')
    ELSE canal
END
WHERE (tipo_transaccion = 'Deposito Efectivo' AND canal NOT IN ('Sucursal','Cajero'))
   OR (tipo_transaccion = 'Retiro Efectivo' AND canal NOT IN ('Sucursal','Cajero'))
   OR (tipo_transaccion = 'Deposito Cheque' AND canal <> 'Sucursal')
   OR (tipo_transaccion = 'Transferencia SPEI' AND canal NOT IN ('App','Web','Sucursal'))
   OR (tipo_transaccion = 'Pago Tarjeta' AND canal NOT IN ('App','Web','Sucursal','Cajero'));

-- QUERY 3: Depósitos en efectivo cercanos al umbral de aviso
-- Pregunta de negocio: ¿qué depósitos en efectivo están justo debajo
-- del umbral ilustrativo de $150,000 MXN (posible estructuración)?
-- =====================================================================

SELECT cuenta_id, fecha_hora, monto_mxn, tipo_transaccion, canal
FROM transacciones 
WHERE tipo_transaccion = 'Deposito Efectivo'
AND monto_mxn BETWEEN 120000 AND 149000
ORDER BY cuenta_id, fecha_hora;

-- LIMPIEZA DE DATOS: verificación de montos grandes mal canalizados
-- como Cajero (depósito/retiro en efectivo)
-- Motivo: un cajero automático no puede manejar montos grandes en
-- efectivo por límites operativos y de seguridad reales. Esta consulta
-- cuenta cuántas filas violan ese límite antes de corregirlas.
-- =====================================================================

SELECT tipo_transaccion, canal, COUNT(*) AS filas
FROM transacciones
WHERE (tipo_transaccion = 'Deposito Efectivo' AND canal = 'Cajero' AND monto_mxn > 25000)
OR (tipo_transaccion = 'Retiro Efectivo' AND canal = 'Cajero' AND monto_mxn > 12000)
GROUP BY tipo_transaccion, canal;

LIMPIEZA DE DATOS: límite de monto para canal Cajero en operaciones
-- de efectivo (depósito y retiro)
-- Motivo: un cajero automático (Depositador/ATM) no puede manejar
-- montos grandes en efectivo por límites operativos y de seguridad
-- reales:
--   Deposito Efectivo en Cajero -> máximo $25,000 MXN
--   Retiro Efectivo en Cajero   -> máximo $12,000 MXN (límite oficial ATM en México)
-- Montos mayores, aunque el canal actual diga "Cajero", se reasignan
-- a "Sucursal" (solo se pueden hacer en ventanilla).
-- =====================================================================

UPDATE transacciones
SET canal = 'Sucursal'
WHERE (tipo_transaccion = 'Deposito Efectivo' AND canal = 'Cajero' AND monto_mxn > 25000)
OR (tipo_transaccion = 'Retiro Efectivo' AND canal = 'cajero' AND monto_mxn > 12000);

SELECT tipo_transaccion, canal, COUNT(*) AS filas
FROM transacciones
WHERE (tipo_transaccion = 'Deposito Efectivo' AND canal = 'Cajero' AND monto_mxn > 25000)

-- =====================================================================
-- Query para confirmar que ya no hay ninguna fila mal
-- =====================================================================

SELECT tipo_transaccion, canal, COUNT(*) AS filas
FROM transacciones
WHERE (tipo_transaccion = 'Deposito Efectivo' AND canal = 'Cajero' AND monto_mxn > 25000)
OR (tipo_transaccion = 'Retiro Efectivo' AND canal = 'Cajero' AND monto_mxn > 12000)
GROUP BY tipo_transaccion, canal;

-- =====================================================================
-- QUERY 4: Conteo de depósitos sospechosos por cuenta
-- Pregunta de negocio: ¿qué cuentas tienen múltiples depósitos en
-- efectivo cercanos al umbral de aviso, y cuánto suman en total?
-- =====================================================================

SELECT cuenta_id, 
COUNT(*) AS num_depositos, 
SUM(monto_mxn) AS monto_total,
MIN(fecha_hora) AS primera_fecha, 
MAX(fecha_hora) AS ultima_fecha
FROM transacciones
WHERE tipo_transaccion = 'Deposito Efectivo'
AND monto_mxn BETWEEN 120000 AND 149000
GROUP BY cuenta_id
ORDER BY num_depositos DESC;

-- =====================================================================
-- QUERY 5: Cuentas con posible estructuración (múltiples depósitos
-- cercanos al umbral de aviso)
-- Pregunta de negocio: ¿qué cuentas tienen 13 o más depósitos en
-- efectivo dentro del rango sospechoso, sugiriendo fraccionamiento
-- deliberado en vez de coincidencia?
-- =====================================================================

SELECT cuenta_id, 
COUNT(*) AS num_depositos,
SUM(monto_mxn) AS monto_total, 
MIN(fecha_hora) AS primera_fecha, 
MAX(fecha_hora) AS ultima_fecha
FROM transacciones
WHERE tipo_transaccion = 'Deposito Efectivo'
AND monto_mxn BETWEEN 120000 AND 149000
GROUP BY cuenta_id
HAVING COUNT(*) >= 13
ORDER BY num_depositos DESC;

-- =====================================================================
-- QUERY 6: Estructuración con contexto del cliente (giro e ingreso)
-- Pregunta de negocio: de las cuentas con posible estructuración,
-- ¿cuáles tienen un giro/ingreso declarado que no justifica tanto
-- efectivo, y cuáles sí podrían tener una explicación de negocio
-- legítima (comercio, giro de alto manejo de efectivo)?
-- =====================================================================

SELECT
c.cuenta_id, 
cl.cliente_id,
cl.ocupacion_giro,
cl.ingreso_mensual_declarado_mxn,
COUNT(*) AS num_depositos, 
SUM(t.monto_mxn) AS monto_total, 
MIN(t.fecha_hora) AS primera_fecha,
MAX(t.fecha_hora) AS ultima_fecha 
FROM transacciones t
JOIN cuentas c ON c.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = c.cliente_id
WHERE t.tipo_transaccion = 'Deposito Efectivo'
AND t.monto_mxn BETWEEN 120000 AND 149999
GROUP BY c.cuenta_id, cl.cliente_id, cl.ocupacion_giro, cl.ingreso_mensual_declarado_mxn
HAVING COUNT(*) >= 13
ORDER BY num_depositos DESC;

-- =====================================================================
-- QUERY 7: Estructuración con identidad y ubicación del cliente
-- Pregunta de negocio: ¿quiénes son exactamente estas 16 cuentas
-- sospechosas, de qué ciudad/estado son, y son Persona Física o Moral?
-- =====================================================================

SELECT
c.cuenta_id,
cl.cliente_id, 
cl.nombre_completo, 
cl.tipo_persona,
cl.ciudad,
cl.estado_republica,
cl.ocupacion_giro,
cl.ingreso_mensual_declarado_mxn, 
COUNT(*) AS num_depositos, 
SUM(t.monto_mxn) AS monto_total
FROM transacciones t 
JOIN cuentas c ON c.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = c.cliente_id
WHERE t.tipo_transaccion = 'Deposito Efectivo'
AND t.monto_mxn BETWEEN 120000 AND 149999
GROUP BY c.cuenta_id, cl.cliente_id, cl.nombre_completo, cl.tipo_persona, cl.ciudad, cl.estado_republica, cl.ocupacion_giro, cl.ingreso_mensual_declarado_mxn
HAVING COUNT(*) >= 13
ORDER BY num_depositos DESC;

-- =====================================================================
-- QUERY 8: Histórico mensual de depósitos en efectivo de las cuentas
-- con posible estructuración
-- Pregunta de negocio: ¿el patrón sospechoso es una ráfaga aislada en
-- el tiempo, o estas cuentas siempre han manejado montos así de
-- efectivo (comportamiento habitual, menos alarmante)?
-- =====================================================================

SELECT 
c.cuenta_id,
DATE_FORMAT(t.fecha_hora, '%Y-%m') AS mes, 
COUNT(*) AS num_depositos, 
SUM(t.monto_mxn) AS monto_total_mes
FROM transacciones t
JOIN cuentas c ON c.cuenta_id = t.cuenta_id
WHERE t.tipo_transaccion = 'Deposito Efectivo'
AND c.cuenta_id IN (47,127,169,212,306,782,49,684,46,175,539,554,48,413,672)
GROUP BY c.cuenta_id, DATE_FORMAT(t.fecha_hora, '%Y-%m')
ORDER BY c.cuenta_id, mes;

-- =====================================================================
-- QUERY 9: Verificación de PEP y nivel de riesgo KYC de onboarding
-- para las cuentas con posible estructuración
-- Pregunta de negocio: ¿alguno de estos 16 clientes es Persona
-- Políticamente Expuesta, o ya tenía un nivel de riesgo alto desde
-- que se dio de alta?
-- =====================================================================

SELECT cl.cliente_id, cl.nombre_completo, cl.tipo_persona, cl.es_pep, cl.nivel_riesgo_kyc_onboarding
FROM clientes cl
WHERE cl.cliente_id IN (47,127,169,212,306,782,49,684,46,175,539,554,569,48,413,672);

-- =====================================================================
-- QUERY 10: Resultado de investigación histórica para los casos de
-- estructuración identificados
-- Pregunta de negocio: de estos 16 casos, ¿cuántos ya se investigaron
-- y con qué resultado (aclarado, escalado, confirmado)?
-- =====================================================================

SELECT cr.cliente_id, cl.nombre_completo, cr.tipo_alerta, cr.detalle_alerta, cr.prioridad, cr.resultado, cr.es_caso_verdadero_ground_truth
FROM casos_revision_kyc cr
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.tipo_alerta = 'Estructuracion'
AND cr.cliente_id IN(47,127,169,212,306,782,49,684,46,175,539,554,569,48,413,672)
ORDER BY cr.cliente_id;

-- =====================================================================
-- QUERY 11: Fechas del caso histórico vs. ráfagas mensuales detectadas
-- Pregunta de negocio: ¿el caso ya investigado corresponde a una sola
-- de las dos ráfagas de cada cliente, dejando la otra sin revisar
-- (posible reincidencia no detectada)?
-- =====================================================================

SELECT cr.cliente_id, cl.nombre_completo, cr.detalle_alerta, cr.fecha_generacion, cr.fecha_asignacion, cr.fecha_cierre, cr.resultado
FROM casos_revision_kyc cr
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.tipo_alerta = 'Estructuracion'
AND cr.cliente_id IN (47,127,169,212,306,782,49,684,46,175,539,554,569,48,413,672)
ORDER BY cr.cliente_id;

-- =====================================================================
-- QUERY 12: Reincidencia post-cierre — actividad sospechosa después
-- de que el caso ya se había cerrado
-- Pregunta de negocio: ¿cuántos días después de cerrado el caso el
-- cliente siguió haciendo depósitos fraccionados sin que se generara
-- un caso nuevo?
-- =====================================================================

SELECT cr.cliente_id, cl.nombre_completo, cr.fecha_cierre, cr.resultado,
MAX(t.fecha_hora) AS ultimo_deposito_sospechoso,
DATEDIFF(MAX(t.fecha_hora), cr.fecha_cierre) AS dias_reincidencia_no_detectada
FROM casos_revision_kyc cr
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
JOIN cuentas c ON c.cliente_id = cr.cliente_id
JOIN transacciones t ON t.cuenta_id = c.cuenta_id
WHERE cr.tipo_alerta = 'Estructuracion'
AND t.tipo_transaccion = 'Deposito Efectivo'
AND t.monto_mxn BETWEEN 120000 AND 149999
AND cr.cliente_id IN (47,127,169,212,306,782,49,684,46,175,539,554,569,48,413,672)
GROUP BY cr.cliente_id, cl.nombre_completo, cr.fecha_cierre, cr.resultado
HAVING DATEDIFF(MAX(t.fecha_hora), cr.fecha_cierre) > 0
ORDER BY dias_reincidencia_no_detectada DESC;

-- =====================================================================
-- RESUMEN EJECUTIVO: Estructuración / Smurfing
-- Hallazgos, insight de negocio y recomendaciones para Cumplimiento
-- =====================================================================
--
-- HALLAZGO PRINCIPAL
-- Se identificaron 16 cuentas con patrón de depósitos en efectivo
-- fraccionados justo debajo del umbral de aviso (Queries 5-7), con
-- 100% de coincidencia contra los casos conocidos (ground truth).
-- Al cruzar estas cuentas contra el histórico de casos ya investigados
-- (Query 11-12), se encontró que TODOS los casos ya habían sido
-- cerrados previamente (Falso Positivo, Cliente Contactado - Aclarado,
-- Escalado a EDD, e incluso Confirmado - Aviso a UIF), pero la
-- actividad sospechosa continuó DESPUÉS del cierre en el 100% de los
-- casos, con brechas de entre 23 y 241 días sin ningún caso nuevo
-- generado ni seguimiento activo.
--
-- INSIGHT DE NEGOCIO
-- El problema no es que el sistema de detección falle en identificar
-- el patrón la primera vez -- sí lo hace. El problema es que el
-- proceso de revisión es de "una sola vez": se investiga, se cierra
-- el caso, y no existe un mecanismo de reevaluación periódica para
-- detectar reincidencia. Esto genera retrabajo para el equipo de
-- Cumplimiento (que eventualmente re-detecta el mismo patrón en el
-- mismo cliente como si fuera nuevo) y, más grave, deja ventanas de
-- varios meses de actividad potencialmente ilícita sin monitoreo
-- activo -- incluso en el caso ya confirmado y notificado a UIF
-- (cliente 539), donde la actividad continuó 241 días después de la
-- notificación.
--
-- RECOMENDACIONES PARA GERENCIA / CUMPLIMIENTO (EDD, KYC, PLD)
-- 1. Ningun caso de estructuracion debe cerrarse sin una ventana de
--    revision de seguimiento obligatoria (30-60-90 dias) antes de
--    marcarlo como definitivamente resuelto.
-- 2. Reincidencia en el mismo tipo de patron tras un cierre debe
--    escalar automaticamente a EDD en el segundo incidente, sin
--    importar el resultado original.
-- 3. Citar a sucursal a las 16 cuentas identificadas para actualizar
--    expediente (ingreso declarado, giro/ocupacion), solicitar
--    Constancia de Situacion Fiscal reciente y carta de cumplimiento
--    del SAT como soporte documental del origen de los depositos.
-- 4. Asignar perfil de riesgo elevado en el sistema de gestion de
--    clientes (p. ej. HOGAN) para que cualquier ejecutivo que
--    interactue con estas cuentas tenga visibilidad del historial.
-- 5. Para el caso ya confirmado con aviso a UIF (cliente 539) que
--    reincidio 241 dias despues: evaluar bloqueo de cuenta y gestion
--    de salida del banco, no una tercera ronda de aclaracion.
-- 6. Este hallazgo debe documentarse como un ISSUE formal para las
--    areas de EDD/KYC/PLD sobre la falta de un mecanismo de
--    reevaluacion periodica en el proceso de cierre de casos.
--
-- RIESGO DE NO ACTUAR
-- Exposicion a riesgo reputacional y regulatorio ante la CNBV y la
-- UIF por deficiencias en el seguimiento de casos de PLD, ademas del
-- costo operativo de retrabajo para el equipo de Cumplimiento al
-- re-investigar patrones que nunca dejaron de ocurrir.
-- =====================================================================









