# Task 0014: Getters no-mutantes en SMC_Structures (idempotencia para Replay)

## Spec relacionada
`specs/0004-smc-structures.md`. Desbloquea task 0008 (overlay SMC) y la integración con Replay
(spec 0002). Resuelve el punto 2 de TECH_DEBT (mutación de estado en getters).

## Contexto / defecto (escalado por el implementor, confirmado por el arquitecto)
`Market/Indicators/SMC_Structures.pm::get_pivots()` confirma los pivotes provisionales
(`_current`, `_trailing`) llamando `_confirm_pivot(...)` y luego los pone a `undef`. Eso **muta
destructivamente** el estado: tras una llamada a un getter, los siguientes `update_last` (pasos del
Replay) pierden el rastro del candidato y la FSM del zigzag deja de calcular bien. Como
`get_events/get_major/get_fvg/get_fibonacci/get_all_items/get_values` invocan `get_pivots()`
internamente, **cualquier** consulta del overlay corrompe el indicador.

El overlay (0008) consultará el indicador en CADA frame y en CADA paso de Replay. Por tanto los
getters deben ser de SOLO LECTURA.

## Objetivo
Hacer que TODOS los getters públicos sean **idempotentes y no-mutantes**: invocarlos cualquier
número de veces, en cualquier orden, entre llamadas a `update_last`, no debe cambiar el estado
interno ni el resultado de cálculos posteriores. El resultado observable (incluida la cola
provisional de pivotes) debe seguir siendo el mismo que hoy.

## Archivos permitidos
- `Market/Indicators/SMC_Structures.pm`
- `t/09-smc-structures.t`

## Diseño requerido (confirmación provisional PURA)
1. `_pivots` solo crece por las confirmaciones REALES de la FSM dentro de `_process_swing` (cuando
   un swing opuesto confirma un giro). Eso NO cambia.
2. La "cola provisional" (`_current` y luego `_trailing`) NO se persiste. En su lugar:
   - Extraer la lógica de etiquetado de `_confirm_pivot` a un helper **puro**
     `_label_for(candidate, last_high, last_low)` que, dado el candidato y los últimos extremos,
     devuelva `(label, new_last_high, new_last_low)` SIN tocar `$self` (sin push a `_pivots`, sin
     modificar `_last_high/_last_low/_last_hh/_major_*/_values`).
   - `get_pivots()` construye y devuelve una **copia**:
     `@{ $self->{_pivots} }` + la confirmación provisional de `_current` y, después, `_trailing`,
     etiquetadas con `_label_for` usando **copias locales** de `_last_high`/`_last_low` aplicadas en
     orden (current primero, trailing después, porque el label del segundo depende del primero).
   - NO poner `_current`/`_trailing` a `undef`. NO llamar `_confirm_pivot` desde getters.
3. `get_events`, `get_fvg`: devolver los arrays ya calculados durante `update_last`
   (`_events`, FVG activos). **Quitar** la llamada interna a `get_pivots()` (era el origen de la
   mutación; esos datos ya existen sin flush).
4. `get_major`, `get_fibonacci`: devolver el major ya mantenido por la FSM durante `update_last`.
   Si hoy dependían de que el flush actualizara el major con la cola provisional, replicar ese
   efecto de forma NO-mutante (calcular el major "efectivo" considerando la cola provisional con
   copias locales). Documentar la elección.
5. `reset` sigue igual.
6. Conservar la equivalencia incremental==batch y todas las anclas/invariantes de 0005–0007.

`get_pivots()` que mutaba era el atajo del caso "fin de datos batch"; ahora la confirmación
provisional se materializa solo en la respuesta, nunca en el estado.

## Tests requeridos (en t/09)
1. **Idempotencia de lectura (NUEVO, es el corazón de esta task):**
   - Construir un fixture de varias velas.
   - Caso A: alimentar `update_last` 0..n y al final leer `get_pivots()`/`get_events()`/`get_fvg()`.
   - Caso B: alimentar `update_last` 0..n PERO llamando `get_pivots()`, `get_events()`, `get_major()`,
     `get_fvg()`, `get_fibonacci()` DESPUÉS DE CADA `update_last` (simulando el overlay/Replay).
   - Afirmar que el resultado final de A y B es **idéntico** (mismo nº de pivotes/eventos, mismos
     index/type/price). Con el código viejo, B difiere de A → el test falla; con el fix, coinciden.
2. **Idempotencia simple:** llamar `get_pivots()` dos veces seguidas devuelve lo mismo y no cambia
   `get_pivots()` una tercera vez.
3. Conservar TODOS los tests existentes de 0005/0006/0007 en verde (anclas HH@5, LL@8, BOS, CHoCH
   true/false, FVG exacto/mitigación, fib_0.618=12.326, equiv incremental==batch).

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- `Market/MarketData.pm`, `Data/2026_03.csv`.
- La lógica de detección (swing/FSM/BOS/CHoCH/FVG/fibo): solo se REUBICA el etiquetado provisional
  a un helper puro; no se cambian las reglas ni los umbrales.

## Verificación obligatoria
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Indicators/SMC_Structures.pm && prove -l t"
```
(Copia Windows desde WSL: `cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA`.)

## Prompt mínimo para implementor
Implementa `tasks/0014-smc-non-mutating-getters.md`. Haz que TODOS los getters de
`Market/Indicators/SMC_Structures.pm` sean de solo lectura (idempotentes): extrae el etiquetado de
`_confirm_pivot` a un helper puro `_label_for`, y que `get_pivots()` devuelva una copia con la cola
provisional etiquetada sin tocar `$self` (sin poner `_current`/`_trailing` a undef, sin push). Quita
las llamadas internas a `get_pivots()` de los demás getters. Añade en `t/09` un test de idempotencia
que alimente `update_last` consultando los getters DESPUÉS DE CADA vela y afirme que el resultado
final es idéntico a no consultar nunca (debe fallar con el código viejo). No toques Market/Debug/,
MarketData.pm ni el CSV. Ejecuta `prove -l t` completo.
