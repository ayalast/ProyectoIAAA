# AI Context

Resumen reutilizable del proyecto para que cualquier sesión de IA recupere contexto rápido.
Última actualización: 2026-06-20 (bootstrap SDD para Fase 2).

## Producto

Plataforma de trading/charting financiero tipo TradingView, construida en Perl 5 + Tk.
Renderiza velas OHLCV con indicadores técnicos, paneles sincronizados e interacciones de
usuario (zoom, drag, crosshair, timeframes). Es la base de visualización sobre la que se
montan, en el segundo bimestre, los modelos de Machine Learning (HMM/Viterbi tensorial)
para predecir cambios de estructura de mercado (no precio vela a vela).

Contexto académico: asignatura de IA y Aprendizaje Automático, EPN 2026A, GR1SW.
Integrantes: Bryan Ayala, Juan Chugá, Sebastián Jibaja, Oscar Tamayo.
Repo remoto: `https://github.com/amsipan/ProyectoIAAA` (branch `main`).

## Usuarios objetivo

- El estudiante/operador que analiza estructura de mercado de forma visual e interactiva.
- El profesor que evalúa contra una rúbrica y un PDF de especificación por fase.
- Las fases posteriores de ML, que consumen las etiquetas (BOS/CHoCH/FVG/liquidez,
  ATR por bins, volumen) como observaciones discretas para entrenar el HMM.

## Estado por fases

- **Fase 1 (Primer bimestre) — COMPLETADA y evaluada (89/100).** Motor gráfico, paneles,
  ATR, interacciones de UI, 3 timeframes (1m/5m/15m).
- **Fase 2 (Segundo bimestre) — EN ARRANQUE.** Es el foco actual. Ver
  `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` (documento oficial) y las
  specs en `specs/`. Vale 20/100 puntos. Dos entregas: 29/06 y 13/07.
- **Fase 3 (ML recurrente) — FUTURA.** HMM + Viterbi tensorial (órdenes superiores),
  posibles LSTM/Transformers. Insumo: las etiquetas que produce la Fase 2.

## Módulos principales (estado actual, Fase 1)

- `market.pl` — punto de entrada; UI Tk, controles, tema, orquestación inicial.
- `Market/MarketData.pm` — capa de datos: OHLCV, timeframes 1m/5m/15m, slicing, anclas.
- `Market/ChartEngine.pm` — orquestador: render, zoom, drag, crosshair, ejes (archivo grande, ~1700 líneas).
- `Market/IndicatorManager.pm` — contenedor genérico de indicadores desacoplados.
- `Market/Indicators/ATR.pm` — cálculo del ATR (14 periodos, incremental O(1) por vela).
- `Market/Panels/PricePanel.pm` — render de velas + crosshair.
- `Market/Panels/ATRPanel.pm` — render de línea ATR + crosshair sincronizado.
- `Market/Panels/Scales.pm` — conversión datos↔píxeles (X compartida, Y por panel).
- `Market/Debug/TimeAxisSnapshot.pm` — módulo removible de diagnóstico avanzado del eje temporal. Permite capturar por estado actual o por rango explícito (`timeframe`, `start_ts`, `end_ts`, `canvas_width`) la misma información que dibuja la app: labels visibles, coordenadas X, índices, timestamps, cadencia, `bar_w`, gaps y resumen textual. No forma parte del render/producto final; existe para comparar con TradingView sin depender de screenshots internos de la app.
- `Market/Debug/IndicatorSnapshot.pm` — módulo removible y genérico de diagnóstico de indicadores/overlays de Fase 2. Convierte la salida estructurada de cualquier indicador (items con `index`/`type`/`price`/`state`/zona/`meta`) en texto determinista comparable en tests, e incluye el guard de Replay (cero items con índice > tope). Es la forma de verificar SMC/Liquidez SIN ver la GUI. Contrato y patrón de test: `docs/PHASE2_DEBUG_CONTRACT.md`. Self-test: `t/08-indicator-debug-harness.t`. **Capa del arquitecto; el implementor no la edita.**

## Módulos a crear (Fase 2, definidos en el PDF oficial — aún NO existen)

- `Market/Indicators/SMC_Structures.pm` — cálculo de BOS, CHoCH, FVG, Fibonacci e integración con liquidez.
- `Market/Overlays/SMC_Structures.pm` — render de estructuras en el Canvas.
- `Market/Indicators/Liquidity.pm` — detección de Swing Points, EQH/EQL, Sweep/Grab/Run; máquina de estados.
- `Market/Overlays/Liquidity.pm` — render de líneas/velas/etiquetas de liquidez; visibilidad interactiva.
- `Market/Indicators/Strategy_Builder.pm` — SuperTrend, HalfTrend, Range Filter, Supply, Demand.
- `Market/Overlays/Strategy_Builder.pm` — render de estrategias.
- (Sistema Replay, Volume Profile y Anchored VWAP — ubicación de package por confirmar; ver specs.)

Nota: el directorio `Market/Overlays/` es nuevo en Fase 2. La especificación distingue
explícitamente entre **Indicators/** (cálculo) y **Overlays/** (render), reforzando la
separación cálculo/render que ya regía en Fase 1.

## Stack detectado

- **Lenguaje:** Perl 5 (POO con `bless`, `package`).
- **GUI:** Tk (Canvas). Confirmado en código y PDF.
- **Tensores/ML (Fase 2-3):** AI::MXNet (NDArray) — slice estilo NumPy, GPU opcional.
  Requiere parches MXNet en Fedora35 (ver `docs/SETUP_FEDORA35.md`).
- **Gráficas de análisis (PCC/heatmap):** Chart::Plotly (en los ejemplos del profesor).
- **Datos:** `Data/2026_03.csv` — 29.888 velas 1-minuto; aunque el nombre dice `03`, el contenido real va de `2026-04-01T00:00:00-05:00` a `2026-04-30T23:59:00-05:00`. Comparación visual confirmada contra TradingView `NQ1!` (NASDAQ 100 E-mini Futures, CME) en 15m, zona `UTC-5` Bogotá/Quito.
- **Tiempo:** `Time::Moment`.
- **Entorno:** WSL Fedora35 (EOL; mirrors en `archives.fedoraproject.org`). WSLg para GUI.
- **VCS:** Git.

## Estructura de carpetas

```
ProyectoIAAA/
  market.pl                     # entrada, UI Tk
  Market/
    MarketData.pm               # datos
    ChartEngine.pm              # orquestador/render
    IndicatorManager.pm         # contenedor de indicadores
    Indicators/                 # CÁLCULO (sin Tk)
      ATR.pm
      SMC_Structures.pm  (Fase 2, por crear)
      Liquidity.pm       (Fase 2, por crear)
      Strategy_Builder.pm(Fase 2, por crear)
    Overlays/                   # RENDER (Fase 2, carpeta nueva)
      SMC_Structures.pm
      Liquidity.pm
      Strategy_Builder.pm
    Panels/
      PricePanel.pm
      ATRPanel.pm
      Scales.pm
  Data/2026_03.csv
  docs/                         # documentación SDD (esta carpeta)
    material_profesor/          # PDFs/docx originales del profesor + textos extraídos
  specs/                         # qué construir y por qué (incluye cierre Fase 1 0000b antes de Fase 2)
  tasks/                        # unidades de trabajo accionables
  t/                            # tests Test::More de sintaxis/regresión/eje temporal
```

## Flujos principales

1. **Carga y agregación de datos:** `market.pl` lee el CSV → `MarketData` almacena 1m y
   construye 5m/15m por fronteras reales de reloj (`_bucket_timestamp`).
2. **Render del chart:** `ChartEngine` calcula la ventana visible (offset desde el final),
   delega a `PricePanel`/`ATRPanel` usando `Scales` para mapear datos↔píxeles.
3. **Indicadores:** `IndicatorManager` propaga cada vela a los indicadores (`update_last`,
   O(1)); al cambiar timeframe se hace `reset_all` + recálculo vela por vela.
4. **(Fase 2) Overlays SMC/Liquidez:** se calcularán solo sobre velas visibles + ventana de
   contexto, y se renderizarán como overlays sobre el Canvas; recálculo dinámico al avanzar
   velas o al mover el puntero de Replay.

## Integraciones externas

Ninguna en runtime (app de escritorio local). Dependencias CPAN: `Tk`, `Time::Moment`,
y para Fase 2/3 `AI::MXNet`, `Chart::Plotly`. Datos desde archivo CSV local.

## Riesgos conocidos

- Antes de Fase 2 queda cerrar `0000g`: `0000f` introdujo tickmarks ponderados, pero la validación visual aún falla por la mezcla irregular de días/horas y distancias no uniformes. El eje temporal debe elegir un plan global de cadencia por ventana con **Modo A obligatorio**: días + horas uniformes; nunca secuencias tipo `DAY | HOUR | DAY | DAY | HOUR`. El modo diario conservador no es cierre final, solo fallback temporal/incompleto. Ver spec/task `0000g` y ADR `docs/adr/0002-official-tradingview-time-axis-reference.md`.
- `ChartEngine.pm` es muy grande (~70 KB) y concentra orquestación + render + ejes +
  eventos: riesgo de convertirse en god object al añadir Replay y overlays. Ver TECH_DEBT.
- La validación visual contra TradingView ahora debe apoyarse primero en `Market/Debug/TimeAxisSnapshot.pm`: para un rango concreto se extrae `labels_text`, cadencia, coordenadas e índices exactos; el usuario solo confirma si TradingView muestra la misma secuencia/rango en su screenshot.
- El entorno (Fedora35 EOL + parches MXNet manuales) es frágil de reproducir.
- El proyecto vive en OneDrive vía junction `C:\m\...`; algunas herramientas no "ven"
  archivos hidratados desde la nube en listados recursivos (cosmético).

## Preguntas abiertas

Ver `docs/ROADMAP.md` (decisiones pendientes) y la sección 18 de
`../Requisitos_Proyecto_2do_Bimestre.md`. Principales: número final de estados del HMM,
ubicación de packages para Replay/VolumeProfile/VWAP, parámetros exactos de tolerancias.
