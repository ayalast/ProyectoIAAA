# Spec 0000e: Coherencia definitiva del eje temporal tipo TradingView

## Estado

Bloqueante antes de Fase 2. Esta spec reemplaza la parte de `0000c/0000d` que permitía ticks temporales sintéticos/fraccionales.

## Referencia investigada

Se revisó el código abierto oficial de TradingView Lightweight Charts en una carpeta temporal fuera del repo/OneDrive:

```text
C:\Users\ASUS ROG\AppData\Local\Temp\opencode\lwc
```

Archivos clave:

- `src/model/time-scale.ts`
- `src/model/tick-marks.ts`
- `src/model/horz-scale-behavior-time/time-scale-point-weight-generator.ts`
- `src/views/time-axis/crosshair-time-axis-view.ts`
- `src/model/horz-scale-behavior-time/default-tick-mark-formatter.ts`

Hallazgos relevantes:

1. La escala horizontal se basa en **índices lógicos** y `barSpacing`, no en coordenadas de tiempo real continuas.
2. `indexToCoordinate(index)` calcula una coordenada desde el índice lógico; los ticks se construyen desde `TickMark.index`.
3. `TickMarks.build(spacing, maxWidth, ...)` filtra marcas por separación mínima en **índices**, de mayor peso a menor peso.
4. El crosshair toma el mismo índice aplicado (`appliedIndex`) y formatea el `TimeScalePoint` de ese índice. Por eso la etiqueta negra del crosshair y el eje inferior no deben discrepar.
5. Los pesos temporales se calculan comparando puntos consecutivos reales (`Year`, `Month`, `Day`, `Hour12`, `Hour6`, etc.), pero las marcas se adhieren a puntos/índices existentes.

Conclusión para nuestra app:

- No debemos dibujar labels/grid en índices fraccionales si no existe una vela o un punto lógico real.
- Si queremos mostrar tiempos sin vela en el futuro, debe existir una representación explícita de whitespace/logical points y el crosshair debe conocerla. Eso queda fuera de esta spec.
- Para cerrar Fase 1, el eje temporal debe ser coherente con las velas reales: todo label/grid visible se ancla a un índice entero de vela real.

## Problema actual

Aunque `0000d` arregló la posición del crosshair y limitó algunos gaps, aún quedan dos problemas centrales:

1. La barra inferior puede mostrar marcas a posiciones que no corresponden a una vela real, especialmente por ticks sintéticos de `0000c`.
2. Al poner el crosshair sobre una vela o sobre una línea vertical del eje, la caja negra inferior no siempre coincide con la hora/fecha del eje inferior.
3. Las líneas verticales del grid no mantienen una cadencia visual dominante; se mezclan fechas forzadas (`day_change`) con horas, creando intervalos visuales irregulares como en la captura: `19 Apr`, `20 Apr`, `06:00`, `12:00`, `18:00`, `21 Apr` con espacios desiguales.

## Objetivo

Rehacer la política final de ticks del eje temporal para que sea coherente y casi equidistante, estilo TradingView:

- Misma fuente lógica para velas, eje inferior y crosshair.
- Sin ticks fraccionales/sintéticos invisibles para el modelo de datos.
- Ticks seleccionados por separación mínima en índice/píxel.
- Una cadencia dominante por ventana visible.
- Fechas como reemplazo/etiqueta de un tick real de la cadencia, no como inyección extra que rompe el ritmo.

## Requisitos funcionales

### R1. No índices fraccionales en labels/grid

`compute_intraday_labels()` no debe retornar items con `index` fraccional.

Permitido:

```perl
{ index => 120, text => '12:00', ... }
```

No permitido:

```perl
{ index => 91.5, text => '16:30', ... }
```

Motivo: el crosshair se resuelve contra índices de velas reales. Un label a `91.5` no puede coincidir siempre con la caja negra del crosshair.

### R2. No ticks sintéticos sin punto lógico real

Eliminar o desactivar la generación de ticks sintéticos/interpolados dentro de gaps.

Esto cambia el criterio anterior de `0000c`:

- Antes se pedía sintetizar `16:30` entre `15:00` y `18:00`.
- Ahora queda prohibido si no hay vela/punto lógico real en `16:30`.

Si en el futuro se desea ese comportamiento, debe implementarse con whitespace/logical points conocidos por el eje y el crosshair, no con índices fraccionales ocultos.

### R3. Crosshair y eje inferior deben coincidir

Para cualquier label visible del eje inferior:

- convertir `label.index` a X con la misma `Scales::index_to_center_x()`;
- poner el crosshair en esa X;
- `_crosshair_time_label()` debe terminar con la misma hora si el label es `HH:MM`.

Ejemplo:

```text
label inferior: 13:00
crosshair en esa X: Mon 20 Apr '26 13:00
```

### R4. Cadencia visual dominante y casi equidistante

Para una ventana continua de 1m/5m/15m, el eje debe elegir un intervalo dominante y mostrar labels/grid con separación lógica regular.

Ejemplos esperados:

```text
06:00 | 12:00 | 18:00 | 21 Apr | 06:00
```

donde `21 Apr` reemplaza al tick de medianoche real (`00:00`), no se inserta adicionalmente.

No permitido:

```text
19 Apr -- 20 Apr ------ 06:00 ------ 12:00 ------ 18:00 ------ 21 Apr
```

si `19 Apr` y `20 Apr` fueron inyectados fuera de la cadencia dominante y generan distancias visuales demasiado distintas.

### R5. Fechas no deben ser ticks extra obligatorios

El cambio de día (`day_change`) no debe forzar un tick si ese índice no cae en la cadencia seleccionada o si rompe la separación mínima.

Regla recomendada:

- Si un tick real de la cadencia cae en `00:00`, formatearlo como fecha (`DD Mon`) y `is_date=1`.
- Si no hay vela en `00:00`, se puede usar la primera vela real del día como fecha solo si pasa el mismo filtro de separación mínima y no rompe la cadencia visual.
- No insertar fechas extra con prioridad absoluta si quedan demasiado cerca de horas vecinas.

### R6. Grid solo para labels visibles

Conservar lo arreglado en `0000d`: no dibujar grid si `label=0`.

## Diseño sugerido

Inspirado en `lightweight-charts/src/model/tick-marks.ts`:

1. Construir candidatos solo a partir de timestamps reales visibles o cercanos a la ventana.
2. Asignar peso/categoría:
   - `date` para `00:00` o primer punto real de nuevo día;
   - `time` para fronteras del intervalo seleccionado.
3. Elegir una separación mínima en índices:

```perl
my $min_indices = int(($min_label_px / $bar_w) + 0.999);
```

4. Insertar candidatos solo si están al menos a `$min_indices` del anterior aceptado.
5. No generar candidatos con índice fraccional.
6. Ordenar por índice antes de retornar.
7. El texto de fecha debe reemplazar a la hora en ese mismo índice; no crear un segundo tick.

## Criterios de aceptación

- `prove -l t` pasa completo.
- `t/05-time-axis-tradingview-coherence.t` pasa.
- `t/03` y `t/04` actualizados ya no exigen `16:30` sintético sin vela.
- Ningún label/grid visible tiene índice fraccional.
- Si el crosshair se pone sobre la X de un label `HH:MM`, la caja negra termina con esa misma hora.
- En zoom amplio, las líneas verticales del grid se ven casi equidistantes y con cadencia dominante.
- La caja negra del crosshair sigue en el `time_axis_canvas`.
- Paneo fraccional de `0000c` sigue funcionando.

## Fuera de alcance

- Crear whitespace bars/puntos lógicos.
- Cambiar `MarketData.pm`.
- Reescribir todo el motor de escalas.
- Fase 2 (`0001+`).
- Refactor amplio de `ChartEngine.pm`.
