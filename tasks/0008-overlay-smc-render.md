# Task 0008: Overlays/SMC_Structures — render de estructura

## Spec relacionada
`specs/0004-smc-structures.md` (render). Depende de tasks 0003, 0006, 0007.

## Objetivo
Crear `Market/Overlays/SMC_Structures.pm` que dibuje en el Canvas la estructura calculada por
`Indicators/SMC_Structures.pm`: etiquetas BOS/CHoCH, líneas de major high/low, cajas de FVG (que se
reducen al mitigarse) y niveles de Fibonacci. Activable/desactivable; respeta Replay.

## Archivos probablemente relevantes
- Nuevo: `Market/Overlays/SMC_Structures.pm` (bajo el contrato de task 0003).
- `Market/OverlayManager.pm`, `Market/Panels/Scales.pm`, `Market/ChartEngine.pm`.
- `Market/Indicators/SMC_Structures.pm` (fuente de datos).

## Pasos
1. Implementar el overlay bajo el contrato (`new`, `set_visible`, `compute_visible`, `draw`, `clear`)
   con tag de Canvas propio (p. ej. `ov_smc`).
2. En `compute_visible`, pedir al indicador los pivotes/eventos/FVG/fibo dentro de la ventana
   visible + contexto (no todo el historial).
3. `draw($scales)`:
   - Etiquetas BOS / CHoCH (verdadero vs falso con estilo distinto) en la vela de confirmación.
   - Líneas horizontales de major high / major low vigentes.
   - Cajas de FVG con el tamaño actual (reflejando la mitigación); distinguir "Zona de Alta Reacción".
   - Niveles de Fibonacci entre major high/low (0.618 destacado).
4. Registrar el overlay en `OverlayManager` y cablearlo al toggle de UI (task 0004).
5. Respetar `replay_idx`: no dibujar nada de índice > tope.

## Criterios de aceptación
- La estructura se dibuja correctamente y coincide visualmente con la referencia (SMC Structure+FVG).
- Las cajas de FVG se ven reducir al mitigarse.
- On/off del overlay no afecta a otros ni a las velas.
- En Replay no aparecen elementos futuros.

## Verificación por debug (OBLIGATORIA)
El render no se valida "a ojo": se valida por las operaciones que el overlay manda al Canvas.

Ampliar `t/13-overlays-base.t` (o `t/09`) usando un `TestCanvas` que registre ops:
1. alimentar el overlay con una lista de items del contrato (`docs/PHASE2_DEBUG_CONTRACT.md`) que
   incluya BOS, CHoCH_true, CHoCH_false, un FVG y niveles fib;
2. afirmar que `draw($scales)` genera al menos una op por item visible, con su tag `ov_smc`;
3. afirmar que un FVG con `mitig` mayor produce una caja más pequeña (comparar coords de dos casos);
4. con `replay_idx=k`, afirmar (vía `IndicatorSnapshot->replay_violations`) que el overlay no recibe
   ni dibuja items de índice > k.

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Overlays/SMC_Structures.pm && perl -I. -c Market/ChartEngine.pm && perl -I. -c market.pl && prove -l t"
```
Prueba manual con WSLg (complementaria, NO sustituye el test): comparar con TradingView.

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- La lógica de cálculo (Indicators/SMC_Structures). El módulo de liquidez (tasks 0009-0012).
