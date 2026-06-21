# Spec 0000g: Cadencia global uniforme del eje temporal tipo TradingView

## Estado

Bloqueante antes de Fase 2. Esta spec nace después de implementar `0000f`.

`0000f` introdujo tickmarks ponderados y corrigió parte del formato (`DAY` como `15`, etc.), pero la validación visual del usuario sigue fallando: el eje temporal aún no mantiene una cadencia global uniforme como TradingView.

## Problema principal confirmado

El problema central ya no es solamente:

- formato de fecha;
- ticks fraccionales;
- crosshair desalineado;
- grid demasiado fuerte.

El problema principal es:

> El eje temporal mezcla fechas y horas con una cadencia local/accidental, no con una estructura global uniforme tipo TradingView.

En las capturas actuales de la app se observan secuencias como:

```text
06:00 | 12:00 | 18:00 | 24 | 06:00 | 12:00 | 26 | 27 | 06:00 | 12:00 | 18:00 | 28
```

```text
12:00 | 22 | 12:00 | 23 | 12:00 | 24 | 09:00 | 26 | 27 | 12:00 | 28
```

```text
15 | 11:30 | 16 | 11:30 | 17 | 19 | 06:00 | 21 | 11:30 | 22 | 11:30 | 23 | 11:30 | 24 | 26 | 06:00 | 28
```

Estas secuencias son visualmente incorrectas porque el usuario no puede leer una cadencia temporal estable.

## Fallos visuales actuales documentados

### F1. Distancias no uniformes entre fechas

Algunos días aparecen muy cerca y otros mucho más lejos. Esto produce una sensación de eje torcido o accidental.

Ejemplo problemático:

```text
26 | 27 ---- 28
```

El cierre aceptado no es un modo diario puro: debe verse una cadencia Modo A con días como anchors y horas uniformes. Si los gaps reales impiden esa lectura usando solo velas existentes, se debe diseñar una estrategia coherente de puntos lógicos/whitespace conocida por el eje y el crosshair, en vez de aceptar una mezcla irregular o solo días como resultado final.

### F2. Días sin horas intermedias mientras otros días sí tienen horas

En la misma ventana algunos tramos tienen horas intermedias (`06:00`, `12:00`, `18:00`) y otros no tienen ninguna.

Esto es el síntoma más importante.

Incorrecto:

```text
24 | 06:00 | 12:00 | 26 | 27 | 06:00 | 12:00 | 18:00 | 28
```

La app parece decidir localmente si una hora cabe, pero no garantiza una política global por toda la ventana.

### F3. Mezcla de días y horas sin jerarquía estable

TradingView muestra una narrativa temporal legible:

```text
22:00 | 15 | 03:00 | 06:00 | 09:00 | 12:00 | 15:00 | 18:00 | 22:00 | 16 | 03:00
```

La app muestra combinaciones como:

```text
24 | 09:00 | 26 | 27
```

Esto no comunica bien si estamos viendo una cadencia diaria, intradía o una mezcla de ambas.

### F4. Horas raras o no dominantes en zoom alejado

Aparecen horas como `11:30` repetidas entre días, lo que se siente raro en zoom alejado.

TradingView en zooms similares tiende a usar horas limpias y legibles:

```text
03:00 | 06:00 | 09:00 | 12:00 | 15:00 | 18:00 | 22:00
```

o, cuando corresponde:

```text
01:30 | 03:00 | 04:30 | 06:00
```

Pero no una mezcla accidental donde algunos días tienen `11:30` y otros no tienen horas.

### F5. El algoritmo actual selecciona por peso local, pero no por modo global

La implementación post-`0000f` parece haber hecho esto:

1. asignar pesos a candidatos;
2. aceptar candidatos si caben contra vecinos;
3. retornar lo aceptado.

Eso se parece parcialmente a `lightweight-charts`, pero no resuelve nuestro caso porque:

- nuestros datos tienen gaps/sesiones comprimidas;
- el usuario exige una visualización tipo Supercharts;
- el profesor pidió crear anchors de fecha y distribuir horas entre anchors;
- el eje debe elegir un modo/cadencia dominante por ventana, no permitir una mezcla irregular.

### F6. Zoom alejado no se simplifica correctamente

En zoom alejado, TradingView se ve simple y ordenado. La app todavía muestra demasiada mezcla:

- días;
- horas intermedias en algunos tramos;
- huecos sin horas;
- anchors que no parecen equidistantes.

Si la ventana no permite mantener horas uniformes entre fechas con los puntos actuales, la implementación debe corregir el plan global hasta lograr Modo A. Un modo superior/diario puede servir como protección temporal para no mostrar una combinación irregular durante desarrollo, pero no es aceptación final de esta spec.

### F7. El grid amplifica la irregularidad

Aunque el grid sea más tenue que antes, cada línea vertical asociada a un label irregular hace que el ojo detecte más la no uniformidad. Por eso el problema no es solo texto: también es grid.

## Referencia técnica local

Código oficial abierto descargado en:

```text
C:\Users\ASUS ROG\AppData\Local\Temp\opencode\lwc
```

ADR asociado:

```text
docs/adr/0002-official-tradingview-time-axis-reference.md
```

Archivos de referencia:

- `src/model/tick-marks.ts`
- `src/model/time-scale.ts`
- `src/model/horz-scale-behavior-time/time-scale-point-weight-generator.ts`
- `src/model/horz-scale-behavior-time/types.ts`
- `src/model/horz-scale-behavior-time/horz-scale-behavior-time.ts`
- `src/gui/time-axis-widget.ts`

## Calibración visual confirmada con TradingView

El dataset local fue comparado manualmente contra TradingView usando **NQ1! — NASDAQ 100 E-mini Futures, CME, 15m**, en zona **UTC-5**. El CSV `Data/2026_03.csv` contiene realmente abril 2026 (`2026-04-01T00:00:00-05:00` a `2026-04-30T23:59:00-05:00`).

Hallazgo crítico: TradingView también comprime la pausa diaria de sesión. En el tramo del 30 de abril, se observa `15:45 -> 17:00` sin velas ni labels intermedios `16:00/16:15/16:30/16:45`. Por tanto, no debemos inventar labels o velas en gaps de sesión si no existen puntos lógicos/whitespace explícitos.

## Interpretación correcta para nuestra app

Lightweight Charts usa pesos y separación mínima, pero nuestra app necesita un paso adicional por los gaps/sesiones del dataset:

> Elegir una cadencia global dominante para toda la ventana visible y luego validar que esa cadencia produce una distribución visual aceptable.

No basta aceptar marcas individualmente.

## Modelo esperado

### Decisión de producto: Modo A obligatorio

La solución final aceptada para cerrar Fase 1 es **Modo A: intradía con anchors de día y horas uniformes**.

No se acepta como cierre visual una degradación permanente a "solo días" si TradingView muestra días + horas en el mismo tipo de zoom. El modo diario puede usarse únicamente como fallback diagnóstico/intermedio mientras se implementa la solución, pero no como criterio final de aceptación.

### Modo A: intradía con anchors de día y horas consistentes

Deben aparecer días y horas con una cadencia coherente:

```text
22:00 | 15 | 03:00 | 06:00 | 09:00 | 12:00 | 15:00 | 18:00 | 22:00 | 16 | 03:00
```

Reglas:

- día reemplaza a medianoche;
- horas pertenecen a una sola cadencia dominante sobre puntos existentes;
- gaps reales de sesión como `15:45 -> 17:00` en 15m son válidos y deben comprimirse por índice lógico, igual que TradingView;
- no se inventan labels intermedios en gaps (`16:00`, `16:15`, `16:30`, etc.) salvo futura implementación explícita de whitespace bars;
- no hay días con horas y otros días sin horas salvo edge/ventana parcial claramente justificada;
- las distancias visuales no deben tener saltos abruptos adicionales a gaps reales de sesión confirmados.

### Fallback no aceptable como cierre: diario conservador

Un modo diario puro:

```text
15 | 16 | 17 | 20 | 21 | 22 | 23 | 24 | 27 | 28
```

puede usarse solo para diagnóstico o como protección temporal contra una mezcla caótica, pero **no cierra esta spec** cuando la referencia de TradingView muestra días + horas. La implementación debe seguir iterando hasta lograr Modo A.

### Modo superior mensual/anual

En zooms extremadamente lejanos o con datasets más grandes:

```text
Apr | May | Jun
```

```text
2026 | 2027
```

## Requisitos funcionales

### R1. Separar generación de candidatos de planificación global

`compute_intraday_labels()` no debe decidir labels finales únicamente por aceptación local.

Debe haber una fase explícita de planificación:

1. construir candidatos reales;
2. agrupar por tipo/cadencia;
3. proponer planes de visualización;
4. puntuar uniformidad;
5. elegir el mejor plan global;
6. renderizar solo ese plan.

### R2. Elegir una cadencia dominante por ventana

La ventana visible debe tener una cadencia dominante:

```text
5m, 15m, 30m, 1h, 90m, 3h, 6h, 1D, Month, Year
```

No se permite una mezcla accidental como:

```text
DAY | 11:30 | DAY | DAY | 06:00 | DAY
```

### R3. Validar uniformidad antes de aceptar un plan

Para los labels visibles de un plan, calcular deltas de índice/píxel entre labels consecutivos.

Métricas sugeridas:

- `min_gap_px` >= ancho mínimo de label;
- `max_gap_px / min_gap_px` dentro de un umbral razonable para modo intradía;
- coeficiente de variación de gaps bajo un umbral;
- permitir excepciones solo en bordes de ventana o gaps de sesión explícitos.

Si un plan intradía produce demasiada variación, la implementación debe ajustar la cadencia, los anchors o la estrategia de puntos lógicos hasta conseguir Modo A. Degradar a diario solo puede considerarse fallback temporal de seguridad, no aceptación final.

### R4. Consistencia por segmentos entre días

Si se muestran horas entre días, debe haber consistencia:

- cada segmento día-a-día debe tener la misma cadencia base;
- no debe haber un día con 3 horas intermedias y otro con 0, salvo inicio/fin visible parcial;
- si no se puede cumplir con velas reales por datos faltantes, evaluar una estrategia explícita de puntos lógicos/whitespace conocidos por eje y crosshair; no aceptar modo diario como solución final si TradingView muestra días + horas.

### R5. Anchors de día siguen siendo prioritarios

Los días son anchors importantes:

- se muestran como `15`, `16`, `24`, etc.;
- reemplazan medianoche;
- no son desplazados por horas cercanas;
- pero tampoco deben forzar una mezcla irregular de horas.

### R6. Mantener invariantes de `0000e/0000f`

No romper:

- sin índices fraccionales;
- sin ticks sintéticos invisibles para crosshair;
- crosshair coincide con labels `HH:MM`;
- caja negra en `time_axis_canvas`;
- grid solo para labels visibles;
- día en bold;
- grid tenue.

### R7. Verificación automática antes de pedir validación manual

La IA/agente debe verificar por código antes de pedir screenshot manual:

- tests unitarios de secuencias de labels;
- tests de uniformidad de gaps;
- tests de consistencia por segmento;
- snapshot estructurado de labels visibles para casos reales del dataset mediante `Market/Debug/TimeAxisSnapshot.pm`.

Solo pedir validación manual cuando:

- tests pasan;
- no se puede comprobar percepción exacta del grid/espaciado por código;
- se necesita comparar visual final con TradingView.

## Casos de aceptación automatizables

### A1. No mezclar días y horas irregularmente

Fixture con varios días y gaps. El plan final debe mostrar horas en todos los segmentos internos comparables con la misma cadencia. Si no puede hacerlo, el test debe fallar o marcar explícitamente que la implementación sigue incompleta; no aceptar modo diario como cierre.

### A2. No permitir días consecutivos sin política clara

Secuencia visible inválida:

```text
24 | 06:00 | 12:00 | 26 | 27 | 06:00 | 12:00 | 28
```

Debe convertirse a una secuencia Modo A con horas uniformes entre anchors de día. Si temporalmente se protege con solo días, eso debe considerarse fallback incompleto, no aceptación final.

### A3. Evitar horas raras aisladas

Secuencia inválida:

```text
15 | 11:30 | 16 | 11:30 | 17 | 19 | 06:00 | 21
```

No debe aparecer si no hay una cadencia global clara de 90m/3h/etc. en toda la ventana.

### A4. TradingView-like zoom alejado

En zoom alejado, la app debe preferir claridad con Modo A:

- días + horas uniformes;
- nunca mezcla accidental;
- diario puro solo como fallback temporal/incompleto, no como cierre visual aceptado.

### A5. Crosshair no se rompe

Cualquier label horario visible debe seguir coincidiendo con `_crosshair_time_label()` al poner `last_mouse_x` sobre su índice.

### A6. Subcasos abiertos delegados a `0000h`

La validación visual posterior detectó dos refinamientos pendientes dentro de esta misma spec:

1. densificación adaptativa de huecos grandes con candidatos reales, por ejemplo insertar `14:30` entre `12:00` y `18:00` cuando TradingView lo hace y hay espacio suficiente;
2. evitar entrar demasiado pronto en modo calendario/solo días cuando TradingView todavía muestra horas entre días.

Estos puntos se implementan en `tasks/0000h-time-axis-adaptive-density-calendar-threshold.md`. Validación posterior abrió además `tasks/0000i-time-axis-calendar-density-overscan-render.md` para: calendario mensual más denso y overscan de velas parcialmente visibles durante paneo suave. No abrir Fase 2 si estos subcasos siguen fallando visualmente.

## Sistema de debug para comparación con TradingView

El diagnóstico avanzado del eje temporal vive separado en `Market/Debug/TimeAxisSnapshot.pm` para no contaminar las clases principales. `ChartEngine.pm` solo conserva el wrapper mínimo `debug_time_axis_snapshot()`.

Uso esperado para comparar contra una captura de TradingView:

```perl
my $snapshot = $chart->debug_time_axis_snapshot(
    timeframe    => '15m',
    start_ts     => '2026-04-29T15:00:00-05:00',
    end_ts       => '2026-05-01T00:00:00-05:00',
    canvas_width => 1400,
);
```

Salida relevante:

- `$snapshot->{labels_text}`: secuencia exacta del eje, por ejemplo `15:00 | 18:00 | ... | May`.
- `$snapshot->{cadence_min}`: cadencia dominante inferida en minutos.
- `$snapshot->{visible_bars}`, `start_index`, `end_index`, `first_ts`, `last_ts`.
- `$snapshot->{bar_w}`, `plot_width`, `x_shift`, `canvas_width`.
- `$snapshot->{labels}`: cada label visible con `text`, índice local/global, timestamp y coordenada `x`.
- `$snapshot->{hidden_labels}` y `all_candidates`: candidatos ocultos/diagnóstico.
- `$snapshot->{gaps}`: gaps de timestamp detectados en la ventana.
- `$snapshot->{summary}`: resumen textual imprimible.

Regla operativa: antes de pedir una screenshot interna de la app, se debe extraer este snapshot. El usuario solo necesita pasar o confirmar la captura/rango de TradingView; la app se compara por datos exactos.

## Criterios de aceptación visual

Comparar manualmente contra TradingView solo después de pasar tests y snapshot debug:

- El eje se lee con una cadencia estable.
- No hay días con horas intermedias arbitrarias mientras otros no tienen ninguna.
- No hay secuencias visualmente caóticas de `DAY | HOUR | DAY | DAY | HOUR`.
- El zoom alejado muestra Modo A como TradingView: días + horas uniformes, no solo días salvo fallback no final documentado.
- El grid no amplifica irregularidades.

## Fuera de alcance

- Implementar whitespace bars completos si no son necesarios para pasar la validación visual.
- Cambiar `MarketData.pm` salvo autorización explícita.
- Fase 2 (`0001+`).
- Refactor masivo de `ChartEngine.pm`.
- Copiar código TypeScript literalmente.
