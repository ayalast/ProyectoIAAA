# Task 0007: SMC — FVG con mitigación progresiva + Fibonacci

## Spec relacionada
`specs/0004-smc-structures.md` (secciones FVG y Fibonacci). Depende de task 0005.

## Objetivo
Ampliar `Market/Indicators/SMC_Structures.pm` para detectar Fair Value Gaps (FVG) entre 3 velas
con mitigación progresiva, y trazar los niveles de Fibonacci entre el major high/low vigentes.

## Archivos probablemente relevantes
- `Market/Indicators/SMC_Structures.pm`.
- `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf`; spec 0004.

## Pasos
1. **FVG:** detectar el hueco/imbalance entre 3 velas consecutivas (gap dejado por la vela central):
   - FVG alcista: `low[i+1] > high[i-1]` (gap entre vela i-1 y i+1, centrado en i). 
   - FVG bajista: `high[i+1] < low[i-1]`.
   - (Ajustar la convención exacta de índices a la guía; documentarla.)
2. **Mitigación progresiva:** cuando velas posteriores penetran el gap, **reducir** la zona
   (recortar el borde consumido); cuando se consume del todo, **eliminarla**. Guardar el estado de
   cada FVG: límites actuales y % mitigado.
3. Marcar como **"Zona de Alta Reacción"** los FVG formados en la vela de un Sweep/Grab o
   inmediatamente posterior (la marca la setea la concurrencia, spec 0006; aquí dejar el campo).
4. **Fibonacci:** trazar niveles entre el major high y major low vigentes (de task 0006):
   0.236, 0.382, 0.5, 0.618, 0.786 (clave 0.618). Recalcular cuando cambie el major.
5. Exponer FVGs (con límites y estado) y niveles Fibonacci para el overlay.

## Criterios de aceptación
- Los FVG se detectan entre 3 velas y se reducen progresivamente al mitigarse; se eliminan al
  consumirse.
- Los niveles de Fibonacci se calculan entre el major high/low vigentes y se actualizan al cambiar.
- Cálculo puro, sin Tk.

## Verificación por debug (OBLIGATORIA)
Lee `docs/PHASE2_DEBUG_CONTRACT.md`. Los FVG salen como items `type` ∈ {`FVG_up`,`FVG_down`} con
`index`, `hi`, `lo`, `mitig` (0..1); los niveles de Fibo como `fib_0.236`...`fib_0.786` con `price`.

Ampliar `t/09-smc-structures.t`:
1. un FVG alcista conocido (p.ej. velas i-1,i,i+1 con `low[i+1] > high[i-1]`): verificar `hi`/`lo`
   exactos vía `render_items(..., fields => [qw(index type hi lo mitig)])`;
2. tras introducir velas que penetran parcialmente el gap, `mitig` aumenta y `hi`/`lo` se recortan;
3. al consumirse del todo, el FVG desaparece de la lista;
4. dados major_high/major_low conocidos, los 5 niveles `fib_*` tienen `price` esperado (0.618 clave).
Comparar contra el esperado transcrito y `replay_violations == 0`.

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Indicators/SMC_Structures.pm && prove -l t"
```

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- El render (task 0008).
- BOS/CHoCH y major (task 0006); aquí solo se consume el major ya calculado.
