# Task 0000b: Corregir eje inferior por fronteras reales tipo TradingView

## Spec relacionada

`specs/0000b-time-axis-tradingview-scale.md`

## Objetivo

Reemplazar el comportamiento de `compute_intraday_labels` introducido en Task 0000 (stride equidistante anclado a la primera frontera visible) por un eje temporal estilo TradingView: marcas en fronteras reales de reloj/calendario, con escalera de zoom completa para `1m/5m/15m` y preparada para Fase 2.

Mantener intacta la etiqueta del crosshair ya aceptada: `Thu 23 Apr '26`.

## Contexto obligatorio para el implementor

- La Task 0000 ya implementó `_crosshair_date_label($tm)` correctamente. No rehacerlo salvo ajuste mínimo de comentarios.
- Lo que quedó mal fue la decisión de grid equidistante. El usuario confirmó que TradingView prioriza coherencia temporal, no distancias iguales perfectas en el grid.
- Bug visible: la primera vela visible puede mostrar `DD Mon` aunque esté a mitad del día. Eso debe desaparecer.
- TradingView/Supercharts no publica tabla exacta completa; usamos la spec 0000b como contrato del proyecto.
- El profesor pide referencia TradingView para la mayoría de UX, salvo requisitos explícitamente diferentes del material oficial.

## Archivos probablemente relevantes

- `Market/ChartEngine.pm`
  - `compute_intraday_labels`
  - `_time_axis_interval_minutes`
  - `_is_time_axis_boundary`
  - `_time_label_for_index`
  - `_timeframe_minutes`
  - `get_all_timestamps`
  - NO romper `_crosshair_time_label` / `_crosshair_date_label`
- `t/01-chart-time-axis.t`
  - actualizar pruebas que hoy esperan stride equidistante.
- Posiblemente `Market/Panels/PricePanel.pm`
  - solo si el render del eje necesita respetar `grid/label`; no tocar si no hace falta.
- Posiblemente `Market/Panels/Scales.pm`
  - evitar tocar salvo bug real de coordenadas.

## Pasos

1. Leer `specs/0000b-time-axis-tradingview-scale.md` completa.
2. En `Market/ChartEngine.pm`, preservar sin cambios funcionales:
   - `_crosshair_date_label($tm)` con salida `Thu 23 Apr '26`.
   - `_crosshair_time_label()` salvo que haya un bug estrictamente relacionado con coordenadas.
3. Rehacer `compute_intraday_labels` para generar ticks por escaneo de timestamps visibles/globales:
   - Obtener ventana global con `compute_window()`.
   - Usar `get_all_timestamps()` o un escaneo equivalente de timestamps parseables.
   - Convertir índice global a índice local con `local = global - start`.
   - No crear ticks en índices sin timestamp real, salvo el comportamiento futuro ya existente para espacio a la derecha si está documentado; para esta task es preferible no etiquetar futuro.
4. Cambiar la selección de intervalo:
   - Implementar/ajustar `_time_axis_interval_minutes($tf_minutes, $bar_w)` con estas escaleras:
     - `1m`: `(1, 5, 15, 30, 60, 90, 180, 360, 720, 1440, 10080, 43200, 525600)`
     - `5m`: `(5, 15, 30, 60, 90, 180, 360, 1440, 10080, 43200, 525600)`
       - Observado por el usuario: después de `6h` pasa a días; no meter `12h` como paso obligatorio en `5m`.
     - `15m`: `(15, 30, 60, 90, 180, 360, 1440, 2880, 4320, 10080, 43200, 525600)`
       - Observado por el usuario: después de `6h` pasa a días; luego `2D/3D` en zoom muy alejado.
     - Preparar para Fase 2:
       - `1h`: `(60, 180, 360, 720, 1440, 10080, 43200, 525600)`
       - `2h`: `(120, 240, 360, 720, 1440, 10080, 43200, 525600)`
       - `4h`: `(240, 720, 1440, 10080, 43200, 525600)`
       - `D`: `(1440, 10080, 43200, 129600, 259200, 525600)`
       - `W`: `(10080, 43200, 129600, 259200, 525600)`
   - Elegir el primer intervalo cuya separación estimada sea legible (`target_px` inicial 90–110 px).
   - Mantener solo intervalos `>= tf_minutes`; si no son compatibles, omitir o degradar de forma documentada.
5. Ajustar `_is_time_axis_boundary($tm, $interval_minutes)`:
   - Para `< 1440`: frontera real desde medianoche: `($tm->hour * 60 + $tm->minute) % $interval_minutes == 0` y segundos `00` si disponible.
   - Para `1440`: inicio real de día (`00:00`) o primer timestamp real del nuevo día detectado en `compute_intraday_labels`.
   - Para `10080`: inicio de semana (lunes recomendado, consistente con ISO y Time::Moment) o primer timestamp real de nueva semana.
   - Para mes/año: no basta con minutos; detectar cambio de mes/año en el escaneo.
6. Corregir el bug de fecha falsa:
   - Mantener información del timestamp global anterior real (índice `global - 1`, si existe) o del último timestamp parseable antes del índice actual.
   - `is_date => 1` solo cuando hay cambio real de día/mes/año respecto al timestamp anterior global, o cuando el timestamp mismo cae en inicio calendario real.
   - La primera vela visible a mitad de día debe ser `is_date => 0` y mostrar hora si corresponde.
7. Generar etiquetas:
   - Si el intervalo elegido es intradía (`< 1440`), ticks regulares muestran `HH:MM`.
   - Si el tick coincide con cambio real de día, el texto debe ser `DD Mon` y `is_date => 1`.
   - Para intervalos diarios/semanales/mensuales/anuales, usar texto de fecha/mes/año según spec.
   - Mantener `{ index, text, is_date, grid, label }` porque `PricePanel` depende de esa forma.
8. Solape de textos:
   - Se puede mantener lógica de ocultar `label => 0` cuando se solapan.
   - No mover ticks a posiciones arbitrarias para solucionar solape.
9. Hacer pasar las pruebas automatizadas ya creadas en `t/01-chart-time-axis.t`:
   - No rediseñar la suite salvo que haya un error evidente en el test; si cambias tests, justificarlo en la entrega.
   - La suite ya comprueba: crosshair `Thu 23 Apr '26`, escalera 5m/15m con `90m`, gap sin drift a `01:10`, primera vela visible a mitad de día sin fecha falsa, 5m con `6h`, y fechas en negrita frente a horas normales.
10. Ejecutar verificación completa.

## Criterios de aceptación

- `Thu 23 Apr '26` sigue pasando en tests.
- En `1m`, `_time_axis_interval_minutes` permite al menos `1,5,15,30,60,90,180,360,720,1440`.
- En `5m`, permite la secuencia observada `5,15,30,60,90,180,360,1440` y no fuerza `720/12h` antes de diario.
- En `15m`, permite la secuencia observada `15,30,60,90,180,360,1440,2880,4320` para diario/2D/3D en zoom lejano.
- Las marcas se ubican en fronteras reales de reloj; no se generan marcas tipo `anchor + n*stride_bars` si el anchor no coincide con la frontera elegida.
- La primera vela visible a mitad de día no se etiqueta como fecha.
- El inicio real de día o primera vela real de un nuevo día sí se etiqueta como `DD Mon`.
- No se rompe el render/crosshair/snap X.
- `prove -l t` pasa.

## Comandos de verificación

Sintaxis + tests:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

Si trabajas sobre la copia Windows desde WSL:

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

Prueba manual WSLg:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. market.pl"
```

Validación visual manual:

1. Timeframe `1m`, zoom cercano: marcas cada 1m/5m/15m/30m/1h según alejas.
2. Más alejado en `1m`: debe aparecer `1h30m`/`90m` y luego `3h`.
3. En `3h`, comprobar etiquetas en horas coherentes (`03:00`, `06:00`, `09:00`, `12:00`, etc.) según el dataset visible.
4. Arrastrar a mitad de día: la primera vela visible no debe decir `DD Mon`.
5. Arrastrar al inicio real de día: sí debe decir `DD Mon`.
6. Mover crosshair: la caja inferior debe seguir diciendo formato completo `Thu 23 Apr '26` para esa fecha.

## Qué no tocar

- `Data/2026_03.csv`.
- `Market/MarketData.pm` salvo que descubras un bug estrictamente necesario para detectar timestamps reales; si lo tocas, justifica y añade test.
- `Market/Indicators/*`.
- Fase 2: Replay, Overlays, SMC, Liquidity, Strategy Builder, Volume Profile, VWAP.
- Refactors amplios de `ChartEngine.pm`.
- No hacer commit/push sin aprobación humana.

## Pruebas automatizadas ya preparadas

Ya existe una suite TDD en `t/01-chart-time-axis.t` para esta task. En el estado actual del código, estas pruebas fallan a propósito porque describen el comportamiento esperado de `0000b`.

El implementor NO debe inventar nuevas pruebas como parte principal de la task; debe hacer pasar estas pruebas. Solo puede modificar tests si detecta un error objetivo en la prueba, y debe justificarlo explícitamente en su entrega.

Cobertura añadida:

- Crosshair `Thu 23 Apr '26` no debe romperse.
- Escalera 5m: incluye `90m`, llega a `6h`, y salta de `6h` a diario sin forzar `12h`.
- Escalera 15m: incluye `90m` y soporta `3D` en zoom muy lejano.
- Gap de datos: debe marcar fronteras reales como `01:00`/`01:15`, no drift tipo `01:10`.
- Primera vela visible a mitad de día: debe mostrar hora (`09:00`), no fecha falsa (`01 Apr`).
- 5m en zoom lejano: debe mostrar `06:00`, `12:00`, `18:00` para espaciado de `6h`.
- Etiquetas de día en negrita/resaltadas frente a horas normales.

## Nota para el implementor barato

Haz solo esta task. No pases a `0001` hasta que el usuario valide visualmente el eje inferior. Si ves contradicción entre `0000` y `0000b`, manda `0000b`: es la corrección posterior basada en observación real de TradingView.
