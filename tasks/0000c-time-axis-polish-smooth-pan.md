# Task 0000c: Pulido 90m, crosshair con hora y paneo horizontal suave

## Spec relacionada

`specs/0000c-time-axis-polish-smooth-pan.md`

## Objetivo

Corregir los tres fallos visuales encontrados después de `0000b`:

1. En intervalos de 90m, no saltarse la frontera `16:30` cuando cae dentro de un gap visible entre `15:00` y `18:00`.
2. Mostrar hora en la etiqueta inferior negra del crosshair: `Thu 23 Apr '26 09:31`.
3. Implementar paneo horizontal suave/fraccional para que las velas puedan desplazarse parcialmente y quedar recortadas en los bordes, estilo TradingView.

## Pruebas automatizadas ya creadas

Ya existe `t/03-chart-time-axis-polish.t`. En el estado actual debe fallar; el implementor debe hacerla pasar sin rediseñarla.

Cobertura:

- `_crosshair_time_label()` debe devolver `Thu 23 Apr '26 09:31`.
- En fixture 90m con gap, `compute_intraday_labels()` debe incluir `15:00`, `16:30`, `18:00`.
- Drag horizontal menor que una vela debe dejar `offset` igual y producir `ctrl_zoom_x_shift` no-cero.

## Archivos probablemente relevantes

- `Market/ChartEngine.pm`
  - `compute_intraday_labels`
  - `_crosshair_time_label`
  - `_crosshair_date_label` (solo reutilizar; no romper formato base)
  - `_start_horizontal_drag`
  - `_on_horizontal_drag`
  - `_end_drag`
  - `render`
  - `_clear_ctrl_zoom_state`
  - `_snap_crosshair_x`
- `Market/Panels/PricePanel.pm`
  - `draw_crosshair` si la caja inferior necesita más ancho para fecha+hora.
- `Market/Panels/Scales.pm`
  - probablemente no hace falta; ya soporta `x_shift` e índices fraccionales.
- `t/03-chart-time-axis-polish.t`
  - NO modificar salvo error objetivo y justificado.

## Pasos sugeridos

### 1. Crosshair con fecha + hora

- Mantener `_crosshair_date_label($tm)` como helper de fecha.
- Cambiar `_crosshair_time_label()` para devolver:

```perl
sprintf("%s %02d:%02d", $self->_crosshair_date_label($tm), $tm->hour, $tm->minute)
```

- Verificar que la caja inferior no se recorte. Si se recorta, ajustar `PricePanel::draw_crosshair` ancho/caracteres.

### 2. Ticks sintéticos en gaps para 90m y otros intervalos intradía

Problema actual:

- `compute_intraday_labels` solo crea tick si una vela visible cae exactamente en frontera.
- Si hay gap `15:00 -> 18:00`, falta `16:30`.

Implementación esperada:

- Durante el escaneo de timestamps visibles, mantener `prev_visible_el` y `prev_visible_tm`.
- Para cada par consecutivo visible `(prev, curr)`:
  - detectar fronteras reales del intervalo entre `prev_tm` y `curr_tm`.
  - para cada frontera intermedia `boundary_tm`:
    - crear item con `text => HH:MM`.
    - usar índice local fraccional interpolado entre `prev_local` y `curr_local`.
    - ejemplo simple: si solo importa posición media, `local = prev_local + ($boundary_epoch - prev_epoch) / ($curr_epoch - prev_epoch) * ($curr_local - prev_local)`.
- Además, seguir incluyendo ticks de velas reales que caen exactamente en frontera.
- No crear velas ni modificar MarketData.
- Evitar duplicados por texto/tiempo si la frontera coincide con una vela real.

Notas técnicas:

- `Time::Moment` puede compararse convirtiendo a epoch si hay método disponible; si no, usar diferencias por minutos calculadas desde fecha/hora dentro del fixture. Mantén la implementación simple y robusta.
- Los labels pueden tener `index` fraccional; `Scales::index_to_center_x` ya acepta número, no solo entero.
- Para fechas (`is_date=1`) mantener índice de la vela real de cambio de día, no sintético salvo que sea estrictamente necesario.

### 3. Paneo horizontal suave/fraccional

Problema actual:

```perl
my $delta_bars = int(($current_x - $self->{drag_start_x}) / $bar_w);
$self->{offset} = $self->_clamp_offset($self->{drag_start_offset} + $delta_bars);
```

Esto salta por velas enteras.

Implementación esperada:

- En `_start_horizontal_drag` guardar también:
  - `drag_start_x_shift => $self->{ctrl_zoom_x_shift} || 0`
  - quizá `drag_start_visible_bars` si hace falta.
- En `_on_horizontal_drag` calcular desplazamiento en píxeles:

```perl
my $dx = $current_x - $self->{drag_start_x};
my $bar_w = ...;
my $delta_float = $dx / $bar_w;
my $delta_whole = int($delta_float); # cuidando signo si se permite izquierda/derecha
my $remainder_px = $dx - ($delta_whole * $bar_w);
```

- Actualizar:
  - `offset = clamp(drag_start_offset + delta_whole)`
  - `ctrl_zoom_x_shift = drag_start_x_shift + $remainder_px` con signo correcto según el comportamiento visual.
- Normalizar si el signo queda invertido visualmente, pero conservar la intención: arrastre menor que `bar_w` => `offset` igual y `x_shift` no-cero.
- El render ya usa `ctrl_zoom_x_shift` en `price_scale`, `atr_scale` y time axis. Aprovechar eso.
- `_snap_crosshair_x` y `_crosshair_time_label` ya usan `x_shift`; verificar que no se rompan.
- En `_end_drag`, NO limpiar inmediatamente el `x_shift` si eso provoca salto visual. El shift debe persistir como parte de la posición horizontal hasta que se normalice con un cruce de vela o zoom/reset.
- En `reset_view`, `set_timeframe` y `_clear_ctrl_zoom_state`, sí puede volver a 0.

### 4. Ejecutar tests

- Hacer pasar `t/03-chart-time-axis-polish.t`.
- Asegurar que `t/01-chart-time-axis.t` sigue pasando.
- Correr suite completa.

## Criterios de aceptación

- `prove -l t` pasa.
- `_crosshair_time_label()` devuelve `Thu 23 Apr '26 09:31` en test.
- 90m con gap incluye `16:30`.
- Drag horizontal sub-bar produce `ctrl_zoom_x_shift != 0` y `offset` igual.
- No se rompe `0000b`.
- No se modifica `MarketData.pm`.

## Comandos de verificación

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

Si trabaja en Fedora:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

## Qué no tocar

- `Data/2026_03.csv`.
- `Market/MarketData.pm` salvo bug estrictamente necesario y justificado.
- `Market/Indicators/*`.
- Fase 2: Replay, Overlays, SMC, Liquidity, Strategy Builder, Volume Profile, VWAP.
- No hacer refactor amplio de `ChartEngine.pm`.
- No hacer commit/push sin aprobación humana.

## Entrega esperada

- Archivos modificados.
- Explicación de cómo resolviste los ticks sintéticos en gaps.
- Explicación de cómo resolviste paneo fraccional.
- Confirmación de crosshair con hora.
- Salida completa de `prove -l t`.
- Si no abriste GUI, decirlo explícitamente.
