-- =====================================================================
-- SECCIÓN 8: VALIDACIÓN FINAL DEL SISTEMA (PRECISIÓN Y RECALL)
-- =====================================================================
-- CONTEXTO DE NEGOCIO:
-- Las 7 secciones anteriores son, cada una, un tipo de fraude/riesgo
-- distinto (estructuración, país sancionado, monto inusual, velocidad,
-- UBO en lista negra, prestanombres, credential stuffing). Esta
-- sección ya NO detecta un fraude más: audita al sistema completo.
--
-- Ningún banco despliega un sistema de alertas PLD sin medir qué tan
-- bueno es. Un sistema con baja PRECISIÓN genera demasiado "ruido"
-- (falsos positivos) y satura al equipo de cumplimiento, que termina
-- revisando casos irrelevantes en vez de los que importan. Un sistema
-- con bajo RECALL deja pasar casos de riesgo reales sin ser detectados,
-- lo cual expone al banco a sanciones regulatorias y a ser usado para
-- lavado de dinero sin saberlo.
--
-- En este proyecto, la tabla ground_truth_casos_riesgo es la "verdad
-- conocida": son las entidades que se sembraron deliberadamente con un
-- patrón de riesgo específico al generar los datos sintéticos
-- (ver sql/postgres/05_inyectar_casos_riesgo.sql). Compararla contra lo
-- que las queries de detección SÍ marcaron (vw_alertas_consolidadas)
-- es el mismo ejercicio que hace un equipo de Data/Analytics cuando
-- audita o recalibra un modelo o una regla de negocio con datos
-- etiquetados.
--
-- PREGUNTA DE NEGOCIO:
-- De cada 100 casos de riesgo real que existen en la base, ¿cuántos
-- está atrapando nuestro sistema de alertas (recall)? Y de cada 100
-- alertas que el sistema dispara, ¿cuántas corresponden a un caso de
-- riesgo real y no son ruido (precisión)?
-- =====================================================================
SET search_path TO kyc, public;

-- ---------------------------------------------------------------------
-- QUERY 8.1: PRECISIÓN, RECALL Y F1-SCORE GLOBAL
-- Comparamos, a nivel (entidad + tipo de riesgo) -- no a nivel de cada
-- fila de alerta individual -- lo que el sistema SÍ detectó
-- (vw_alertas_consolidadas) contra la verdad conocida
-- (ground_truth_casos_riesgo). Colapsar a nivel entidad+tipo evita
-- inflar el conteo cuando una misma entidad disparó la misma alerta
-- varias veces (p. ej. 6 depósitos de estructuración = 1 solo caso,
-- no 6).
-- ---------------------------------------------------------------------
WITH alertas AS (
    SELECT DISTINCT tipo_entidad, entidad_id, tipo_alerta AS tipo_riesgo
    FROM kyc.vw_alertas_consolidadas
),
comparacion AS (
    SELECT
        gt.caso_id,
        gt.tipo_entidad,
        gt.entidad_id,
        gt.tipo_riesgo,
        (a.entidad_id IS NOT NULL) AS fue_detectado
    FROM kyc.ground_truth_casos_riesgo gt
    LEFT JOIN alertas a
           ON a.tipo_entidad = gt.tipo_entidad
          AND a.entidad_id   = gt.entidad_id
          AND a.tipo_riesgo  = gt.tipo_riesgo
),
conteos AS (
    SELECT
        count(*) FILTER (WHERE fue_detectado)     AS verdaderos_positivos,
        count(*) FILTER (WHERE NOT fue_detectado) AS falsos_negativos,
        (SELECT count(*) FROM alertas)             AS total_alertas_generadas
    FROM comparacion
)
SELECT
    verdaderos_positivos,
    falsos_negativos,
    (verdaderos_positivos + falsos_negativos)          AS total_casos_reales_ground_truth,
    total_alertas_generadas,
    (total_alertas_generadas - verdaderos_positivos)   AS falsos_positivos,
    round(verdaderos_positivos::numeric
          / NULLIF(total_alertas_generadas, 0), 3)      AS precision,
    round(verdaderos_positivos::numeric
          / NULLIF(verdaderos_positivos + falsos_negativos, 0), 3) AS recall,
    round(
        2.0 * (verdaderos_positivos::numeric / NULLIF(total_alertas_generadas, 0))
            * (verdaderos_positivos::numeric / NULLIF(verdaderos_positivos + falsos_negativos, 0))
        / NULLIF(
            (verdaderos_positivos::numeric / NULLIF(total_alertas_generadas, 0))
          + (verdaderos_positivos::numeric / NULLIF(verdaderos_positivos + falsos_negativos, 0))
        , 0)
    , 3)                                                 AS f1_score
FROM conteos;

-- Lectura de resultado: "precision" = de cada alerta que disparamos,
-- qué fracción correspondía a un caso realmente sembrado como riesgo.
-- "recall" = de cada caso realmente sembrado, qué fracción alcanzamos
-- a atrapar con las 7 queries. F1 resume ambas en un solo número
-- cuando hay que comparar versiones del sistema entre sí.
