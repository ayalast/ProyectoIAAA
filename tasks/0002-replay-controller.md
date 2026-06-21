# Task 0002: ReplayController + índice-tope

## Spec relacionada
`specs/0002-sistema-replay.md`

## Objetivo
Introducir un control de Replay que mantiene un índice-tope (`replay_idx`) y garantiza que ninguna
capa lea/dibuje velas con índice > `replay_idx`. Sin UI todavía (eso es task 0004); aquí la lógica.

## Archivos probablemente relevantes
- Nuevo: `Market/ReplayController.pm` (o, si se prefiere, estado dentro de `ChartEngine`; preferir
  módulo separado para no engordar ChartEngine — ver TECH_DEBT).
- `Market/ChartEngine.pm` (`compute_window`, render: deben respetar el tope).
- `Market/IndicatorManager.pm` (recálculo hasta el tope).

## Pasos
1. Crear `ReplayController` con estado: `active` (bool), `replay_idx` (entero), `playing` (bool),
   `speed` (para fast forward). Métodos: `start($idx)`, `play`, `pause`, `step_forward`,
   `step_backward`, `fast_forward`, `exit`, `current_index`, `is_active`.
2. En `ChartEngine.compute_window`: si el Replay está activo, el límite superior efectivo de datos
   es `min(last_index, replay_idx)`. Las velas con índice > `replay_idx` NO entran en el slice.
3. El recálculo de indicadores y overlays se hace hasta `replay_idx` (truncado), nunca más allá.
4. `play`/`fast_forward` avanzan `replay_idx` con un temporizador Tk `after` (el cableado del timer
   puede dejarse mínimo aquí y completarse en task 0004); `pause` lo detiene; `exit` restaura tope
   = `last_index`.
5. Clamp de `replay_idx` a `[0, last_index]`.

## Criterios de aceptación
- Con Replay activo en índice k, `compute_window` jamás devuelve índices > k.
- Step forward/backward mueven exactamente 1; clamp en extremos.
- Exit restaura la vista normal (tope = última vela).
- Los indicadores en `replay_idx=k` == indicadores con dataset truncado a k (sin fuga de futuro).

## Verificación por debug (OBLIGATORIA)
El criterio duro del PDF ("bajo ninguna circunstancia velas futuras") se prueba con texto, no a ojo.

Crear `t/12-replay.t` (sin Tk; usar el `TestMarketData`/`TestCanvas` de `t/07` como referencia):
1. con `replay_idx=k`, afirmar que `compute_window` jamás devuelve `end > k`;
2. `step_forward`/`step_backward` mueven exactamente 1; clamp en `[0,last_index]`;
3. `exit` restaura tope = `last_index`;
4. usar `Market::Debug::IndicatorSnapshot->replay_violations(\@items, $replay_idx)` con una lista
   sintética de items que incluya índices > k, y afirmar que el guard los detecta (== prueba de que
   overlays/indicadores respetarán el tope cuando se integren en 0008/0012).

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ReplayController.pm && perl -I. -c Market/ChartEngine.pm && prove -l t"
```

## Estado
**Arrancable ya** (no depende de 0000g ni de 0001).

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- La UI (task 0004). Aquí solo la lógica del tope y su efecto en window/render.
- La lógica de indicadores concretos (solo el punto de truncado).
