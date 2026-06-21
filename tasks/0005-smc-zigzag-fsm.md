# Task 0005: Indicators/SMC_Structures — zigzag por FSM + HH/HL/LL/LH

## Spec relacionada
`specs/0004-smc-structures.md` (sección Zigzag/pivotes). Depende de task 0001.

## Objetivo
Crear `Market/Indicators/SMC_Structures.pm` (cálculo puro, sin Tk) que detecte swing points y
construya el zigzag etiquetando cada extremo como HH/HL/LL/LH mediante una **máquina de estados**
(NO ventanas de tamaño fijo), sin saltar velas.

## Archivos probablemente relevantes
- Nuevo: `Market/Indicators/SMC_Structures.pm`.
- `Market/IndicatorManager.pm` (contrato `update_last`/`get_values`/`reset`; registrar el indicador).
- `Market/MarketData.pm` (lectura de velas/slices por índice).
- Referencia teórica: `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` §4.1 y
  `docs/material_profesor/imagenes/formula_swing_high.png` / `formula_swing_low.png`.

## Pasos
1. Implementar detección de swing con profundidad `k` (default 3, parámetro configurable):
   - Swing High en `i`: `High[i] > High[i-k..i-1]` y `High[i] > High[i+1..i+k]`.
   - Swing Low en `i`: `Low[i] < Low[i-k..i-1]` y `Low[i] < Low[i+1..i+k]`.
2. Implementar la FSM del zigzag: mantener dirección actual (buscando alto / buscando bajo) y el
   último extremo confirmado; al confirmar un nuevo extremo, etiquetarlo comparando con el extremo
   previo del mismo tipo: HH/HL (en tramos al alza) y LL/LH (en tramos a la baja). La FSM decide el
   giro por ruptura de estructura, **sin contar un número fijo de velas**.
3. Garantizar que cada extremo relevante queda etiquetado (no saltar velas de liquidez).
4. Respetar el contrato del IndicatorManager: `update_last($market_data,$i)` (incremental),
   `get_values()` (lista de etiquetas/pivotes por índice), `reset()`.
5. Exponer la lista de pivotes con: índice, precio, tipo (HH/HL/LL/LH) para que el overlay y el
   módulo de liquidez los consuman.

## Criterios de aceptación
- Cada extremo del zigzag queda etiquetado HH/HL/LL/LH; no se saltan extremos.
- En mercado lateral no se generan HH/LL espurios (la FSM filtra ruido interno).
- El cálculo es puro (sin `Tk`, sin coordenadas de pantalla).
- `reset()` + recálculo vela por vela reproduce el mismo resultado que un cálculo batch.

## Verificación por debug (OBLIGATORIA)
Lee `docs/PHASE2_DEBUG_CONTRACT.md` (§5.bis: política de exactitud). `get_pivots()` (o equivalente)
debe devolver items con `index` (global) y `type` ∈ {`HH`,`HL`,`LL`,`LH`} según el contrato §4.

El zigzag es **FSM-dependiente** → se prueba con `input exacto + invariantes + anclas`, NO con una
única cadena forzada.

Crear `t/09-smc-structures.t` que:
1. construya un fixture de velas sintéticas deterministas (sin Tk). Fixture mínimo (high,low) por
   índice 0..8, con `k=1`:
   `(10,9) (12,10) (11,10) (14,11) (13,12) (16,13) (15,12) (12,9) (10,7)`;
2. corra el indicador puro vela a vela (`update_last`);
3. afirme las **invariantes** sobre `type_sequence($items)`:
   - todo extremo confirmado tiene una de las 4 etiquetas (no hay `?` ni huecos);
   - no hay dos `HH` consecutivos sin un `HL`/`LL` entre medias, ni dos `LL` sin un `LH`/`HH`;
   - en tendencia clara al alza los máximos crecientes son `HH` y en el desplome final aparece `LL`/`LH`;
4. afirme **anclas concretas**: el máximo en `index=5` (high=16) es `HH`; el mínimo del desplome
   (`index=8`, low=7) es `LL`;
5. afirme `replay_violations($items, 4) == 0` para los items hasta index 4.

Si tu FSM/`k` produce otra secuencia que respeta input+invariantes+anclas, es válida; documenta el
porqué en un comentario del test. NO conviertas esto en "test recomendado": debe existir y pasar.

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Indicators/SMC_Structures.pm && prove -l t"
```

## Qué no tocar
- `Market/Debug/` (lo mantiene el arquitecto; si falta un campo, repórtalo, no lo edites).
- El render (eso es task 0008).
- BOS/CHoCH y FVG (tasks 0006 y 0007); aquí solo swing + zigzag etiquetado.
