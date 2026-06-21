# Spec 0003: Arquitectura base de Overlays

Fuente: PDF Fase 2 §2 "Arquitectura General y de Packages". Constitución (separación cálculo/render).

## Objetivo
Definir e implementar el patrón base de la carpeta nueva `Market/Overlays/`: cómo un overlay se
registra, calcula sobre la ventana visible y se dibuja en el Canvas, de forma uniforme y
activable/desactivable. Es el **habilitador** de las specs 0004, 0005, 0007, 0008, 0009.

## Problema
Fase 2 introduce muchos elementos visuales (estructuras SMC, líneas/velas de liquidez,
estrategias, perfil de volumen, VWAP) que deben dibujarse sobre el chart, activarse/desactivarse
por separado y recalcularse al avanzar el Replay. Sin un patrón común, cada overlay se haría
distinto y `ChartEngine` se volvería un god object (ver TECH_DEBT).

## Usuarios afectados
Todos los módulos visuales de Fase 2; el operador que activa/desactiva capas; `ChartEngine`.

## Comportamiento esperado
- Cada overlay vive en `Market/Overlays/<Nombre>.pm` y consume un indicador de cálculo de
  `Market/Indicators/<Nombre>.pm` (separación estricta cálculo/render).
- Contrato uniforme de overlay (nombres orientativos, ajustar al estilo Perl del repo):
  - `new(%args)` — recibe referencias a Canvas/escala/tema necesarias.
  - `set_visible($bool)` — activa/desactiva el overlay.
  - `compute_visible($market_data, $indicator, $start, $end)` — prepara datos solo de la ventana
    visible + ventana de contexto (no todo el historial; regla de rendimiento del PDF §2).
  - `draw($scales)` — dibuja en el Canvas usando `Scales` para mapear datos↔píxeles.
  - `clear()` — borra sus ítems del Canvas (tags propios por overlay).
- Un **registro de overlays** (en ChartEngine o en un `OverlayManager` nuevo) itera los overlays
  activos en cada render, respetando el `replay_idx` (spec 0002).
- Los overlays NO calculan estructura: piden los resultados al indicador correspondiente.

## Fuera de alcance
- La lógica concreta de SMC/liquidez/estrategias (sus propias specs).
- El menú de UI para los toggles (spec 0010), aunque este patrón debe exponer el `set_visible`.

## Criterios de aceptación
- Existe `Market/Overlays/` con al menos un overlay de ejemplo funcionando bajo el contrato.
- Activar/desactivar un overlay lo muestra/oculta sin afectar a otros ni al render de velas.
- El cálculo se limita a la ventana visible + contexto (verificable: no recorre las ~29888 velas
  por frame).
- Cada overlay limpia solo sus propios ítems del Canvas (tags namespaced).

## Casos límite
- Overlay activo con ventana vacía (sin datos en el rango): no dibuja nada, no falla.
- Cambio de timeframe / zoom extremo (downsample por píxel) coherente con los paneles.
- Replay: el overlay solo dibuja hasta `replay_idx`.

## Plan de verificación
- `perl -I. -c` de los nuevos módulos.
- Test manual: overlay de ejemplo on/off; medir que el cómputo es proporcional a velas visibles.
