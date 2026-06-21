# Arquitectura

Estado real del sistema. Separa lo implementado (Fase 1) de lo planificado (Fase 2/3).
Última actualización: 2026-06-20.

## Diagrama (texto)

```
                          market.pl  (Capa Aplicación)
                          - crea ventana Tk, tema, controles
                          - lee CSV, instancia MarketData
                          - instancia ChartEngine y arranca loop
                                   |
                                   v
        +-------------------- ChartEngine.pm --------------------+
        | (orquestador: ventana de datos, eventos, render coord) |
        |   conoce a: paneles, escalas, (Fase2) overlays         |
        +----+-------------------+--------------------+----------+
             |                   |                    |
             v                   v                    v
        PricePanel.pm        ATRPanel.pm          (Fase 2)
        (render velas)       (render ATR)         Overlays/*.pm
             |                   |                 (render SMC,
             +---------+---------+                  Liquidity,
                       v                            Strategy)
                   Scales.pm
              (datos <-> pixeles;
               X compartida, Y por panel)

   Capa Datos:        MarketData.pm  (OHLCV, timeframes, slicing, anclas)
   Capa Indicadores:  IndicatorManager.pm  ->  Indicators/ATR.pm
                      (Fase 2) Indicators/{SMC_Structures,Liquidity,Strategy_Builder}.pm
   Capa Debug:        Market/Debug/TimeAxisSnapshot.pm   (eje temporal)
                      Market/Debug/IndicatorSnapshot.pm  (indicadores/overlays Fase 2)
                      (diagnóstico removible; no participa en render/producto final)
```

## Capas del sistema

1. **Datos** — `MarketData.pm`. Almacena OHLCV en 1m y agrega a 5m/15m por fronteras reales
   de reloj. Acceso por índice, slicing, última vela, anclas temporales. (Fase 2: deberá
   soportar 1h/2h/4h/D/W y un puntero de Replay.)
2. **Indicadores (cálculo, sin Tk)** — `IndicatorManager.pm` + `Indicators/`. Contrato:
   `update_last`, `get_values`, `reset`. ATR es O(1) por vela. (Fase 2: SMC_Structures,
   Liquidity, Strategy_Builder.)
3. **Renderizado** — `ChartEngine.pm`, `Panels/*`, `Scales.pm`. (Fase 2: `Overlays/` para
   dibujar estructuras/liquidez/estrategias sobre el Canvas.)
4. **Aplicación** — `market.pl`. Punto de entrada y orquestación inicial.
5. **Debug removible** — `Market/Debug/`. No renderiza ni muta permanentemente la app.
   - `TimeAxisSnapshot.pm`: replica las conversiones del motor para capturar, por estado actual o
     por rango explícito, lo que se dibuja en el eje temporal (labels, coordenadas, índices,
     timestamps, `bar_w`, cadencia, gaps, deltas X y resumen textual).
   - `IndicatorSnapshot.pm` (Fase 2): convierte la salida estructurada de cualquier indicador/overlay
     (items con `index`/`type`/`price`/`state`/...) en texto determinista comparable en tests, e
     incluye el guard de Replay (cero items con índice > tope). Contrato en
     `docs/PHASE2_DEBUG_CONTRACT.md`. **Capa propiedad del arquitecto; el implementor no la edita.**
   Se mantiene fuera de `ChartEngine.pm` para poder omitirla al final sin afectar las clases
   principales pedidas por el profesor.

## Flujo de datos

CSV → `MarketData.add_candle` (1m) → `build_timeframes` (5m/15m) → `ChartEngine.compute_window`
(qué rango es visible, offset desde el final) → `Scales` mapea índice/valor a píxeles →
`PricePanel`/`ATRPanel` dibujan. Indicadores: cada vela se propaga con `update_last`; al
cambiar timeframe, `reset_all` + recálculo vela por vela (O(N)).

(Fase 2) El Replay fija un índice tope; indicadores y overlays solo calculan hasta ese índice
(jamás velas futuras). Overlays SMC/Liquidez calculan sobre velas visibles + ventana de
contexto, no sobre todo el historial.

## Dependencias principales

- `Tk` (Canvas, eventos), `Time::Moment` (timestamps). Confirmadas en código.
- (Fase 2/3) `AI::MXNet` (NDArray, tensores, corrcoef), `Chart::Plotly` (heatmaps/scatter de
  análisis). Confirmadas en el material del profesor.
- Datos: `Data/2026_03.csv` contiene abril 2026 (`2026-04-01` a `2026-04-30`, zona `UTC-5`), 29.888 velas 1m. La calibración visual se hace contra TradingView `NQ1!` / NASDAQ 100 E-mini Futures / CME en 15m.

## Estado actual (qué funciona hoy — Fase 1)

- Render de velas + ATR con paneles sincronizados.
- Zoom (rueda, Ctrl+rueda con ancla), drag horizontal, downsample por píxel.
- Crosshair sincronizado, snap a centro de vela, labels de precio/tiempo.
- Eje temporal estilo TradingView en cierre de `0000g`: `compute_intraday_labels()` elige un plan global de cadencia por ventana con **Modo A obligatorio** (días + horas uniformes), preserva gaps reales comprimidos por índice lógico y evita thinning por peso que degradaba 90m a 3h. El caso calibrado NQ1!/CME 15m UTC-5 `2026-04-29T15:00 -> 2026-05-01T00:00` se verifica por `Market/Debug/TimeAxisSnapshot.pm` y `t/07-time-axis-global-cadence.t` con la secuencia TradingView esperada.
- Timeframes 1m/5m/15m con agregación por fronteras reales.
- ATR 14 con modo auto/manual independiente y controles propios.
- Validado contra la rúbrica (89/100); según observación actual, está más cerca del 100% al cerrar los detalles de spec `0000`.

## Problemas arquitectónicos (con evidencia)

- **`ChartEngine.pm` ~70 KB / ~65 subs.** Concentra orquestación, render de 3 ejes, eventos de
  mouse/teclado, zoom, drag, cursores. Añadir Replay + overlays multi-temporal puede
  convertirlo en god object. Evidencia: inventario de subs (`_render_price_axis`,
  `_render_time_axis`, `_render_atr_axis`, `_draw_*_crosshair`, `_wheel_zoom_delta`, etc.).
  Recomendación: aislar el control de Replay y el registro de overlays en colaboradores
  dedicados, no inline en ChartEngine. (Ver TECH_DEBT.)
- **Sin capa de "controlador de overlays".** Hoy ChartEngine llama paneles directamente; Fase 2
  introduce N overlays activables/desactivables. Conviene un registro de overlays análogo a
  `IndicatorManager` (cálculo) pero para render.
- **Acoplamiento timeframe → recálculo total de indicadores.** Hoy O(N) por timeframe está
  bien para ATR; SMC/Liquidez son más caros, de ahí la regla de "solo velas visibles +
  contexto" del PDF.
- **Sin tests automatizados.** Validación 100% visual. Para los algoritmos de ML (Viterbi,
  Pearson) sí hay valores de referencia que permiten tests deterministas.

## Recomendaciones futuras (no obligaciones inmediatas)

- Introducir `Market/Overlays/` con un patrón uniforme (cada overlay: `compute_visible`,
  `draw`, `set_visible`).
- Un `ReplayController` que posea el índice-tope y notifique a ChartEngine para re-render.
- Tests `.t` (Test::More) para Indicators de cálculo puro (ATR, SMC labels, Viterbi tensorial,
  Pearson) usando los valores de referencia del material del profesor.
- A mediano plazo, evaluar partir `ChartEngine` (render de ejes vs orquestación de eventos).
