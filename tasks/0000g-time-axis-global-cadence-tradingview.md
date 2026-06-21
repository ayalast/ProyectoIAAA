# Task 0000g: Cadencia global uniforme del eje temporal tipo TradingView

## Spec relacionada

`specs/0000g-time-axis-global-cadence-tradingview.md`

## Contexto

`0000f` fue implementada y añadió tickmarks ponderados, pero la validación visual manual del usuario sigue fallando.

Problema principal confirmado por el usuario:

> Las distancias entre días/horas no son uniformes y el eje mezcla fechas y horas de forma irregular. Hay días sin horas intermedias mientras otros sí tienen horas, y el resultado no se parece a TradingView en zoom alejado.

Ejemplos de secuencias visualmente incorrectas observadas en la app:

```text
06:00 | 12:00 | 18:00 | 24 | 06:00 | 12:00 | 26 | 27 | 06:00 | 12:00 | 18:00 | 28
```

```text
12:00 | 22 | 12:00 | 23 | 12:00 | 24 | 09:00 | 26 | 27 | 12:00 | 28
```

```text
15 | 11:30 | 16 | 11:30 | 17 | 19 | 06:00 | 21 | 11:30 | 22 | 11:30 | 23 | 11:30 | 24 | 26 | 06:00 | 28
```

Referencia visual TradingView esperada:

```text
22:00 | 15 | 03:00 | 06:00 | 09:00 | 12:00 | 15:00 | 18:00 | 22:00 | 16 | 03:00
```

Esta referencia es obligatoria como objetivo de cierre. Si durante desarrollo se usa una secuencia de solo días para evitar caos, debe marcarse como fallback temporal/incompleto, no como final aceptado.

Calibración visual confirmada:

- TradingView: `NQ1!` — NASDAQ 100 E-mini Futures, CME, `15m`.
- Zona: `UTC-5` / Bogotá-Quito, compatible con timestamps del CSV.
- CSV local: `Data/2026_03.csv` contiene realmente abril 2026 (`2026-04-01T00:00:00-05:00` a `2026-04-30T23:59:00-05:00`).
- En TradingView, el gap de sesión `15:45 -> 17:00` en 15m se muestra comprimido y sin labels intermedios `16:00/16:15/16:30/16:45`. No inventar esos labels salvo futura implementación explícita de whitespace bars.

## Objetivo

Modificar la política final de labels del eje temporal para que elija un **plan global de cadencia** por ventana visible, no solo candidatos individuales por peso.

La app debe evitar mezclas locales irregulares y cerrar con **Modo A obligatorio**:

1. días + horas con cadencia uniforme;
2. mes/año solo en zooms extremadamente superiores si aplica a datasets más amplios;
3. modo diario conservador solo como fallback temporal/incompleto, nunca como cierre final cuando TradingView muestra días + horas.

## Archivos permitidos

- `Market/ChartEngine.pm`
- `Market/Panels/PricePanel.pm` solo si hace falta conservar grid/estilo
- Tests en `t/`, preferiblemente un nuevo `t/07-time-axis-global-cadence.t`
- Specs/tasks si hay que aclarar el contrato

## No tocar

- `Market/MarketData.pm` sin autorización explícita
- `Data/2026_03.csv`
- `Market/Indicators/*`
- `Market/Overlays/*`
- Replay/Fase 2
- `market.pl` salvo necesidad estricta
- No hacer refactor amplio
- No commit/push

## Implementación requerida

### 1. Mantener los avances de 0000e/0000f

No romper:

- índices enteros reales para velas existentes;
- sin ticks sintéticos/fraccionales desconectados del crosshair;
- si se agregan puntos lógicos/whitespace para lograr Modo A, deben ser conocidos por el eje y el crosshair, con pruebas explícitas;
- crosshair coincide con labels `HH:MM`;
- días como `15`, `16`, no `15 Apr` en intradía;
- caja negra en `time_axis_canvas`;
- grid solo para labels visibles;
- día en bold;
- grid tenue.

### 2. Añadir fase de planificación global

En `compute_intraday_labels()`, no retornar directamente candidatos aceptados localmente.

Agregar una fase conceptual:

```text
candidatos reales -> planes de cadencia -> score de uniformidad -> elegir mejor plan -> labels finales
```

Helpers sugeridos:

```perl
sub _build_time_axis_candidates { ... }
sub _build_time_axis_plan { ... }
sub _score_time_axis_plan_uniformity { ... }
sub _choose_time_axis_plan { ... }
sub _finalize_time_axis_plan { ... }
```

Mantener helpers pequeños; no hacer refactor masivo.

### 3. Definir planes candidatos

Crear planes por cadencia dominante:

```text
5m, 15m, 30m, 1h, 90m, 3h, 6h, 1D, Month, Year
```

Cada plan debe producir labels coherentes con el eje/crosshair:

- `DAY` se incluye como anchor si cae en la ventana.
- El plan final aceptado es intradía Modo A: incluir horas solo de la cadencia elegida y anchors de día.
- Si se usa un plan diario, marcarlo como fallback temporal/incompleto, no como éxito final de `0000g`.
- Si el plan es mensual/anual, no incluir días/horas; esto solo aplica a zooms extremadamente superiores/datasets más amplios.

### 4. Reglas para plan intradía

Un plan intradía es válido solo si:

- sus horas siguen una única cadencia dominante;
- los días reemplazan medianoche o primer punto real del día;
- no genera segmentos internos donde algunos días tienen horas y otros días comparables no tienen ninguna;
- no genera secuencias visuales tipo `DAY | HOUR | DAY | DAY | HOUR`;
- no produce variación extrema en distancias visuales.

Si falla, probar una cadencia superior/inferior o ajustar la estrategia hasta lograr Modo A. El modo diario solo puede ser fallback de seguridad durante desarrollo, no aceptación final.

### 5. Score de uniformidad

Para cada plan calcular, al menos:

```perl
min_gap_px
max_gap_px
ratio = max_gap_px / min_gap_px
```

Recomendación inicial:

- `min_gap_px` debe ser suficiente para labels (`>= 60px` aprox. o derivado de ancho de label).
- Para modo intradía, `ratio` no debe ser extremo.
- Permitir excepciones en bordes de ventana, pero no en segmentos centrales.

También calcular consistencia por día:

- Para cada par de anchors DAY internos, contar cuántos labels horarios hay entre ellos.
- Si la varianza es alta o hay mezcla de días con 0 horas y otros con varias horas, el plan intradía es inválido.

### 6. Modo A obligatorio, sin degradación final a diario

Si el mejor plan intradía produce irregularidad, no mostrar esa mezcla irregular. Pero la tarea no se considera terminada hasta producir Modo A: días + horas uniformes.

Ejemplo inválido actual:

```text
24 | 06:00 | 12:00 | 26 | 27 | 06:00 | 12:00 | 18:00 | 28
```

Debe convertirse a una secuencia Modo A con horas uniformes entre anchors de día, por ejemplo el patrón conceptual:

```text
22:00 | 24 | 03:00 | 06:00 | 09:00 | 12:00 | 15:00 | 18:00 | 22:00 | 26 | 03:00
```

adaptado a las velas/puntos lógicos disponibles y manteniendo coherencia con el crosshair.

Una salida tipo:

```text
24 | 26 | 27 | 28
```

solo puede aceptarse como fallback temporal para evitar caos durante desarrollo, no como cierre final de `0000g`.

### 7. Tests automatizados nuevos

Crear:

```text
t/07-time-axis-global-cadence.t
```

Debe cubrir al menos:

1. Fixture multi-día/gaps no retorna secuencia con días y horas irregularmente mezcladas.
2. Si una ventana contiene varios días internos y el plan muestra horas, cada segmento día-a-día interno tiene cantidad comparable de horas.
3. Secuencia tipo `DAY | HOUR | DAY | DAY | HOUR` es rechazada o no generada.
4. En zoom alejado problemático, genera Modo A con días + horas uniformes; si cae a diario, el test debe dejar claro que es fallback incompleto/no final.
5. Labels visibles mantienen índices enteros.
6. Crosshair sigue coincidiendo con labels horarios.
7. La suite anterior (`t/00..t/06`) sigue pasando.

### 8. Sistema de debug separado para comparación exacta

Agregar un módulo removible, fuera del flujo normal de render, para inspeccionar el eje temporal por estado actual o por rango explícito:

```text
Market/Debug/TimeAxisSnapshot.pm
```

Contrato esperado:

```perl
my $snapshot = $chart->debug_time_axis_snapshot(
    timeframe    => '15m',
    start_ts     => '2026-04-29T15:00:00-05:00',
    end_ts       => '2026-05-01T00:00:00-05:00',
    canvas_width => 1400,
);
```

Debe devolver al menos:

- `labels_text` exacto para comparar con TradingView;
- `cadence_min`;
- `visible_bars`, `start_index`, `end_index`, `first_ts`, `last_ts`;
- `bar_w`, `plot_width`, `x_shift`, `canvas_width`;
- `labels` visibles con texto, índice local/global, timestamp y coordenada `x`;
- candidatos ocultos/all candidates;
- gaps detectados;
- `summary` textual.

Este módulo no debe afectar runtime normal. `ChartEngine.pm` puede tener solo un wrapper mínimo. La comparación principal desde ahora es: el usuario pasa screenshot/rango de TradingView, la IA extrae el snapshot de la app y compara por datos exactos antes de pedir cualquier captura interna de la app.

## Comando obligatorio

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

Si trabaja en Fedora:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

## Validación manual

Solo pedir validación manual al usuario cuando:

1. `prove -l t` pase;
2. el nuevo test `t/07-time-axis-global-cadence.t` pase;
3. se haya inspeccionado por código que las secuencias irregulares ya no aparecen.

Entonces pedir screenshots de los mismos zooms problemáticos y comparar contra TradingView.

## Entrega esperada

Reportar:

1. Archivos modificados.
2. Cómo elegiste el plan global de cadencia.
3. Qué métricas de uniformidad usaste.
4. Cómo garantizaste Modo A obligatorio y, si existe fallback diario, por qué no se considera aceptación final.
5. Tests agregados/modificados.
6. Salida completa de `prove -l t`.
7. Si abriste GUI, resultado visual; si no, decirlo explícitamente.
