# Task 0012: Overlays/Liquidity — render Tabla 2 + toggles

## Spec relacionada
`specs/0005-liquidez.md` (render, Tabla 2). Depende de tasks 0003, 0010.

## Objetivo
Crear `Market/Overlays/Liquidity.pm` que dibuje las estructuras de liquidez sobre el Canvas con los
estilos/colores/etiquetas exactos de la Tabla 2 del PDF, con toggles individuales y respeto a Replay.

## Archivos probablemente relevantes
- Nuevo: `Market/Overlays/Liquidity.pm` (bajo el contrato de task 0003).
- `Market/OverlayManager.pm`, `Market/Panels/Scales.pm`, `Market/ChartEngine.pm`.
- `Market/Indicators/Liquidity.pm` (fuente de datos).

## Pasos
1. Implementar el overlay bajo el contrato, con tag de Canvas propio (p. ej. `ov_liq`).
2. `compute_visible`: pedir al indicador niveles/eventos dentro de la ventana visible + contexto.
3. `draw($scales)` según la Tabla 2:
   | Elemento | Estilo | Color | Etiqueta |
   |---|---|---|---|
   | BSL | horizontal discontinua/punteada | Rojo | BSL |
   | SSL | horizontal discontinua/punteada | Verde | SSL |
   | EQH | línea que conecta máximos | Configurable | EQH |
   | EQL | línea que conecta mínimos | Configurable | EQL |
   | Sweep Up | marcador / línea de quiebre | Rojo | SWEEP ↑ |
   | Sweep Down | marcador / línea de quiebre | Verde | SWEEP ↓ |
   | Liquidity Grab | destacado de rechazo rápido | Naranja | LQ GRAB |
   | Liquidity Run | extensión de ruptura | Azul | LQ RUN |
4. Toggles individuales por elemento (cablear a UI, task 0004); colores EQH/EQL configurables.
5. Actualización dinámica al entrar nuevas velas; respeta `replay_idx` (no dibujar futuro).

## Criterios de aceptación
- Render conforme a la Tabla 2 (estilos, colores, textos de etiqueta).
- Cada elemento se puede activar/desactivar individualmente.
- Comportamiento comparable a LuxAlgo/TradingView SMC; sin futuro en Replay.

## Verificación por debug (OBLIGATORIA)
Validar el render por las ops del Canvas, no a ojo.

Ampliar el test de overlays con un `TestCanvas`:
1. alimentar el overlay con items del contrato (BSL, SSL, EQH, EQL, SWEEP_UP, GRAB, RUN);
2. afirmar que cada elemento produce ops con su tag `ov_liq` y el color/estilo esperado de la
   Tabla 2 (BSL rojo punteado, SSL verde punteado, GRAB naranja, RUN azul, etc.) — comparar el
   argumento de color que se pasa a `createLine/createText`;
3. afirmar que `set_visible(0)` por elemento oculta solo ese elemento;
4. con `replay_idx=k`, sin items de índice > k (vía `IndicatorSnapshot->replay_violations`).

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Overlays/Liquidity.pm && perl -I. -c Market/ChartEngine.pm && perl -I. -c market.pl && prove -l t"
```
Prueba manual con WSLg (complementaria): activar capas y verificar en Replay vela a vela.

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- La lógica de cálculo (Indicators/Liquidity). El render de SMC (task 0008).
