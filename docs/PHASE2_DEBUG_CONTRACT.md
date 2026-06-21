# Contrato de Debug de Fase 2 (OBLIGATORIO para el agente implementor)

Este documento define **cómo se verifica** cada indicador/overlay de Fase 2 sin
necesidad de ver la GUI. Es el equivalente, para indicadores, de lo que
`Market::Debug::TimeAxisSnapshot` hace con el eje temporal.

> El sistema de debug es responsabilidad del arquitecto, **NO del implementor**.
> Ver "Reglas de oro" al final.

## 1. Por qué existe

El agente implementor usa un modelo barato y **no tiene visión**. No puede mirar
el Canvas para saber si un BOS, un FVG o un Sweep quedó bien. Por eso cada
indicador de cálculo debe exponer su resultado como **datos estructurados** que
`Market::Debug::IndicatorSnapshot` convierte en **texto determinista**
comparable en un test `.t`.

Regla dura: **si no se puede verificar por snapshot de texto, la task no está
terminada.** Nada de "validación visual" como única prueba.

## 2. El módulo de debug ya existe y está cerrado

`Market/Debug/IndicatorSnapshot.pm` (NO modificar). API estable:

- `Market::Debug::IndicatorSnapshot->render_items(\@items, %opts)` → string
  determinista (una línea por item, ordenado por `index` y luego `type`, números
  con precisión fija). `opts`: `fields => \@names`, `precision => N`,
  `replay_idx => K`, `title => '...'`.
- `->type_sequence(\@items)` → `"HH HL LH LL"` (secuencia de `type` en orden de
  índice; ignora precios).
- `Market::Debug::IndicatorSnapshot::summary_line(\@items)` → `"BOS=1 FVG_up=2 ..."`.
- `->replay_violations(\@items, $replay_idx)` → lista de items con
  `index > replay_idx` (criterio duro del PDF de Replay: cero fuga de futuro).

Su self-test es `t/08-indicator-debug-harness.t` (tampoco se toca).

## 3. Contrato de "item" que TU indicador debe devolver

Cada indicador de Fase 2 debe ofrecer un método que devuelva una **lista de
hashrefs** (no objetos Tk, no coordenadas de pantalla). Campos:

| Campo  | Tipo   | Uso |
|--------|--------|-----|
| `index`| int    | **Obligatorio.** Índice GLOBAL de la vela donde el elemento se ancla/confirma. |
| `type` | str    | **Obligatorio.** Etiqueta canónica (ver tabla §4). |
| `dir`  | str    | `'up'` / `'down'` cuando aplique. |
| `price`| num    | Precio del nivel/extremo cuando aplique. |
| `hi`,`lo`| num  | Límites de una zona (FVG, order block). |
| `state`| str    | Estado FSM: `Detected/Swept/Acceptance/Reclaimed/Resolved`. |
| `mitig`| num    | % mitigado de un FVG en `[0,1]`. |
| `meta` | hashref| Extra: volúmenes `v1m/v5m/v15m`, `internal`/`external`, etc. |

El método de cálculo debe ser **puro** (sin Tk) e **incremental** (contrato
`IndicatorManager`: `update_last`/`get_values`/`reset`). El overlay solo lee
estos items y dibuja.

## 4. Tipos canónicos por task (usar EXACTAMENTE estos strings)

- **0005 (zigzag):** `HH`, `HL`, `LL`, `LH`.
- **0006 (BOS/CHoCH):** `BOS`, `CHoCH_true`, `CHoCH_false`; nivel vigente como
  `major_high`, `major_low`.
- **0007 (FVG/Fibo):** `FVG_up`, `FVG_down` (con `hi`,`lo`,`mitig`);
  `fib_0.236`, `fib_0.382`, `fib_0.5`, `fib_0.618`, `fib_0.786`.
- **0009 (liquidez base):** `BSL`, `SSL`, `EQH`, `EQL`.
- **0010 (clasificación + FSM):** `SWEEP_UP`, `SWEEP_DOWN`, `GRAB`, `RUN`
  (cada uno con `state` durante el ciclo y final inmutable en `Resolved`).
- **0011 (volumen/zonas):** items de liquidez con `meta` = `{ v1m, v5m, v15m,
  internal => 0|1 }`; las 7 zonas con `type => "zone_1".."zone_7"`.

## 5. Cómo se ve un test obligatorio (patrón a copiar)

```perl
use Market::Debug::IndicatorSnapshot;
my $D = 'Market::Debug::IndicatorSnapshot';

# 1. construir velas sintéticas deterministas (sin Tk)
my $md = build_synthetic_candles();   # helper local al test
# 2. correr el indicador puro
my $smc = Market::Indicators::SMC_Structures->new(k => 3);
$smc->update_last($md, $_) for 0 .. $md->last_index;
my $items = $smc->get_pivots();        # lista de hashrefs del contrato

# 3. comparar la secuencia esperada (transcrita a mano por el arquitecto)
is($D->type_sequence($items), 'HH HL HH HL LH LL', 'zigzag esperado');

# 4. replay guard: nada por encima del tope
is(scalar($D->replay_violations($items, 10)), 0, 'sin fuga de futuro');
```

El **valor esperado** (`'HH HL HH HL LH LL'`) lo fija el arquitecto en la task;
el implementor solo debe lograr que su código lo reproduzca.

## 5.bis Política de "exactitud" del esperado (decisión del arquitecto)

No todo se prueba igual. Dos niveles:

- **Vector EXACTO cerrado** — cuando la salida es matemática pura y no depende del
  diseño del algoritmo. El número esperado es único y se afirma tal cual:
  - FVG: `hi`/`lo` exactos y su recorte al mitigarse.
  - EQH/EQL: tolerancia `ATR*0.10` (dentro → empareja, fuera → no).
  - BSL/SSL: `price` exacto del nivel.
  - Fibonacci: los 5 niveles entre major high/low (0.618 clave).
  - Volumen multi-TF: `v1m/v5m/v15m` = suma exacta de sub-velas.
  - Replay guard: `replay_violations == 0`.
- **Input exacto + invariantes** — cuando el resultado depende del diseño de la FSM
  (zigzag HH/HL/LL/LH, BOS/CHoCH verdadero vs falso). Aquí NO se fuerza una única
  cadena, porque eso podría empujar una implementación incorrecta. Se fija:
  1. el fixture de entrada exacto (velas OHLC);
  2. las invariantes que cualquier implementación correcta debe cumplir
     (p.ej. "no hay dos HH consecutivos sin un HL/LL entre medias", "todo extremo
     queda etiquetado, sin huecos", "CHoCH_true solo rompiendo el major");
  3. 1–2 anclas concretas verificables (p.ej. "en index=9 hay un BOS up").

  Si el implementor produce una secuencia distinta pero que respeta input+invariantes
  +anclas, es válida. Si quiere desviarse de las invariantes, debe justificarlo en el
  test, nunca borrarlas.

Regla práctica: **número que solo puede ser uno → exacto; etiqueta que depende de la
FSM → invariante + ancla.**

## 6. Reglas de oro

1. **El implementor NO crea ni modifica nada bajo `Market/Debug/`.** Si un test
   necesita un campo que el snapshot no expone, el implementor lo **reporta** y
   el arquitecto extiende el módulo de debug.
2. Cada task de indicador (0005–0012) **debe** añadir un test `.t` que use
   `IndicatorSnapshot` y compare contra el esperado transcrito en la task.
3. `prove -l t` debe pasar **completo** (no solo el archivo nuevo).
4. Cálculo y render separados: el item del contrato no lleva coordenadas de
   pantalla; eso lo resuelve el overlay con `Scales`.
