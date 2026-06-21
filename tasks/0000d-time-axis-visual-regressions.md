# Task 0000d: Corregir regresiones visuales del eje temporal post-0000c

## Spec relacionada

`specs/0000d-time-axis-visual-regressions.md`

## Objetivo

Corregir los fallos visuales detectados después de `0000c` sin revertir sus mejoras válidas.

Problemas a resolver:

1. La etiqueta negra inferior del crosshair está en el `price_canvas`, arriba del eje temporal. Debe estar sobre el `time_axis_canvas`, a la altura de las fechas/horas.
2. Los ticks sintéticos de `0000c` se generan en gaps demasiado grandes y producen horas comprimidas (`15:00`, `07:00`, `23:00`, etc.) y muchas líneas verticales juntas.
3. El grid vertical se dibuja incluso para labels ocultos por thinning, creando bloques densos de líneas aunque el texto no aparezca.

## Prueba TDD ya creada

Existe:

` t/04-chart-time-axis-visual-regressions.t `

Estado actual esperado antes de implementar:

- `t/00`, `t/01`, `t/02`, `t/03` pasan.
- `t/04` falla 4/8 tests:
  - crosshair no se dibuja en `time_axis_canvas`;
  - crosshair aún se dibuja en `price_canvas`;
  - gap cross-day sintetiza horas comprimidas;
  - grid se dibuja para label oculto.

No modifiques esta prueba salvo bug objetivo y justificado.

## Diagnóstico exacto

### A. Crosshair temporal en canvas incorrecto

Actualmente:

```perl
$self->{price_panel}->draw_crosshair($last_x, $price_y, $time_text);
```

`PricePanel::draw_crosshair()` dibuja la caja al fondo del `price_canvas`.

Pero la UI tiene un canvas separado:

```perl
$self->{time_axis_canvas}
```

Por eso la caja negra queda flotando arriba del eje temporal.

### B. Ticks sintéticos demasiado agresivos

En `compute_intraday_labels()`, la lógica de `0000c` sintetiza todas las fronteras intradía entre dos velas consecutivas visibles.

Eso está bien para un gap corto como:

```text
15:00 -> 18:00 con intervalo 90m => 16:30
```

Pero está mal para gaps largos como:

```text
2026-04-25 15:00 -> 2026-04-26 17:00
```

Ahí no se deben meter `16:30`, `18:00`, `19:30`, etc. comprimidas entre dos velas.

### C. Grid para labels ocultos

En `PricePanel::draw_time_axis()` se dibuja grid si `grid=1` aunque `label=0`. Eso permite que el thinning quite texto pero deje muchas líneas verticales.

## Implementación requerida

### 1. Mover la etiqueta del crosshair temporal al time axis

Implementación sugerida mínima:

- Agregar método nuevo en `PricePanel.pm`, por ejemplo:

```perl
sub draw_time_crosshair_label {
    my ($self, $canvas, $x, $time_text) = @_;
    ...
}
```

- Debe:
  - borrar un tag propio, por ejemplo `time_axis_crosshair`;
  - retornar si no hay `$canvas`, `$x` o `$time_text`;
  - calcular ancho con `char_w=7`, `pad_x=6`;
  - clamp horizontal igual que `draw_crosshair`;
  - dibujar rectángulo y texto centrados verticalmente en el canvas del eje temporal;
  - usar colores `label_bg`, `label_fg`, `crosshair_line`.

- En `ChartEngine::_draw_crosshair_all()`:
  - si existe `$self->{time_axis_canvas}`:
    - llamar a `price_panel->draw_crosshair($last_x, $price_y, undef)` para que NO pinte caja temporal en price canvas;
    - llamar a `price_panel->draw_time_crosshair_label($self->{time_axis_canvas}, $last_x, $time_text)`;
  - si NO existe `time_axis_canvas`, conservar fallback anterior: `draw_crosshair($last_x, $price_y, $time_text)`.

- Al limpiar crosshair (`last_x` undef), también borrar `time_axis_crosshair` del canvas temporal.

### 2. Restringir ticks sintéticos a gaps intradía cortos

En `compute_intraday_labels()` modificar el bloque de ticks sintéticos:

Reglas obligatorias:

- Solo sintetizar si `$daily_mode` es falso.
- Solo sintetizar si `prev_tm` y `tm` son el mismo día local:
  - mismo año, mes y `day_of_month`.
- Calcular cuántas fronteras intermedias habría:

```perl
my $boundary_count = $last_k - $first_k + 1;
```

- Si `$boundary_count > 1`, no sintetizar para ese par.
- Si `$boundary_count <= 0`, no sintetizar.
- Si `$boundary_count == 1`, sintetizar esa única frontera.

Esto conserva el caso `15:00 -> 18:00` con `16:30`, pero evita meter docenas de horas en gaps de noche/fin de semana.

No crear velas. No tocar `MarketData.pm`.

### 3. No dibujar grid para labels ocultos

En `PricePanel::draw_time_axis()` cambiar la condición de grid.

Ahora está conceptualmente así:

```perl
if ($draw_grid && $item_grid) {
    createLine(...)
}
next unless $draw_labels && $item_label;
```

Debe quedar equivalente a:

```perl
my $draw_item_grid = $draw_grid && $item_grid && $item_label;
if ($draw_item_grid) {
    createLine(...)
}
next unless $draw_labels && $item_label;
```

Hacerlo tanto para fechas como para horas.

Nota: si necesitas que fechas prioritarias mantengan grid, asegúrate de que su `label` siga siendo 1 por el algoritmo de thinning. No dibujar grid para items ocultos.

## Criterios de aceptación

- `prove -l t` pasa completo.
- `t/04-chart-time-axis-visual-regressions.t` pasa.
- `t/03-chart-time-axis-polish.t` sigue pasando.
- La GUI muestra la caja negra del crosshair sobre la barra inferior de tiempo, no arriba en el panel de precio.
- En gaps multi-día no aparecen horas sintéticas comprimidas.
- No se ven bloques densos de líneas verticales causadas por labels ocultos.
- El caso 90m corto sigue mostrando `15:00 -> 16:30 -> 18:00`.

## Comandos obligatorios

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

Si trabajas en Fedora:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

## Archivos permitidos

- `Market/ChartEngine.pm`
- `Market/Panels/PricePanel.pm`
- `t/04-chart-time-axis-visual-regressions.t` solo si hay error objetivo y justificado.

## Qué no tocar

- `Market/MarketData.pm`
- `Data/2026_03.csv`
- `Market/Indicators/*`
- `Market/Overlays/*`
- Replay/Fase 2
- `market.pl`, salvo que sea estrictamente necesario para una integración visual; en principio no hace falta.
- No hacer refactor amplio.
- No hacer commit/push.

## Entrega esperada

Reportar:

1. Archivos modificados.
2. Cómo moviste el crosshair temporal al `time_axis_canvas`.
3. Cómo limitaste ticks sintéticos para que no exploten en gaps largos.
4. Cómo evitaste grid para labels ocultos.
5. Salida completa de `prove -l t`.
6. Si abriste GUI o no; si sí, reportar validación visual.
