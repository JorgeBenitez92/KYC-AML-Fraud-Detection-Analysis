-- ============================================================
-- SECCION 5: UBO EN LISTA NEGRA
-- ============================================================

-- Pregunta de negocio: ¿Que personas morales (empresas) clientes
-- del Banco tienen entre sus beneficiarios finales (UBO) a alguien
-- que aparece marcado en lista negra?
--
-- Ver archivo de Seccion 1 (Estructuracion) para el mandato
-- completo del proyecto.
-- ============================================================

-- Query 1: Quiero ver todas las personas en lista negra (UBO y no-UBO), para dimensionar el universo antes de filtrar

SELECT nombre_socio, porcentaje_participacion, es_beneficiario_final_ubo
FROM personas_morales_socios
WHERE en_lista_negra = TRUE 

-- Query 2: Empresas cuyos UBO (beneficiario final) estan en lista negra

SELECT nombre_socio, porcentaje_participacion, cl.nombre_completo AS nombre_empresa, cl.nivel_riesgo_kyc_onboarding, cl.cliente_id
FROM personas_morales_socios pm
JOIN clientes cl ON cl.cliente_id = pm.cliente_id
WHERE en_lista_negra = TRUE AND es_beneficiario_final_ubo = TRUE
ORDER BY porcentaje_participacion DESC;

-- Query 3: Cruce de las empresas con UBO en lista negra contra casos_revision_kyc

SELECT cr.caso_id, cr.cliente_id, cl.nombre_completo, cr.tipo_alerta, cr.detalle_alerta, cr.fecha_generacion, cr.fecha_cierre, cr.resultado, cr.es_caso_verdadero_ground_truth
FROM casos_revision_kyc cr
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.cliente_id IN (202, 738, 205, 569, 219, 666, 562)
ORDER BY cr.cliente_id;

-- Query 4: Estructura de la tabla casos_revision_kyc, para documentar
-- que columnas existen realmente al cerrar un caso -- y demostrar que
-- NO hay una columna que capture el detalle/motivo de lo que encontro
-- Screening, KYC, PLD o EDD antes de decidir el resultado

DESCRIBE casos_revision_kyc;

-- Query 5: Horas invertidas y analista asignado en los 8 casos de UBO en
-- Lista Negra, para ver si los casos cerrados como Falso Positivo se
-- resolvieron con poco tiempo invertido (indicio de cierre a la ligera)

SELECT cr.caso_id, cr.cliente_id, cl.nombre_completo, cr.analista_asignado, cr.horas_invertidas, cr.prioridad, cr.resultado, cr.es_caso_verdadero_ground_truth
FROM casos_revision_kyc cr 
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.cliente_id IN (202, 738, 205, 569, 219, 666, 562)
AND cr.tipo_alerta = 'UBO en Lista Negra'
ORDER BY cr.horas_invertidas ASC;

-- ============================================================
-- RESUMEN EJECUTIVO -- SECCION 5: UBO EN LISTA NEGRA
-- ============================================================

-- UNIVERSO DETECTADO:
-- 9 personas fisicas marcadas en_lista_negra = TRUE dentro de
-- personas_morales_socios. De estas, 7 son beneficiario final (UBO)
-- de una empresa cliente del banco; 2 estan en lista negra pero NO
-- son UBO (participacion sin control real, no se investigan aqui).
--
-- Las 7 empresas con UBO en lista negra, por % de participacion:
-- Comercializadora Casa de Cambio Sanchez (Paola Benitez, 73.96%,
-- Venezuela) / Servicios Bienes Raices Gomez (Raul Garcia, 71.01%,
-- Mexico) / Industrias Construccion Vazquez (Carlos Chavez, 50.15%,
-- Mexico) / Servicios Bienes Raices Ortiz (Raul Vazquez, 42.47%,
-- Mexico) / Constructora Restaurantero Gonzalez (Karla Gonzalez,
-- 38.92%, Mexico, riesgo ALTO desde onboarding) / Industrias
-- Comercio al por menor Ramos (Juan Mendoza, 24.45%, COREA DEL
-- NORTE) / Soluciones Transporte y Logistica Salazar (Monica
-- Garcia, 22.10%, Mexico).
--
-- CRUCE CONTRA CASOS_REVISION_KYC:
-- Las 7 empresas generaron caso bajo tipo_alerta = "UBO en Lista
-- Negra", TODOS con es_caso_verdadero_ground_truth = 1 (el dataset
-- confirma que los 7 eran casos genuinos, no ruido). Resultado real:
--   - 5 de 7: Falso Positivo (incluye el cliente de riesgo ALTO)
--   - 1 de 7: Escalado a EDD (Raul Garcia, 738)
--   - 1 de 7: Cliente Contactado - Aclarado (Juan Mendoza, 666)
--
-- HALLAZGO 1 -- Cierre inconsistente con la verdad del dataset:
-- 5 de 7 casos confirmados como genuinos (ground_truth=1) se
-- cerraron como Falso Positivo, incluido el cliente 219, marcado
-- riesgo ALTO desde el onboarding. Se descarto la hipotesis de
-- "cierre a la ligera": horas_invertidas en los 7 casos va de 4.74
-- a 8.66 horas, consistente con trabajo real de verificacion (no
-- negligencia por tiempo). El schema de casos_revision_kyc (ver
-- DESCRIBE) NO tiene columna de motivo/detalle de resolucion, por
-- lo que no se puede auditar CON QUE evidencia se determino cada
-- Falso Positivo -- pudo ser identidad distinta comprobada (CURP,
-- fecha de nacimiento), o pudo ser un cierre sin sustento documentado.
-- Esta falta de trazabilidad es en si misma un hallazgo.
--
-- HALLAZGO 2 (ANCLA) -- Exposicion a sancion de Corea del Norte:
-- El caso 666 (Juan Mendoza, UBO 24.45%, nacionalidad Corea del
-- Norte) NO cerro como Falso Positivo -- cerro como "Cliente
-- Contactado - Aclarado", con 7.87 horas invertidas, indicando que
-- el banco identifico al UBO, lo confirmo, y decidio mantener la
-- relacion activa. A diferencia de Venezuela (sanciones selectivas,
-- dirigidas a personas/entidades especificas), Corea del Norte
-- opera bajo regimen de sancion INTEGRAL (OFAC) la sola
-- relacion financiera con una persona vinculada a la economia
-- norcoreana es en si misma el riesgo de sancion, independientemente
-- de si esa persona "aclaro" su situacion particular. Este es el
-- hallazgo de mayor severidad de la seccion: conflicto potencial
-- grave con el regimen de sanciones de EE.UU., con el mismo tipo de
-- exposicion que motivo el precedente real de CI Banco.
--
-- LIMITACION DE DATOS:
-- en_lista_negra es un campo booleano sin motivo -- no distingue
-- entre alguien en lista negra por buro de credito/morosidad
-- (posiblemente sin obligacion de aviso a UIF) y alguien en lista
-- negra por ser criminal o sancionado (obligacion clara de aviso a
-- UIF). Con el dataset actual, esta distincion no se puede resolver
-- de forma automatizada.
--
-- RECOMENDACIONES:
-- 1. Escalacion obligatoria a EDD para TODO match confirmado de UBO
--    en lista negra, sin importar el nivel de riesgo de onboarding.
--    A diferencia de alertas de comportamiento (Monto Inusual,
--    Rafagas), un match de lista negra es un control de screening,
--    no de monitoreo -- no admite discrecionalidad basada en riesgo.
-- 2. Repositorio centralizado de identificadores de criminales/
--    sancionados (CURP, RFC, huella dactilar, firma, fecha de
--    nacimiento) para automatizar el match de identidad y activar
--    salida no negociable de la cuenta completa de persona moral.
-- 3. Dataset de motivo de salida del banco, para diferenciar
--    morosidad/buro de credito de salida por criminalidad/sancion,
--    y saber cuales casos ameritan notificacion formal a UIF.
-- 4. Agregar trazabilidad obligatoria al cierre de casos (campo de
--    motivo/detalle de resolucion) para poder auditar en el futuro
--    si un Falso Positivo fue identidad distinta comprobada o un
--    cierre sin sustento documentado.
-- 5. Revision inmediata y prioritaria del caso 666 (UBO nacionalidad
--    Corea del Norte) por parte de Cumplimiento/Legal, dado el
--    riesgo de sancion de E.U.A. -- "Cliente Contactado -
--    Aclarado" no es resolucion suficiente para exposicion a un
--    regimen de sancion integral; se requiere validacion formal de
--    la relacion antes de mantenerla activa.
-- ============================================================
