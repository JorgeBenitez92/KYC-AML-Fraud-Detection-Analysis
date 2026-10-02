-- =====================================================================
-- SECCIÓN 8: VALIDACIÓN FINAL (PRECISIÓN Y RECALL) -- version MySQL
-- =====================================================================
USE kyc_aml_portafolio;

WITH

alertas_estructuracion AS (
    SELECT DISTINCT cliente_id, 'Cliente' AS tipo_entidad, 'Estructuracion' AS tipo_riesgo
    FROM (
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
        GROUP BY c.cuenta_id, cl.cliente_id, cl.nombre_completo, cl.tipo_persona,
                 cl.ciudad, cl.estado_republica, cl.ocupacion_giro, cl.ingreso_mensual_declarado_mxn
        HAVING COUNT(*) >= 13
    ) AS q1
),

alertas_pais_ofac AS (
    SELECT DISTINCT cliente_id, 'Cliente' AS tipo_entidad, 'Pais Sancionado OFAC' AS tipo_riesgo
    FROM (
        SELECT cl.cliente_id, cl.nombre_completo,
               COUNT(*) AS veces_ofac,
               SUM(t.monto_mxn) AS monto_total_mxn,
               MIN(t.fecha_hora) AS primera_transferencia,
               MAX(t.fecha_hora) AS ultima_transferencia
        FROM transacciones t
        JOIN paises p ON p.pais_id = t.pais_destino_id
        JOIN cuentas c ON c.cuenta_id = t.cuenta_id
        JOIN clientes cl ON cl.cliente_id = c.cliente_id
        WHERE p.es_sancionado_ofac = TRUE
        GROUP BY cl.cliente_id, cl.nombre_completo
    ) AS q2
),

alertas_monto_inusual AS (
    SELECT DISTINCT cliente_id, 'Cliente' AS tipo_entidad, 'Monto Inusual' AS tipo_riesgo
    FROM (
        SELECT cl.cliente_id, cl.nombre_completo, t.cuenta_id,
               COUNT(*) AS numero_transacciones,
               ROUND(AVG(t.monto_mxn), 2) AS promedio_historico_mxn,
               MAX(t.monto_mxn) AS transaccion_maxima_mxn,
               ROUND(MAX(t.monto_mxn) / AVG(t.monto_mxn), 1) AS veces_sobre_promedio
        FROM transacciones t
        JOIN cuentas c ON c.cuenta_id = t.cuenta_id
        JOIN clientes cl ON cl.cliente_id = c.cliente_id
        WHERE t.tipo_transaccion <> 'Transferencia Internacional'
        GROUP BY cl.cliente_id, cl.nombre_completo, t.cuenta_id
        HAVING MAX(t.monto_mxn) > 10 * AVG(t.monto_mxn)
    ) AS q3
),

alertas_velocidad AS (
    SELECT DISTINCT cl.cliente_id, 'Cliente' AS tipo_entidad, 'Velocidad Alta' AS tipo_riesgo
    FROM (
        SELECT cuenta_id,
               COUNT(*) AS numero_retiros,
               DATEDIFF(MAX(fecha_hora), MIN(fecha_hora)) AS dias_diferencia
        FROM transacciones
        WHERE tipo_transaccion = 'Retiro Efectivo'
        GROUP BY cuenta_id
        HAVING numero_retiros >= 3 AND dias_diferencia <= 7
    ) AS q4
    JOIN cuentas c ON c.cuenta_id = q4.cuenta_id
    JOIN clientes cl ON cl.cliente_id = c.cliente_id
),

alertas_ubo AS (
    SELECT DISTINCT socio_id AS entidad_id, 'Socio' AS tipo_entidad, 'UBO en Lista Negra' AS tipo_riesgo
    FROM (
        SELECT pm.socio_id, pm.nombre_socio, pm.porcentaje_participacion,
               cl.nombre_completo AS nombre_empresa, cl.nivel_riesgo_kyc_onboarding, cl.cliente_id
        FROM personas_morales_socios pm
        JOIN clientes cl ON cl.cliente_id = pm.cliente_id
        WHERE pm.en_lista_negra = TRUE AND pm.es_beneficiario_final_ubo = TRUE
    ) AS q5
),

alertas_prestanombres AS (
    SELECT DISTINCT cliente_id, 'Cliente' AS tipo_entidad, 'Posible Prestanombres' AS tipo_riesgo
    FROM (
        SELECT DISTINCT ia.dispositivo_id, ia.cliente_id, cl.nombre_completo, cl.nivel_riesgo_kyc_onboarding
        FROM intentos_acceso ia
        JOIN clientes cl ON cl.cliente_id = ia.cliente_id
        WHERE ia.dispositivo_id IN ('DEV-67FB306831', 'DEV-917C07F483', 'DEV-F6032BE7C2', 'DEV-FC8DB4B3C9')
    ) AS q6
),

alertas_credential_stuffing AS (
    SELECT DISTINCT cliente_id, 'Cliente' AS tipo_entidad, 'Credential Stuffing / Fuerza Bruta' AS tipo_riesgo
    FROM (
        SELECT cliente_id,
               COUNT(*) AS intentos_fallidos,
               COUNT(DISTINCT ip_origen) AS ips_distintas
        FROM intentos_acceso
        WHERE exitoso = 0
        GROUP BY cliente_id
        HAVING intentos_fallidos >= 5
    ) AS q7
),

alertas AS (
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_estructuracion
    UNION ALL
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_pais_ofac
    UNION ALL
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_monto_inusual
    UNION ALL
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_velocidad
    UNION ALL
    SELECT tipo_entidad, entidad_id, tipo_riesgo FROM alertas_ubo
    UNION ALL
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_prestanombres
    UNION ALL
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_credential_stuffing
),

comparacion AS (
    SELECT
        gt.caso_id,
        gt.tipo_entidad,
        gt.entidad_id,
        gt.tipo_riesgo,
        (a.entidad_id IS NOT NULL) AS fue_detectado
    FROM ground_truth_casos_riesgo gt
    LEFT JOIN alertas a
           ON a.tipo_entidad = gt.tipo_entidad
          AND a.entidad_id   = gt.entidad_id
          AND a.tipo_riesgo  = gt.tipo_riesgo
),

conteos AS (
    SELECT
        SUM(fue_detectado)     AS verdaderos_positivos,
        SUM(1 - fue_detectado) AS falsos_negativos,
        (SELECT COUNT(*) FROM alertas) AS total_alertas_generadas
    FROM comparacion
)

SELECT
    verdaderos_positivos,
    falsos_negativos,
    (verdaderos_positivos + falsos_negativos)        AS total_casos_reales_ground_truth,
    total_alertas_generadas,
    (total_alertas_generadas - verdaderos_positivos) AS falsos_positivos,
    ROUND(verdaderos_positivos / NULLIF(total_alertas_generadas, 0), 3) AS precision_sistema,
    ROUND(verdaderos_positivos / NULLIF(verdaderos_positivos + falsos_negativos, 0), 3) AS recall_sistema,
    ROUND(
        2.0 * (verdaderos_positivos / NULLIF(total_alertas_generadas, 0))
            * (verdaderos_positivos / NULLIF(verdaderos_positivos + falsos_negativos, 0))
        / NULLIF(
            (verdaderos_positivos / NULLIF(total_alertas_generadas, 0))
          + (verdaderos_positivos / NULLIF(verdaderos_positivos + falsos_negativos, 0))
        , 0)
    , 3) AS f1_score
FROM conteos;

-- =====================================================================
-- QUERY 8.2: DESGLOSE DE RECALL POR TIPO DE RIESGO
-- De cada una de las 7 categorias, cuantos casos reales (ground truth)
-- SI se detectaron y cuantos se quedaron sin detectar. Util para ver
-- en que seccion especifica esta fallando el recall, en vez de un
-- numero global que esconde el detalle.
--
-- (Nota tecnica: un CTE (WITH ...) solo vive dentro de UN statement en
-- MySQL, por eso aqui abajo se repite la misma definicion de "alertas"
-- -- no es un error de copy/paste, es necesario para que esta segunda
-- query tambien pueda usarla.)
-- =====================================================================
WITH

alertas_estructuracion AS (
    SELECT DISTINCT cliente_id, 'Cliente' AS tipo_entidad, 'Estructuracion' AS tipo_riesgo
    FROM (
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
        GROUP BY c.cuenta_id, cl.cliente_id, cl.nombre_completo, cl.tipo_persona,
                 cl.ciudad, cl.estado_republica, cl.ocupacion_giro, cl.ingreso_mensual_declarado_mxn
        HAVING COUNT(*) >= 13
    ) AS q1
),

alertas_pais_ofac AS (
    SELECT DISTINCT cliente_id, 'Cliente' AS tipo_entidad, 'Pais Sancionado OFAC' AS tipo_riesgo
    FROM (
        SELECT cl.cliente_id, cl.nombre_completo,
               COUNT(*) AS veces_ofac,
               SUM(t.monto_mxn) AS monto_total_mxn,
               MIN(t.fecha_hora) AS primera_transferencia,
               MAX(t.fecha_hora) AS ultima_transferencia
        FROM transacciones t
        JOIN paises p ON p.pais_id = t.pais_destino_id
        JOIN cuentas c ON c.cuenta_id = t.cuenta_id
        JOIN clientes cl ON cl.cliente_id = c.cliente_id
        WHERE p.es_sancionado_ofac = TRUE
        GROUP BY cl.cliente_id, cl.nombre_completo
    ) AS q2
),

alertas_monto_inusual AS (
    SELECT DISTINCT cliente_id, 'Cliente' AS tipo_entidad, 'Monto Inusual' AS tipo_riesgo
    FROM (
        SELECT cl.cliente_id, cl.nombre_completo, t.cuenta_id,
               COUNT(*) AS numero_transacciones,
               ROUND(AVG(t.monto_mxn), 2) AS promedio_historico_mxn,
               MAX(t.monto_mxn) AS transaccion_maxima_mxn,
               ROUND(MAX(t.monto_mxn) / AVG(t.monto_mxn), 1) AS veces_sobre_promedio
        FROM transacciones t
        JOIN cuentas c ON c.cuenta_id = t.cuenta_id
        JOIN clientes cl ON cl.cliente_id = c.cliente_id
        WHERE t.tipo_transaccion <> 'Transferencia Internacional'
        GROUP BY cl.cliente_id, cl.nombre_completo, t.cuenta_id
        HAVING MAX(t.monto_mxn) > 10 * AVG(t.monto_mxn)
    ) AS q3
),

alertas_velocidad AS (
    SELECT DISTINCT cl.cliente_id, 'Cliente' AS tipo_entidad, 'Velocidad Alta' AS tipo_riesgo
    FROM (
        SELECT cuenta_id,
               COUNT(*) AS numero_retiros,
               DATEDIFF(MAX(fecha_hora), MIN(fecha_hora)) AS dias_diferencia
        FROM transacciones
        WHERE tipo_transaccion = 'Retiro Efectivo'
        GROUP BY cuenta_id
        HAVING numero_retiros >= 3 AND dias_diferencia <= 7
    ) AS q4
    JOIN cuentas c ON c.cuenta_id = q4.cuenta_id
    JOIN clientes cl ON cl.cliente_id = c.cliente_id
),

alertas_ubo AS (
    SELECT DISTINCT socio_id AS entidad_id, 'Socio' AS tipo_entidad, 'UBO en Lista Negra' AS tipo_riesgo
    FROM (
        SELECT pm.socio_id, pm.nombre_socio, pm.porcentaje_participacion,
               cl.nombre_completo AS nombre_empresa, cl.nivel_riesgo_kyc_onboarding, cl.cliente_id
        FROM personas_morales_socios pm
        JOIN clientes cl ON cl.cliente_id = pm.cliente_id
        WHERE pm.en_lista_negra = TRUE AND pm.es_beneficiario_final_ubo = TRUE
    ) AS q5
),

alertas_prestanombres AS (
    SELECT DISTINCT cliente_id, 'Cliente' AS tipo_entidad, 'Posible Prestanombres' AS tipo_riesgo
    FROM (
        SELECT DISTINCT ia.dispositivo_id, ia.cliente_id, cl.nombre_completo, cl.nivel_riesgo_kyc_onboarding
        FROM intentos_acceso ia
        JOIN clientes cl ON cl.cliente_id = ia.cliente_id
        WHERE ia.dispositivo_id IN ('DEV-67FB306831', 'DEV-917C07F483', 'DEV-F6032BE7C2', 'DEV-FC8DB4B3C9')
    ) AS q6
),

alertas_credential_stuffing AS (
    SELECT DISTINCT cliente_id, 'Cliente' AS tipo_entidad, 'Credential Stuffing / Fuerza Bruta' AS tipo_riesgo
    FROM (
        SELECT cliente_id,
               COUNT(*) AS intentos_fallidos,
               COUNT(DISTINCT ip_origen) AS ips_distintas
        FROM intentos_acceso
        WHERE exitoso = 0
        GROUP BY cliente_id
        HAVING intentos_fallidos >= 5
    ) AS q7
),

alertas AS (
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_estructuracion
    UNION ALL
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_pais_ofac
    UNION ALL
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_monto_inusual
    UNION ALL
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_velocidad
    UNION ALL
    SELECT tipo_entidad, entidad_id, tipo_riesgo FROM alertas_ubo
    UNION ALL
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_prestanombres
    UNION ALL
    SELECT tipo_entidad, cliente_id AS entidad_id, tipo_riesgo FROM alertas_credential_stuffing
)

SELECT
    gt.tipo_riesgo,
    COUNT(*) AS casos_reales,
    SUM(a.entidad_id IS NOT NULL) AS detectados,
    COUNT(*) - SUM(a.entidad_id IS NOT NULL) AS no_detectados,
    ROUND(SUM(a.entidad_id IS NOT NULL) / COUNT(*), 3) AS recall_de_la_categoria
FROM ground_truth_casos_riesgo gt
LEFT JOIN alertas a
       ON a.tipo_entidad = gt.tipo_entidad
      AND a.entidad_id   = gt.entidad_id
      AND a.tipo_riesgo  = gt.tipo_riesgo
GROUP BY gt.tipo_riesgo
ORDER BY recall_de_la_categoria ASC;

-- ============================================================
-- RESUMEN EJECUTIVO -- SECCION 8: VALIDACION FINAL (PRECISION Y RECALL)
-- ============================================================

-- RESULTADO GLOBAL:
-- El sistema completo de deteccion (las 7 queries de las Secciones
-- 1-7, corridas juntas) alcanzo 86.0% de precision y 81.3% de recall
-- (F1 = 0.836) contra los 91 casos de riesgo real sembrados en el
-- dataset. De las 86 alertas generadas, 74 correspondieron a casos
-- genuinos y 12 fueron falsos positivos; de los 91 casos reales, 17
-- se quedaron sin detectar por ninguna de las 7 queries.
--
-- HALLAZGO PRINCIPAL -- el promedio esconde una categoria en cero:
-- El 81.3% de recall global NO esta repartido parejo entre las 7
-- categorias. El desglose por tipo de riesgo (Query 8.2) muestra:
--   Estructuracion                        100% (16/16)
--   Pais Sancionado OFAC                  100% (14/14)
--   Posible Prestanombres                 100% (12/12)
--   Credential Stuffing / Fuerza Bruta    100% (15/15)
--   Monto Inusual                        83.3% (10/12)
--   UBO en Lista Negra                   77.8% (7/9)
--   Velocidad Alta                         0.0% (0/13)
-- Cuatro de siete categorias detectan el 100% de sus casos reales.
-- Pero "Velocidad Alta" -- 13 casos reales, el segundo grupo mas
-- grande del dataset -- tiene 0% de deteccion: el sistema jamas
-- atrapo NINGUNO de esos 13 casos.
--
-- INSIGHT DE NEGOCIO:
-- El 0% de Velocidad Alta no es un error de sintaxis ni una query
-- rota -- corre sin problema y SI detecta un patron de riesgo real
-- (rafagas de retiro de efectivo en ventana de 7 dias, asociado a
-- cuenta comprometida o fraude con tarjeta fisica, ver Seccion 4).
-- El problema es un desalineamiento de definicion: el riesgo que
-- efectivamente se sembro en el dataset para esta categoria fue
-- "6 a 10 transacciones concentradas en menos de 15 minutos" (firma
-- de prueba de tarjeta / toma de control automatizada), una ventana
-- de tiempo y un tipo de transaccion distintos a los que la query
-- de deteccion busca. Esto demuestra algo que ningun numero agregado
-- revela por si solo: un KPI consolidado de "81% de recall" puede
-- esconder una categoria completa con cobertura real de cero. Es el
-- mismo patron de falta de granularidad senalado como hallazgo en
-- las Secciones 3, 4, 5 y 6 sobre casos_revision_kyc -- aqui se
-- repite, ahora a nivel de medicion del propio sistema de deteccion.
--
-- En Monto Inusual (83.3%) y UBO en Lista Negra (77.8%) las fugas si
-- son decisiones de diseno conscientes y defendibles, no errores:
-- Monto Inusual excluye a proposito las Transferencias Internacionales
-- (para no duplicar lo que ya cubre Pais Sancionado OFAC), y UBO en
-- Lista Negra solo marca a quien es beneficiario final, dejando fuera
-- a socios minoritarios que tambien estan en lista negra pero sin
-- control real de la empresa. Son decisiones de alcance razonables,
-- pero cuestan puntos de recall que deben quedar documentados, no
-- descubrirse hasta una auditoria externa.
--
-- RECOMENDACIONES:
-- 1. Nunca reportar la efectividad del sistema de alertas como un
--    solo numero agregado -- siempre acompañarlo del desglose por
--    tipo de alerta (Query 8.2), porque el promedio esconde
--    categorias con cobertura cero.
-- 2. Revisar y redefinir el criterio de "Velocidad Alta" junto con
--    Seguridad/Fraude: decidir si el banco quiere monitorear rafagas
--    de transacciones en minutos (toma de control / prueba de
--    tarjeta), rafagas de retiro de efectivo en dias (patron
--    distinto, igual de valido), o ambas como alertas separadas --
--    hoy solo se cubre una de las dos.
-- 3. Documentar explicitamente el alcance y las exclusiones de cada
--    regla de deteccion (ej. "Monto Inusual excluye transferencias
--    internacionales porque ya las cubre OFAC", "UBO en Lista Negra
--    solo marca beneficiarios finales") para que una revision futura
--    no confunda una decision de diseno con un defecto.
-- 4. Repetir esta validacion cada vez que se modifique una query de
--    deteccion o se agregue una categoria de riesgo nueva -- es la
--    unica forma objetiva de saber si un cambio mejoro o empeoro la
--    cobertura real del sistema, en vez de confiar en percepcion.
-- 5. Para el dashboard de Power BI: incluir este desglose de
--    precision/recall por categoria como KPI permanente, no solo el
--    conteo de alertas generadas -- contar alertas sin saber cuantas
--    son reales mide actividad, no efectividad.
--
-- RIESGO DE NO ACTUAR:
-- Un sistema reportado como "81% de recall" sin desglose por
-- categoria puede dar a Cumplimiento y Auditoria una falsa sensacion
-- de cobertura total, cuando en realidad una categoria completa de
-- riesgo (rafagas de transacciones) tiene deteccion real de cero.
-- Ante una revision regulatoria o un incidente real de ese tipo, el
-- banco no podria sostener que "el sistema funciona bien en general"
-- si el tipo de fraude ocurrido es precisamente el que nunca se
-- detecto.
-- ============================================================
