# Task 0000f: Tickmarks ponderados tipo TradingView/Supercharts

## Spec relacionada

`specs/0000f-time-axis-weighted-tickmarks-tradingview.md`

## Contexto

El agente implementó `0000e` y la suite pasa:

```text
Files=6, Tests=83
Result: PASS
```

Pero la validación visual del usuario contra TradingView 1m sigue fallando. `0000e` resolvió lo lógico mínimo —sin índices fraccionales/sintéticos— pero la selección visual de ticks aún no replica TradingView.

Referencia local oficial documentada:

```text
docs/adr/0002-official-tradingview-time-axis-reference.md
C:\Users\ASUS ROG\AppData\Local\Temp\opencode\lwc
```

Archivos clave de referencia:

- `src/model/tick-marks.ts`
- `src/model/time-scale.ts`
- `src/model/horz-scale-behavior-time/time-scale-point-weight-generator.ts`
- `src/model/horz-scale-behavior-time/types.ts`
- `src/model/horz-scale-behavior-time/horz-scale-behavior-time.ts`
- `src/model/horz-scale-behavior-time/default-tick-mark-formatter.ts`
- `src/gui/time-axis-widget.ts`

## Objetivo

Reemplazar la política actual de `compute_intraday_labels()` por una selección de tickmarks ponderados tipo TradingView:

- candidatos reales por índice lógico;
- pesos temporales;
- selección por prioridad de peso y separación mínima;
- día intradía como `15`, `16`, etc., en negrita;
- horas con cadencia 5m/15m/30m/1h/90m/3h/6h según zoom;
- crosshair sigue alineado con eje inferior.

## Archivos permitidos

- `Market/ChartEngine.pm`
- `Market/Panels/PricePanel.pm`
- Tests nuevos o existentes en `t/`
- Docs de spec/task solo si hay que corregir ambigüedad

## No tocar

- `Market/MarketData.pm`
- `Data/2026_03.csv`
- `Market/Indicators/*`
- `Market/Overlays/*`
- Replay/Fase 2
- `market.pl` salvo necesidad estricta
- No hacer commit/push
- No copiar código TypeScript literal de TradingView

## Implementación requerida

### 1. Añadir helpers de pesos temporales en `ChartEngine.pm`

Crear helpers pequeños, sin refactor masivo, por ejemplo:

```perl
sub _time_axis_weight_for_point { ... }
sub _time_axis_label_for_weight { ... }
sub _time_axis_intraday_weight { ... }
sub _select_weighted_time_labels { ... }
```

Pesos recomendados:

```perl
YEAR    => 70
MONTH   => 60
DAY     => 50
HOUR12  => 33
HOUR6   => 32
HOUR3   => 31
HOUR1   => 30
MIN90   => 29
MIN30   => 22
MIN15   => 21.5
MIN5    => 21
MIN1    => 20
```

`MIN90` y `MIN15` son extensiones observadas en Supercharts, aunque Lightweight Charts abierto no las incluya explícitamente.

### 2. Construir candidatos desde velas reales

Dentro de `compute_intraday_labels()`:

- Recorrer los timestamps visibles reales.
- Mantener el timestamp anterior real para detectar cambios.
- Para cada vela visible, asignar `weight`:
  - año nuevo: `YEAR`;
  - mes nuevo: `MONTH`;
  - día nuevo: `DAY`;
  - si no, detectar frontera intradía relevante.
- No retornar índices fraccionales.
- No crear candidatos sintéticos.

Importante:

- Si hay cambio de día y no existe vela exacta `00:00`, el primer punto real del nuevo día recibe peso `DAY`.
- Si hay `00:00`, ese mismo índice se etiqueta como día.

### 3. Selección tipo `TickMarks.build()`

No hacer thinning lineal cronológico como ahora.

Implementar selección de candidatos por grupos de peso:

1. Agrupar candidatos por `weight`.
2. Ordenar pesos descendente.
3. Mantener lista aceptada ordenada por índice.
4. Para cada candidato del peso actual, buscar vecino izquierdo/derecho aceptado.
5. Aceptar solo si cabe contra ambos lados:

```perl
($idx - $left_idx >= $min_indices) && ($right_idx - $idx >= $min_indices)
```

6. Si no cabe, descartar el candidato de menor peso.

Esto garantiza que un día `15` no sea desplazado por `23:55` o `00:05`.

### 4. Calcular separación mínima como TradingView

Inspirarse en `time-scale.ts`:

```ts
const defaultTickMarkMaxCharacterLength = 8;
const pixelsPer8Characters = (fontSize + 4) * 5;
const pixelsPerCharacter = pixelsPer8Characters / 8;
const maxLabelWidth = pixelsPerCharacter * tickMarkMaxCharacterLength;
const maxIndexesPerMark = Math.ceil(maxLabelWidth / spacing);
```

En Perl/Tk, usar equivalente simple:

```perl
my $font_size = 9;
my $max_chars = 8;
my $pixels_per_8 = ($font_size + 4) * 5; # 65 px aprox
my $max_label_width = $pixels_per_8;     # o calibrar 70-85 px
my $min_indices = int(($max_label_width / $bar_w) + 0.999);
$min_indices = 1 if $min_indices < 1;
```

No usar 90/100 rígido si impide que aparezcan cadencias como TradingView en zoom cercano.

### 5. Formatear labels según peso

Cambiar formato del eje inferior:

- `YEAR`  => `2026`
- `MONTH` => `Apr`
- `DAY`   => `15` o `16` sin mes
- intradía => `HH:MM`

Mantener `_crosshair_time_label()` como fecha completa + hora:

```text
Thu 23 Apr '26 09:31
```

### 6. Dibujar día en negrita y grid tenue

En `PricePanel.pm`:

- `is_date`/`weight >= DAY` debe usar fuente bold para el texto.
- El grid vertical de día debe seguir siendo sutil. Si actualmente el color de fecha es muy fuerte, reducirlo para aproximarse a TradingView.
- Mantener: no dibujar grid si `label=0`.

### 7. Agregar tests visuales automatizables

Crear un test nuevo, por ejemplo:

```text
t/06-time-axis-weighted-tickmarks.t
```

Debe cubrir al menos:

1. Día intradía se formatea como `15`, no `15 Apr`.
2. En fixture `23:45..01:20`, aparece `15` y no `00:00` en ese índice.
3. Las horas cercanas no desplazan el día.
4. Labels visibles siguen siendo índices enteros.
5. Crosshair sigue coincidiendo con labels `HH:MM`.
6. Fixtures de zoom simulado producen cadencias esperadas en 1m:
   - cercano: 5m o 15m;
   - medio: 30m o 1h;
   - amplio: 90m o 3h.

No fragilizar excesivamente el test con píxeles exactos; verificar textos/cadencias.

## Comando obligatorio

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

Si trabaja en Fedora:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

## Validación visual obligatoria

Después de pasar tests, abrir GUI en 1m y comparar contra las capturas de TradingView:

- Zoom muy cercano: `23:55 | 15 | 00:05 | 00:10`.
- Zoom cercano: `23:45 | 15 | 00:15 | 00:30`.
- Zoom medio: `23:30 | 15 | 00:30 | 01:00`.
- Zoom medio-amplio: `23:00 | 15 | 01:00 | 02:00`.
- Zoom amplio: `22:00 | 15 | 01:30 | 03:00 | 04:30`.
- Zoom más amplio: `22:00 | 15 | 03:00 | 06:00 | 09:00`.

## Entrega esperada

Reportar:

1. Archivos modificados.
2. Cómo implementaste pesos temporales.
3. Cómo seleccionaste labels por prioridad de peso y separación mínima.
4. Cómo formateaste días/meses/años.
5. Qué pruebas agregaste/modificaste.
6. Salida completa de `prove -l t`.
7. Resultado de validación visual GUI, con discrepancias si quedan.
