# Task 0000h: Densificación adaptativa y umbral correcto de calendario en eje temporal

## Spec relacionada

`specs/0000g-time-axis-global-cadence-tradingview.md`

Esta task continúa `0000g`: ya existe planificación global, debug snapshot y varios rangos calibrados, pero la validación visual contra TradingView muestra dos fallos restantes en ciertos zooms.

> Estado posterior: el implementor reportó `0000h` implementada y `123/123` tests pasando. La validación visual posterior abrió `tasks/0000i-time-axis-calendar-density-overscan-render.md` para dos refinamientos adicionales: calendario mensual más denso y overscan de velas parcialmente visibles durante paneo suave.

## Contexto visual confirmado por el usuario

Activo/fuente de calibración:

- TradingView/Supercharts: `NQ1!` — NASDAQ 100 E-mini Futures, CME.
- Timeframe: `15m`.
- Zona: `UTC-5` / Bogotá-Quito.
- Dataset local: `Data/2026_03.csv`, contiene abril 2026 aunque el nombre dice marzo.
- Las velas se distribuyen por índice lógico; gaps de sesión/weekend se comprimen como en TradingView.
- No inventar velas/labels dentro de gaps de sesión si no hay punto real o whitespace explícito.

### Caso A — falta densificación intradía tipo TradingView

En una ventana cercana a `2026-04-29 -> 2026-05-01`, TradingView muestra un label intermedio `14:30` entre `12:00` y `18:00`:

```text
29 | 03:00 | 06:00 | 09:00 | 12:00 | 14:30 | 18:00 | 21:00 | 30 | 03:00 | 06:00 | 09:00 | 12:00 | 14:30 | 18:00 | 21:00 | May
```

La app actualmente se queda con algo equivalente a:

```text
29 | 03:00 | 06:00 | 09:00 | 12:00 | 18:00 | 21:00 | 30 | 03:00 | 06:00 | 09:00 | 12:00 | 18:00 | 21:00 | May
```

Problema: el plan mantiene cadencia dominante, pero deja huecos visuales demasiado grandes. TradingView rompe controladamente la cadencia dominante con un candidato real (`14:30`) para rellenar espacio y mejorar la lectura.

### Caso B — la app entra demasiado pronto en modo solo días/calendario

En una vista más alejada alrededor de `2026-04-23 -> 2026-05-01`, TradingView todavía muestra horas entre días, por ejemplo:

```text
23 | 12:00 | 24 | 09:00 | 26 | 27 | 12:00 | 28 | 12:00 | 29 | 12:00 | 30 | 12:00 | May
```

La app ya cae a una vista de solo días:

```text
23 | 24 | 26 | 28 | 29 | 30 | May
```

Problema: el modo calendario/diario está entrando antes de lo que TradingView hace. Antes de degradar a solo días, se debe intentar un plan intradía sparse con horas reales suficientes.

## Objetivo

Ajustar el selector de planes del eje temporal para que:

1. pueda **densificar adaptativamente** huecos grandes con candidatos reales de menor jerarquía cuando TradingView lo hace;
2. no entre demasiado pronto en modo calendario/solo días;
3. preserve todos los casos ya calibrados de `0000g`;
4. mantenga el debug snapshot como fuente principal de comparación antes de pedir screenshots.

## Archivos permitidos

- `Market/ChartEngine.pm`
- `Market/Debug/TimeAxisSnapshot.pm` solo si hace falta exponer métricas de diagnóstico (`gap_ratio`, `filled_gaps`, `calendar_reason`, etc.)
- `t/07-time-axis-global-cadence.t`
- Esta task/spec si hay que aclarar contrato

## No tocar

- `Market/MarketData.pm` salvo autorización humana explícita.
- `Data/2026_03.csv`.
- `Market/Indicators/*`.
- `Market/Overlays/*`.
- Replay/Fase 2.
- `market.pl` salvo necesidad estricta.
- No hacer refactor amplio de `ChartEngine.pm`.
- No hacer commit/push.

## Requisitos de implementación

### R1. Densificación adaptativa de huecos grandes

Después de construir un plan global intradía válido, evaluar los huecos visuales entre labels consecutivos.

Si un hueco es demasiado grande respecto a la separación típica del plan, intentar insertar candidatos reales existentes entre ambos labels.

Regla conceptual:

```text
plan base -> medir gaps -> detectar gaps grandes -> insertar candidato real que reduzca max_gap sin colisiones -> revalidar
```

Candidatos válidos:

- deben venir de `@candidates` reales generados desde velas/timestamps existentes;
- no deben caer dentro de gaps de sesión inexistentes;
- no deben crear ticks fraccionales ni desconectados del crosshair;
- deben respetar separación mínima de labels;
- deben mejorar el score del plan (`max_gap`, `gap_ratio`, distribución por día).

El caso `14:30` debe salir de esta regla general, no de hardcodear la fecha/hora. En particular, para un hueco `12:00 -> 18:00`, un candidato real como `14:30` puede ser preferible si reduce el hueco sin colisionar con labels vecinos.

Sugerencia técnica:

- Crear helper pequeño, por ejemplo:

```perl
sub _densify_sparse_gaps_in_time_axis_plan { ... }
```

- Aplicarlo después de `_build_time_axis_plan(...)` y/o después de `_adjust_sparse_time_axis_plan(...)`.
- Score sugerido para candidatos:
  - reducción de `max_gap_px`;
  - proximidad al centro visual del hueco;
  - peso temporal (`HOUR3`, `HOUR1`, `MIN90`, etc.);
  - texto legible;
  - no rompe consistencia día-a-día.

### R2. No degradar demasiado pronto a calendario/solo días

El modo calendario mensual/días confirmado para zoom máximo sigue siendo válido, pero no debe activarse mientras un plan intradía sparse todavía sea legible y comparable a TradingView.

No usar únicamente `bar_w` + cantidad de días como condición final.

Antes de retornar calendario/solo días:

1. intentar planes intradía sparse;
2. intentar densificación adaptativa;
3. evaluar si el plan resultante tiene suficientes horas reales y gaps aceptables;
4. solo si falla, degradar a calendario.

Sugerencia:

- El calendario debe ser el último modo, no un early return demasiado agresivo.
- Si se mantiene un early return, debe estar protegido por una condición más fuerte que demuestre que TradingView ya estaría en modo calendario, por ejemplo:
  - ventana muy larga;
  - `bar_w` extremadamente pequeño;
  - ningún plan intradía puede cumplir separación mínima;
  - la cantidad de labels horarios posibles sería insignificante frente a días visibles.

### R3. Preservar casos calibrados existentes

No romper los casos ya confirmados en `t/07-time-axis-global-cadence.t`:

#### 90m

```text
15:00 | 18:00 | 19:30 | 21:00 | 22:30 | 30 | 01:30 | 03:00 | 04:30 | 06:00 | 07:30 | 09:00 | 10:30 | 12:00 | 13:30 | 15:00 | 18:00 | 19:30 | 21:00 | 22:30 | May
```

#### 6h

```text
27 | 06:00 | 12:00 | 18:00 | 28 | 06:00 | 12:00 | 18:00 | 29 | 06:00 | 12:00 | 18:00 | 30 | 06:00 | 12:00 | 18:00
```

#### 6h con gaps comprimidos

```text
24 | 06:00 | 12:00 | 26 | 27 | 06:00 | 12:00 | 18:00 | 28 | 06:00 | 12:00 | 18:00 | 29 | 06:00 | 12:00 | 18:00 | 30 | 06:00 | 12:00 | 18:00 | May
```

#### Sparse 12h/días

```text
03:00 | 12:00 | 21 | 12:00 | 22 | 12:00 | 23 | 12:00 | 24 | 26 | 03:00 | 12:00 | 28 | 12:00 | 29 | 12:00 | 30 | 12:00 | May
```

#### Zoom máximo calendario

```text
Apr | 3 | 7 | 9 | 12 | 14 | 16 | 19 | 21 | 23 | 26 | 28 | May
```

### R4. Debug obligatorio antes de validar visualmente

Usar `debug_time_axis_snapshot(...)` para los rangos nuevos antes de pedir screenshot.

El snapshot debe permitir inspeccionar:

- `labels_text`;
- `cadence_min`;
- `visible_bars`;
- `bar_w`;
- `canvas_width`;
- índices/timestamps de labels;
- gaps grandes;
- candidatos ocultos entre huecos grandes.

Si hace falta, extender `Market/Debug/TimeAxisSnapshot.pm` con campos opcionales:

```text
gap_stats
filled_gaps
calendar_reason
candidate_scores
```

Mantener este debug separado/removible; no mezclarlo con render normal.

## Tests requeridos

Actualizar `t/07-time-axis-global-cadence.t`.

### T1. Densificación `14:30` en rango 29 -> May

Crear fixture/snapshot para el rango visual equivalente a la captura de TradingView:

```text
2026-04-29 -> 2026-05-01, 15m, canvas comparable a screenshot
```

Esperado aproximado:

```text
29 | 03:00 | 06:00 | 09:00 | 12:00 | 14:30 | 18:00 | 21:00 | 30 | 03:00 | 06:00 | 09:00 | 12:00 | 14:30 | 18:00 | 21:00 | May
```

Si el canvas exacto produce una pequeña variación, documentar en el test el `canvas_width`, `bar_w`, `visible_bars` y usar el snapshot como fuente de verdad. No hardcodear rangos invisibles.

### T2. No calendario prematuro en rango 23 -> May

Crear fixture/snapshot para el rango visual equivalente a la captura alejada:

```text
2026-04-23 -> 2026-05-01, 15m
```

Debe contener días y horas, no solo días.

Esperado orientativo según TradingView:

```text
23 | 12:00 | 24 | 09:00 | 26 | 27 | 12:00 | 28 | 12:00 | 29 | 12:00 | 30 | 12:00 | May
```

El criterio mínimo de aceptación:

- `labels_text` contiene al menos varias horas (`HH:MM`);
- no retorna solo `23 | 24 | 26 | 28 | 29 | 30 | May`;
- mantiene gaps razonables;
- no inventa labels en gaps de sesión.

### T3. Regresiones existentes intactas

Todos los tests previos de `t/07` deben seguir pasando.

### T4. Regresión completa

Ejecutar obligatoriamente:

```bash
wsl -d Fedora35 -- bash -lc "cd /mnt/c/m/ia/proyecto_iaaa/Proyecto/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c Market/Debug/TimeAxisSnapshot.pm && perl -I. -c market.pl && prove -l t"
```

Si se trabaja en la copia Fedora directa:

```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/Scales.pm && perl -I. -c Market/Debug/TimeAxisSnapshot.pm && perl -I. -c market.pl && prove -l t"
```

## Criterios de aceptación

- El rango 29 -> May incluye `14:30` o una densificación equivalente confirmada por snapshot y coherente con TradingView.
- El rango 23 -> May conserva horas entre días y no cae prematuramente a solo días.
- El zoom máximo confirmado sigue usando calendario:

```text
Apr | 3 | 7 | 9 | 12 | 14 | 16 | 19 | 21 | 23 | 26 | 28 | May
```

- No se introducen ticks sintéticos/fraccionales.
- Crosshair sigue alineado con labels reales.
- Grid vertical se dibuja solo para labels visibles.
- `prove -l t` pasa completo.
- No se modifican `MarketData.pm`, datos ni features de Fase 2.

## Prompt mínimo para el implementor

Implementa `tasks/0000h-time-axis-adaptive-density-calendar-threshold.md`.

Reglas:

- Antes de tocar código, lee `AGENTS.md`, `docs/AI_CONTEXT.md`, `docs/ARCHITECTURE.md`, `specs/0000g-time-axis-global-cadence-tradingview.md`, `tasks/0000g-time-axis-global-cadence-tradingview.md` y esta task.
- No toques `MarketData.pm` ni Fase 2.
- Trabaja solo en `Market/ChartEngine.pm`, `Market/Debug/TimeAxisSnapshot.pm` si hace falta, y `t/07-time-axis-global-cadence.t`.
- Usa snapshots para comparar rangos, no screenshots como primera fuente.
- Agrega tests para los dos nuevos casos visuales.
- Preserva todos los tests existentes.
- Ejecuta el comando obligatorio completo antes de declarar listo.
