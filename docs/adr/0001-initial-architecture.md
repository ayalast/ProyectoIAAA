# ADR 0001: Arquitectura inicial documentada (4 capas Perl/Tk + cálculo/render separados)

## Estado
Aceptado.

## Contexto
La Fase 1 (motor de charting) ya está construida y evaluada (89/100). Al iniciar la Fase 2
(SMC, liquidez, Replay, ML) se hace bootstrap SDD para que el desarrollo asistido por IA no
pierda contexto. Este ADR fija la arquitectura asumida como punto de partida, derivada del PDF
base de Fase 1, el PDF de especificación de Fase 2 y las clases.

## Decisión
- **Arquitectura en 4 capas:** Datos → Indicadores → Renderizado → Aplicación.
- **Separación estricta cálculo ↔ render.** En Fase 2 se materializa con dos carpetas:
  `Market/Indicators/` (solo cálculo, sin Tk) y `Market/Overlays/` (solo render sobre Canvas).
- **`ChartEngine` es el único orquestador**, conoce paneles/escalas/overlays y coordina eventos.
- **Escalas centralizadas en `Scales.pm`:** X compartida entre paneles, Y por panel.
- **Indicadores desacoplados** vía contrato (`update_last`/`get_values`/`reset`).
- **Sin variables globales; solo las librerías de la guía** (`Tk`, `Time::Moment`, `AI::MXNet`,
  `Chart::Plotly`).
- **Rendimiento Fase 2 por overlays:** calcular solo sobre velas visibles + ventana de contexto.

## Consecuencias
- **Positivas:** modularidad, testeabilidad del cálculo puro, alineación con la rúbrica del
  profesor, escalabilidad a nuevos indicadores sin tocar el render.
- **Negativas:** más archivos y más "plomería" (registros/contratos); `ChartEngine` corre
  riesgo de crecer demasiado (ver TECH_DEBT) si no se aíslan Replay y el registro de overlays.

## Alternativas consideradas
- **Monolito en ChartEngine** (todo el render y cálculo juntos): rechazado, viola separación
  cálculo/render y la regla de "no archivos de 5000 líneas".
- **Mezclar cálculo dentro de los overlays**: rechazado, el PDF separa explícitamente
  Indicators (cálculo) de Overlays (render).

## Preguntas abiertas
- Ubicación definitiva de Replay / Volume Profile / Anchored VWAP como packages (ver ROADMAP).
- Si el registro de overlays debe ser una clase nueva (`OverlayManager`) o vivir en ChartEngine.
