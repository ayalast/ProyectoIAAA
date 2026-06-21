# Constitución del proyecto

Principios no negociables. Cualquier cambio que los viole requiere aprobación humana.
Derivados del PDF base de Fase 1, del PDF de especificación de Fase 2 y de las clases.

## Misión

Construir una plataforma de charting financiero tipo TradingView en Perl/Tk que sirva como
base de visualización y extracción de características para modelos de ML (HMM/Viterbi
tensorial) capaces de predecir cambios de estructura de mercado.

## Principios técnicos

1. **Separación estricta cálculo ↔ render.** El cálculo de un indicador NUNCA contiene
   código de Tk ni coordenadas de pantalla. En Fase 2 esto se hace explícito con la
   división `Market/Indicators/` (cálculo) vs `Market/Overlays/` (render).
2. **Sin variables globales.** El estado vive en la instancia (`$self`).
3. **Indicadores desacoplados del chart.** Un indicador no conoce al ChartEngine ni a los
   paneles; se comunica por su contrato (`update_last`, `get_values`, `reset`).
4. **POO y responsabilidad única.** Cada package hace una cosa. Nada de "un archivo de 5000
   líneas" inmantenible.
5. **Solo las librerías definidas en la guía/codex.** No introducir librerías nuevas sin
   aprobación. Las permitidas: `Tk`, `Time::Moment`, `AI::MXNet`, `Chart::Plotly`.
6. **Respetar los contratos (inputs/outputs) de cada método definido por el profesor.** No
   inventar métodos ni clases fuera de los especificados; no cambiar el orden de etiquetas
   ni de ejes de los tensores (la mayoría de errores de ML son de shape).
7. **Escala horizontal (X) compartida entre todos los paneles; escala vertical (Y) por
   panel.** La gestión de escalas está centralizada en `Scales.pm`; ningún panel calcula su
   propio mapeo datos↔píxeles por su cuenta.
8. **Rendimiento por overlays (Fase 2).** Los indicadores de alta complejidad calculan solo
   sobre las velas visibles + una ventana de contexto indexada suficiente para validar
   estructuras pasadas. No recalcular todo el historial en cada frame.
9. **Render incremental, objetivo O(1) por vela nueva** donde sea posible (como ATR).

## Principios de UX

- Comportamiento equivalente a TradingView: si coincide con TradingView, está bien; si no
  coincide, hay que corregir. Validar primero en 1m antes de expandir a otras temporalidades.
- Separación horizontal uniforme entre velas (índice, no tiempo continuo): gaps de fin de
  semana/noche no crean huecos visuales.
- Crosshair sincronizado entre todos los paneles; etiquetas de tiempo en negrilla al cambiar
  de fecha.
- Overlays activables/desactivables individualmente desde el menú de la interfaz.
- En modo Replay: **jamás** mostrar velas futuras a la fecha/hora del puntero.

## Principios de seguridad

- Proyecto académico de escritorio sin red ni secretos en runtime. No introducir llamadas de
  red ni credenciales.
- No imprimir tokens/claves si en el futuro se añaden (referenciar por nombre).

## Principios de testing

- Validación principal: visual contra TradingView/LuxAlgo/ICT y contra la rúbrica del profesor.
- Verificación mínima obligatoria antes de declarar listo un cambio: `perl -I. -c` sobre los
  módulos tocados y sobre `market.pl` (ver AGENTS.md), más la suite de regresión `prove -l t`.
- Para los algoritmos de ML (Viterbi tensorial, Pearson): validar contra los valores de
  referencia del material del profesor (p. ej. la salida esperada del ejercicio de Viterbi).
- `t/` está reservada para tests automatizados futuros.

## Reglas de arquitectura

- Arquitectura en 4 capas: Datos → Indicadores → Renderizado → Aplicación.
- `ChartEngine` es el único punto de ensamblaje/orquestación; conoce a sus hijos (paneles,
  escalas, overlays) y coordina los eventos de usuario.
- Orden de desarrollo recomendado por el profesor: datos → main/ventana → carga de datos →
  ChartEngine → renderizado.
- Todo el código de la librería vive bajo `Market/`.

## Límites para agentes de IA

Un agente NO puede, sin confirmación humana:
- Borrar o sobrescribir `Data/2026_03.csv`, `Rubrica_Proyecto_GUI.xlsx`,
  `PDF_BASE_EXTRACTED.txt` ni nada en `docs/material_profesor/`.
- Introducir librerías/dependencias nuevas fuera de las permitidas.
- Cambiar la arquitectura de 4 capas o romper la separación cálculo/render.
- Hacer `git push`, `commit`, merges o force-push (solo cuando Bryan lo pida explícitamente).
- Ejecutar los pasos de parcheo de MXNet en Fedora35 (ver `docs/SETUP_FEDORA35.md`): primero
  verificar estado, nunca aplicar a ciegas.
- Refactorizar `ChartEngine.pm` masivamente "de paso"; un refactor de ese tamaño es su propia
  spec.
