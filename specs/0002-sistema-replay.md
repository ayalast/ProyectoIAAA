# Spec 0002: Sistema Replay

Fuente: PDF Fase 2 §3 "Mecánica del Sistema Replay". Clase 06-15.

## Objetivo
Permitir reproducir el mercado vela a vela desde una fecha/hora seleccionada, recalculando
indicadores y overlays únicamente hasta la última vela visible, **sin mostrar jamás velas
futuras**.

## Problema
Para validar visualmente cuándo se activa cada etiqueta SMC/liquidez (y para demostrar al
profesor el momento exacto de cada confirmación) se necesita avanzar el tiempo de forma
controlada. Hoy el chart siempre muestra el dataset completo hasta el final.

## Usuarios afectados
El operador que estudia/demuestra el comportamiento; todos los indicadores y overlays (que
deben respetar el índice-tope del Replay).

## Comportamiento esperado
- Existe un **índice-tope de Replay** `replay_idx`: ninguna capa puede leer ni dibujar velas con
  índice > `replay_idx`.
- Controles en la UI (Tk) que mapean: **Inicio Replay, Play, Pause, Step Forward, Step Backward,
  Fast Forward, Exit Replay** (spec 0010).
- `Play`/`Fast Forward` avanzan `replay_idx` con un temporizador Tk (`after`); `Pause` lo detiene.
- Cada avance/retroceso dispara recálculo incremental de indicadores y re-render de overlays
  hasta `replay_idx`.
- `Exit Replay` vuelve al modo normal (tope = última vela del dataset).
- El Replay opera sobre la temporalidad activa; al cambiar de TF en Replay, el tope se mapea a la
  vela equivalente.

## Fuera de alcance
- Persistir sesiones de Replay entre ejecuciones.
- Reproducción a velocidades arbitrarias finas (basta Play normal + Fast Forward).

## Criterios de aceptación
- En cualquier punto del Replay, el Canvas NO contiene ninguna vela ni etiqueta de índice
  > `replay_idx` (criterio duro del PDF: "bajo ninguna circunstancia").
- Step Forward/Backward mueven exactamente 1 vela; Play avanza automáticamente; Pause detiene.
- Los indicadores muestran exactamente el mismo valor que tendrían si el dataset terminara en
  `replay_idx` (no hay "fuga" de información futura).
- Exit Replay restaura la vista normal sin artefactos.

## Casos límite
- `replay_idx` en la primera vela (no hay historial para algunos indicadores): degradar limpio.
- Fast Forward más allá del final: clamp al último índice y pausar.
- Cambiar timeframe durante Replay: re-mapear el tope sin mostrar futuro.
- Interacción con zoom/drag: el usuario puede navegar, pero el futuro sigue oculto.

## Plan de verificación
- `perl -I. -c` de los módulos tocados (ChartEngine + control de Replay + market.pl).
- Test manual: iniciar Replay a mitad del dataset, verificar que no aparecen velas futuras;
  Step Forward 1 a 1 y observar aparición de etiquetas.
- Verificar que indicadores en `replay_idx=k` == indicadores con dataset truncado a k.
