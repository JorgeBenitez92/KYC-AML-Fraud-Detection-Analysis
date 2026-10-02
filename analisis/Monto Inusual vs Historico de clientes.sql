-- =====================================================================
-- PROYECTO: Portafolio de Analista de Datos
-- =====================================================================

-- (mandato completo y pregunta de negocio raiz en el script de la
-- Seccion 1 - Estructuracion / Smurfing)

-- SECCION 3: MONTO INUSUAL VS. HISTORICO
-- Pregunta tecnica: ¿que transacciones se desvian fuertemente del
-- comportamiento historico normal de cada cliente, en monto?
-- =====================================================================

 -- Vista previa: segmentacion estimada de clientes por ingreso mensual declarado
-- Basada en los rangos reales de banca (Retail / Advance-One / Premier)

SELECT cliente_id, nombre_completo, ingreso_mensual_declarado_mxn, 
CASE 
WHEN ingreso_mensual_declarado_mxn >= 75000 THEN 'Premier'
WHEN ingreso_mensual_declarado_mxn >= 35000 THEN 'Advance / One'
ELSE 'Retail'
END AS segmento_estimado
FROM clientes
ORDER BY ingreso_mensual_declarado_mxn DESC; 

SELECT cliente_id, nombre_completo, ingreso_mensual_declarado_mxn, 
CASE 
WHEN ingreso_mensual_declarado_mxn >= 75000 THEN 'Premier'
WHEN ingreso_mensual_declarado_mxn >= 35000 THEN 'Advance / One'
ELSE 'Retail'
END AS segmento_estimado
FROM clientes
WHERE tipo_persona = 'Fisica'
ORDER BY ingreso_mensual_declarado_mxn DESC; 

-- Promedio historico de monto por cuenta (paso base, antes de comparar desviaciones)

SELECT cl.cliente_id, cl.nombre_completo, t.cuenta_id, 
COUNT(*) AS numero_transacciones, 
AVG(t.monto_mxn) AS promedio_historico_mxn
FROM transacciones t 
JOIN cuentas c ON c.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = c.cliente_id
GROUP BY cl.cliente_id, cl.nombre_completo, t.cuenta_id
ORDER BY promedio_historico_mxn DESC
LIMIT 20

-- Detecta cuentas con al menos una transaccion muy por encima de su propio promedio historico

SELECT cl.cliente_id, cl.nombre_completo, t.cuenta_id, 
COUNT(*) AS numero_transacciones, 
ROUND(AVG(t.monto_mxn), 2) AS promedio_historico_mxn, 
MAX(t.monto_mxn) AS transaccion_maxima_mxn, 
ROUND(MAX(t.monto_mxn) / AVG(t.monto_mxn), 1) AS veces_sobre_promedio
FROM transacciones t 
JOIN cuentas c ON c.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = c.cliente_id
GROUP BY cl.cliente_id, cl.nombre_completo, t.cuenta_id
HAVING MAX(t.monto_mxn) > 10 * AVG(t.monto_mxn)
 ORDER BY veces_sobre_promedio DESC;

-- Detalle transaccional de las cuentas con desviacion fuerte de su promedio
-- Permite ver si el monto atipico fue un evento unico o parte de un patron repetido

SELECT cl.cliente_id, cl.nombre_completo, t.transaccion_id, t.fecha_hora, 
YEAR(t.fecha_hora) AS anio, t.monto_mxn, t.tipo_transaccion
FROM transacciones t
JOIN cuentas c ON c.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = c.cliente_id
WHERE t.cuenta_id IN (780,56,288,520,576,554,86,156,121,332,284,252,200,408,368,488,514,292,596,296,390,196)
ORDER BY t.cuenta_id, t.monto_mxn DESC; 

-- Detecta cuentas con al menos una transaccion domestica muy por encima de su propio promedio
-- Excluye Transferencia Internacional: esas ya se investigaron a fondo en la Seccion 2 (OFAC)

SELECT
    cl.cliente_id,
    cl.nombre_completo,
    t.cuenta_id,
    COUNT(*) AS numero_transacciones,
    ROUND(AVG(t.monto_mxn), 2) AS promedio_historico_mxn,
    MAX(t.monto_mxn) AS transaccion_maxima_mxn,
    ROUND(MAX(t.monto_mxn) / AVG(t.monto_mxn), 1) AS veces_sobre_promedio
FROM transacciones t
JOIN cuentas c   ON c.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = c.cliente_id
WHERE t.tipo_transaccion <> 'Transferencia Internacional'
GROUP BY cl.cliente_id, cl.nombre_completo, t.cuenta_id
HAVING MAX(t.monto_mxn) > 10 * AVG(t.monto_mxn)
ORDER BY veces_sobre_promedio DESC;

-- Cruce: cuentas con Monto Inusual (domestico) que TAMBIEN transfirieron a un pais OFAC

SELECT cl.cliente_id, cl.nombre_completo, cl.ingreso_mensual_declarado_mxn, t.cuenta_id, 
COUNT(*) AS numero_transacciones,
ROUND(AVG(t.monto_mxn), 2) AS promedio_historico_mxn,
ROUND(MAX(t.monto_mxn) / AVG(t.monto_mxn), 1) AS veces_sobre_promedio
FROM transacciones t
JOIN cuentas c ON c.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = c.cliente_id
WHERE t.tipo_transaccion <> 'Transferencia Internacional'
AND t.cuenta_id IN (
SELECT DISTINCT t2.cuenta_id
FROM transacciones t2
JOIN paises p ON p.pais_id = t2.pais_destino_id
WHERE p.es_sancionado_ofac = TRUE 
)
GROUP BY cl.cliente_id, cl.nombre_completo, cl.ingreso_mensual_declarado_mxn, t.cuenta_id
HAVING MAX(t.monto_mxn) > 10 * AVG(t.monto_mxn)
ORDER BY veces_sobre_promedio DESC;

SELECT DISTINCT t2.cuenta_id
FROM transacciones t2
JOIN paises p ON p.pais_id = t2.pais_destino_id
WHERE p.es_sancionado_ofac = TRUE
ORDER BY t2.cuenta_id;

SELECT cr.caso_id, cr.cliente_id, cl.nombre_completo, cr.tipo_alerta, cr.detalle_alerta, cr.fecha_generacion, cr.fecha_cierre, cr.prioridad, cr.resultado, cr.es_caso_verdadero_ground_truth
FROM casos_revision_kyc cr 
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.tipo_alerta = 'Monto Inusual'
AND cr.cliente_id IN (554,156,121,252,200,408,368,514,292,596,296,196)
ORDER BY cr.cliente_id;

SELECT cliente_id, tipo_alerta, resultado, fecha_generacion 
FROM casos_revision_kyc
WHERE cliente_id IN (368, 296, 196)
ORDER BY cliente_id;

SELECT cl.cliente_id, cl.nombre_completo, cl.ingreso_mensual_declarado_mxn, t.transaccion_id, t.fecha_hora, t.monto_mxn, t.tipo_transaccion, t.canal
FROM transacciones t 
JOIN cuentas c ON c.cuenta_id = t.cuenta_id
JOIN clientes cl ON cl.cliente_id = c.cliente_id
WHERE t.cuenta_id = 296
ORDER BY t.fecha_hora;

-- ============================================================
-- RESUMEN EJECUTIVO — SECCION 3: MONTO INUSUAL VS. HISTORICO
-- ============================================================

-- HALLAZGOS:

-- Se detectaron 12 cuentas con al menos una transaccion domestica
-- (excluyendo Transferencia Internacional para no contaminar con
-- la Seccion 2 - OFAC) que supera entre 10.6 veces y 17.4 veces el promedio
-- historico de esa misma cuenta.
--
-- Caso mas alto: Ricardo Diaz Aguilar, $2,114,211.48 MXN vs. un
-- promedio historico de $121,281.23 MXN (17.4x). Fue escalado
-- correctamente a EDD y cerrado como Confirmado - Aviso a UIF:
-- el unico caso de esta seccion con desenlace de riesgo real
-- confirmado.
--
-- Al cruzar las 12 cuentas contra casos_revision_kyc, el
-- seguimiento se divide en tres grupos:
--
--   1) 9 cuentas SI tienen caso directo bajo "Monto Inusual":
--      8 cerradas como Falso Positivo / Cliente Contactado -
--      Aclarado, y 1 (Ricardo Diaz Aguilar) Confirmado - Aviso
--      a UIF.
--
--   2) 2 cuentas (196, 368) NO aparecen bajo "Monto Inusual", pero
--      SI existen bajo "Posible Prestanombres" - con fecha_generacion
--      y fecha_cierre identicas (cero tiempo transcurrido). Patron
--      que sugiere un cierre automatico/sello de goma en vez de una
--      revision real. Queda marcado para investigarse a fondo cuando
--      se trabaje la seccion dedicada a Prestanombres.
--
--   3) 1 cuenta (296, Lucia Ruiz Martinez - $470,349.10 MXN via
--      Transferencia SPEI, canal App) NO tiene NINGUN caso
--      registrado, bajo ninguna alerta. A diferencia de los otros
--      dos grupos, aqui no hubo revision de mala calidad: no hubo
--      revision en absoluto. Es un vacio de cobertura del
--      monitoreo, no un problema de gestion de un caso existente.
--
-- Cruce con Seccion 2 (OFAC): 0 clientes en comun - se confirma
-- que ambos grupos de riesgo son poblaciones independientes en
-- este dataset.
--
-- El monto de la transaccion, por si solo, no es buen indicador
-- de riesgo: varios de estos casos tienen explicacion legitima
-- (cheques de instituciones serias, SPEI entre cuentas propias o
-- familiares, finiquitos/indemnizaciones) y no deberian escalar
-- automaticamente a Cumplimiento.
--
-- RECOMENDACIONES:
--
-- 1. Aplicar un modelo de Tres Lineas de Defensa: la primera
--    revision la hace sucursal / ejecutivo de cuenta, solicitando
--    al cliente el origen del dinero y, de ser posible, evidencia
--    documental (contrato de compraventa, finiquito, comprobante
--    de la institucion que emite el cheque, etc.). Solo los casos
--    sin explicacion satisfactoria o con inconsistencias se
--    escalan a Cumplimiento/EDD - evitando sobresaturar al equipo
--    con alertas que ya tienen una razon logica detras.
--
-- 2. El proceso de escalacion SI funciona cuando el caso lo
--    amerita: el ejemplo de Ricardo Diaz Aguilar (+$2 millones) se
--    escalo correctamente a EDD y se resolvio como Confirmado -
--    Aviso a UIF. El modelo no esta roto, solo le falta un primer
--    filtro que reduzca el ruido antes de llegar a Cumplimiento.
--
-- 3. Regla operativa innegociable: una vez que el cliente deposita
--    el efectivo o cheque en ventanilla, el banco no puede
--    regresarlo sin poner al cliente en riesgo - el dinero SIEMPRE
--    se recibe y se resguarda en la cuenta. Lo que cambia segun el
--    resultado de la revision es si el caso se investiga a fondo o
--    se documenta y cierra como falso positivo.
--
-- 4. Cerrar el vacio de cobertura expuesto por la cuenta 296: la
--    regla de deteccion (>10x sobre el promedio historico de la
--    propia cuenta) debe implementarse como monitoreo automatico
--    real dentro del sistema, no solo quedar como hallazgo de este
--    analisis. De lo contrario seguiran existiendo transacciones
--    de riesgo real sin ningun registro.
--
-- 5. Los 2 casos bajo "Posible Prestanombres" con cierre en cero
--    tiempo (196, 368) quedan marcados para revision profunda
--    cuando se aborde esa seccion dedicada.
-- ============================================================





