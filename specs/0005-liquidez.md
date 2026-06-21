# Spec 0005: Módulo de Liquidez

Fuente: PDF Fase 2 §4 (Definiciones, Confirmación, Máquina de Estados, Multi-TF, Etiquetado).
Clase 06-16. Packages: `Market/Indicators/Liquidity.pm` (cálculo + FSM) +
`Market/Overlays/Liquidity.pm` (render).

## Objetivo
Detectar, clasificar y visualizar estructuras de liquidez: swing points, EQH/EQL, BSL/SSL, y
clasificar los eventos de ruptura en Sweep / Grab / Run mediante una máquina de estados
determinista, con pesado de volumen multi-temporal.

## Problema
La liquidez (stops, órdenes límite) es el objetivo del precio; identificar dónde se barre
liquidez y si fue manipulación (sweep/grab) o ruptura real (run) es insumo de alta probabilidad
para las decisiones y para las observaciones del HMM. Pine Script no permite máquina de estados
ni el cómputo necesario.

## Comportamiento esperado

### Niveles base
- **Swing High/Low** con profundidad `k=3` (inicial, calibrable) — misma definición que spec 0004.
- **BSL (Buy Side Liquidity):** liquidez por **encima** de máximos relevantes (swing highs, EQH,
  techos de rango). Órdenes Buy Stop.
- **SSL (Sell Side Liquidity):** liquidez por **debajo** de mínimos relevantes (swing lows, EQL,
  suelos de rango). Órdenes Sell Stop.
- **EQH / EQL (Equal Highs/Lows):** dos pivotes "iguales" si la diferencia absoluta de sus
  extremos no supera una tolerancia dinámica:
  - EQH: `abs(high_1 - high_2) <= tolerancia`
  - EQL: `abs(low_1 - low_2) <= tolerancia`
  - **Tolerancia = `ATR * 0.10`** (del PDF; calibrable).

### Clasificación del evento (reglas estrictas de cierre)
Tras la ruptura de un nivel válido de BSL/SSL:
- **Liquidity Sweep (barrido estándar):** el precio rompe temporalmente el swing capturando
  órdenes, pero la vela **regresa y cierra dentro** del rango previo. Es manipulación.
  - Alcista: `High > BSL` seguido de `Close < BSL`.
  - Bajista: `Low < SSL` seguido de `Close > SSL`.
- **Liquidity Grab (rechazo rápido):** barrido con alta velocidad y rechazo inmediato, sin
  aceptación fuera del nivel; el retorno/rechazo ocurre en **≤ 3 velas** posteriores a la
  penetración. (≈ sweep pero más rápido y puntual; se asocia a reversal.)
- **Liquidity Run (expansión con aceptación):** el precio rompe y demuestra aceptación fuera del
  nivel, continuando en la misma dirección sin retornar.
  - Alcista: al menos `N` velas consecutivas (N=3 inicial) cierran estrictamente por encima del BSL barrido.
  - Bajista: al menos `N` velas cierran estrictamente por debajo del SSL barrido.

### Máquina de estados del evento (ciclo de vida por nivel)
1. **Detected** — nivel válido (BSL/SSL/EQH/EQL) identificado y almacenado.
2. **Swept** — el precio cruzó el extremo (`High > BSL` o `Low < SSL`).
3. **Acceptance** — cierres fuera del nivel sostenidos por `N` velas (→ rumbo a Run).
4. **Reclaimed** — el precio no se sostiene y el cierre (o el cuerpo, dentro de ≤3 velas) regresa
   al rango (→ rumbo a Sweep/Grab).
5. **Resolved** — fin del ciclo; el nivel se archiva con su clasificación final inmutable
   (Sweep, Grab o Run) para servir de entrada a las reglas de mercado.
   (Ver diagrama: `docs/material_profesor/imagenes/maquina_estados_liquidez.png`.)

### Las 7 zonas de liquidez a detectar
1. Debajo de equal lows / arriba de equal highs.
2. Debajo/arriba de swing highs/lows.
3. Debajo/arriba de trendlines y canales.
4. Dentro de un order block (con doji o vela envolvente/engulfing).
5. Debajo/arriba de soporte/resistencia y niveles de Fibonacci.
6. Niveles de la vela diaria (high/low/open/close del día anterior).
7. Niveles de la vela semanal.

### Pesado de volumen multi-temporal
- Cada evento almacena el volumen transaccionado en 1m, 5m y 15m, **independientemente** del TF
  macro que el usuario visualice (si ve 1h/4h/D, el motor extrae los volúmenes de las sub-velas).
- Estos pesos filtran niveles institucionales reales del ruido. Volumen elevado (pico) = indicio
  de zona de liquidez/barrido. (El profesor: ~5 toques agotan un nivel — calibrable.)

### Liquidez interna vs externa
- **Interna:** niveles de la misma temporalidad activa.
- **Externa:** niveles de HTF proyectados sobre el gráfico actual.
- El precio alterna entre ambas (máquina de estados con estados intermedios). El ingreso de alta
  probabilidad es al salir de la liquidez externa hacia la interna.

### Validación cross-temporal
- El barrido instantáneo se identifica en TF pequeña (1m); el nivel relevante (p. ej. double
  bottom) se ve en TF mayor. Validar cruzando ambas.

### Render (Overlays/Liquidity.pm) — Tabla 2 del PDF
| Elemento | Estilo | Color | Etiqueta |
|---|---|---|---|
| BSL | Horizontal discontinua/punteada | Rojo | BSL |
| SSL | Horizontal discontinua/punteada | Verde | SSL |
| EQH | Línea que conecta ambos máximos | Configurable | EQH |
| EQL | Línea que conecta ambos mínimos | Configurable | EQL |
| Sweep Up | Marcador / línea de quiebre | Rojo | SWEEP ↑ |
| Sweep Down | Marcador / línea de quiebre | Verde | SWEEP ↓ |
| Liquidity Grab | Destacado de rechazo rápido | Naranja | LQ GRAB |
| Liquidity Run | Extensión de ruptura | Azul | LQ RUN |
- Cada elemento activable/desactivable desde el menú (spec 0010). Actualización dinámica al
  entrar nuevas velas. Respeta `replay_idx`.
- Referencias de comportamiento: TradingView SMC, LuxAlgo SMC, ICT Concepts, Smart Money Setup.

## Fuera de alcance
- Los pesos de probabilidad que modifican BOS/CHoCH (spec 0006).
- El HMM (Fase 3).

## Criterios de aceptación
- Detección correcta de swing points, EQH/EQL (con tolerancia ATR*0.10) y BSL/SSL.
- Clasificación Sweep/Grab/Run según las reglas de cierre exactas (incluyendo N velas y ≤3 velas).
- La FSM transita Detected→Swept→(Acceptance|Reclaimed)→Resolved con clasificación final inmutable.
- Cada evento guarda volúmenes 1m/5m/15m sin importar el TF macro visible.
- Render conforme a la Tabla 2 (estilos/colores/etiquetas), toggles individuales, sin futuro en Replay.

## Casos límite
- Nivel barrido varias veces (re-toques); agotamiento por volumen.
- Grab vs Sweep ambiguo (ambos retornan): decidir por velocidad/nº de velas de rechazo.
- EQH/EQL con ATR muy bajo/alto (tolerancia dinámica).
- Falta de datos HTF para externa (contingencia).

## Plan de verificación
- `perl -I. -c` de ambos módulos.
- Test manual comparando con LuxAlgo/TradingView SMC; verificar etiquetas en Replay vela a vela.
- (Recomendado) test `.t` de la clasificación Sweep/Grab/Run sobre tramos sintéticos controlados.
