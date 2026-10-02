# Revisión Trimestral de Riesgo PLD — Detección de Fraude KYC/AML

Proyecto de portafolio que simula el trabajo de un analista de datos dentro de un equipo de **Cumplimiento / PLD (Prevención de Lavado de Dinero)** en un banco. Simula también la relación jerárquica real de ese trabajo: un gerente de Cumplimiento que encarga el análisis y un analista que lo ejecuta y entrega conclusiones accionables, no solo código.

## Contexto de negocio (el encargo)

El área de Cumplimiento pidió una **revisión trimestral del histórico transaccional**. El trimestre anterior, la tasa de falsos positivos en las alertas automáticas fue muy alta: el equipo de revisión terminó invirtiendo la mayoría de sus horas en descartar ruido en lugar de investigar casos reales de riesgo.

Como gerente de Cumplimiento, el encargo hacia el analista fue:

1. Analizar la base histórica de transacciones, accesos y clientes.
2. Identificar los patrones de riesgo más relevantes para PLD: **estructuración, jurisdicciones sancionadas, comportamiento transaccional atípico, posibles préstanombres y toma de control de cuentas**.
3. Convertir ese análisis en **insights accionables**: qué tan grave es cada tipo de riesgo, dónde se concentra en la cartera, y qué se le recomienda a Cumplimiento y a Negocio para priorizar mejor sus recursos.
4. Entregar entre 4 y 10 recomendaciones basadas en datos — no en corazonadas.

### Pregunta de negocio raíz

> **¿Dónde está el riesgo real de PLD en nuestra cartera, y cómo optimizamos el proceso de revisión para enfocar los recursos del equipo en lo que de verdad importa?**

## Dataset

Base de datos relacional sintética (`kyc_aml_portafolio`, MySQL 8.0) con clientes, cuentas, transacciones, intentos de acceso, socios de personas morales y una tabla de países con bandera OFAC. Incluye una tabla `ground_truth_casos_riesgo` con 91 casos de riesgo sembrados deliberadamente al generar los datos — la "verdad conocida" que permite medir, y no solo asumir, si el sistema de detección realmente funciona.

## Insights principales

**1. El riesgo real no se concentra en un solo tipo — está repartido entre las 7 categorías.**
De los 91 casos de riesgo reales en la cartera, ninguna categoría domina de forma aplastante: Estructuración (16 casos), Credential Stuffing/Fuerza Bruta (15), País Sancionado OFAC (14), Velocidad Alta (13), Monto Inusual (12), Posible Préstanombres (12) y UBO en Lista Negra (9). Esto significa que concentrar recursos de revisión en un solo tipo de alerta (el error más común en equipos de Cumplimiento con poco tiempo) deja descubiertas las otras seis.

**2. La severidad no es igual al volumen — y eso cambia cómo se deben priorizar los recursos.**
Volumen y gravedad no son lo mismo. **País Sancionado OFAC** tiene el menor número de casos (14) pero la mayor severidad regulatoria: un solo caso no detectado expone al banco a sanciones internacionales, no solo a una multa administrativa. **UBO en Lista Negra** tiene aún menos casos (9) pero implica relación directa con personas ya identificadas como de alto riesgo a nivel estructural de la empresa. En el otro extremo, **Monto Inusual** es la señal más genérica y ambigua (puede ser un cliente con un ingreso extraordinario legítimo), por lo que es la que más tolerancia a falsos positivos amerita.

**3. El hallazgo más grave no son los falsos positivos — es una categoría con cobertura real de cero.**
El sistema de reglas actual alcanza 81.3% de recall global, pero ese número agregado esconde que **"Velocidad Alta" (el segundo grupo de riesgo más grande, 13 de 91 casos) nunca detectó ni un solo caso real (0%)**. No es una falla de código: la regla corre bien y sí detecta un patrón de riesgo válido (ráfagas de retiros en 7 días). El problema es que el riesgo que realmente se sembró en los datos para esta categoría fue otro patrón — ráfagas de 6 a 10 transacciones concentradas en menos de 15 minutos, firma típica de prueba de tarjeta o toma de control automatizada de cuenta — y la regla actual busca una ventana de tiempo distinta. Esto es exactamente el tipo de brecha que un reporte de "81% de recall" sin desglose jamás revelaría, y es más riesgoso para el banco que cualquier falso positivo: da una falsa sensación de cobertura total.

**4. Las otras dos brechas de recall sí son decisiones de diseño conscientes, no errores — pero deben quedar documentadas.**
"Monto Inusual" (83.3% de recall) excluye a propósito las transferencias internacionales porque ya las cubre la regla de País Sancionado OFAC, y "UBO en Lista Negra" (77.8%) solo marca a quien es beneficiario final, dejando fuera a socios minoritarios en lista negra sin control real de la empresa. Son exclusiones razonables, pero si no se documentan, una auditoría externa puede confundir una decisión de alcance con una falla del sistema.

**5. El ruido de falsos positivos existe, pero es manejable — el problema de fondo es la falta de desglose, no solo el volumen.**
De las 86 alertas generadas por las 7 reglas, 12 fueron falsos positivos (14% del total). Es un nivel razonable, no el que describió el trimestre anterior — lo que confirma que gran parte del problema de "quemar horas en ruido" no viene del volumen de falsos positivos en sí, sino de que el equipo revisa alertas sin saber cuáles categorías son confiables (100% de precisión histórica) y cuáles necesitan más escrutinio.

## Recomendaciones

1. **Redefinir "Velocidad Alta" antes que cualquier otra mejora.** Es la única categoría con 0% de cobertura real y el segundo grupo de riesgo más grande de la cartera (14% de los 91 casos). Decidir junto con Seguridad/Fraude si el banco quiere monitorear ráfagas en minutos (toma de control/prueba de tarjeta), ráfagas de retiro en días (patrón distinto, igual de válido), o ambas como alertas separadas.
2. **Tratar a País Sancionado OFAC como la categoría de mayor severidad regulatoria, no la de mayor volumen.** Mantener su 100% de recall actual como no negociable, con revisión más frecuente que trimestral dado el riesgo de sanciones internacionales por un solo caso no detectado.
3. **Reportar siempre el desglose de precisión/recall por categoría, nunca solo el número agregado.** Un "81% de recall" global esconde que una categoría completa tiene cobertura real de cero — el promedio es el peor lugar para detectar ese tipo de brecha.
4. **Documentar explícitamente el alcance y las exclusiones de cada regla** (ej. "Monto Inusual excluye transferencias internacionales porque ya las cubre OFAC", "UBO en Lista Negra solo marca beneficiarios finales") para que una revisión futura no confunda una decisión de diseño con un defecto.
5. **Redistribuir las horas del equipo de revisión según dónde se concentra el riesgo real, no según el volumen de alertas.** Como el riesgo está repartido de forma pareja entre las 7 categorías (9 a 16 casos cada una), ningún analista debería estar dedicado desproporcionadamente a un solo tipo de alerta mientras otras categorías de alta severidad (OFAC, UBO) quedan con menos atención.
6. **Cerrar las brechas conocidas de las 7 reglas actuales antes de agregar reglas nuevas.** Agregar más categorías de detección sin resolver Velocidad Alta (0%), UBO (77.8%) y Monto Inusual (83.3%) no reduce el riesgo real — solo agrega más alertas que el equipo tiene que revisar.
7. **Incorporar timestamp de generación a nivel de caso en el sistema de alertas.** Hoy no se puede medir tendencia temporal (ej. picos de alertas por trimestre), lo cual es información crítica para dimensionar la carga de trabajo del equipo de revisión y planear capacidad con anticipación.
8. **Repetir esta validación (alertas vs. ground truth) cada trimestre o cada vez que se modifique una regla.** Es la única forma objetiva de saber si un cambio realmente redujo el riesgo no detectado o solo lo movió de categoría — reemplaza la percepción por medición.

## Metodología: 7 reglas de detección en SQL

Cada regla es una consulta SQL independiente, guardada como vista en la base de datos:

| # | Regla | Qué detecta |
|---|---|---|
| 1 | **Estructuración** | Clientes con 13+ depósitos en efectivo de entre $120,000 y $149,999 MXN — justo por debajo del umbral de reporte regulatorio, patrón clásico de fraccionamiento para evadir reportes. |
| 2 | **País Sancionado (OFAC)** | Transferencias hacia países marcados como sancionados por OFAC. |
| 3 | **Monto Inusual** | Transacciones domésticas cuyo monto máximo supera 10 veces el promedio histórico de la cuenta (se excluyen transferencias internacionales a propósito, para no duplicar lo que ya cubre la regla de País Sancionado). |
| 4 | **Velocidad Alta** | Cuentas con 3 o más retiros de efectivo concentrados en una ventana de 7 días. |
| 5 | **UBO en Lista Negra** | Socios beneficiarios finales (UBO) de una empresa que están marcados en lista negra. |
| 6 | **Posible Préstanombres** | Clientes cuyos accesos provienen de un dispositivo ya identificado como asociado a actividad sospechosa — firma de cuentas usadas para ocultar al verdadero dueño. |
| 7 | **Credential Stuffing / Fuerza Bruta** | Clientes con 5 o más intentos de acceso fallidos — señal de intento de toma de control de cuenta. |

## Dashboard en Power BI

Conexión en vivo (DirectQuery/Import vía conector MySQL, no CSV) a la base de datos. Dos páginas:

**Validación Final** — tarjetas de KPI (precisión, recall, F1), gráfica de recall por categoría con formato condicional tipo semáforo (rojo/amarillo/verde) y un recuadro de texto con el hallazgo principal y la recomendación, para que el dashboard cuente la historia sin que el usuario tenga que leer el código SQL.

**Detalle de Alertas** — tabla interactiva con medidas DAX propias (no solo columnas arrastradas):
- `Total de Alertas = COUNTROWS(...)`
- `Clientes Unicos en Riesgo = DISTINCTCOUNT(...)`
- `% del Total = DIVIDE([Total de Alertas], CALCULATE([Total de Alertas], ALL(...)))`

Más 4 filtros interactivos (tipo de riesgo, tipo de persona, ciudad, nivel de riesgo KYC) y una tabla de detalle que se filtra en vivo.

## Validación del sistema (Sección 8)

Antes de confiar en las conclusiones de arriba, se midió formalmente qué tan bien funcionan las 7 reglas: se comparó el total de alertas generadas contra los 91 casos de riesgo reales sembrados en el dataset (`ground_truth_casos_riesgo`), en vez de asumir que las reglas son efectivas solo porque corren sin errores.

**Resultado global:**

| Métrica | Valor |
|---|---|
| Verdaderos positivos | 74 |
| Falsos negativos | 17 |
| Falsos positivos | 12 |
| Total de alertas generadas | 86 |
| **Precisión** | **86.0%** |
| **Recall** | **81.3%** |
| **F1-Score** | **0.836** |

**Desglose por categoría** (de menor a mayor recall) — la base de los insights y recomendaciones de arriba:

| Categoría | Casos reales | Recall |
|---|---|---|
| Velocidad Alta | 13 | **0.0%** (0 de 13) |
| UBO en Lista Negra | 9 | 77.8% (7 de 9) |
| Monto Inusual | 12 | 83.3% (10 de 12) |
| Estructuración | 16 | 100% (16 de 16) |
| País Sancionado OFAC | 14 | 100% (14 de 14) |
| Posible Préstanombres | 12 | 100% (12 de 12) |
| Credential Stuffing / Fuerza Bruta | 15 | 100% (15 de 15) |

## Stack tecnológico

- **MySQL 8.0** (MySQL Workbench) — modelado de datos, 7 reglas de detección, validación con CTEs y comparación contra ground truth.
- **Power BI Desktop** — conexión en vivo vía MySQL Connector/NET, modelo de relaciones, medidas DAX, formato condicional.

## Próximos pasos (Fase 2 — fuera de alcance de este proyecto)

Este dataset da para más de lo que se cubrió aquí, pero requeriría generar datos sintéticos adicionales diseñados para ese fin:

- **Análisis estacional**: los bancos suelen ver picos de movimiento de efectivo (y por lo tanto de riesgo) en épocas de pago de aguinaldo y PTU — analizarlo requeriría regenerar el dataset con fechas de transacción distribuidas deliberadamente en esos periodos.
- **Modelo predictivo de riesgo (Python / scikit-learn)**: en vez de reglas fijas, entrenar un modelo de clasificación usando `ground_truth_casos_riesgo` como variable objetivo, para asignar una probabilidad de riesgo en vez de una alerta binaria.

Esto se deja documentado como roadmap, no como trabajo pendiente de este entregable.
