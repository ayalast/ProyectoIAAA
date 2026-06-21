# Spec 0004: SMC Structures (BOS / CHoCH / FVG / Fibonacci)

Fuente: PDF Fase 2 §4 y §5. Clases 06-15 (SMC), 06-16 (relación con liquidez).
Packages: `Market/Indicators/SMC_Structures.pm` (cálculo) + `Market/Overlays/SMC_Structures.pm` (render).

## Objetivo
Detectar y etiquetar la estructura de mercado: zigzag de pivotes (HH/HL/LL/LH), rupturas
estructurales (BOS), cambios de carácter (CHoCH verdadero vs falso/inducement), Fair Value Gaps
(FVG) con mitigación progresiva, y niveles de Fibonacci entre el major high/low vigente.

## Problema
La estructura es el cimiento de todo el análisis (y de las observaciones del HMM futuro). El
indicador SMC de TradingView solo dibuja BOS/CHoCH básicos: NO distingue verdadero/falso, NO
confirma con cierre de cuerpo, NO mantiene major high/low. El alumno debe implementar esa lógica.

## Comportamiento esperado

### Zigzag / pivotes (cimiento crítico)
- El zigzag se calcula con **máquina de estados**, NO con ventanas de tamaño fijo (k velas a la
  izquierda/derecha como el "Pivot" de TradingView). Regla del profesor: la FSM controla si la
  estructura va hacia una dirección u otra **sin contar número de velas**.
- **Toda** vela relevante recibe una de las 4 etiquetas: HH (Higher High), HL (Higher Low),
  LL (Lower Low), LH (Lower High). No se permite saltar velas / dejar extremos sin marcar.
- Definición formal de swing (del PDF, profundidad `k=3` inicial, calibrable):
  - Swing High en `i`: `High[i] > High[i-k..i-1]` y `High[i] > High[i+1..i+k]`.
  - Swing Low en `i`: `Low[i] < Low[i-k..i-1]` y `Low[i] < Low[i+1..i+k]`.
  - (El PDF da swing por ventana; el profesor exige además la FSM para el zigzag continuo. Usar
    swing como detector de candidatos y la FSM para encadenar HH/HL/LL/LH sin huecos.)

### Major high / major low
- En cada momento hay **un solo** major high y **un solo** major low vigentes (estructura externa).
- Se actualizan solo tras romper (con confirmación) el nivel opuesto. Lo demás es estructura
  interna (ruido).

### BOS (Break of Structure) — continuación de tendencia
- Se confirma con **cierre de cuerpo** que supera el HH/LL relevante anterior (no basta la mecha).
- Regla operativa: BOS alcista si `close` de la vela supera el último HH relevante (o
  `high(vela_siguiente) > high(vela_inicial)` según confirmación). Mecha sin cuerpo ⇒ pendiente.
- Existe BOS válido y BOS falso.

### CHoCH (Change of Character) — cambio de tendencia
- **Verdadero** solo si rompe el **major** low/high (no un nivel interno) con **cierre de cuerpo**
  y se mantiene en la vela siguiente.
- **Falso = inducement**: ruptura de estructura interna / manipulación; se etiqueta distinto.
- Etiquetar correctamente verdadero vs falso es crítico (si se confunde, el HMM no predice bien).
  La distinción se apoya en temporalidad mayor (HTF).

### FVG (Fair Value Gap)
- Hueco/imbalance entre **3 velas** (gap dejado por la vela central).
- **Mitigación progresiva**: cuando velas posteriores consumen el gap, reducir/adelgazar la zona
  ("Reduce Mitigated FVG"); eliminarla cuando se consume del todo.
- Los FVG formados en la vela de un Sweep/Grab o inmediatamente después se marcan "Zona de Alta
  Reacción" (entrada de la spec 0006 / strategy builder).

### Fibonacci
- Trazar niveles de Fibonacci entre el major high y major low vigentes.
- Niveles estándar: 0.236, 0.382, 0.5, 0.618, 0.786 (nivel clave: **0.618**). (En el audio los
  decimales salen mal transcritos; usar los estándar.)

### Multi-temporalidad
- La estructura "limpia" se obtiene en HTF (1m tiene demasiado ruido) y se proyecta/dibuja sobre
  LTF (solapamiento de niveles HTF, activable desde UI — spec 0010).

### Render (Overlays/SMC_Structures.pm)
- Dibuja etiquetas BOS/CHoCH ubicadas en la vela/tiempo de confirmación, líneas de major high/low,
  cajas de FVG (que se reducen al mitigarse) y los niveles de Fibonacci.
- Activable/desactivable (spec 0003). Respeta `replay_idx` (spec 0002).

## Fuera de alcance
- El HMM y las observaciones discretas (Fase 3, spec 0011).
- Los pesos de probabilidad liquidez→estructura (spec 0006).

## Criterios de aceptación
- Cada extremo del zigzag queda etiquetado HH/HL/LL/LH sin saltar velas.
- BOS y CHoCH se etiquetan solo tras cierre de cuerpo confirmado; CHoCH verdadero requiere romper
  el major.
- Existe siempre a lo sumo un major high y un major low vigentes.
- Los FVG se dibujan entre 3 velas y se reducen progresivamente al ser mitigados.
- Fibonacci se traza entre el major high/low vigentes con los niveles estándar.
- Comportamiento comparable a "SMC Structure + FVG" / LuxAlgo / ICT como referencia visual.

## Casos límite
- Mercado lateral (choppy): muchos pivotes pequeños; la FSM no debe generar HH/LL espurios.
- Velas con cuerpo nulo (doji) o gaps; mechas largas sin cuerpo (pendiente, no confirma).
- Inicio del dataset sin historial suficiente para `k` velas.
- Replay: etiquetas aparecen solo cuando la vela de confirmación entra en `replay_idx`.

## Plan de verificación
- `perl -I. -c` de ambos módulos.
- Comparación visual contra TradingView (SMC Structure + FVG) en 1m y en HTF.
- (Recomendado) test `.t` del cálculo puro de zigzag/BOS/CHoCH sobre un tramo conocido.
