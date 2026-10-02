USE kyc_aml_portafolio;
INSERT INTO paises (nombre_pais, codigo_iso3, es_sancionado_ofac, nivel_riesgo_pais, observaciones) VALUES
('Mexico',               'MEX', FALSE, 'Bajo',  'Pais de operacion del banco'),
('Estados Unidos',        'USA', FALSE, 'Bajo',  'Principal socio comercial'),
('Canada',                'CAN', FALSE, 'Bajo',  NULL),
('España',                'ESP', FALSE, 'Bajo',  NULL),
('Colombia',              'COL', FALSE, 'Medio', 'Alto volumen de remesas'),
('Panama',                'PAN', FALSE, 'Medio', 'Historial de opacidad corporativa'),
('China',                 'CHN', FALSE, 'Medio', 'Mayor escrutinio por comercio exterior'),
('Emiratos Arabes Unidos','ARE', FALSE, 'Medio', 'Centro financiero de mayor riesgo'),
('Corea del Norte',       'PRK', TRUE,  'Alto',  'Sancionado OFAC (uso educativo)'),
('Iran',                  'IRN', TRUE,  'Alto',  'Sancionado OFAC (uso educativo)'),
('Siria',                 'SYR', TRUE,  'Alto',  'Sancionado OFAC (uso educativo)'),
('Cuba',                  'CUB', TRUE,  'Alto',  'Sancionado OFAC (uso educativo)'),
('Venezuela',             'VEN', TRUE,  'Alto',  'Sancionado OFAC (uso educativo)'),
('Rusia',                 'RUS', TRUE,  'Alto',  'Sancionado OFAC (uso educativo)');
