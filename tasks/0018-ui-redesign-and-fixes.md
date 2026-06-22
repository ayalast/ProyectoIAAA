# Task 0018: Rediseño de UI + corrección de fallos visuales (Fase 2)

## Origen
Primera validación visual real de la app con el dataset completo (usuario, 2026-06-22).
La lógica (658 tests) estaba bien, pero la UI tenía fallos que solo se ven al abrir la GUI.
Este documento REGISTRA todos los fallos observados para no repetirlos, y define el rediseño.

## Fallos observados (NO volver a introducir ninguno)

### F1 — Toggles de capas no restauran las líneas al reactivar
- **Síntoma:** desactivar una capa la oculta; volver a activarla NO la vuelve a mostrar.
- **Causa raíz:** en `market.pl` los `Checkbutton`/menú se cablearon como `-command => $cb`,
  pero Tk **no pasa el valor de `-variable` como argumento** al `-command`. La factoría
  `make_overlay_toggle`/`make_liq_element_toggle` espera `($on)` explícito (así lo prueba t/17),
  por lo que recibía `undef` → siempre interpretaba "off". Apagar coincidía por casualidad.
- **Regla:** todo `-command` de Checkbutton debe pasar EXPLÍCITO el valor de su `-variable`:
  `-command => sub { $cb->($var ? 1 : 0) }`. Nunca `-command => $cb` a secas.

### F2 — Barra de controles saturada; Optionmenu de TF y botones de Replay recortados
- **Síntoma:** no se ven los botones de cambiar temporalidad (solo un "1m" comido abajo-izq);
  Replay abajo-derecha aparece como "ic" (=`Inicio` recortado) y no responde; aparece una
  ventana "menú" de Linux que no abre al click.
- **Causa raíz:** TODOS los controles en UNA fila horizontal (`pack -side left/right`). Con ~28
  widgets (la caja "Capas" sola tenía SMC+Liquidez+7 elementos+3 placeholders = 12), la fila
  desbordaba el ancho de la ventana y recortaba lo de los extremos. El Optionmenu además quedaba
  sin ancho suficiente.
- **Regla:** no apilar decenas de widgets en una sola fila. Usar **menubar** (menús desplegables)
  para el grueso de opciones + una barra inferior compacta con lo esencial. Anchos fijos en los
  menús/labels para que no se "coman" el texto.

### F3 — Arranque innecesariamente pesado
- **Síntoma:** la app tarda en cargar las velas (segundos en blanco).
- **Causa raíz:** (a) `market.pl` registraba un indicador `SMC` EXTRA en `indicator_manager`
  (línea 26) y lo alimentaba sobre las 29888 velas en el bucle de arranque, ADEMÁS del
  `smc_indicator` propio de ChartEngine — doble cómputo inútil. (b) Los indicadores SMC/Liquidity
  de los overlays se alimentaban siempre en el primer render aunque las capas estén apagadas.
- **Regla:** el arranque solo debe calcular lo imprescindible para pintar como Fase 1 (velas + ATR,
  ya precomputado). SMC/Liquidity se alimentan **bajo demanda**: solo cuando su overlay está
  visible. Así abrir es instantáneo y el costo se paga al activar la capa (una vez, cacheado).

### F4 — Demasiadas líneas al abrir (saturación visual)
- **Síntoma:** el gráfico abre con decenas de líneas BSL/SSL encima, saturado.
- **Causa raíz:** los overlays nacen `visible => 1`; al abrir se dibuja todo.
- **Regla:** los overlays empiezan **desactivados por defecto** (el usuario los enciende cuando
  quiere). El estado inicial del menú/checkbutton y el del overlay deben coincidir (ambos off).

### F5 — App en blanco sin posibilidad de recuperación
- **Síntoma:** en algún estado el gráfico quedó en blanco y, como los controles estaban recortados
  (F2), no había forma de pulsar Reset/Exit.
- **Regla:** los controles críticos (Reset Vista, Exit Replay, Temporalidad) deben estar SIEMPRE
  accesibles (menubar + barra compacta), nunca dependientes de que el render funcione.

## Rediseño de UI (libertad de diseño concedida por el usuario)

### Estructura
1. **Menubar superior** (`$mw->Menu -type menubar`) con todo el control, sin saturar:
   - **Temporalidad:** radiobuttons 1m/5m/15m/1h/2h/4h/D/W (→ `set_timeframe`).
   - **Capas:** checkbuttons SMC, Liquidez; submenú de elementos de liquidez
     (BSL/SSL/EQH/EQL/SWEEP/GRAB/RUN); placeholders Strategy/Volume/VWAP deshabilitados;
     "Niveles HTF sobre LTF". TODOS empiezan OFF (overlays) salvo los elementos de liquidez
     (que son sub-filtros del overlay Liquidez, irrelevantes mientras Liquidez está off).
   - **Replay:** Inicio, Play, Pause, Step adelante, Step atrás, Fast Forward, Salir.
   - **Escala:** Precio Auto/Manual, ATR Auto/Manual, Reset Vista.
2. **Barra inferior compacta** (esencial, siempre visible, sin recortes):
   - Indicador de TF actual (Optionmenu compacto con ancho fijo).
   - Precio Auto/Manual.
   - Botones rápidos de Replay (los 7, texto corto ASCII).
   - Reset Vista.
   - Etiqueta de estado de Replay (ON/OFF + índice).

### Alimentación bajo demanda (resuelve F3/F4)
`ChartEngine::sync_overlay_indicators` solo alimenta un indicador si su overlay existe y está
visible. Si no hay overlay registrado (tests t/16), alimenta igual (preserva el test). En
producción, con overlays OFF al inicio, no se alimenta nada pesado → arranque instantáneo.

## Actualización 0018b (segunda validación visual)

Tras el primer rediseño, la validación visual reveló dos fallos NUEVOS por widgets que abren
ventanas X separadas bajo WSLg:

### F6 — Menubar nativo abre popups erráticos
- **Síntoma:** los menús (Temporalidad/Capas/Replay/Escala) abrían una ventana Linux aparte que
  aparecía en posiciones distintas, tardaba, se trababa o no cargaba.
- **Causa:** `$mw->Menu(-type=>menubar)` + `cascade` usan ventanas toplevel del WM; bajo WSLg el
  manejo de popups es inestable.
- **Fix:** ELIMINADO el menubar. Todos los controles van INLINE en la ventana, en dos filas,
  con Radiobutton/Checkbutton/Button (no crean ventanas).

### F7 — Optionmenu de TF recortado y con popup
- **Síntoma:** el selector "TF: 1m 1m" con letras entrecortadas y sin responder bien.
- **Causa:** `Optionmenu` también despliega un popup (mismo problema que el menubar).
- **Fix:** reemplazado por 8 Radiobutton con `-indicatoron=>0` (estilo botón), sin popup.

Verificación: los 18 callbacks de la barra (8 TF, SMC/Liq ON-OFF-ON, elemento liquidez, HTF, y los
7 de Replay) probados por script contra el ReplayController real → 18/18 ok. 672/672 PASS.

## Qué NO romper
- Las factorías de `Market/UI/Callbacks.pm` NO cambian su firma (`($on)` explícito) → t/17 verde.
- `sync_overlay_indicators` debe seguir alimentando en t/16 (donde no hay overlay registrado).
- La truncación de Replay (t/15/t/16), la idempotencia (t/14), el rendimiento (0016/0017).
- Fase 1: zoom/drag/crosshair/escalas.

## Verificación
- `perl -I. -c market.pl` y `prove -l t` completos en verde (los 661 + lo que se añada).
- Arranque real: la app pinta velas de inmediato (como Fase 1); activar una capa la dibuja;
  desactivar y reactivar la restaura (F1); los 7 controles de Replay responden (F2); Replay no
  muestra futuro; Reset siempre accesible (F5).
