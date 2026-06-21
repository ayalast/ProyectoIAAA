# Spec 0010: UI — menú de timeframe, toggles de overlays y controles Replay

Fuente: PDF Fase 2 §3 + §4.5 (toggles). Clase 06-15 ("pongan menú que se despliega... ya tienen
muchos botones"). Toca: `market.pl` y `ChartEngine.pm`.

## Objetivo
Actualizar la interfaz Tk para Fase 2: reemplazar los botones de temporalidad por un **menú
desplegable**, añadir **controles de Replay** y un panel de **toggles** para activar/desactivar
cada overlay y los niveles de HTF sobre LTF.

## Problema
Con 8 temporalidades y muchos overlays, los Radiobutton actuales saturan la barra. El profesor
pidió explícitamente un menú desplegable y controles de Replay para demostrar las etiquetas.

## Comportamiento esperado
- **Selector de timeframe:** menú desplegable (Tk `Optionmenu`/menubutton) con 1m,5m,15m,1h,2h,4h,
  D,W; sustituye a los Radiobutton. Cambia el TF activo (spec 0001).
- **Controles de Replay** (spec 0002): botones Inicio Replay, Play, Pause, Step Forward, Step
  Backward, Fast Forward, Exit Replay.
- **Toggles de overlays:** checkboxes para mostrar/ocultar cada capa: estructura SMC (BOS/CHoCH),
  FVG, Fibonacci, BSL/SSL, EQH/EQL, Sweep/Grab/Run, estrategias, volume profile, VWAP.
- **Toggle de niveles HTF sobre LTF:** habilitar/deshabilitar la proyección de niveles de mayor
  temporalidad para contexto macro (spec 0001/0004/0005).
- Mantener separación visual de controles (como ya hace Fase 1: cajas con `relief => 'groove'`).

## Fuera de alcance
- La lógica de cada overlay (sus specs); aquí solo el cableado UI → `set_visible`/estado.

## Criterios de aceptación
- El menú desplegable cambia de timeframe y recalcula correctamente.
- Los 7 controles de Replay funcionan y mapean a la lógica de spec 0002.
- Cada toggle muestra/oculta su overlay sin afectar a los demás.
- La barra no queda saturada; controles agrupados y legibles.

## Casos límite
- Toggles cuyo overlay aún no tiene datos en la ventana: no fallar.
- Cambiar timeframe mientras se está en Replay (spec 0002).

## Plan de verificación
- `perl -I. -c market.pl` y `perl -I. -c Market/ChartEngine.pm`.
- Prueba manual con WSLg: cambiar TF por menú, ejecutar Replay, alternar cada toggle.
