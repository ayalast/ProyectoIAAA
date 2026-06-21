# Task 0000j: Filtrar anchors de sesión parcial en calendario mensual TradingView

## Specs relacionadas

- `specs/0000g-time-axis-global-cadence-tradingview.md`
- `tasks/0000i-time-axis-calendar-density-overscan-render.md`

## Contexto

`0000i` implementó calendario mensual denso con spacing por cajas y overscan de velas. Los tests pasaron (`127/127`), pero la validación visual del usuario muestra que el calendario mensual aún no coincide con TradingView.

Este NO parece ser fallo del debug: el snapshot mensual reproduce prácticamente lo que se ve en la app.

Snapshot actual con CSV real abril + punto lógico May:

```text
canvas_width=1400
labels=Apr | 2 | 3 | 6 | 7 | 8 | 9 | 10 | 12 | 14 | 15 | 16 | 17 | 19 | 21 | 22 | 23 | 24 | 26 | 28 | 29 | 30 | May
```

La captura de la app muestra visualmente lo mismo o muy parecido:

```text
Apr | 2 | 3 | 6 | 7 | 8 | 9 | 10 | 12 | 14 | 15 | 16 | 17 | 19 | 21 | 22 | 23 | 24 | 26 | 28 | 29 | 30
```

La referencia TradingView para el mismo tipo de vista mensual muestra aproximadamente:

```text
Apr | 2 | 3 | 7 | 8 | 9 | 10 | 13 | 14 | 15 | 16 | 17 | 20 | 21 | 22 | 23 | 24 | 27 | 28 | 29 | 30 | May
```

Observación visual crítica adicional: en TradingView, las líneas verticales del grid en esta vista se ven **casi equidistantes**. La excepción notoria es el salto `3 -> 7` por el fin de semana/gap comprimido. Después de eso, la distancia entre grids se ve muy regular. No basta con igualar `labels_text`; también debe calzar la distribución horizontal de los labels/grid para que las velas queden en la misma lectura visual.

## Diagnóstico

El implementor explicó que la diferencia se debe a que el CSV local tiene velas en domingos de sesión parcial:

```text
2026-04-05 17:00 -> 23:59
2026-04-12 17:00 -> 23:59
2026-04-19 17:00 -> 23:59
2026-04-26 17:00 -> 23:59
```

Pero eso no es suficiente para aceptar el resultado, porque TradingView/Supercharts en el modo calendario mensual **no usa esos domingos parciales como labels principales** cuando compiten con días regulares cercanos.

En otras palabras:

- los datos de domingo existen y deben seguir existiendo para velas/crosshair;
- pero el eje calendario mensual debe priorizar anchors de calendario/sesión visualmente equivalentes a TradingView;
- días con primera vela muy tarde (`17:00`) y sesión parcial pueden ser candidatos débiles en modo calendario mensual;
- si compiten por espacio con días de sesión completa o anchors regulares cercanos, deben omitirse.

## Objetivo

Ajustar el modo calendario mensual para que filtre o penalice anchors de días con sesión parcial nocturna, de modo que el snapshot del rango mensual se acerque a TradingView:

```text
Apr | 2 | 3 | 7 | 8 | 9 | 10 | 13 | 14 | 15 | 16 | 17 | 20 | 21 | 22 | 23 | 24 | 27 | 28 | 29 | 30 | May
```

No hardcodear fechas concretas (`5`, `12`, `19`, `26`). La regla debe ser general.

## Reglas esperadas

### R1. Detectar calidad del anchor diario en modo calendario

Para cada `DAY` candidate en modo calendario, derivar metadatos del día visible, por ejemplo:

- hora/minuto de la primera vela del día;
- hora/minuto de la última vela del día;
- cantidad de barras del día en el timeframe activo o en la ventana;
- si el día empieza tarde (`first intraday_mins >= 17:00`) y no tiene sesión regular diurna;
- si el día es una sesión parcial nocturna previa a un día regular cercano.

No hace falta tocar `MarketData.pm`; se puede calcular desde `@candidates` dentro de `ChartEngine.pm` o desde los timestamps visibles.

### R2. Penalizar/filtrar días parciales nocturnos en calendario mensual

En `_build_calendar_time_axis_plan(...)` o helper equivalente:

- `MONTH` anchors siguen siendo obligatorios.
- `DAY` anchors con primera vela tarde (`>= 17:00`) y sin velas antes de mediodía deben considerarse débiles.
- En modo calendario mensual, omitir esos anchors débiles si hay presión de espacio o si su inclusión desplaza anchors de días regulares cercanos.

Ejemplos concretos esperados en abril 2026:

- Omitir `5`, mantener `7`.
- Omitir `12`, mantener `13`.
- Omitir `19`, mantener `20`.
- Omitir `26`, mantener `27`.

Pero implementar como regla general de sesión parcial, no como fechas hardcodeadas.

### R3. Mantener días completos y viernes parciales normales

No filtrar automáticamente todo día parcial.

TradingView sí muestra días como:

- `3` aunque el CSV del 3 termina temprano (`08:14`) por ser sesión parcial/cierre;
- `10`, `17`, `24` aunque sean viernes con fin de sesión temprano.

Por tanto, la regla NO debe ser simplemente “filtrar días con pocas barras”. El patrón problemático específico es “día que empieza tarde como sesión nocturna” (`17:00 -> 23:59`), no “día que termina temprano”.

### R4. Mantener `May`

Si el punto lógico `2026-05-01T00:00:00-05:00` está en el rango, `May` debe aparecer si cabe. Si no aparece en la captura por borde visual, el snapshot/test debe aclarar canvas/viewport usado. En general el objetivo es conservarlo.

### R5. Calzar espaciado horizontal del grid, no solo textos

La referencia TradingView muestra grids casi equidistantes en el rango mensual. Por tanto, el plan calendario final debe reportar y validar deltas horizontales (`x_delta`) entre labels visibles.

Criterio esperado:

- El salto `3 -> 7` puede ser mayor por weekend/gap comprimido.
- Fuera de esa excepción, los deltas entre labels consecutivos deben ser razonablemente uniformes.
- No aceptar una secuencia que tenga los textos correctos pero con grids visualmente torcidos o con huecos grandes inesperados.
- Grid vertical debe dibujarse solo para labels visibles, como ya exige `0000d`.

Sugerencia de métrica:

```text
x_delta[i] = labels[i].x - labels[i-1].x
median_delta = mediana de deltas excluyendo gaps de weekend/sesión parcial
ratio = max_regular_delta / min_regular_delta
```

El test no necesita ser matemáticamente perfecto, pero debe detectar regresiones obvias como anchors dominicales que desplazan la secuencia y hacen que el grid no calce con TradingView.

### R6. Si el debug no permite verificarlo, robustecer el debug

Si `debug_time_axis_snapshot(...)` no expone suficiente información para confirmar el spacing visual, extender `Market/Debug/TimeAxisSnapshot.pm` antes de declarar listo.

Campos recomendados:

```text
label_deltas: [ { left_text, right_text, dx, left_ts, right_ts, left_global, right_global, is_gap_exception } ]
grid_spacing_stats: { min_regular_dx, max_regular_dx, median_regular_dx, ratio_regular_dx }
calendar_day_quality: por label/candidate, indicando first_intraday_mins, last_intraday_mins, bars_in_day, weak_partial_session
```

El resumen textual (`summary`) debería imprimir al menos los `dx` entre labels visibles para el rango mensual cuando se solicite debug, o dejarlos en la estructura para tests.

## Tests requeridos

Actualizar `t/07-time-axis-global-cadence.t`.

### T1. Snapshot mensual filtra domingos parciales nocturnos

Usar el mismo helper de CSV real abril + punto lógico May.

Rango:

```text
start_ts = 2026-04-01T00:00:00-05:00
end_ts   = 2026-05-01T00:00:00-05:00
timeframe = 15m
canvas_width = 1400 o ancho documentado
```

Esperado objetivo para `canvas_width=1400` o equivalente:

```text
Apr | 2 | 3 | 7 | 8 | 9 | 10 | 13 | 14 | 15 | 16 | 17 | 20 | 21 | 22 | 23 | 24 | 27 | 28 | 29 | 30 | May
```

Si el ancho exacto de la app produce una pequeña diferencia, documentar `bar_w`, `visible_bars` y justificar. Pero NO aceptar que aparezcan `5`, `12`, `19`, `26` en vez de `13`, `20`, `27` para esta vista.

### T2. No filtrar viernes/cierres parciales tempranos

Asegurar que días como `3`, `10`, `17`, `24` siguen apareciendo cuando caben.

### T3. Espaciado horizontal/grid casi equidistante

Para el mismo snapshot mensual, inspeccionar `labels` y sus coordenadas `x`.

Test mínimo:

- calcular deltas `dx` entre labels visibles consecutivos;
- marcar como excepción permitida el salto `3 -> 7` o cualquier salto que corresponda claramente a weekend/gap comprimido documentado;
- para los deltas regulares restantes, exigir que el ratio `max/min` no sea extremo;
- si el debug no tiene `label_deltas`/`grid_spacing_stats`, agregarlos y testearlos.

Este test existe para evitar que el algoritmo solo coincida en textos pero no en distribución visual. La captura de TradingView muestra grids casi equidistantes, y la app debe verse igual.

### T4. No romper zoom calendario denso de `0000i`

La solución sigue siendo box-based/densa; no volver al patrón sparse anterior.

### T5. No romper casos 0000g/0000h

Preservar:

- 90m.
- 6h.
- 6h con gaps comprimidos.
- sparse 12h/días.
- densificación `14:30`.
- no calendario prematuro `23 -> May`.
- overscan de `0000i`.

## Archivos permitidos

- `Market/ChartEngine.pm`
- `t/07-time-axis-global-cadence.t`
- `Market/Debug/TimeAxisSnapshot.pm` solo si hace falta exponer metadatos de day/session quality.

## No tocar

- `MarketData.pm`.
- `Data/2026_03.csv`.
- Fase 2.
- Overlays/Indicators/Replay.
- No refactor amplio.
- No commit/push.

## Verificación obligatoria

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/ATRPanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c Market/Debug/TimeAxisSnapshot.pm && perl -I. -c market.pl && prove -l t"
```

Si se trabaja en Fedora directo:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/ATRPanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c Market/Debug/TimeAxisSnapshot.pm && perl -I. -c market.pl && prove -l t"
```

## Prompt mínimo para implementor

Implementa `tasks/0000j-time-axis-calendar-filter-partial-session-anchors.md`.

No tienes visión: usa esta transcripción como fuente visual. El debug NO parece roto: el snapshot actual reproduce la app. El problema es que el calendario mensual acepta anchors de sesiones parciales nocturnas (`5`, `12`, `19`, `26`) que TradingView no muestra como labels principales.

Corrige la regla general del calendario para penalizar/filtrar días cuya primera vela visible sea tarde (`>=17:00`) y que no tengan sesión diurna, sin filtrar viernes/cierres tempranos (`3`, `10`, `17`, `24`). Además, no basta con coincidir en textos: valida que los `x`/grid verticales queden casi equidistantes como en TradingView, con excepción del salto `3 -> 7`. Si `debug_time_axis_snapshot` no expone deltas/estadísticas suficientes para comprobar eso, mejora `Market/Debug/TimeAxisSnapshot.pm`.

No toques `MarketData.pm`. Agrega tests en `t/07`. Ejecuta la regresión completa.
