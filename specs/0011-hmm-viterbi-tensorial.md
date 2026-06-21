# Spec 0011: HMM + Viterbi tensorial (MXNet) — FASE 3 (futura)

Fuente: docx `Viterbi-tensorial-v0.3_ejercicio.docx`, clases 06-08/06-09. Requiere AI::MXNet
(ver `docs/SETUP_FEDORA35.md`). Package (sugerido): `Algorithm/Viterbi.pm` (estilo del docx).

## Objetivo
Implementar el algoritmo de Viterbi en versión **tensorial** sobre AI::MXNet (NDArray), con
soporte de logaritmos y de órdenes superiores, para hallar la secuencia de estados ocultos más
probable de un HMM que modela el estado/estructura del mercado.

## Problema
Predecir vela a vela es inviable por el ruido. El objetivo es predecir el cambio de
estado/estructura macro (alcista/bajista/lateral) con un autómata probabilístico. La versión
escalar no escala a órdenes superiores; se exige la tensorial.

## Comportamiento esperado

### Convención (del profesor)
- **Filas = estados ocultos (Y); columnas = observaciones/tiempo (N).** Cada columna es un instante.
- Entradas: `A` (transición Y×Y), `B` (emisión Y×K), `pi` (inicial), `O` (observaciones como
  índices enteros). Salidas: `S_opt` (vector N), `D` (trellis Y×N), `E` (backtrack Y×(N-1)).

### Pseudocódigo de referencia (orden 1, del docx)
```
FUNCTION viterbi_tensors_order1(self, O)
    D ← zeros(I, N);  E ← zeros(I, N-1)
    obs ← O[0];  D[:,0] ← pi × B[:, obs]            # inicialización
    for n in 1..N-1:
        obs  ← O[n]
        prev ← D[:, n-1:n]                           # columna n-1 (mantener 2D)
        temp ← prev × A                              # temp(i,j) = prev(i)·A(i,j)  (broadcast)
        max_vals ← max(temp, axis=0)
        argmaxes ← argmax(temp, axis=0)
        emit ← B[:, obs]
        D[:,n]   ← max_vals × emit                   # recursión
        E[:,n-1] ← argmaxes
    S_opt[N-1] ← argmax(D[:, N-1])                   # finalización
    for n in (N-2)..0:                               # backtrack
        S_opt[n] ← E[ S_opt[n+1], n ]
    RETURN S_opt, D, E
```

### Operaciones MXNet requeridas
- `slice` (begin/end/step; escalar reduce dimensión, rango la conserva), `expand_dims`, `squeeze`,
  `reshape`, asignación de columnas (`set_column`), `arange`, `max(axis)`, `argmax(axis)`, producto
  Hadamard (elementwise) y **broadcast**. El bucle se reduce a un solo `for` temporal.

### Logaritmos (flag `log=1`)
- Al inicio convertir A, B, pi a log con `nd.log`, sumando un mínimo (p. ej. `1e-300`) antes para
  evitar `log(0) = -inf`.
- En modo log, los **productos se reemplazan por sumas** (operador ternario según el flag).
- Necesario por desbordamiento numérico (~228.000 iteraciones).
- Al final, si `log` activo, deshacer con `nd.exp`.

### Órdenes superiores
- Orden 1 → coste N·Y²; orden 2 → N·Y³; orden 3/4 → N·Y⁴.
- Al subir de orden, `pi` pasa de vector a matriz, y A/B suben una dimensión.
  **Regla: dimensión del tensor = orden del Viterbi + 1** (orden 2 → 3D, orden 3 → 4D).
- El proyecto necesita contexto de 2/3/4 velas hacia atrás → por eso la versión tensorial.

### Modelado del HMM del proyecto
- Estados ocultos base: alcista, bajista, lateral choppy (no predecible), lateral tipo seno
  (predecible); **más de 4** (auxiliares de espera/confirmación entre estados). Nº final por confirmar.
- Capa oculta alterna liquidez interna ↔ externa, con estados intermedios.
- Observaciones (discretas, enteras): etiquetas de estructura (HH/HL/LL/LH, BOS, CHoCH verdadero,
  CHoCH falso/inducement), tipo de liquidez (sweep/grab/run), estado del evento de liquidez,
  ATR por bins (3–4 niveles), volumen, volume profile, supertrend, range filter, FVG armado/mitigado.
- La data continua se discretiza a etiquetas enteras antes de entrenar (K-Means/KNN/PCA/EM — U5).

### Forward (concepto de apoyo)
- Igual estructura pero **suma** todos los caminos (en vez de `max`); da probabilidad total
  acumulada, NO la secuencia óptima.

## Criterios de aceptación
- La salida del orden 1 reproduce los valores de referencia del docx (ejemplo `A,B,pi,O` →
  `S_opt=[0 1 0]`, `D` y `E` esperados).
- Funciona con `log=0` y `log=1` dando la misma secuencia óptima.
- Soporta al menos orden 1 y 2; el shape de cada tensor es correcto en cada paso.

## Casos límite
- `log(0)` (emisión nula): mitigado con el mínimo sumado.
- Empates en `argmax`: política determinista (primer índice).
- Observación fuera de rango de B.

## Plan de verificación
- Verificar carga de MXNet (`docs/SETUP_FEDORA35.md`).
- Test contra el ejemplo del docx (valores D/E/S_opt exactos).
- (Recomendado) test `.t` con tolerancia numérica para el modo log.
