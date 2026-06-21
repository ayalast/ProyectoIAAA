# Spec 0000c: Pulido visual post-0000b — 90m, crosshair con hora y paneo suave

Fuente:
- Validación visual del usuario después de que `tasks/0000b-time-axis-tradingview-scale.md` pasó tests.
- Comparación manual contra TradingView/Supercharts en temporalidad 1m.
- Imágenes aportadas por el usuario: TradingView muestra 90m con `15:00`, `16:30`, `18:00`; la app actual salta de `15:00` a `18:00`. TradingView muestra crosshair inferior con fecha + hora; la app actual muestra solo fecha. TradingView permite paneo horizontal fraccional con velas parcialmente recortadas; la app actual salta por barras enteras.

## Objetivo

Cerrar los fallos visuales que no quedaron cubiertos por `0000b` antes de pasar a `0001`:

1. En intervalos de `90m`, no saltarse fronteras de reloj cuando caen dentro de un gap de datos; debe aparecer `16:30` entre `15:00` y `18:00` si esa frontera está dentro del rango visible.
2. La etiqueta inferior negra del crosshair debe mostrar fecha **y hora**, estilo TradingView: `Thu 23 Apr '26 09:31`.
3. El paneo horizontal del gráfico debe ser suave/fraccional, no por saltos enteros de vela. Deben poder verse velas parcialmente cortadas en los bordes.

## Problema

`0000b` pasó pruebas automatizadas, pero la validación visual encontró tres huecos:

### 1. Fronteras de 90m dentro de gaps

La implementación actual escanea timestamps visibles y solo crea ticks si existe una vela exactamente en la frontera. En TradingView, si el eje está en `90m`, la frontera `16:30` debe aparecer aunque el tramo visible tenga un gap entre `15:00` y `18:00`. Como la escala X del proyecto sigue siendo por índice de vela, no se debe crear hueco temporal; pero sí se debe anclar el tick `16:30` a una posición visual coherente entre la vela anterior y la siguiente.

Regla propuesta para gaps intradía:

- Si hay dos timestamps visibles consecutivos `prev_tm` y `tm` con una o más fronteras de intervalo entre ellos:
  - generar un tick sintético para cada frontera intermedia importante;
  - su `index` puede ser fraccional, por interpolación lineal entre los índices locales de las velas vecinas;
  - `PricePanel::draw_time_axis` y `Scales::index_to_center_x` ya aceptan índices numéricos; no hay obligación de que `index` sea entero para ticks de eje.
- No crear velas ni alterar datos; solo ticks/labels del eje temporal.

Ejemplo esperado en 90m:

```text
13:30, 15:00, 16:30, 18:00, 19:30, ...
```

### 2. Crosshair inferior sin hora

La app ahora muestra algo como:

```text
Wed 29 Apr '26
```

TradingView muestra fecha + hora:

```text
Wed 17 Jun '26 16:16
```

Contrato del proyecto:

```text
Dow DD Mon 'YY HH:MM
```

Ejemplo:

```text
Thu 23 Apr '26 09:31
```

Se mantiene el formato aceptado anterior como prefijo, pero se añade la hora.

### 3. Paneo horizontal por saltos enteros

La app actual calcula durante drag:

```perl
my $delta_bars = int(($current_x - $drag_start_x) / $bar_w);
$self->{offset} = drag_start_offset + $delta_bars;
```

Esto produce saltos por vela entera. En zoom máximo con 2 velas, las velas no se desplazan suavemente: una desaparece y otra aparece, sin posiciones intermedias.

TradingView permite posiciones fraccionales: al arrastrar un poco, una vela puede quedar centrada y las velas laterales parcialmente cortadas por los bordes.

Contrato del proyecto:

- Mantener `offset` como entero para seleccionar la ventana base de datos.
- Añadir/usar un `x_shift` fraccional para desplazar visualmente las velas durante paneo.
- Reutilizar el mecanismo existente `ctrl_zoom_x_shift` o renombrarlo a un concepto más general solo si es un cambio pequeño y seguro.
- En drag horizontal:
  - calcular `delta_float = (current_x - drag_start_x) / bar_w`;
  - separar `delta_whole = floor/trunc` y `delta_px_remainder`;
  - actualizar `offset` con la parte entera;
  - actualizar `x_shift` con la parte fraccional en píxeles;
  - al cruzar una vela completa, normalizar para que el shift quede en un rango estable, por ejemplo `[-bar_w, bar_w]`.
- El render ya propaga `x_shift` a `PricePanel`, `ATRPanel` y eje temporal; debe usarse para paneo, no solo para Ctrl+zoom.

## Comportamiento esperado

### Eje 90m

- En 1m, cuando `_time_axis_interval_minutes` elige `90`, el eje debe mostrar fronteras cada 90 minutos desde medianoche:
  - `00:00`, `01:30`, `03:00`, `04:30`, `06:00`, `07:30`, `09:00`, `10:30`, `12:00`, `13:30`, `15:00`, `16:30`, `18:00`, `19:30`, `21:00`, `22:30`.
- Si una frontera cae dentro de un gap visible, mostrar el label/tick en posición interpolada entre las velas reales vecinas.
- No crear marcas absurdas por stride de índice; la hora debe seguir siendo frontera real.

### Crosshair inferior

- `_crosshair_time_label()` debe devolver:

```text
Dow DD Mon 'YY HH:MM
```

- Ejemplo exacto de prueba:

```text
Thu 23 Apr '26 09:31
```

- La caja negra inferior debe ampliar su ancho si hace falta para no cortar texto.

### Paneo horizontal suave

- Al arrastrar horizontalmente menos de una vela de distancia:
  - `offset` no necesariamente cambia;
  - `x_shift` sí debe cambiar;
  - el render debe desplazar velas y grid de forma visible.
- En zoom máximo (`visible_bars = 2`), debe ser posible dejar una vela centrada y las velas vecinas parcialmente recortadas en los bordes, como TradingView.
- El crosshair y la conversión X→índice deben respetar el `x_shift` activo.
- Al soltar drag, el estado debe quedar estable; no debe saltar visualmente a la posición entera más cercana salvo que se haya normalizado de manera imperceptible.

## Fuera de alcance

- No implementar Fase 2.
- No modificar `MarketData.pm` salvo bug estrictamente necesario.
- No cambiar el modelo de eje X a tiempo continuo.
- No crear velas falsas en gaps; solo ticks sintéticos del eje.
- No refactorizar masivamente `ChartEngine.pm`.

## Criterios de aceptación

- `t/03-chart-time-axis-polish.t` pasa.
- La suite completa `prove -l t` pasa.
- Crosshair inferior muestra fecha + hora, no solo fecha.
- En 90m, un gap `15:00 → 18:00` muestra también `16:30`.
- El paneo horizontal menor que una vela produce `x_shift` no-cero y no cambia `offset` hasta cruzar una vela completa.
- El render visual de velas, ATR y eje temporal se desplaza junto, sin desalinearse.
- `t/01-chart-time-axis.t` sigue pasando.

## Plan de verificación

Automático:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

Manual WSLg:

1. Abrir app.
2. En 1m, buscar zoom donde aparecen labels de 90m.
3. Confirmar que no salta `15:00 → 18:00`; debe aparecer `16:30` si esa frontera cae en el tramo visible.
4. Mover crosshair y confirmar caja inferior tipo `Wed 29 Apr '26 15:xx`.
5. En zoom máximo con 2 velas, arrastrar suavemente izquierda/derecha:
   - deben verse velas parcialmente cortadas;
   - no debe saltar solo por velas enteras.
