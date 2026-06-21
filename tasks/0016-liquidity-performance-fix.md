# Task 0016: Rendimiento — el primer render se cuelga con el dataset real (29888 velas)

## Severidad: CRÍTICA (bloquea ejecución de la app; la 1ª entrega no abre)

## Síntoma
`perl -I. market.pl` con `Data/2026_03.csv` (29888 velas) abre la ventana y la barra de
controles, pero el área de gráfico queda en BLANCO y la app se cuelga varios minutos. El log
para en `[*] Render geometry: ... bars=60` y no continúa. Con datasets de test (10-35 velas)
no se reproduce — por eso los 654 tests pasan.

## Causa raíz (perfilada por el arquitecto, no suposición)
En el primer `render()`, `ChartEngine::sync_overlay_indicators` alimenta los indicadores SMC y
Liquidity sobre TODO el dataset (sin Replay, `feed_to = size()-1 = 29887`). Medición:

- SMC: ~0.36s para 5000 velas → rápido, NO es el problema.
- **Liquidity: ~16 ms/vela → ~6-7 min para 29888 velas. ESTE es el cuelgue.**

Perfilado interno de Liquidity (N=2000 velas, 38.8s totales):

```
_resolve              37.32s   (362 llamadas)
 └ _compute_event_meta 37.31s  (362 llamadas)
   └ _sum_volume_for_tf 37.29s (1086 llamadas)   ← 96% del tiempo
```

`_sum_volume_for_tf($tf, $ts_start, $ts_end)` (introducida en task 0013) recorre el **array
COMPLETO** del timeframe (`@{ $md->{data}{$tf} }`, hasta 29888 elementos) y hace
`Time::Moment->from_string($c->[0])` en CADA vela, para CADA evento resuelto y CADA uno de los 3
TFs (1m/5m/15m). Es O(eventos × velas_totales) con una constante enorme por el parseo de fecha.

Secundario (no es el cuelgue pero conviene): `_update_fsm` recorre `_active_levels`, que crece sin
límite porque los niveles `Resolved` nunca se eliminan (1138 niveles tras 6000 velas). Es O(n²)
pero con constante baja; el dominante es el volumen.

## Objetivo
Que `update_last` de Liquidity sea ~O(1) amortizado por vela, de modo que alimentar 29888 velas
tarde pocos segundos y la GUI pinte de inmediato. Sin cambiar los resultados (los 654 tests deben
seguir verdes, incluido el Case 26 de volumen por timestamp de 0013).

## Archivos permitidos
- `Market/Indicators/Liquidity.pm`
- `t/10-liquidity.t` (solo para añadir un test de rendimiento/cota; NO relajar los existentes)

## Correcciones requeridas

### R1. `_sum_volume_for_tf` por rango de índices, no escaneo completo con parseo de fecha
El cálculo debe seguir siendo "suma de volúmenes de las sub-velas cuyo timestamp cae en el rango
del evento" (semántica de 0013, que el Case 26 valida). Pero implementarlo eficiente:
1. **Cachear los epochs** de cada array de TF una sola vez (no parsear `from_string` por vela en
   cada llamada). P.ej. `$self->{_epoch_cache}{$tf}` = arrayref de epochs, construido perezosamente
   y reusado; o convertir el timestamp a epoch una vez al alimentar.
2. **Búsqueda binaria** del rango `[ts_start_epoch, ts_end_next_epoch)` sobre los epochs (los arrays
   están ordenados cronológicamente) en vez de recorrer todo el array. Sumar solo el sub-rango.
   - Para sumar rápido un sub-rango, mantener un **prefix-sum de volumen** por TF
     (`$self->{_volsum}{$tf}[i] = vol[0..i-1]`), así la suma del rango es una resta O(1) tras
     localizar los bordes por binaria O(log n).
3. Resultado idéntico al actual para los fixtures de `t/10` (incluido Case 26: v1m=296, v5m=410,
   v15m=345, independencia del TF macro).

### R2. Podar niveles resueltos de `_active_levels`
Tras resolver un nivel (estado `Resolved`), sácalo de `_active_levels` (muévelo a un `_resolved`
o simplemente no lo conserves ahí; los eventos ya quedan en `_events`). Así `_update_fsm` solo
itera niveles vivos. Mantén la semántica: un nivel resuelto no se reabre.
- Cuidado: `get_active_levels()` debe seguir devolviendo solo no-resueltos (ya lo hace).
- Cuidado: no cambiar el orden ni el contenido de `get_events()`.

### R3. (Opcional, si hace falta para la cota) límite de antigüedad de niveles `Detected`
Si tras R1+R2 sigue habiendo coste alto por niveles `Detected` que nunca se barren y se acumulan,
considera expirar niveles `Detected` demasiado viejos (p.ej. > X velas sin ser barridos), con X
configurable y documentado. Solo si es necesario para cumplir la cota de R4; no lo añadas
preventivamente (YAGNI).

## Tests requeridos
1. **Cota de rendimiento (NUEVO):** en `t/10`, alimentar un dataset sintético de >= 5000 velas y
   afirmar que `update_last` completo tarda por debajo de un umbral generoso (p.ej.
   `ok($elapsed < 5, ...)` con `Time::HiRes`). Debe FALLAR con el código actual y pasar con el fix.
   (Usar un umbral holgado para no ser flaky en máquinas lentas, pero que detecte el O(n²): el
   código viejo tarda decenas de segundos en 5000 velas.)
2. **Conservar TODOS los tests de volumen 0013** (Case 26: v1m=296, v5m=410, v15m=345, TF macro
   independiente) y los de FSM Sweep/Grab/Run, EQH/EQL, zonas, replay guard, equiv incremental==batch.
3. `prove -l t` completo en verde.

## Verificación obligatoria
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Indicators/Liquidity.pm && prove -l t"
```
Y prueba REAL de arranque (debe pintar el gráfico en segundos, no colgarse):
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && timeout 30 perl -I. market.pl; echo EXIT=\$?"
```
(EXIT por timeout de 30s significa que la GUI quedó abierta = OK; lo que NO debe pasar es que el
log se quede en 'Render geometry' sin avanzar. Añade un print tras sync_overlay_indicators si
quieres evidenciar que el primer render termina.)

## Qué no tocar
- `Market/Debug/`, `Market/MarketData.pm`, `Data/2026_03.csv`.
- La semántica de volumen multi-TF de 0013 (rango temporal) — solo su implementación interna.
- SMC, overlays, ChartEngine (salvo que un print de diagnóstico ayude; preferible no tocar).
- La FSM (clasificación Sweep/Grab/Run) y las 7 zonas: misma salida, solo más rápido.

## Prompt mínimo para implementor
Implementa `tasks/0016-liquidity-performance-fix.md`. La app se cuelga al abrir con el CSV real
(29888 velas) porque `Liquidity::_sum_volume_for_tf` recorre el array completo del TF parseando
Time::Moment por vela, en cada evento resuelto (96% del tiempo, perfilado). Cachea los epochs una
vez por TF y usa prefix-sum de volumen + búsqueda binaria para sumar el rango en O(log n); poda los
niveles Resolved de _active_levels. Mantén EXACTA la semántica de volumen por timestamp de 0013
(Case 26: v1m=296, v5m=410, v15m=345). Añade en t/10 un test de cota de tiempo (>=5000 velas < 5s)
que falle con el código viejo. No toques Market/Debug/, MarketData.pm ni el CSV. Verifica con
prove -l t y con un arranque real de market.pl (timeout 30s) que ya no se cuelga.
