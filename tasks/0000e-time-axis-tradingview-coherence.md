# Task 0000e: Coherencia definitiva del eje temporal tipo TradingView

## Spec relacionada

`specs/0000e-time-axis-tradingview-coherence.md`

## Objetivo

Alinear de forma definitiva la barra inferior de tiempo, las líneas verticales del grid y la etiqueta negra del crosshair.

Problema observado por el usuario:

- Las distancias entre marcas del eje temporal no son consistentemente casi equidistantes.
- El crosshair sobre una vela a veces muestra una hora en la caja negra que no coincide con la hora/fecha sugerida por la barra inferior.
- La app llegó a mostrar fechas/horas con cadencia visual irregular (`19 Apr`, `20 Apr`, `06:00`, `12:00`, `18:00`, `21 Apr`) y espacios desiguales.

Referencia:

- Se revisó `tradingview/lightweight-charts` en:

```text
C:\Users\ASUS ROG\AppData\Local\Temp\opencode\lwc
```

Hallazgo clave: TradingView Lightweight Charts ancla tickmarks a índices lógicos reales (`TickMark.index`) y el crosshair formatea el mismo punto lógico (`appliedIndex`). No hay labels fraccionales invisibles para el modelo.

## Cambio de decisión respecto a 0000c

`0000c` pidió sintetizar `16:30` entre `15:00` y `18:00`. Eso resolvía una observación puntual, pero introduce incoherencia sistémica: el eje puede mostrar una hora donde el crosshair no tiene una vela/punto lógico equivalente.

Desde `0000e` queda prohibido retornar ticks con índice fraccional/sintético.

Nuevo criterio:

- Mostrar solo labels/grid anclados a velas reales existentes.
- Si en el futuro se quiere mostrar `16:30` sin vela, primero habrá que implementar whitespace/logical points conocidos por el eje y el crosshair. Eso queda fuera de esta task.

## Pruebas automatizadas ya preparadas

Se agregó:

```text
t/05-time-axis-tradingview-coherence.t
```

Además se actualizaron `t/03` y `t/04` para que ya no exijan `16:30` sintético sin vela.

Estado actual esperado antes de implementar:

- `t/00`, `t/01`, `t/02` pasan.
- `t/03` falla porque aún aparece `16:30` sintético.
- `t/04` falla por el mismo motivo.
- `t/05` falla al menos por:
  - labels con índices fraccionales;
  - `16:30` inventado sin vela.

## Archivos permitidos

- `Market/ChartEngine.pm`
- `Market/Panels/PricePanel.pm` solo si hay que conservar/ajustar render de grid visible.
- `t/05-time-axis-tradingview-coherence.t` solo si hay bug objetivo y justificado.

## No tocar

- `Market/MarketData.pm`
- `Data/2026_03.csv`
- `Market/Indicators/*`
- `Market/Overlays/*`
- Replay/Fase 2
- `market.pl`, salvo necesidad estricta y justificada
- No hacer refactor amplio
- No hacer commit/push

## Implementación requerida

### 1. Eliminar ticks sintéticos/fraccionales

En `Market/ChartEngine.pm`, dentro de `compute_intraday_labels()`:

- eliminar o desactivar el bloque que genera ticks sintéticos entre `prev_tm` y `tm`.
- No hacer `push @items` con `$slocal` interpolado.
- Garantizar que todos los `index` retornados son enteros de velas reales.

Debe desaparecer este comportamiento:

```perl
my $slocal = $prev_local + $frac * ($local - $prev_local);
push @items, { index => $slocal, text => '16:30', ... };
```

### 2. Rehacer selección final con cadencia dominante

La selección actual mezcla `day_change` con boundaries y puede inyectar fechas fuera de ritmo.

Criterio recomendado:

1. Calcular `interval_minutes` con `_time_axis_interval_minutes()` como ahora.
2. Recorrer solo timestamps reales visibles.
3. Crear candidatos si:
   - la vela cae en boundary real del intervalo (`_is_time_axis_boundary`), o
   - es cambio de día y quieres permitir fecha, pero sin prioridad absoluta.
4. Si una vela es `00:00` o cambio real de día, formatear como fecha (`is_date=1`) en ese mismo índice. No crear tick extra.
5. Aplicar separación mínima en píxeles/índices de forma global:

```perl
my $min_label_px = 90; # o 100, consistente con _time_axis_interval_minutes
my $min_indices = int(($min_label_px / $bar_w) + 0.999);
$min_indices = 1 if $min_indices < 1;
```

6. Aceptar candidatos ordenados por índice solo si:

```perl
!defined($last_accepted_index) || $candidate_index - $last_accepted_index >= $min_indices
```

7. Si dos candidatos compiten por una zona, preferir el de mayor peso:
   - fecha real de medianoche/cambio de día puede reemplazar al tick horario en el mismo índice;
   - pero no debe romper la separación mínima.

Nota: esta task no exige copiar exactamente el algoritmo completo de lightweight-charts, pero sí su principio: ticks por índice lógico real + separación mínima por índice/píxel.

### 3. Mantener coherencia con crosshair

`_crosshair_time_label()` ya usa la misma `Scales` con `x_shift`, pero verificar:

- si un label visible `13:00` está en `index => N`, entonces X = `index_to_center_x(N)`;
- con `last_mouse_x = X`, `_crosshair_time_label()` debe terminar en `13:00`.

No usar coordenadas fraccionales para labels.

### 4. Conservar 0000d

No romper:

- caja negra del crosshair en `time_axis_canvas`;
- no dibujar grid para labels ocultos;
- limpieza del tag `time_axis_crosshair`.

### 5. Conservar paneo fraccional

No revertir la lógica de `ctrl_zoom_x_shift` de `0000c`.

## Criterios de aceptación

- `prove -l t` pasa completo.
- Ningún label/grid visible retorna índice fraccional.
- `16:30` no aparece si no existe vela/punto lógico real.
- Crosshair en la X de un label `HH:MM` muestra la misma hora en la caja negra.
- La cadencia visual del grid es dominante y casi equidistante en fixtures continuos.
- Visualmente, en GUI, la barra inferior no mezcla fechas/horas con distancias absurdamente distintas.

## Comando obligatorio

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

Si trabaja en Fedora:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

## Entrega esperada

Reportar:

1. Archivos modificados.
2. Qué bloque de ticks sintéticos se eliminó/desactivó.
3. Cómo garantizaste índices enteros/lógicos reales.
4. Cómo garantizaste cadencia visual casi equidistante.
5. Cómo verificaste coherencia crosshair ↔ eje inferior.
6. Salida completa de `prove -l t`.
7. Si abriste GUI, reportar validación visual; si no, decirlo explícitamente.
