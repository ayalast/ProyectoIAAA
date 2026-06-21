# Deuda técnica

Clasificada por severidad. No se resuelve aquí; solo se documenta. Última act.: 2026-06-20.

## Crítico

(Ninguna bloqueante hoy. La Fase 1 funciona y está evaluada.)

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

### Sin tests automatizados
- **Descripción:** validación 100% visual; `t/` está vacía.
- **Impacto:** regresiones silenciosas al añadir Fase 2; difícil verificar algoritmos de ML.
- **Evidencia:** `t/` vacío; AGENTS.md ("No hay tests automatizados").
- **Recomendación:** Test::More para cálculo puro (ATR, SMC labels, Viterbi tensorial con la
  salida de referencia del docx, Pearson con el ejemplo Iris).
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
