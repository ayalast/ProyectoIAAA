# AGENTS.md — Proyecto Motor de Charting Financiero (Tk/Perl)

> **ESTAMOS EN FASE 2 (segundo bimestre).** Antes de escribir código, lee en este orden:
> 1. `docs/AI_CONTEXT.md` — resumen del proyecto y estado por fases.
> 2. `docs/ARCHITECTURE.md` — capas, estado actual vs planificado, problemas.
> 3. `docs/CONSTITUTION.md` — principios no negociables (separación cálculo/render, etc.).
> 4. `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` — requisitos OFICIALES de Fase 2.
> 5. La spec concreta en `specs/` y su task en `tasks/`.
>
> **Antes de Fase 2:** `0000f` introdujo tickmarks ponderados, pero la validación visual aún falla por el problema principal histórico: mezcla irregular de días/horas y distancias no uniformes. Cerrar ahora `tasks/0000g-time-axis-global-cadence-tradingview.md` con **Modo A obligatorio**: días + horas uniformes por ventana, evitando secuencias tipo `DAY | HOUR | DAY | DAY | HOUR`. No aceptar modo diario conservador como cierre final; solo puede ser fallback temporal/incompleto. Luego seguir con `0001`.
>
> **Flujo de trabajo (SDD):** toma una task de `tasks/` → implementa solo eso → verifica con
> `perl -I. -c` de los archivos tocados + `prove -l t` → no toques nada fuera de "Archivos relevantes"/"Qué no tocar" de la task.
>
> **Entregas Fase 2 (PDF oficial):** 1ª = **29/06**, 2ª = **13/07**. (En una clase se dijo
> "29 de julio"; el PDF manda: 29/06.) Vale 20/100.

## Resumen

Aplicación de visualización de datos OHLCV con indicador técnico ATR, construida con Perl/Tk para la asignatura IA y Aprendizaje Automático (EPN, 2026A, GR1SW). El profesor evaluó con una rúbrica (ver `Rubrica_Proyecto_GUI.xlsx`, hoja `AA-GR1`, columna `Grupo 2`). Puntaje base: 89/100 (Fase 1).

## Fase 2 — qué se añade (resumen)

Extender la plataforma con: nuevas temporalidades (1m,5m,15m,1h,2h,4h,D,W), **sistema Replay**
(sin mostrar velas futuras), **Overlays** avanzados SMC (BOS/CHoCH/FVG/Fibonacci), **módulo de
liquidez** unificado (swing points, EQH/EQL, sweep/grab/run con máquina de estados, pesado de
volumen multi-TF), **DIY Strategy Builder** (SuperTrend, HalfTrend, Range Filter, Supply,
Demand), **Perfil de Volumen** avanzado y **Anchored VWAP**. Carpeta nueva `Market/Overlays/`
(render) separada de `Market/Indicators/` (cálculo). Detalle por feature en `specs/`.

Regla de rendimiento clave (PDF §2): los indicadores de alta complejidad calculan **solo sobre
las velas visibles + una ventana de contexto indexada**, nunca todo el historial por frame.

## Stack

- **Lenguaje:** Perl 5 con Tk para GUI nativa
- **Entorno de ejecución:** WSL Fedora35 (EOL, mirrors en `archives.fedoraproject.org`)
- **Dependencias Perl:** `Time::Moment`, `Tk` (módulos CPAN ya instalados en Fedora35)
- **Datos:** `Data/2026_03.csv` — 29,888 velas 1-minuto (marzo 2026)
- **Control de versiones:** Git, remote `https://github.com/amsipan/ProyectoIAAA`

## Estructura

```
ProyectoIAAA/
  market.pl                  # Punto de entrada, UI Tk, controles
  Market/
    MarketData.pm            # Capa de datos: OHLCV, timeframes, slicing
    ChartEngine.pm           # Motor principal: render, zoom, crosshair, drag
    IndicatorManager.pm      # Gestor de indicadores
    Indicators/              # CÁLCULO (sin Tk)
      ATR.pm                 # Cálculo del ATR (14 periodos)
      SMC_Structures.pm      # (Fase 2, por crear) BOS/CHoCH/FVG/Fibonacci
      Liquidity.pm           # (Fase 2, por crear) swings, EQH/EQL, sweep/grab/run, FSM
      Strategy_Builder.pm    # (Fase 2, por crear) SuperTrend/HalfTrend/RangeFilter/Supply/Demand
    Overlays/                # (Fase 2, carpeta nueva) RENDER sobre Canvas
      SMC_Structures.pm
      Liquidity.pm
      Strategy_Builder.pm
    Panels/
      PricePanel.pm          # Render de velas japonesas + crosshair
      ATRPanel.pm            # Render línea ATR + crosshair sincronizado
      Scales.pm              # Conversión coordenadas ↔ valores
    Debug/
      TimeAxisSnapshot.pm    # Diagnóstico removible del eje temporal por rango/estado
      IndicatorSnapshot.pm   # Diagnóstico removible genérico de indicadores/overlays Fase 2
  Data/
    2026_03.csv              # Datos OHLCV 1-minuto, ~29888 filas
  docs/                      # Documentación SDD (LEER PRIMERO)
    AI_CONTEXT.md  CONSTITUTION.md  ARCHITECTURE.md  ROADMAP.md  TECH_DEBT.md
    SETUP_FEDORA35.md        # Parches MXNet (pendiente de verificar)
    adr/                     # Decisiones de arquitectura
    material_profesor/       # PDFs/docx originales del profesor + textos/imágenes extraídos
  specs/                     # QUÉ construir y POR QUÉ (Fase 2)
  tasks/                     # Unidades de trabajo accionables (NNNN-nombre.md)
  Rubrica_Proyecto_GUI.xlsx  # Rúbrica del profesor (NO BORRAR)
  PDF_BASE_EXTRACTED.txt     # Requisitos extraídos del PDF de Fase 1 (NO BORRAR)
  AGENTS.md                  # Este archivo
```

## Cómo ejecutar y validar

### Sistema de debug (CERRADO al implementor)

`Market/Debug/` es propiedad del arquitecto. El agente implementor **NO crea ni modifica** nada
bajo `Market/Debug/`. Si un test necesita un campo que el snapshot no expone, el implementor lo
**reporta**; el arquitecto extiende el módulo.

- Eje temporal: `Market/Debug/TimeAxisSnapshot.pm` (Fase 1, `0000g`–`0000j`).
- Indicadores/overlays Fase 2: `Market/Debug/IndicatorSnapshot.pm` (genérico). Contrato y patrón de
  test en `docs/PHASE2_DEBUG_CONTRACT.md`. Self-test: `t/08-indicator-debug-harness.t`.

Regla dura para Fase 2: **cada task de indicador/overlay debe traer un test `.t` que verifique su
salida vía el módulo de debug contra un esperado transcrito.** Sin ese test, la task NO está
terminada. La "validación visual" con WSLg es complementaria, nunca la única prueba.

### Debug del eje temporal contra TradingView

Antes de pedir capturas internas de la app, usar `Market/Debug/TimeAxisSnapshot.pm` vía `ChartEngine::debug_time_axis_snapshot(...)`. Permite pasar `timeframe`, `start_ts`, `end_ts` y `canvas_width` para obtener exactamente lo que la app dibujaría: `labels_text`, cadencia, índices, timestamps, coordenadas X, `bar_w`, gaps y resumen. El usuario solo debe aportar/confirmar el screenshot o rango de TradingView; la comparación de nuestra app debe hacerse por snapshot textual/estructurado.

Caso calibrado `0000g`:

```perl
$chart->debug_time_axis_snapshot(
    timeframe    => '15m',
    start_ts     => '2026-04-29T15:00:00-05:00',
    end_ts       => '2026-05-01T00:00:00-05:00',
    canvas_width => 1400,
);
```

Debe producir la secuencia TradingView esperada en `labels_text` con cadencia dominante `90`.

```bash
# Validación de sintaxis (sin GUI):
wsl -d Fedora35 -- bash -lc "cd '/mnt/c/Users/ASUS ROG/OneDrive - Escuela Politécnica Nacional/Académico/Universidad/Semestres/05_quinto_semestre/ia/proyecto_iaaa/Proyecto/ProyectoIAAA' && perl -I. -c Market/ChartEngine.pm && perl -I. -c Market/Panels/PricePanel.pm && perl -I. -c Market/Panels/ATRPanel.pm && perl -I. -c Market/MarketData.pm && perl -I. -c market.pl"

# Ejecutar (desde WSL Fedora35 con WSLg para GUI):
cd ~/Documents/ProyectoIA/ProyectoIAAA
perl -I. market.pl
```

La copia en Fedora35 está en `~/Documents/ProyectoIA/ProyectoIAAA` y debe mantenerse sync con GitHub (`git pull`).

## Cambios principales realizados (commits recientes)

### Zoom y escala temporal (commits 9952bd7 → 1941241)
- **Zoom multiplicativo** (`_wheel_zoom_delta`): factor = 1 + zoom_scale/10. Cerca pasos pequeños, lejos pasos grandes.
- **Ctrl+rueda** ancla la vela bajo el crosshair con shift exacto (`ctrl_zoom_x_shift`).
- **MAX_VISIBLE_BARS = 40000** — límite tipo TradingView (el CSV solo tiene ~29888 velas 1m).
- **Downsample por píxel**: cuando `bar_w < 2`, PricePanel y ATRPanel agrupan datos por píxel (high/low para velas, promedio para ATR).

### Escala de tiempo (Req. 5.6)
- Estado actual tras Task 0000: el crosshair está bien (`Thu 23 Apr '26`), pero `compute_intraday_labels` fue llevado a un stride equidistante que debe corregirse en `0000b`.
- Regla vigente para implementar: el eje inferior debe usar **fronteras reales de reloj/calendario** tipo TradingView, no fase arbitraria ni primera vela visible como fecha.
- Escalera objetivo 1m: `[1,5,15,30,60,90,180,360,720,1440,...]`; 5m: `[5,15,30,60,90,180,360,1440,...]`; 15m: `[15,30,60,90,180,360,1440,2880,4320,...]`.
- En 1m con intervalo 5, solo marca `:00, :05, :10...`; en 3h marca `00:00,03:00,06:00...` cuando existan velas/fronteras reales.
- Las velas mantienen separación horizontal uniforme por índice; los ticks no tienen que ser visualmente equidistantes si hay gaps.

### Timeframes corregidos (MarketData.pm)
- Agrupación 5m/15m por **fronteras reales de reloj** (`_bucket_timestamp`): porciones `:00-:04`, `:05-:09`, no cada N filas consecutivas.

### Crosshair
- X anclada al centro de vela (`_snap_crosshair_x`).
- Label de precio redondeado a `tick_size = 0.25`.
- Label de tiempo respeta `ctrl_zoom_x_shift`.
- Solo cursores nativos Tk/Windows; no se dibuja cursor duplicado en Canvas.

### ATR — Modo manual independiente
- `set_atr_scale_mode('auto'|'manual')` independiente de price scale.
- Eje ATR tiene drag vertical para zoom (igual que price axis).
- Panel ATR tiene paneo vertical por arrastre dentro del canvas (`_apply_atr_vertical_drag_from_start`).
- Teclas en foco ATR: `a`/`m` = auto/manual, `+/-` = zoom vertical, `Up/Down` = desplazar vertical.
- Al cambiar timeframe o reset, ATR vuelve a auto.
- Controles ATR en barra inferior derecha, controles Precio en izquierda, separados visualmente (frames con `relief => 'groove'`).

### UI (market.pl)
- Timeframes como `Radiobutton` con `active_tf` compartido.
- `Precio: Auto/Manual` en caja izquierda, `ATR: Auto/Manual` en caja derecha.
- Callbacks `scale_mode_callback` y `atr_scale_mode_callback` sincronizan estado de botones con motor.

## Decisiones de diseño (importante para futuros cambios)

1. **Separación horizontal uniforme**: Las velas se dibujan con índice (0, 1, 2...), no con coordenada de tiempo real. Esto implica que fines de semana y gaps nocturnos no crean huecos visuales, igual que TradingView por defecto.

2. **Eje Y de precio**: 5% padding sobre min/max de velas visibles.

3. **Offset y visible_bars**: El offset cuenta desde el final (vista más reciente). `compute_window` calcula `start/end` en índices globales.

4. **Coalescing de render**: `request_render()` usa `after(20ms)` para no saturar con renders múltiples.

5. **Tema claro**: Colores inyectados vía `%theme` en `market.pl` → `ChartEngine` → paneles y escalas. Todos los colores usan defaults con `//`.

6. **ATR**: Siempre 14 periodos. Se recalcula completo al cambiar timeframe.

7. **Pulido visual pendiente antes de Fase 2**: `tasks/0000` ya aceptó la etiqueta inferior del crosshair (`Thu 23 Apr '26`). Ejecutar ahora `tasks/0000b-time-axis-tradingview-scale.md`: eje temporal inferior por fronteras reales de reloj/calendario estilo TradingView; no volver al criterio de grid equidistante.

## Archivos que NO se deben borrar

- `Rubrica_Proyecto_GUI.xlsx` — requisitos oficiales del profesor
- `PDF_BASE_EXTRACTED.txt` — especificaciones extraídas del PDF del profesor
- `Data/2026_03.csv` — única fuente de datos

## Notas para el futuro

- Fedora35 está EOL; los mirrors son lentos. Si hay que instalar paquetes nuevos, usar `dnf --releasever=35` con repos `archives.fedoraproject.org`.
- WSLg funciona para GUI; la variable `DISPLAY` se configura automáticamente.
- `git diff --check` puede mostrar warning CRLF en `market.pl` — es inofensivo (Windows ↔ Linux).
- Suite de tests en `t/` (Test::More, sin GUI): `prove -l t`. Fase 1 cubierta por `t/00`–`t/07`
  (142 tests). El harness de debug de indicadores es `t/08`. La validación de Fase 2 es por test +
  snapshot de debug (ver `docs/PHASE2_DEBUG_CONTRACT.md`); la comparación visual con WSLg es
  complementaria.
- La copia en Fedora35 (`~/Documents/ProyectoIA/ProyectoIAAA`) tiene un stash con el cambio local viejo (`MAX_VISIBLE_BARS = 4000`).