-- =====================================================================
-- PROYECTO: Portafolio de Analista de Datos
-- =====================================================================

-- (mandato completo y pregunta de negocio raiz en el script de la
-- Seccion 1 - Estructuracion / Smurfing)
--
-- SECCION 2: PAIS SANCIONADO OFAC
-- Pregunta tecnica: ¿existen transacciones de clientes del banco
-- relacionadas, directa o indirectamente, con paises sancionados por
-- OFAC (ej. Corea del Norte, Iran, Siria, Cuba, Venezuela, Rusia)?
-- =====================================================================

-- QUERY 1: Paises marcados como sancionados OFAC en el catalogo
-- Confirma la lista de referencia antes de cruzarla contra transacciones

SELECT pais_id, nombre_pais, codigo_iso3, nivel_riesgo_pais
FROM paises 
WHERE es_sancionado_ofac = TRUE; 

-- QUERY 2: Transacciones de clientes hacia paises sancionados OFAC
-- Cruza las transacciones reales contra el catalogo de paises sancionados
-- y trae el cliente/cuenta involucrado

-- QUERY 3: Cuantas veces y cuanto ha movido cada cliente hacia paises OFAC
-- Agrupa la Query 3 por cliente para confirmar reincidencia y exposicion total

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
ORDER BY veces_ofac DESC, monto_total_mxn DESC;

-- QUERY 4: Catalogo de tipos de alerta existentes en casos_revision_kyc
-- Exploracion sin filtro, para encontrar el nombre exacto de la alerta OFAC

SELECT DISTINCT tipo_alerta
FROM casos_revision_kyc;

-- QUERY 5: Casos ya abiertos en Cumplimiento para los clientes con transferencias a paises OFAC
-- Confirma si ya fueron detectados y como se gestiono cada caso

SELECT cr.caso_id, cr.cliente_id, cl.nombre_completo, cr.tipo_alerta, cr.detalle_alerta, cr.fecha_generacion, cr.fecha_cierre, cr.prioridad, cr.resultado, cr.es_caso_verdadero_ground_truth
FROM casos_revision_kyc cr
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.tipo_alerta = 'Pais Sancionado OFAC'
AND cr.cliente_id IN (390,437,488,332,37,56,520,288,780,15,284,576,86,134)
ORDER BY cr.cliente_id;

-- QUERY 6: Dias que tardo Cumplimiento en cerrar cada caso de Pais Sancionado OFAC
-- Mide la velocidad de cierre para validar la hipotesis de revision superficial

SELECT cr.cliente_id, cl.nombre_completo, cr.detalle_alerta,
DATE_FORMAT(cr.fecha_generacion, '%d de %M de %Y') AS fecha_generacion_legible,
DATE_FORMAT(cr.fecha_cierre, '%d de %M de %Y') AS fecha_cierre_legible,
DATEDIFF(cr.fecha_cierre, cr.fecha_generacion) AS dias_para_cerrar, cr.resultado
FROM casos_revision_kyc cr
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.tipo_alerta = 'Pais Sancionado OFAC'
AND cr.cliente_id IN (390,437,488,332,37,56,520,288,780,15,284,576,86,134)
ORDER BY dias_para_cerrar ASC;

-- QUERY 7: Historial cronologico por cliente de casos OFAC (orden correcto)
-- Ordena por cliente y por fecha para leer la reincidencia en la secuencia real

SET lc_time_names = 'es_MX';
SELECT cr.cliente_id, cl.nombre_completo, cr.detalle_alerta,
DATE_FORMAT(cr.fecha_generacion, '%d de %M de %Y') AS fecha_generacion_legible,
DATEDIFF(cr.fecha_cierre, cr.fecha_generacion) AS dias_para_cerrar, cr.resultado
FROM casos_revision_kyc cr
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.tipo_alerta = 'Pais Sancionado OFAC'
AND cr.cliente_id IN (390,437,488,332,37,56,520,288,780,15,284,576,86,134)
ORDER BY cr.cliente_id, cr.fecha_generacion;

-- =====================================================================
-- RESUMEN EJECUTIVO — SECCION 2: PAIS SANCIONADO OFAC
-- =====================================================================

-- HALLAZGO PRINCIPAL
-- Se identificaron 14 clientes con 19 transferencias internacionales
-- hacia paises sancionados por OFAC (Corea del Norte, Iran, Siria,
-- Cuba, Venezuela, Rusia), con una exposicion acumulada de
-- $5,816,994.94 MXN. Los 19 casos ya generaron alerta en el sistema
-- de Cumplimiento (tipo_alerta = 'Pais Sancionado OFAC'), es decir,
-- el filtro de deteccion SI funciono. El problema no es deteccion,
-- es gestion: 12 de los 19 casos (63%) fueron cerrados como "Falso
-- Positivo" pese a tratarse de transferencias confirmadas hacia
-- jurisdicciones sancionadas.
--
-- INSIGHT DE NEGOCIO
-- De los 14 clientes, 5 reincidieron (transfirieron una segunda vez
-- a un pais OFAC). De esos 5, dos casos — Corporativo Comercio al
-- por menor Aguilar S.A. de C.V. (Cuba e Iran) y Karla Contreras
-- Perez (Corea del Norte y Rusia) — tuvieron AMBAS transferencias
-- cerradas como Falso Positivo, sin escalar nunca a EDD. Los otros 3
-- reincidentes (Juan Garcia Ramirez, Luis Vazquez Lopez, Jorge
-- Sanchez Ramos) si tuvieron alguna reaccion en la segunda ocasion,
-- pero de forma inconsistente y en un caso con 14 dias de demora
-- para escalar (Luis Vazquez Lopez, segunda transferencia a Siria).
-- Dato relevante: 2 clientes de una sola ocurrencia (Raul Lopez
-- Mendoza, Lucia Ortiz Salazar) SI fueron escalados correctamente a
-- EDD desde su primera transferencia. Esto confirma que el proceso
-- puede funcionar bien — el problema no es incapacidad del equipo,
-- es falta de un criterio uniforme aplicado a todos los casos por
-- igual.
--
-- RECOMENDACIONES A CUMPLIMIENTO
-- 1. Reclasificar de inmediato los 12 casos cerrados como Falso
--    Positivo y escalarlos a EDD para revision formal.
-- 2. Establecer una regla dura: ninguna transferencia confirmada
--    hacia un pais en la lista OFAC se cierra como Falso Positivo
--    sin evidencia documentada de justificacion de negocio (ej. giro
--    comercial que explique la operacion, como en el caso de la casa
--    de cambio).
-- 3. Ante una segunda transferencia del mismo cliente hacia un pais
--    OFAC, escalar automaticamente a EDD y evaluar restriccion o
--    bloqueo preventivo de transferencias internacionales a esas
--    jurisdicciones en la cuenta del cliente, en lugar de solo
--    generar otra alerta reactiva.
-- 4. Llevar un mejor control y documentacion de estos casos para
--    trazabilidad y evidencia ante auditoria.
-- 5. Abrir una revision de auditoria interna sobre la gestion previa
--    de los casos de Corporativo Aguilar y Karla Contreras Perez,
--    dado que ambos representan reincidencia total sin escalamiento.
-- 6. Actualizar el Instructivo de Trabajo de riesgo Alto (revision
--    anual) para que incluya un criterio explicito de manejo de
--    alertas OFAC, evitando que quede a discrecion de cada analista.
--
-- RIESGO DE NO ACTUAR
-- Una transferencia confirmada hacia un pais sancionado por OFAC no
-- admite el mismo margen de interpretacion que otros tipos de riesgo:
-- expone al banco a sanciones regulatorias, perdida de relaciones de
-- corresponsalia bancaria en Estados Unidos, multas 
-- y daño reputacional. Mientras el criterio de cierre siga
-- siendo inconsistente entre analistas, el banco permanece expuesto
-- a que un caso real se siga clasificando como ruido.
-- =====================================================================



















