# Task 0009: Indicators/Liquidity — swings, EQH/EQL, BSL/SSL

## Spec relacionada
`specs/0005-liquidez.md` (niveles base). Depende de task 0005 (swings/zigzag).

## Objetivo
Crear `Market/Indicators/Liquidity.pm` (cálculo puro) que detecte swing points, Equal Highs/Lows
(EQH/EQL) con tolerancia dinámica, y los niveles BSL/SSL.

## Archivos probablemente relevantes
- Nuevo: `Market/Indicators/Liquidity.pm`.
- `Market/Indicators/SMC_Structures.pm` (reutilizar swings/pivotes ya calculados).
- `Market/Indicators/ATR.pm` (tolerancia EQH/EQL = ATR*0.10).
- `Market/IndicatorManager.pm`; `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` §4.1.

## Pasos
1. Reutilizar los swing highs/lows del módulo SMC (o recalcular con la misma definición `k=3`).
2. **EQH/EQL** con tolerancia dinámica `tolerancia = ATR * 0.10` (parámetro configurable):
   - EQH: `abs(high_1 - high_2) <= tolerancia`.
   - EQL: `abs(low_1 - low_2) <= tolerancia`.
   - Conectar pares de pivotes "iguales" distantes en el tiempo.
3. **BSL:** niveles de liquidez por encima de máximos relevantes (swing highs, EQH, techos de rango).
   **SSL:** por debajo de mínimos relevantes (swing lows, EQL, suelos de rango).
4. Exponer los niveles (precio, índice de origen, tipo BSL/SSL/EQH/EQL) para la FSM (task 0010) y el
   overlay (task 0012).
5. Cálculo puro e incremental (contrato IndicatorManager).

## Criterios de aceptación
- Detección correcta de swings, EQH/EQL (con tolerancia ATR*0.10) y BSL/SSL.
- La tolerancia se adapta a la volatilidad (ATR) en cada punto.
- Sin Tk; reproducible batch vs incremental.

## Verificación por debug (OBLIGATORIA)
Lee `docs/PHASE2_DEBUG_CONTRACT.md`. Los niveles salen como items `type` ∈ {`BSL`,`SSL`,`EQH`,`EQL`}
con `index`, `price`.

Crear `t/10-liquidity.t`:
1. velas sintéticas con dos swing highs casi iguales dentro de `ATR*0.10` → debe emitir `EQH`;
   dos fuera de tolerancia → NO `EQH`;
2. swing high/low conocidos → `BSL` por encima, `SSL` por debajo, con `price` esperado;
3. comparar vía `render_items(...)`/`type_sequence(...)` contra el esperado transcrito;
4. reproducir batch == incremental (mismo `render_items`).

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Indicators/Liquidity.pm && prove -l t"
```

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- Clasificación Sweep/Grab/Run y FSM (task 0010). El render (task 0012).
