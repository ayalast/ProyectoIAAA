# Task 0010: Liquidity — clasificación Sweep/Grab/Run + máquina de estados (5 estados)

## Spec relacionada
`specs/0005-liquidez.md` (clasificación + FSM). Depende de task 0009.

## Objetivo
Ampliar `Market/Indicators/Liquidity.pm` con la clasificación de eventos de liquidez
(Sweep / Grab / Run) según reglas estrictas de cierre, gobernada por una máquina de estados de 5
fases por cada nivel detectado.

## Archivos probablemente relevantes
- `Market/Indicators/Liquidity.pm`.
- `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` §4.2–§4.3.
- `docs/material_profesor/imagenes/maquina_estados_liquidez.png` (diagrama oficial).

## Pasos
1. Implementar la FSM por nivel (parámetro `N`=3 inicial, configurable):
   - **Detected:** nivel válido (BSL/SSL/EQH/EQL) almacenado.
   - **Swept:** `High > BSL` o `Low < SSL`.
   - **Acceptance:** cierres fuera del nivel sostenidos por `N` velas → encaminado a Run.
   - **Reclaimed:** el cierre (o el cuerpo, dentro de ≤3 velas) regresa al rango → Sweep/Grab.
   - **Resolved:** fin de ciclo; clasificación final **inmutable**.
2. Clasificación final:
   - **Sweep:** rompe y **regresa** (Alcista: `High>BSL` luego `Close<BSL`; Bajista: `Low<SSL` luego
     `Close>SSL`).
   - **Grab:** barrido con rechazo rápido, retorno/rechazo en **≤3 velas**, sin aceptación fuera.
   - **Run:** `N` velas consecutivas cierran estrictamente fuera del nivel barrido (aceptación).
3. Emitir, por evento resuelto: tipo (Sweep/Grab/Run), dirección, nivel, índice de resolución y los
   estados intermedios (para etiquetas/HMM).
4. Mantener cálculo puro e incremental.

## Criterios de aceptación
- La FSM transita Detected→Swept→(Acceptance|Reclaimed)→Resolved con clasificación final inmutable.
- Las reglas de cierre (incluyendo `N` velas y la ventana de ≤3 velas del Grab) se aplican exactas.
- Sweep vs Grab vs Run se distinguen según las definiciones del PDF.

## Verificación por debug (OBLIGATORIA)
Lee `docs/PHASE2_DEBUG_CONTRACT.md`. Los eventos salen como items `type` ∈
{`SWEEP_UP`,`SWEEP_DOWN`,`GRAB`,`RUN`} con `index` (vela de resolución), `dir`, `price` (nivel) y
`state` (estado FSM; final inmutable en `Resolved`).

Ampliar `t/10-liquidity.t` con tres tramos sintéticos deterministas:
1. **Sweep:** `High>BSL` y luego `Close<BSL` → item `SWEEP_UP` con `state=Resolved`;
2. **Grab:** barrido con retorno/rechazo en ≤3 velas → item `GRAB`;
3. **Run:** `N=3` cierres consecutivos estrictamente fuera del nivel → item `RUN`.
Comparar `render_items(..., fields => [qw(index type dir state price)])` contra el esperado
transcrito en el test. Verificar también que la FSM pasa por los estados intermedios
(Detected→Swept→…→Resolved) exponiéndolos. `replay_violations == 0`.

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Indicators/Liquidity.pm && prove -l t"
```

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- El pesado de volumen multi-TF y las 7 zonas (task 0011). El render (task 0012). La concurrencia
  con BOS/CHoCH (spec 0006, 2ª entrega).
