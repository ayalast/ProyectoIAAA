# Spec 0000f: Tickmarks ponderados tipo TradingView/Supercharts para eje temporal

## Estado

Bloqueante antes de Fase 2. Reemplaza la política final de selección visual de labels de `0000e`.

`0000e` fue necesario para eliminar ticks fraccionales/sintéticos y alinear crosshair con índices reales, pero no basta visualmente: las capturas del usuario muestran que la app aún no se comporta como TradingView en 1 minuto.

## Referencias

### Código abierto oficial TradingView Lightweight Charts

Referencia local documentada en ADR:

```text
docs/adr/0002-official-tradingview-time-axis-reference.md
```

Repo clonado fuera de OneDrive:

```text
C:\Users\ASUS ROG\AppData\Local\Temp\opencode\lwc
```

Archivos clave:

- `src/model/time-scale.ts`
- `src/model/tick-marks.ts`
- `src/model/horz-scale-behavior-time/time-scale-point-weight-generator.ts`
- `src/model/horz-scale-behavior-time/types.ts`
- `src/model/horz-scale-behavior-time/horz-scale-behavior-time.ts`
- `src/model/horz-scale-behavior-time/default-tick-mark-formatter.ts`
- `src/views/time-axis/crosshair-time-axis-view.ts`
- `src/gui/time-axis-widget.ts`

### Observaciones visuales de TradingView/Supercharts 1m aportadas por el usuario

En las capturas de TradingView 1m se observa esta progresión al hacer zoom:

```text
5m:   ... 23:55 | 15 | 00:05 | 00:10 | 00:15 ...
15m:  ... 23:45 | 15 | 00:15 | 00:30 | 00:45 ...
30m:  ... 23:30 | 15 | 00:30 | 01:00 | 01:30 ...
1h:   ... 23:00 | 15 | 01:00 | 02:00 | 03:00 ...
90m:  ... 22:00 | 15 | 01:30 | 03:00 | 04:30 ...
3h:   ... 22:00 | 15 | 03:00 | 06:00 | 09:00 ...
```

Reglas visuales observadas:

- El cambio de día se muestra como número de día (`15`, `16`), no como `15 Apr` cuando el contexto de mes ya es claro.
- El día aparece en negrita/alta prioridad.
- La fecha/día reemplaza el tick horario de medianoche (`00:00`), no aparece como tick extra.
- Los ticks horarios quedan en una cadencia dominante: 5m, 15m, 30m, 1h, 90m, 3h, 6h, 1D según zoom.
- Al acercarse mucho, las velas y los labels se ven como TradingView: 5m/15m/30m con día ancla en medianoche.
- Al alejarse, los labels diarios no deben aparecer como `24 Apr`, `27 Apr`, etc. si TradingView mostraría solo día del mes o mes/año según peso.

## Problema actual post-0000e

`0000e` pasó tests (`Files=6, Tests=83, Result: PASS`), pero las capturas actuales de la app muestran diferencias claras:

1. **Formato de día incorrecto:** la app muestra `24 Apr`, `27 Apr`, `29 Apr`; TradingView muestra `15`, `16` para cambios de día intradía y reserva mes/año para pesos mayores.
2. **Selección lineal insuficiente:** la app elige un único `interval_minutes` y luego hace thinning cronológico. TradingView construye marcas con pesos y añade primero las de mayor peso.
3. **Prioridad de fecha mal modelada:** en `0000e` las fechas no tienen prioridad absoluta. En TradingView/Lightweight los cambios de día tienen mayor peso y desplazan horas cercanas.
4. **Grid visual demasiado pesado/irregular:** las líneas verticales de día se ven más dominantes que en TradingView. En TradingView el énfasis principal está en el label en negrita; el grid sigue siendo tenue.
5. **No se replica la escalera 1m observada:** TradingView/Supercharts usa 90m (`01:30`, `03:00`, `04:30`, etc.) en ciertos zooms. Lightweight Charts no documenta 90m, pero Supercharts observado sí; para este proyecto debe primar la referencia visual del profesor/TradingView.

## Objetivo

Implementar una política de tickmarks ponderados, inspirada en `TickMarks.build()` de Lightweight Charts y ajustada a las capturas de Supercharts, para que el eje temporal 1m/5m/15m se vea como TradingView.

## Requisitos funcionales

### R1. Modelo de candidatos por peso temporal

`compute_intraday_labels()` debe construir candidatos desde puntos lógicos reales, asignando un `weight` numérico comparable.

Pesos propuestos, compatibles con Lightweight + 90m Supercharts:

```perl
YEAR    => 70
MONTH   => 60
DAY     => 50
HOUR12  => 33
HOUR6   => 32
HOUR3   => 31
HOUR1   => 30
MIN90   => 29   # extensión Supercharts observada
MIN30   => 22
MIN15   => 21.5 # extensión Supercharts observada
MIN5    => 21
MIN1    => 20
```

Para cada vela/punto real visible:

1. Comparar con el timestamp real anterior disponible.
2. Si cambia año => `YEAR`.
3. Si cambia mes => `MONTH`.
4. Si cambia día => `DAY`.
5. Si cruza frontera intradía de 12h/6h/3h/90m/1h/30m/15m/5m/1m => peso correspondiente.
6. El punto de cambio de día debe ser el primer punto real del nuevo día si no existe vela exacta `00:00`.

### R2. Selección por pesos, no por thinning lineal único

La selección debe imitar `src/model/tick-marks.ts`:

1. Agrupar candidatos por `weight`.
2. Procesar pesos de mayor a menor.
3. Mantener candidatos ya aceptados de pesos superiores.
4. Insertar un candidato solo si hay separación mínima contra el vecino aceptado izquierdo y derecho.
5. Si una marca de menor peso no cabe, se descarta; nunca debe desplazar una de mayor peso.

Pseudo-criterio:

```perl
my $max_width_px = ...; # ancho máximo estimado de label
my $min_indices = ceil($max_width_px / $bar_w);

for weight desc:
    for candidate asc index:
        accept if index - left_index >= min_indices
              && right_index - index >= min_indices
```

Esto reemplaza el algoritmo actual que acepta cronológicamente y puede ocultar anchors de día.

### R3. Formato de labels según peso

Formato esperado para intradía:

- `YEAR`  => `2026`
- `MONTH` => `Apr`
- `DAY`   => `15`, `16`, `29` (día del mes sin mes, en negrita)
- intradía => `HH:MM`

No usar `DD Mon` para cada cambio de día en el eje inferior intradía. `DD Mon` puede seguir usándose en la caja negra del crosshair (`Thu 23 Apr '26 09:31`) porque esa caja sí necesita contexto completo.

### R4. Día como anchor de alta prioridad

El cambio de día debe tener prioridad alta:

- Debe reemplazar al tick de `00:00` si hay vela exacta en medianoche.
- Si no hay vela exacta en medianoche, usar la primera vela real del nuevo día como anchor `DAY`.
- Si hay una hora cercana (`23:55`, `00:05`, etc.) que solapa visualmente, se descarta la hora, no el día.

Esto corrige la contradicción de `0000e`: las fechas no deben ser ticks fraccionales extra, pero sí son anchors reales de mayor peso.

### R5. Escalera visual por zoom para 1m

En timeframe 1m, la cadencia visible debe seguir esta escalera observada:

```text
5m -> 15m -> 30m -> 1h -> 90m -> 3h -> 6h -> 1D -> Month -> Year
```

La selección por pesos puede producir esta escalera de forma natural, siempre que la separación mínima elimine pesos bajos al alejar zoom.

### R6. Escalera para 5m y 15m

Mantener lo observado por el usuario:

```text
5m:  5m -> 15m -> 30m -> 1h -> 90m -> 3h -> 6h -> 1D
15m: 15m -> 30m -> 1h -> 90m -> 3h -> 6h -> 1D -> 2D -> 3D
```

Si el modelo de pesos no cubre `2D/3D`, usar una extensión explícita para zooms muy lejanos, sin romper la regla de anchors reales.

### R7. Grid tenue y consistente

El grid vertical debe dibujarse solo para labels visibles, pero las líneas de día no deben verse exageradamente más oscuras que TradingView.

Ajuste esperado:

- Día puede tener texto bold.
- Línea vertical del día debe ser sutil, no una barra dominante.
- Si se conserva un color distinto para fechas, debe ser apenas más fuerte que grid normal.

### R8. Crosshair sigue coherente

Se mantiene de `0000e`:

- Ningún label temporal con índice fraccional.
- Si el eje inferior muestra `HH:MM` en índice `N`, el crosshair en `index_to_center_x(N)` debe terminar en esa misma hora.
- La caja negra inferior permanece en `time_axis_canvas`.

### R9. No romper requisitos de Fase 2

Esta task debe fortalecer, no retrasar arquitectónicamente, Fase 2:

- Replay usará el mismo índice lógico para no mostrar velas futuras.
- Overlays SMC/Liquidez/FVG se ubicarán en el tiempo por índice real.
- La escala X compartida sigue siendo única para Price/ATR/futuros overlays.

## Casos de aceptación visual

Usar la GUI 1m y comparar con las capturas de TradingView:

1. Zoom muy cercano: labels tipo `23:55 | 15 | 00:05 | 00:10`.
2. Zoom cercano: `23:45 | 15 | 00:15 | 00:30`.
3. Zoom medio: `23:30 | 15 | 00:30 | 01:00`.
4. Zoom medio-amplio: `23:00 | 15 | 01:00 | 02:00`.
5. Zoom amplio: `22:00 | 15 | 01:30 | 03:00 | 04:30`.
6. Zoom más amplio: `22:00 | 15 | 03:00 | 06:00 | 09:00`.
7. En vistas multi-día, los días deben verse como `17`, `18`, `21`, etc. o `Apr`/`2026` cuando cambie peso, no como todos `DD Apr`.

## Criterios automatizables sugeridos

Crear o actualizar tests para verificar:

- Día intradía se formatea como `15`, no `15 Apr`.
- En ventana 23:45..01:20 con ancho amplio, aparece el anchor `15` y no `00:00`.
- Las horas cercanas a medianoche no desplazan el anchor de día.
- En fixture continuo 1m, al variar ancho/visible_bars se obtienen cadencias esperadas: 5m, 15m, 30m, 60m, 90m, 180m.
- Los labels visibles tienen índices enteros.
- Crosshair sigue coincidiendo con labels `HH:MM`.

## Fuera de alcance

- Implementar whitespace bars completos.
- Cambiar `MarketData.pm`.
- Fase 2 (`0001+`).
- Refactor masivo de `ChartEngine.pm`.
- Copiar código TypeScript de TradingView literalmente.
