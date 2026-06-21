# Task 0000: Pulido Fase 1 — etiqueta de fecha TradingView + grid temporal equidistante

> Estado posterior: implementada parcialmente y verificada por el agente implementor. La etiqueta del crosshair (`Thu 23 Apr '26`) está aceptada. No continuar con el criterio de grid equidistante; seguir `tasks/0000b-time-axis-tradingview-scale.md`.

## Spec relacionada

`specs/0000-fase1-polish-time-axis-crosshair.md`

## Objetivo

Corregir los últimos detalles visuales de Fase 1 antes de iniciar Fase 2: formato de fecha del crosshair como TradingView y uniformidad de las líneas verticales del eje temporal inferior para cada nivel de zoom.

## Archivos probablemente relevantes

- `Market/ChartEngine.pm`
  - `_crosshair_time_label`
  - `_time_label_for_index`
  - `compute_intraday_labels`
  - `_time_axis_interval_minutes`
  - `_is_time_axis_boundary`
  - `get_all_timestamps`
- `Market/Panels/PricePanel.pm`
  - `draw_crosshair`
  - `draw_time_axis`
- `Market/Panels/Scales.pm`
  - `index_to_center_x`
  - `x_to_index`

## Pasos

1. Cambiar el formato de la etiqueta inferior del crosshair:
   - Crear un helper dedicado, por ejemplo `_crosshair_date_label($tm)` o ampliar `_crosshair_time_label`.
   - Formato exacto: `Dow DD Mon 'YY`, ejemplo `Thu 23 Apr '26`.
   - Usar abreviaturas en inglés: `Sun Mon Tue Wed Thu Fri Sat` y `Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec`.
   - Confirmar el mapeo real de `Time::Moment->day_of_week`; no asumir sin verificar. Si hay duda, hacer una prueba rápida con una fecha conocida.
2. Ajustar el ancho de la caja inferior del crosshair si hace falta:
   - El texto nuevo es más largo que `HH:MM`.
   - Evitar que la caja se salga de los bordes izquierdo/derecho.
   - Mantener caja negra/texto blanco estilo TradingView.
3. Revisar `compute_intraday_labels` para garantizar que el grid temporal use un único stride uniforme por zoom:
   - Calcular un `stride_bars` entero a partir de `interval_minutes / tf_minutes` o de una escalera equivalente.
   - Elegir una fase/ancla única para la ventana y generar marcas con `local_index = first + n * stride_bars`.
   - No insertar marcas extra por cambio de fecha si rompen el stride uniforme.
   - Si se desea resaltar cambio de día/mes, hacerlo solo en la etiqueta de una marca que ya pertenezca al stride.
4. Mantener etiquetas legibles:
   - Si se solapan, ocultar texto (`label => 0`) pero conservar el grid uniforme (`grid => 1`) si esa marca forma parte del stride.
   - En zoom muy amplio, preferir etiquetas de fecha/mes; en zoom cerrado, horas/minutos.
5. Verificar que el crosshair sigue convirtiendo X→índice usando `Scales`, no cálculo manual.
6. No tocar lógica de ATR, velas, zoom vertical/manual, temporalidades nuevas ni overlays.

## Criterios de aceptación

- Crosshair sobre 2026-04-23 muestra `Thu 23 Apr '26`.
- La etiqueta inferior del crosshair queda alineada al eje temporal y no se sale del canvas.
- Para un zoom fijo, las líneas verticales del fondo se ven equidistantes, tolerancia visual ≤ 1 px.
- Al cambiar zoom, el paso puede cambiar, pero vuelve a ser uniforme dentro del nuevo zoom.
- 1m/5m/15m siguen funcionando; no se rompe el snap del crosshair al centro de vela.
- No aparecen fechas falsas cuando el cursor está sobre espacio en blanco fuera del rango real.

## Comandos de verificación

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl"
```

Prueba manual con WSLg:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. market.pl"
```

Validar visualmente contra TradingView: crosshair con formato `Thu 23 Apr '26` y grid temporal equidistante al hacer zoom.

## Qué no tocar

- `Data/2026_03.csv`.
- `Market/MarketData.pm` salvo que se detecte un bug estrictamente necesario de timestamps.
- `Market/Indicators/*`.
- Fase 2: Replay, OverlayManager, SMC, Liquidity.
- Refactors grandes de `ChartEngine.pm`.
