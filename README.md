# Proyecto del Primer Bimestre de Intelligencia Artificial y Aprendizaje Automático

- EPN - 2026A
- GR1SW
- Integrantes: Bryan Ayala, Juan Chugá, Sebastián Jibaja, Oscar Tamayo

## Tema: “Visualización de Datos mediante Motor de Charting usando la librería Tk”

Este repositorio contiene todos los elementos necesarios para la implementación del desarrollo de un motor de gráficos financieros con indicadores técnicos
mediante la librería Tk en Perl.

## Estructura del proyecto

La estructura de este proyecto es la siguiente. A continuación se detallan los ficheros más importantes:

- **Data:** se encuentra el archivo fuente `2026_03.csv`
- **Market:** directorio principal que contiene el código fuente en Perl estructurado bajo una arquitectura modular de cuatro capas. Aquí se alojan los módulos principales de la aplicación:
- **MarketData.pm:** capa de datos encargada de gestionar los tensores, el almacenamiento OHLCV, los timeframes y el streaming.
- **ChartEngine.pm y Scales.pm:** capa de renderizado responsable del lienzo interactivo con la librería Tk, transformaciones matemáticas y eventos del usuario (zoom, paneo).
- **IndicatorManager.pm:** capa de indicadores que contiene la lógica matemática para extraer características y calcular métricas técnicas (como el ATR).
- **market.pl:** script principal y punto de entrada de la aplicación. Actúa como el controlador que ingesta los datos, inicializa las estructuras de memoria y lanza la interfaz gráfica.
