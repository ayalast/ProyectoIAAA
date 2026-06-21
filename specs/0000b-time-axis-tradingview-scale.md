# Spec 0000b: Eje temporal inferior estilo TradingView por fronteras reales

Fuente:
- Observación visual del usuario contra TradingView/Supercharts en temporalidad 1m.
- Corrección posterior a `specs/0000-fase1-polish-time-axis-crosshair.md`: la etiqueta del crosshair `Thu 23 Apr '26` quedó aceptada; el criterio de grid equidistante queda reemplazado por coherencia temporal tipo TradingView.
- Investigación pública 2026:
  - TradingView Support documenta que la escala de tiempo muestra etiquetas de fecha/hora y permite configurar formato/día de semana, pero no publica una tabla exacta completa de ticks automáticos de Supercharts.
  - `tradingview/lightweight-charts` sí publica un algoritmo de referencia: pesos intradía por fronteras `1s, 1m, 5m, 30m, 1h, 3h, 6h, 12h`, y luego día/mes/año; los ticks se eligen por peso y espacio disponible, no por una fase visual arbitraria.
  - Supercharts observado por el usuario añade pasos intermedios que no aparecen en esa lista pública, especialmente `15m` y `90m`/`1h30m` en 1m.

## Objetivo

Corregir el eje inferior de fechas/horas para que priorice el marcaje temporal coherente tipo TradingView: las líneas/etiquetas deben caer en fronteras reales de reloj/calendario, no en una secuencia equidistante derivada de la primera vela visible.

Esto debe cerrarse antes de continuar con Fase 2 (`tasks/0001-temporalidades-marketdata.md`), porque Replay, temporalidades superiores y overlays necesitan una escala temporal confiable.

## Problema

La Task 0000 implementó correctamente el formato del crosshair, pero cambió `compute_intraday_labels` hacia un `stride_bars` uniforme anclado a la primera vela visible en frontera de reloj. Ese enfoque produce dos problemas:

1. **Prioridad incorrecta:** TradingView no prioriza que todas las distancias del grid sean visualmente idénticas a través de gaps; prioriza que las marcas representen fronteras reales de tiempo.
2. **Fecha falsa en primera vela visible:** la app puede etiquetar la primera vela visible como fecha (`29 Apr`, por ejemplo) solo por ser la primera marca de la ventana. Eso es incorrecto: debe mostrar fecha/día solo cuando la vela marcada coincide con un inicio real de día/mes/año o una frontera mayor relevante.

## Comportamiento esperado

### Regla principal

- El eje X sigue siendo por **índice de vela**: no se crean huecos horizontales por noches, fines de semana o gaps del CSV.
- Pero las marcas del eje inferior se seleccionan por **fronteras reales de reloj/calendario**:
  - minutos: `minute % N == 0` y segundos en `00`;
  - horas: frontera desde medianoche local/exchange (`hour*60 + minute`) múltiplo del intervalo;
  - día: inicio real de día (`00:00`) o primera vela real del nuevo día si la data no contiene exactamente `00:00`;
  - mes: primera vela real del nuevo mes;
  - año: primera vela real del nuevo año.
- No se debe usar `anchor = primera vela visible` para convertirla en fecha.
- No se debe usar `anchor + n*stride_bars` si eso genera etiquetas como `09:31, 10:31, 11:31` cuando el intervalo elegido debería ser `1h`; debe preferirse `10:00, 11:00, 12:00` o la primera vela real disponible posterior a esa frontera.

### Formato de etiquetas

- Intradía menor que 1 día: `HH:MM` (`09:30`, `12:00`, `15:00`).
- Día: `DD Mon` (`29 Apr`) solo en frontera real de día/cambio de día.
- Mes: `Mon` o `Mon 'YY` si hace falta desambiguar.
- Año: `YYYY`.
- La etiqueta del crosshair ya aceptada (`Thu 23 Apr '26`) se mantiene sin cambios.

### Fecha al inicio del día

Una etiqueta tipo `29 Apr` debe aparecer solo si:

- la vela es el primer timestamp real del nuevo día comparado con la vela global anterior; o
- no existe vela global anterior y el timestamp cae en una frontera natural de día (`00:00`) o el dataset empieza exactamente en ese día y se decide mostrar inicio de dataset como caso especial documentado.

No debe aparecer solo porque la vela sea la primera visible tras hacer drag/zoom.

## Escalera de intervalos objetivo

> Nota de honestidad: TradingView/Supercharts no publica una tabla exacta completa de ticks automáticos. La tabla siguiente combina: (a) comportamiento observado por el usuario en Supercharts, (b) la escalera pública de `lightweight-charts`, y (c) la restricción técnica de que el intervalo debe ser compatible con la temporalidad base para evitar marcas inexistentes/irregulares.

### Temporalidades actuales de Fase 1

| TF base | Intervalos candidatos del eje inferior, de zoom cercano a lejano |
|---------|-------------------------------------------------------------------|
| `1m` | `1m`, `5m`, `15m`, `30m`, `1h`, `90m`, `3h`, `6h`, `12h`, `1D`, `1W`, `1M`, `1Y` |
| `5m` | `5m`, `15m`, `30m`, `1h`, `90m`, `3h`, `6h`, `1D`, `1W`, `1M`, `1Y` |
| `15m` | `15m`, `30m`, `1h`, `90m`, `3h`, `6h`, `1D`, `2D`, `3D`, `1W`, `1M`, `1Y` |

Observación específica del usuario en `1m`:

- Zoom muy cercano: marcas cada `1m`.
- Al alejar: `5m` → `15m` → `30m` → `1h`.
- Más alejado: aparece `90m`/`1h30m`.
- Más alejado: aparece `3h`, con etiquetas del tipo `03:00`, `06:00`, `09:00`, `12:00`, `15:00`, `18:00`, `21:00/22:00` según sesión/zona/datos disponibles.
- Luego debe degradar a `6h`, `12h`, `1D`, `1W`, `1M`, `1Y`.

Observación específica del usuario en `5m`:

- Zoom más cercano: marcas cada `5m`.
- Al alejar: `15m` → `30m` → `1h` → `90m`/`1h30m` → `3h`.
- Más alejado: `6h`; se ve el número del día y luego horas `06:00`, `12:00`, `18:00`, y después inicio del día siguiente.
- Alejado al máximo: separación por días (`16`, `17`, `18`, `19`, ...).
- Las etiquetas de día deben verse resaltadas/en negrita respecto a las horas.

Observación específica del usuario en `15m`:

- Zoom más cercano: marcas cada `15m`.
- Al alejar: `30m` → `1h` → `90m`/`1h30m` → `3h` → `6h`.
- Más alejado: separación por días (`16`, `17`, `18`, ...).
- Más alejado aún: separación aproximada por `2D` y/o `3D`. En las observaciones aparecen secuencias no perfectamente uniformes como `mes`, `3`, `5`, `9`, `11`, `14`, `16/17`, `18/19`, `21`, probablemente por selección de labels según espacio y fronteras de datos. Para el proyecto, el contrato es degradar de `1D` a `2D` y luego `3D`, manteniendo días reales y ocultando texto si se solapa, sin inventar fechas.

### Temporalidades planificadas de Fase 2

| TF base | Intervalos candidatos del eje inferior |
|---------|-----------------------------------------|
| `1h` | `1h`, `3h`, `6h`, `12h`, `1D`, `1W`, `1M`, `1Y` |
| `2h` | `2h`, `4h`, `6h`, `12h`, `1D`, `1W`, `1M`, `1Y` |
| `4h` | `4h`, `12h`, `1D`, `1W`, `1M`, `1Y` |
| `D` | `1D`, `1W`, `1M`, `3M`, `6M`, `1Y` |
| `W` | `1W`, `1M`, `3M`, `6M`, `1Y` |

Regla de compatibilidad:

- Para TF intradía, elegir intervalos `>= tf_minutes` y preferiblemente divisibles por `tf_minutes`.
- Si un intervalo observado de TradingView no es divisible por el TF base, omitirlo para esa temporalidad o documentar un fallback. Ejemplo: `90m` tiene sentido en `1m/5m/15m`, no en `1h/2h/4h`.
- Para `D/W`, usar fronteras calendario, no minutos.

## Selección automática por zoom

La app debe seleccionar el intervalo más pequeño cuya separación visual esperada sea legible.

Guía inicial:

- Calcular `bar_w = plot_width / visible_bars`.
- Para cada candidato, estimar separación visual:
  - intradía: `(interval_minutes / tf_minutes) * bar_w`;
  - día/semana/mes/año: estimar por número promedio de barras entre fronteras o por escaneo de timestamps visibles.
- Elegir el primer candidato con separación aproximada `>= target_px`.
- `target_px` inicial recomendado: 80–110 px para etiquetas cortas (`HH:MM`); subir si hay solape.
- Después de generar ticks, aplicar deduplicación/ocultamiento de texto por solape, pero **no mover ticks a posiciones arbitrarias**.

## Fuera de alcance

- No cambiar la etiqueta inferior del crosshair ya aceptada.
- No implementar nuevas temporalidades de Fase 2 dentro de esta task, salvo dejar la escalera preparada para cuando existan.
- No cambiar el modelo horizontal de índice de vela a tiempo continuo.
- No implementar Replay, overlays, SMC, liquidez, Volume Profile ni VWAP.
- No refactorizar masivamente `ChartEngine.pm`.

## Criterios de aceptación

- En `1m`, la app degrada al menos por esta secuencia al alejar zoom: `1m → 5m → 15m → 30m → 1h → 90m → 3h → 6h → 12h → 1D`.
- En `5m`, la app usa exactamente la secuencia observada: `5m → 15m → 30m → 1h → 90m → 3h → 6h → 1D`.
- En `15m`, la app usa la secuencia observada: `15m → 30m → 1h → 90m → 3h → 6h → 1D → 2D → 3D` cuando el zoom se aleja lo suficiente.
- Las marcas horarias caen en fronteras reales: `10:00`, `11:00`, `12:00`, no en offsets derivados de la primera vela visible como `10:31` si el intervalo es `1h`.
- En intervalo `3h`, las etiquetas esperadas son fronteras desde medianoche: `00:00`, `03:00`, `06:00`, `09:00`, `12:00`, `15:00`, `18:00`, `21:00` cuando existan velas en esas fronteras o primeras velas reales del tramo posterior.
- En intervalo `6h`, las etiquetas esperadas son fronteras desde medianoche: día/inicio, `06:00`, `12:00`, `18:00`, siguiente día/inicio.
- Las etiquetas de día (`DD Mon` o número de día según modo lejano) deben renderizarse en negrita/resaltadas respecto a las horas. `PricePanel.pm` ya usa `Helvetica 8 bold` para `is_date`; mantener o reforzar ese contrato.
- La primera vela visible NO muestra `DD Mon` salvo que sea inicio real de día/cambio de día/mes/año.
- El cambio de día se etiqueta sin insertar marcas falsas que no correspondan a timestamps reales.
- `t/01-chart-time-axis.t` deja de exigir equidistancia por `stride_bars` y prueba fronteras reales + no fecha falsa en primera vela visible.
- `prove -l t` pasa.

## Casos límite

- Gaps de sesión/noche/fin de semana: no crear huecos visuales, pero tampoco forzar marcas equidistantes que pierdan coherencia de reloj.
- Dataset sin vela exacta a `00:00`: marcar como fecha la primera vela real del nuevo día si hay cambio de día respecto a la vela anterior global.
- Ventana visible que empieza a mitad de día: primera marca puede ser hora (`09:30`, `10:00`), no fecha.
- Ventana muy comprimida: ocultar texto por solape, pero conservar solo ticks coherentes con la frontera elegida.
- Timestamps no parseables: omitir sin romper render.
- Futuras temporalidades `D/W`: no usar `HH:MM`; usar etiquetas de día/mes/año según zoom.

## Plan de verificación

Automático:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c market.pl && prove -l t"
```

Manual WSLg:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. market.pl"
```

Validación visual:

1. Abrir 1m y hacer zoom out progresivo.
2. Confirmar secuencia observada: 1m, 5m, 15m, 30m, 1h, 90m, 3h.
3. En 3h, confirmar marcas en horas coherentes (`06`, `09`, `12`, `15`, `18`, `21/22` según datos/zona), no por stride arbitrario.
4. Arrastrar para que la ventana empiece a mitad de día: no debe aparecer `DD Mon` en la primera vela visible.
5. Arrastrar hasta inicio real de día: sí debe aparecer `DD Mon`.
6. Confirmar que `Thu 23 Apr '26` en el crosshair sigue igual.
