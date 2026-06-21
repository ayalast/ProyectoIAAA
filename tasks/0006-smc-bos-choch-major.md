# Task 0006: SMC — BOS / CHoCH (verdadero vs falso) + major high/low

## Spec relacionada
`specs/0004-smc-structures.md` (secciones Major high/low, BOS, CHoCH). Depende de task 0005.

## Objetivo
Ampliar `Market/Indicators/SMC_Structures.pm` para mantener el major high/low vigente y detectar
BOS y CHoCH (verdadero vs falso/inducement) con confirmación por cierre de cuerpo.

## Archivos probablemente relevantes
- `Market/Indicators/SMC_Structures.pm` (sobre lo hecho en task 0005).
- `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` §4–§5; spec 0004.

## Pasos
1. **Major high / major low:** mantener exactamente uno de cada uno vigente (estructura externa).
   Actualizarlos solo tras romper (confirmado) el nivel opuesto. El resto es estructura interna.
2. **BOS (continuación):** confirmar con **cierre de cuerpo** que supera el HH/LL relevante previo
   (no basta la mecha). Marcar `pending` si solo la mecha rompe; invalidar si la vela siguiente
   revierte con fuerza. Distinguir BOS válido vs falso.
3. **CHoCH (cambio):** **verdadero** solo si rompe el **major** low/high (no interno) con cierre de
   cuerpo y se mantiene en la vela siguiente. **Falso = inducement** si rompe estructura interna /
   manipulación; etiquetar distinto. Apoyarse en HTF para decidir.
4. Emitir, por índice de confirmación: tipo de evento (BOS / CHoCH_true / CHoCH_false), dirección y
   nivel roto, para overlay y para el módulo de liquidez (concurrencia, spec 0006).
5. Mantener todo como cálculo puro e incremental (contrato IndicatorManager).

## Criterios de aceptación
- Siempre hay a lo sumo un major high y un major low vigentes; se actualizan solo tras ruptura
  confirmada del opuesto.
- BOS/CHoCH se etiquetan solo tras cierre de cuerpo; CHoCH verdadero exige romper el major.
- CHoCH falso (inducement) se distingue del verdadero.
- La etiqueta queda ubicada en la vela/tiempo de confirmación (clave para Replay).

## Verificación por debug (OBLIGATORIA)
Lee `docs/PHASE2_DEBUG_CONTRACT.md`. Los eventos deben salir como items con `index` (vela de
confirmación), `type` ∈ {`BOS`,`CHoCH_true`,`CHoCH_false`}, `dir`, `price` (nivel roto); el major
vigente como `major_high`/`major_low`.

Ampliar `t/09-smc-structures.t` con tramos sintéticos que produzcan, como mínimo:
1. un `BOS` válido (cierre de cuerpo supera HH previo) en un índice conocido;
2. un `BOS` falso (solo mecha) que NO genere item `BOS`;
3. un `CHoCH_true` (rompe el major con cierre de cuerpo);
4. un `CHoCH_false` (rompe solo estructura interna).
Comparar con `render_items(...)` / `type_sequence(...)` contra el esperado transcrito en el test, y
`replay_violations == 0`.

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Indicators/SMC_Structures.pm && prove -l t"
```

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- El render (task 0008). FVG/Fibonacci (task 0007).
