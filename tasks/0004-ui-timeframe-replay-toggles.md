# Task 0004: UI — menú de timeframe + controles Replay + toggles de overlays

## Spec relacionada
`specs/0010-ui-timeframe-replay-toggles.md` (depende de tasks 0001, 0002, 0003)

## Objetivo
Actualizar la interfaz Tk: reemplazar los Radiobutton de timeframe por un menú desplegable con las
8 temporalidades, añadir los 7 controles de Replay y checkboxes de toggle para overlays y niveles HTF.

## Archivos probablemente relevantes
- `market.pl` (construcción de la UI, barra de controles, callbacks).
- `Market/ChartEngine.pm` (callbacks de timeframe, hooks de Replay y de `set_visible`).
- `Market/ReplayController.pm` (task 0002), `Market/OverlayManager.pm` (task 0003).

## Pasos
1. Sustituir los Radiobutton de TF por un `Optionmenu` (o menubutton) con `1m,5m,15m,1h,2h,4h,D,W`,
   enlazado a `active_tf`; al cambiar, llamar al flujo de `set_timeframe`.
2. Añadir una caja "Replay" con botones: Inicio Replay, Play, Pause, Step Fwd, Step Back, Fast Fwd,
   Exit. Cablear cada botón al `ReplayController` y disparar re-render. Play/Fast Fwd usan `after`.
3. Añadir una caja "Capas/Overlays" con checkboxes que llamen `OverlayManager.set_visible($name,$on)`
   para: SMC (BOS/CHoCH), FVG, Fibonacci, BSL/SSL, EQH/EQL, Sweep/Grab/Run (y placeholders para
   strategy/volume profile/VWAP, deshabilitados hasta que existan).
4. Añadir checkbox "Niveles HTF sobre LTF" (contexto macro) — togglea la proyección de niveles de
   mayor temporalidad.
5. Mantener la separación visual con frames `relief => 'groove'` como en Fase 1; no saturar la barra
   (agrupar; si hace falta, una segunda fila de controles).

## Criterios de aceptación
- El menú desplegable cambia de TF y recalcula bien (las 8 opciones).
- Los 7 controles de Replay funcionan (no aparecen velas futuras).
- Cada checkbox muestra/oculta su overlay sin afectar a los demás.
- La UI sigue legible y agrupada.

## Verificación (OBLIGATORIA)
La UI Tk no se testea headless, pero su cableado sí:
1. `perl -I. -c market.pl` y `perl -I. -c Market/ChartEngine.pm` deben pasar;
2. `prove -l t` completo debe seguir verde (no romper Replay/Overlays de 0002/0003);
3. afirmar en un test que los callbacks de TF llaman a `set_timeframe` con los 8 valores válidos y
   que los botones de Replay invocan los métodos del `ReplayController` (puede hacerse con un mock
   que registre llamadas, sin abrir ventana).

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c market.pl && perl -I. -c Market/ChartEngine.pm && prove -l t"
```
Prueba manual con WSLg (complementaria): `perl -I. market.pl` → cambiar TF por menú, ejecutar
Replay, alternar toggles.

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- La lógica interna de cada overlay/indicador (solo el cableado UI ↔ estado).
- El comportamiento de zoom/drag/crosshair de Fase 1.
