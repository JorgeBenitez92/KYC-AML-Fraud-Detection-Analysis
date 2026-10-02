-- ============================================================
-- SECCION 7: CREDENTIAL STUFFING / FUERZA BRUTA
-- ============================================================

-- Pregunta de negocio: ¿Que clientes muestran patrones de acceso
-- (intentos fallidos repetidos, desde multiples IPs, en ventanas de
-- tiempo muy cortas) compatibles con un ataque de fuerza bruta o
-- credential stuffing sobre su cuenta de Banca Movil/Digital?

-- Ver archivo de Seccion 1 (Estructuracion) para el mandato
-- completo del proyecto.
-- ============================================================

-- Query 1: Total de intentos fallidos y numero de IPs distintas por
-- cliente, para detectar el patron clasico de fuerza bruta/credential
-- stuffing (muchos fallos, desde muchas IPs distintas)

SELECT cliente_id,
COUNT(*) AS intentos_fallidos, 
COUNT(DISTINCT ip_origen) AS ips_distintas 
FROM intentos_acceso
WHERE exitoso = 0 
GROUP BY cliente_id 
HAVING intentos_fallidos >= 5 
ORDER BY ips_distintas DESC, intentos_fallidos DESC;

-- Query 2: Primer y ultimo intento fallido por cliente, en fechas en
-- español y con la diferencia en minutos, para ver si los intentos
-- estan concentrados en pocos minutos (sospechoso) o repartidos en
-- mucho tiempo (normal, error humano ocasional)

SET lc_time_names = 'es_MX';

SELECT cliente_id,
COUNT(*) AS intentos_fallidos,
COUNT(DISTINCT ip_origen) AS ips_distintas, 
DATE_FORMAT(MIN(fecha_hora), '%W %d de %M de %Y hora %h:%i %p') AS primer_intento,
DATE_FORMAT(MAX(fecha_hora), '%W %d de %M de %Y hora %h:%i %p') AS ultimo_intento, 
TIMESTAMPDIFF(MINUTE, MIN(fecha_hora), MAX(fecha_hora)) AS minutos_diferencia
FROM intentos_acceso 
WHERE exitoso = 0 
GROUP BY cliente_id
HAVING intentos_fallidos >= 5 
ORDER BY minutos_diferencia ASC;

-- Query 3: Cruce de los 17 clientes con patron de intentos fallidos
-- contra casos_revision_kyc, para ver que alertas generaron y si el
-- banco contacto al cliente o tomo alguna accion

SELECT cr.caso_id, cr.cliente_id, cl.nombre_completo, cr.tipo_alerta, cr.detalle_alerta, cr.fecha_generacion, cr.fecha_cierre, cr.resultado, cr.es_caso_verdadero_ground_truth
FROM casos_revision_kyc cr 
JOIN clientes cl ON cl.cliente_id = cr.cliente_id
WHERE cr.cliente_id IN (763, 615, 96, 347, 465, 649, 4, 521, 12, 207, 719, 190, 53, 599, 629, 26, 343)
ORDER BY cr.cliente_id;

-- Query 4: Detalle cronologico de cada intento fallido de los clientes
-- 12 y 207, para verificar si el "20 min" que dice la alerta es real y
-- nuestra Query 2 mezclo esa rafaga con fallos sueltos de otros dias

SELECT cliente_id, fecha_hora, ip_origen, exitoso
FROM intentos_acceso 
WHERE cliente_id IN (12, 207) AND exitoso = 0 
ORDER BY cliente_id, fecha_hora;

-- Query 5: Comparar el dispositivo de cada intento fallido de
-- Credential Stuffing contra el dispositivo registrado del cliente,
-- para probar si los ataques vinieron de dispositivos ajenos al
-- titular (no solo de IPs distintas)

SELECT ia.cliente_id, ia.dispositivo_id AS dispositivo_del_intento, cdc.dispositivo_id AS dispositivo_registrado, 
CASE WHEN ia.dispositivo_id = cdc.dispositivo_id THEN 'Mismo dispositivo' ELSE 'Dispositivo distinto' END AS comparacion
FROM intentos_acceso ia 
JOIN contacto_dispositivo_cliente cdc ON cdc.cliente_id = ia.cliente_id
WHERE ia.cliente_id IN (4, 12, 26, 53, 96, 190, 207, 343, 347, 465, 521, 615, 649, 719, 763)
AND ia.exitoso = 0 
ORDER BY ia.cliente_id, ia.fecha_hora;

-- Query 6: Dispositivo desde el cual se logro el acceso EXITOSO en
-- estos clientes, para confirmar si el atacante logro entrar
-- (dispositivo desconocido) o fue el titular real

SELECT ia.cliente_id, ia.fecha_hora, ia.ip_origen, ia.dispositivo_id AS dispositivo_del_acceso, cdc.dispositivo_id AS dispositivo_registrado, 
CASE WHEN ia.dispositivo_id = cdc.dispositivo_id THEN 'Titular real' ELSE 'Dispositivo desconocido (atacante)' END AS quien_entro
FROM intentos_acceso ia 
JOIN contacto_dispositivo_cliente cdc ON cdc.cliente_id = ia.cliente_id
WHERE ia.cliente_id IN (4, 12, 26, 53, 96, 190, 207, 343, 347, 465, 521, 615, 649, 719, 763)
AND ia.exitoso = 1 
ORDER BY ia.cliente_id, ia.fecha_hora;


-- ============================================================
-- RESUMEN EJECUTIVO -- SECCION 7: CREDENTIAL STUFFING / FUERZA BRUTA
-- ============================================================

-- METODOLOGIA:
-- Via intentos_acceso se detectaron clientes con 5+ intentos de
-- login fallidos. Se separaron en 3 grupos segun ventana de tiempo:
-- GRUPO A (10 clientes): rafaga de 14-27 minutos, 1 IP distinta por
--   intento, todos arrancando casi a la misma hora (21:58-21:59 PM)
--   sin importar el mes -- firma de ataque automatizado/programado.
-- GRUPO B (7 clientes): mismo patron de 1-IP-por-intento pero
--   repartido en semanas/meses -- ambiguo, podria ser ataque "low
--   and slow" o explicacion benigna, no se puede concluir con este
--   dataset.
-- GRUPO C (2 clientes, 599 y 629): 5 fallos desde 1 sola IP,
--   repartidos en 3 y 6 meses -- comportamiento humano normal.
--
-- CRUCE CONTRA CASOS_REVISION_KYC:
-- Los 15 clientes del Grupo A generaron caso "Credential Stuffing /
-- Fuerza Bruta", todos con es_caso_verdadero_ground_truth = 1. Se
-- verifico que el "20 min" del detalle_alerta es exacto (confirmado
-- con el detalle cronologico real de los clientes 12 y 207) -- la
-- deteccion es confiable.
--
-- HALLAZGO 1 -- Confirmacion de ataque automatizado por huella de
-- dispositivo: cada intento fallido vino no solo de una IP distinta,
-- sino tambien de un dispositivo "DEV-DESCONOCIDO-XXXXXX" distinto
-- cada vez -- doble rotacion de identidad, firma clasica de un bot,
-- no de un humano.
--
-- HALLAZGO 2 -- Recurrencia tras cierre: el cliente 207 (Laura Ortiz
-- Vazquez) registra un intento fallido adicional 11 dias DESPUES de
-- que su caso se cerro como "Cliente Contactado - Aclarado" --
-- evidencia directa de que cerrar sin contencion real deja la puerta
-- abierta para que el atacante reintente.
--
-- HALLAZGO 3 (ANCLA) -- Acceso comprobado sin escalacion real:
-- De los 15 clientes, 10 tienen un acceso EXITOSO confirmado desde
-- un dispositivo/IP desconocidos, dentro de la misma ventana de la
-- rafaga -- prueba directa de cuenta comprometida, no sospecha. Esos
-- 10 coinciden exactamente con los que el detalle_alerta marco como
-- "HUBO acceso exitoso despues". De esos 10 casos con compromiso
-- comprobado, NINGUNO se escalo como Confirmado o aviso a UIF: 7
-- cerraron Falso Positivo y 3 Cliente Contactado - Aclarado. El
-- UNICO caso escalado a EDD (cliente 190) es uno de los 5 donde el
-- atacante NUNCA logro entrar -- el ataque fallo. El sistema trato
-- con mas seriedad un ataque fallido que diez accesos comprobados.
--
-- LIMITACIONES DE DATOS:
-- No existe geolocalizacion de IP (ciudad/pais) en el dataset --
-- no se puede saber si los ataques vienen del extranjero o son
-- domesticos. Tampoco existe tabla de robo/extravio ni campo de
-- motivo/detalle de resolucion en casos_revision_kyc -- mismo hueco
-- senalado en las Secciones 3, 4, 5 y 6.
--
-- RECOMENDACIONES:
-- 1. Bloqueo automatico de cuenta ante intentos fallidos repetidos
--    desde dispositivos no registrados -- no depender solo de una
--    alerta pasiva que espera revision manual.
--
-- 2. Para CUALQUIER caso con acceso exitoso confirmado desde
--    dispositivo/IP desconocidos, accion obligatoria e inmediata:
--    invalidar la sesion, forzar cambio de NIP/contrasena, y avisar
--    proactivamente al cliente -- independientemente de si se
--    detecto robo de dinero en esa sesion, porque el atacante
--    conserva credenciales validas y puede reintentar cuando quiera.
--
-- 3. Integrar geolocalizacion de IP / threat intelligence para
--    enriquecer las alertas con ciudad y pais de origen.
--
-- 4. Agregar trazabilidad obligatoria (motivo/detalle) al cierre de
--    casos en casos_revision_kyc -- mismo hueco de las 6 secciones
--    anteriores, ya un patron sistemico de todo el proyecto.
--
-- 5. Corregir el criterio de priorizacion de Cumplimiento: debe
--    escalar segun el RESULTADO real (hubo acceso exitoso si/no), no
--    con un criterio que hoy trata mas grave un ataque fallido que
--    diez cuentas efectivamente comprometidas.
-- ============================================================
