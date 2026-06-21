# Task 0000i: Calendario mensual denso y overscan de velas durante paneo suave

## Specs relacionadas

- `specs/0000g-time-axis-global-cadence-tradingview.md` — eje temporal tipo TradingView.
- `tasks/0000h-time-axis-adaptive-density-calendar-threshold.md` — densificación adaptativa ya implementada.
- `tasks/0000c-time-axis-polish-smooth-pan.md` — paneo horizontal suave con `ctrl_zoom_x_shift`.

## Contexto

El implementor terminó `0000h` y reportó `123/123` tests pasando en ambas copias. La validación visual del usuario confirma que el resultado está más cerca, pero aún quedan dos fallos visibles antes de cerrar `0000g` y pasar a Fase 2.

El implementor **no tiene visión**, por eso esta task transcribe lo importante de las capturas.

Activo/fuente de calibración:

- TradingView/Supercharts: `NQ1!` — NASDAQ 100 E-mini Futures, CME.
- Timeframe: `15m`.
- Zona: `UTC-5` / Bogotá-Quito.
- Dataset local: `Data/2026_03.csv`, contiene abril 2026 aunque el nombre dice marzo.
- Las velas se distribuyen por índice lógico; gaps de sesión/weekend se comprimen como en TradingView.
- No inventar velas ni labels dentro de gaps de sesión si no hay punto real o whitespace explícito.

## Problema A — zoom mensual/calendario demasiado sparse

### Referencia TradingView de la captura

En el zoom mensual más alejado mostrado por el usuario, TradingView presenta una vista de casi todo abril con labels densos de calendario. La secuencia visible inferior es aproximadamente:

```text
Apr | 2 | 3 | 7 | 8 | 9 | 10 | 13 | 14 | 15 | 16 | 17 | 20 | 21 | 22 | 23 | 24 | 27 | 28 | 29 | 30 | May
```

Notas visuales:

- `Apr` aparece como anchor de mes al inicio.
- `May` aparece como anchor al final.
- TradingView sí muestra días consecutivos cuando caben visualmente (`7 | 8 | 9 | 10`, `13 | 14 | 15 | 16 | 17`, etc.).
- No hay horas en este nivel: es modo calendario mensual/días.
- El grid vertical está alineado con esos labels visibles.

### Estado actual de la app en la captura

La app se ve demasiado sparse. La secuencia visible aproximada es:

```text
Apr | 3 | 7 | 9 | 12 | 15 | 17 | 21 | 23 | 26 | 29
```

Problemas:

- Faltan muchos días que TradingView sí muestra (`2`, `8`, `10`, `13`, `14`, `16`, `20`, `22`, `24`, `27`, `28`, `30`, `May`).
- El criterio de separación actual del modo calendario es demasiado conservador.
- La app deja huecos visuales entre labels que TradingView no deja en ese zoom.

### Objetivo del problema A

Ajustar `_build_calendar_time_axis_plan(...)` y/o la decisión de modo calendario para que, en el rango mensual completo de abril, el snapshot se acerque a TradingView:

```text
Apr | 2 | 3 | 7 | 8 | 9 | 10 | 13 | 14 | 15 | 16 | 17 | 20 | 21 | 22 | 23 | 24 | 27 | 28 | 29 | 30 | May
```

No hardcodear esos días. La regla debe ser general:

- anchors de mes obligatorios (`Apr`, `May`);
- días reales del dataset como candidatos;
- separación por ancho real de label y canvas, no por patrón impar/par;
- permitir días consecutivos si el spacing visual lo permite;
- no mostrar horas en este modo;
- no ocultar `May` si está dentro del rango y cabe.

Sugerencias técnicas:

- Revisar `my $min_px = 100` en `_build_calendar_time_axis_plan`; parece demasiado alto para esta captura.
- El ancho de labels de días (`2`, `10`, `May`) no es igual: usar ancho estimado por texto puede permitir más densidad que un umbral fijo.
- Considerar una regla tipo LWC: construir boxes de labels y aceptar si no colisionan, con prioridad para anchors de mes.
- Mes (`Apr`, `May`) debe reemplazar/ganar frente a un día cercano si colisionan.
- Si el canvas real de la app tiene ancho distinto al browser de TradingView, documentar el `canvas_width`, `bar_w`, `visible_bars` usado en el test.

## Problema B — velas parcialmente fuera de plano no se renderizan durante drag suave

### Referencia TradingView de la captura

En zoom máximo, TradingView muestra solo unas pocas velas enormes. Al desplazar horizontalmente, las velas cercanas fuera de pantalla ya están renderizadas y entran parcialmente al viewport. Si una esquina o parte del cuerpo/mecha entra al plano, debe verse.

Captura de referencia TradingView:

- Se ven 3 velas aproximadamente.
- La vela izquierda está parcialmente fuera de pantalla pero su parte derecha entra al viewport y se ve.
- La vela central y la derecha se ven enormes.
- No hay hueco vacío artificial en el borde izquierdo si una vela vecina debería estar entrando.

### Estado actual de la app

En la app, con zoom máximo y paneo suave:

- se ven solo 2 velas;
- queda un hueco grande a la izquierda;
- al arrastrar, parece que las velas laterales no existen hasta que cruzan un umbral y aparecen de golpe;
- esto ocurre porque el render probablemente solo usa el slice `start..end`; cuando `ctrl_zoom_x_shift` desplaza la ventana, las velas `start-1` o `end+1` que ya deberían intersectar el viewport no están en el slice renderizado.

### Objetivo del problema B

Implementar **overscan de render horizontal** para price y ATR:

- El cálculo lógico de ventana (`compute_window`) puede seguir usando `start..end`.
- Pero el render debe poder dibujar velas/valores adyacentes `start-1` y/o `end+1` cuando `ctrl_zoom_x_shift` hace que entren parcialmente al viewport.
- Las velas overscan deben dibujarse en coordenadas lógicas correctas:
  - `start-1` debe tener índice local `-1` respecto a la ventana visible;
  - `end+1` debe tener índice local `visible_bars` respecto a la ventana visible;
  - no se deben reindexar como si fueran parte del slice visible normal.

Ejemplo conceptual con `visible_bars = 2`, `canvas_width = 1000`, `bar_w = 500`:

- ventana lógica visible: global `[1, 2]`;
- si `ctrl_zoom_x_shift = +250`, el contenido se mueve a la derecha;
- la vela global `0` debe dibujarse con local index `-1` y puede quedar parcialmente visible en el borde izquierdo;
- si `ctrl_zoom_x_shift = -250`, la vela global `3` debe dibujarse con local index `2` y puede quedar parcialmente visible en el borde derecho.

### Sugerencias técnicas para overscan

Hay varias formas válidas; elegir la más pequeña y verificable.

Opción recomendada:

1. En `ChartEngine::render`, calcular:

```perl
my $draw_start = $start - 1;
my $draw_end   = $end + 1;
```

acotado a `[0, total-1]`.

2. Obtener slices de dibujo separados de los slices lógicos:

```perl
my $draw_candles = $market_data->get_slice($draw_start, $draw_end);
my $draw_atr     = $indicator_manager->slice_array('ATR', $draw_start, $draw_end);
```

3. Mantener la escala X con `bars => $x_bars` de la ventana lógica, no con el tamaño del slice overscan.

4. Pasar al panel el índice base lógico visible (`visible_start => $start`, `draw_start => $draw_start`) o transformar cada vela a un índice local explícito.

5. En `PricePanel::render`, dibujar cada vela usando:

```perl
my $local_index = $global_index - $visible_start;
my $cx = $scale->index_to_center_x($local_index);
```

Así se permiten índices `-1` y `visible_bars`.

6. En `ATRPanel::render`, aplicar el mismo principio para puntos overscan.

7. No cambiar `MarketData.pm`.

8. No romper `compute_intraday_labels()` ni crosshair: el eje temporal debe seguir usando la ventana visible lógica, salvo que un futuro test demuestre lo contrario.

Consideración sobre escala Y:

- TradingView normalmente autoscalea según lo visible en pantalla. Si una vela overscan entra parcialmente, puede ser razonable incluirla en el rango Y si intersecta el viewport.
- Implementación mínima aceptable: mantener el rango Y con `visible_candles` actuales y solo usar overscan para dibujo. Si hay clipping vertical raro, documentarlo como follow-up.
- Implementación mejor: incluir en `get_y_range` las velas overscan cuyo cuerpo/mecha intersecte horizontalmente el viewport.

## Archivos permitidos

- `Market/ChartEngine.pm`
- `Market/Panels/PricePanel.pm`
- `Market/Panels/ATRPanel.pm`
- `Market/Panels/Scales.pm` solo si hace falta un helper pequeño para índices locales negativos / clipping.
- `Market/Debug/TimeAxisSnapshot.pm` solo si hace falta exponer métricas adicionales de calendario.
- Tests en `t/`, preferentemente:
  - `t/07-time-axis-global-cadence.t` para calendario mensual;
  - `t/03-chart-time-axis-polish.t` o `t/04-chart-time-axis-visual-regressions.t` para overscan durante drag.

## No tocar

- `Market/MarketData.pm` salvo autorización explícita del humano.
- `Data/2026_03.csv`.
- `Market/Indicators/*`.
- `Market/Overlays/*`.
- Replay/Fase 2.
- `market.pl` salvo necesidad estricta.
- No hacer refactor amplio.
- No hacer commit/push.

## Tests requeridos

### T1. Calendario mensual denso tipo TradingView

Usar `debug_time_axis_snapshot(...)` con el CSV real de abril + punto lógico `May`, como en tests previos.

Rango:

```text
start_ts = 2026-04-01T00:00:00-05:00
end_ts   = 2026-05-01T00:00:00-05:00
timeframe = 15m
```

Canvas sugerido:

- Probar `canvas_width => 1900` y/o el ancho real de la app en la captura.
- Si el ancho exacto cambia el resultado, documentar el ancho elegido en el test.

Esperado objetivo de TradingView para la captura ancha:

```text
Apr | 2 | 3 | 7 | 8 | 9 | 10 | 13 | 14 | 15 | 16 | 17 | 20 | 21 | 22 | 23 | 24 | 27 | 28 | 29 | 30 | May
```

Criterios mínimos:

- contiene `Apr` y `May`;
- no contiene horas (`HH:MM`);
- es significativamente más denso que el patrón anterior `Apr | 3 | 7 | 9 | 12 | 15 | ...`;
- incluye días consecutivos cuando caben (`7|8|9|10`, `13|14|15|16|17`, etc.);
- no muestra labels solapados visualmente según el cálculo de boxes/spacing.

### T2. No romper calendario máximo anterior sin justificar

Si el test anterior de `0000g` esperaba:

```text
Apr | 3 | 7 | 9 | 12 | 14 | 16 | 19 | 21 | 23 | 26 | 28 | May
```

actualizarlo solo si la nueva referencia visual de TradingView demuestra que el resultado correcto en ese ancho es más denso. Dejar comentario claro:

```text
La referencia visual nueva supersede el esperado conservador anterior.
```

### T3. Overscan izquierdo con `ctrl_zoom_x_shift > 0`

Crear test unitario sin GUI real con `TestCanvas` que grabe operaciones.

Fixture conceptual:

- 3 velas con OHLC distintos.
- `visible_bars => 2`.
- ventana lógica final `[1, 2]`.
- `ctrl_zoom_x_shift => +250` con `canvas_width => 1000` para que la vela global `0` tenga parte visible a la izquierda.

El test debe verificar que se dibuja una vela adicional parcialmente visible:

- existe un `createRectangle` o `createLine` de vela con coordenadas X que intersectan el viewport (`x2 > 0` y `x1 < 0` o cerca de 0);
- antes del fix esta vela no existía porque el slice empezaba en `start`.

### T4. Overscan derecho con `ctrl_zoom_x_shift < 0`

Fixture similar:

- 4 velas.
- ventana lógica `[1, 2]`.
- `ctrl_zoom_x_shift => -250`.
- la vela global `3` debe entrar parcialmente por la derecha.

Verificar que se dibuja una vela con coordenadas que intersectan el borde derecho (`x1 < canvas_width` y `x2 > canvas_width` o cerca).

### T5. Crosshair y eje temporal no se rompen

- `_crosshair_time_label()` debe seguir usando la ventana lógica visible y no seleccionar una vela overscan salvo que el cursor esté sobre ella y exista una decisión explícita.
- `compute_intraday_labels()` debe seguir pasando todos los tests actuales.

### T6. Regresión completa

Ejecutar obligatoriamente:

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/ATRPanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c Market/Debug/TimeAxisSnapshot.pm && perl -I. -c market.pl && prove -l t"
```

Si se trabaja en la copia Fedora directa:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/ATRPanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c Market/Debug/TimeAxisSnapshot.pm && perl -I. -c market.pl && prove -l t"
```

## Criterios de aceptación

- En el zoom mensual de abril, el eje se parece a TradingView y muestra calendario denso:

```text
Apr | 2 | 3 | 7 | 8 | 9 | 10 | 13 | 14 | 15 | 16 | 17 | 20 | 21 | 22 | 23 | 24 | 27 | 28 | 29 | 30 | May
```

- No hay horas en ese modo calendario.
- `Apr` y `May` se mantienen como anchors de mes.
- El calendario no queda sparse como `Apr | 3 | 7 | 9 | 12 | ...`.
- En zoom máximo con paneo suave, las velas adyacentes parcialmente dentro del viewport se renderizan desde antes; no aparecen de golpe ni dejan huecos artificiales.
- El overscan funciona a izquierda y derecha.
- No se modifican datos ni `MarketData.pm`.
- Todos los tests pasan.

## Prompt mínimo para el implementor

Implementa `tasks/0000i-time-axis-calendar-density-overscan-render.md`.

Reglas:

- Antes de tocar código, lee `AGENTS.md`, `docs/AI_CONTEXT.md`, `docs/ARCHITECTURE.md`, `specs/0000g-time-axis-global-cadence-tradingview.md`, `tasks/0000g-time-axis-global-cadence-tradingview.md`, `tasks/0000h-time-axis-adaptive-density-calendar-threshold.md` y esta task.
- No tienes visión: usa las transcripciones de esta task como referencia visual.
- No toques `MarketData.pm` ni Fase 2.
- Para calendario: usa snapshots, no screenshots como fuente primaria.
- Para overscan: agrega tests unitarios con canvas fake que demuestren velas parcialmente visibles a izquierda y derecha.
- Preserva todos los casos previos de `0000g`/`0000h` salvo que actualices explícitamente el esperado del calendario porque la referencia nueva lo supersede.
- Ejecuta el comando obligatorio completo antes de declarar listo.
