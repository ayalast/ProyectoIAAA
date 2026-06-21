# Deuda técnica

Clasificada por severidad. No se resuelve aquí; solo se documenta. Última act.: 2026-06-20.

## Crítico

### La app se cuelga al abrir con el dataset real (29888 velas) — task 0016 abierta
- **Descripción:** el primer `render()` alimenta Liquidity sobre las 29888 velas;
  `_sum_volume_for_tf` (task 0013) recorre el array completo del TF parseando `Time::Moment` por
  vela, por cada evento resuelto y cada TF → ~16 ms/vela → ~6-7 min de cuelgue síncrono. La ventana
  abre pero el gráfico queda en blanco. Secundario: `_active_levels` no poda los `Resolved` (O(n²)).
- **Perfilado:** `_sum_volume_for_tf` = 96% del tiempo (1086 llamadas en 2000 velas, 37s).
- **Impacto:** BLOQUEA la ejecución de la 1ª entrega. Los 654 tests pasan porque usan 10-35 velas.
- **Evidencia:** medición del arquitecto (perf_probe/prof_vol); log de la app para en
  "Render geometry ... bars=60".
- **Recomendación:** task `0016-liquidity-performance-fix.md` (cache de epochs + prefix-sum +
  búsqueda binaria; podar niveles Resolved). Resolver ANTES de cualquier validación visual.
- **¿Bloquea?:** sí, totalmente. Máxima prioridad.

### [RESUELTO 2026-06-21] Indicadores se alimentaban hasta el fin del dataset en Replay — task 0015
- **Era:** `ChartEngine::render` alimentaba SMC/Liquidity hasta `size()-1` aunque Replay estuviera
  activo, filtrando solo el dibujo → fuga de futuro (FVG mitigado por velas futuras, pivotes
  confirmados con futuro).
- **Fix:** `sync_overlay_indicators` alimenta hasta `replay_idx` (activo) o `size()-1` (inactivo);
  `_feed_indicator_to` hace avance incremental o `reset()`+realimentación en retroceso. Test `t/16`
  verifica `mitig==0` parado en la formación del FVG, compara contra referencia 0..I, y documenta que
  el cableado viejo daba `mitig=0.3` (fuga). 597/597 PASS.
- **¿Bloquea?:** ya no. Replay listo para cablear a UI (0004).

(Sin otras bloqueantes. La Fase 1 funciona y está evaluada.)

### [RESUELTO 2026-06-21] Pesado de volumen multi-TF — corregido en task 0013
- **Era:** `_sum_volume_for_tf` sumaba por índice del array activo; índices no alineados entre TFs.
- **Fix:** suma por rango temporal (`Time::Moment->epoch`), borde superior `ts < ts_end_next` según
  duración del TF activo. Test Case 26 de `t/10-liquidity.t` verifica valores exactos por timestamp
  (296/410/345), independencia del TF macro y falla con el código viejo. 434/434 PASS.
- **Nota de diseño (menor, a confirmar con profesor):** cuando el rango del evento NO empieza/termina
  en frontera de bucket, `v1m`/`v5m`/`v15m` cuentan conjuntos de velas ligeramente distintos (efecto
  de borde: el bucket parcial inicial se excluye, el final se incluye). Es coherente y aceptable como
  heurística de peso; si el profesor exige igualdad estricta entre TFs, alinear el rango a fronteras
  de bucket. No bloquea.

## Alto

### Cadencia global no uniforme del eje temporal — mitigada, pendiente de validación visual final
- **Descripción:** `0000g` introdujo planificación global por cadencia y corrigió el fallo donde el thinning por peso degradaba 90m a 3h. El caso calibrado NQ1!/CME 15m UTC-5 `2026-04-29T15:00 -> 2026-05-01T00:00` ahora se verifica con `Market/Debug/TimeAxisSnapshot.pm` y `t/07-time-axis-global-cadence.t`.
- **Impacto:** Replay y overlays de Fase 2 dependen de una escala X confiable; el riesgo principal queda reducido, pero conviene confirmar visualmente contra TradingView con screenshot del usuario.
- **Evidencia:** Test `t/07-time-axis-global-cadence.t`; snapshot por rango explícito con `labels_text` esperado y `cadence_min = 90`; validación completa `prove -l t` en PASS.
- **Recomendación:** Antes de abrir `0001`, hacer una última comparación manual de TradingView usando el snapshot debug; no pedir captura interna de la app salvo anomalía.
- **¿Bloquea escalabilidad?:** no si la validación visual final confirma el snapshot; sí volvería a bloquear si TradingView muestra otra secuencia para el mismo rango/ancho.

### ChartEngine.pm como god object en potencia
- **Descripción:** `ChartEngine.pm` (~70 KB, ~65 subs) concentra orquestación, render de 3
  ejes, eventos de mouse/teclado, zoom, drag y cursores. Fase 2 añade Replay + N overlays
  multi-temporal activables.
- **Impacto:** crecer todo ahí dentro hará el archivo inmantenible y violará "responsabilidad
  única" (principio del profesor).
- **Evidencia:** inventario de subs en `Market/ChartEngine.pm`.
- **Recomendación:** introducir un registro de overlays (análogo a IndicatorManager pero de
  render) y un `ReplayController` separado; ChartEngine solo coordina.
- **¿Bloquea escalabilidad?:** sí, para Fase 2 si no se controla.

### Falta de carpeta/patrón de Overlays
- **Descripción:** el PDF exige `Market/Overlays/` (render) separado de `Market/Indicators/`
  (cálculo); hoy no existe.
- **Impacto:** sin un patrón uniforme, cada overlay se implementará distinto.
- **Evidencia:** `Market/` solo tiene `Indicators/` y `Panels/`.
- **Recomendación:** definir contrato de overlay (`compute_visible`, `draw`, `set_visible`)
  antes de implementar el primero. Ver `specs/0003-overlays-base.md`.
- **¿Bloquea escalabilidad?:** sí.

## Medio

### Detección SMC (FVG/CHoCH) — primera versión funcional, simplificaciones conocidas
- **Descripción:** `Market/Indicators/SMC_Structures.pm` (tasks 0005–0007) pasa 317 tests, pero
  tiene tres simplificaciones deliberadas a vigilar:
  1. **Mitigación FVG unidireccional:** `FVG_up` solo recorta `hi` (penetración desde arriba);
     no modela entrada por debajo. TradingView mitiga bidireccional.
  2. **[RESUELTO 0014]** `get_pivots()` mutaba estado al confirmar `_current`/`_trailing`. Corregido:
     `_label_for` puro + `get_pivots`/`_get_effective_majors` materializan la cola provisional con
     copias locales, sin tocar `$self`. Idempotencia verificada (consultar getters tras cada vela ==
     no consultar). 488/488 PASS; el test de idempotencia falla con el código viejo.
   3. **`CHoCH_false` no verifica cierre de cuerpo** (compara solo `close` vs nivel interno, no
     `close` vs `open`), a diferencia de BOS.
- **Impacto:** punto 2 RESUELTO (desbloquea 0008). Puntos 1 y 3: precisión visual vs LuxAlgo, a 2ª entrega.
- **Evidencia:** `Market/Indicators/SMC_Structures.pm`, `t/09-smc-structures.t` (bloque TASK 0014).
- **Recomendación:** mitigación FVG bidireccional y body-close en CHoCH_false en 2ª entrega.
- **¿Bloquea escalabilidad?:** ya no; punto 2 resuelto en 0014, puntos 1/3 no bloquean.

### Tests automatizados — establecidos (entrada previa obsoleta)
- **Descripción:** Ya existe suite `t/00`–`t/13` con Test::More (317 tests al cierre de 0007),
  cubriendo eje temporal, ATR, replay, overlays base y SMC. La nota previa "t/ vacía" quedó
  obsoleta.
- **Recomendación:** mantener la regla de `prove -l t` completo por task; añadir tests de Viterbi
  (salida de referencia del docx) y Pearson (ejemplo Iris) en Fase 3.
- **¿Bloquea escalabilidad?:** no, pero aumenta el riesgo.

### Recálculo total de indicadores al cambiar timeframe
- **Descripción:** `reset_all` + recálculo O(N) por timeframe. OK para ATR, caro para SMC/Liq.
- **Impacto:** rendimiento al subir a 1h/D/W con historial grande.
- **Evidencia:** `IndicatorManager::reset_all` + comentarios en el módulo.
- **Recomendación:** aplicar la regla del PDF (solo velas visibles + ventana de contexto) para
  los indicadores pesados de Fase 2.
- **¿Bloquea escalabilidad?:** parcialmente.

## Bajo

### Módulo de debug removible antes de entrega final
- **Descripción:** `Market/Debug/TimeAxisSnapshot.pm` es intencionalmente un módulo de diagnóstico, no parte del producto final. Está separado para poder omitirlo si el profesor exige una estructura estricta sin utilidades internas.
- **Impacto:** Bajo; ayuda a validar TradingView con precisión. Si se deja, no afecta render/runtime normal, pero debe quedar claro que es herramienta auxiliar.
- **Evidencia:** Wrapper mínimo `ChartEngine::debug_time_axis_snapshot()`; lógica principal en `Market/Debug/`.
- **Recomendación:** Mantener durante desarrollo/Fase 2; antes de entrega, decidir si se conserva como herramienta interna o se excluye.
- **¿Bloquea escalabilidad?:** no.

### Entorno frágil (Fedora35 EOL + parches MXNet manuales)
- **Descripción:** Fedora35 está EOL; AI::MXNet requiere parchear 5 `.pm` a mano.
- **Impacto:** difícil de reproducir en otra máquina.
- **Evidencia:** `docs/SETUP_FEDORA35.md`, AGENTS.md.
- **Recomendación:** documentar bien (hecho) y verificar el estado del parche antes de Fase 3.
- **¿Bloquea escalabilidad?:** no.

### CRLF Windows ↔ Linux
- **Descripción:** `git diff --check` avisa CRLF en `market.pl`.
- **Impacto:** cosmético.
- **Evidencia:** AGENTS.md.
- **Recomendación:** `.gitattributes` con `* text=auto` si molesta.
- **¿Bloquea escalabilidad?:** no.

### Proyecto en OneDrive vía junction
- **Descripción:** `C:\m\...` es junction a OneDrive; archivos hidratados desde la nube a veces
  no aparecen en listados recursivos (`Get-ChildItem -Recurse`).
- **Impacto:** confusión al inventariar; no afecta al código.
- **Evidencia:** observado durante el bootstrap (PDFs invisibles en `-Recurse`, visibles con
  `System.IO.Directory`).
- **Recomendación:** usar rutas literales y `System.IO` para verificar; no bloquear por esto.
- **¿Bloquea escalabilidad?:** no.
