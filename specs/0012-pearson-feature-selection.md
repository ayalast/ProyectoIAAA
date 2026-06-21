# Spec 0012: Selección de features con Pearson/PCC — FASE 3 (futura)

Fuente: PDF `Pearson_Correlation_Coefficients-PCC.pdf`, clase 06-17. Requiere AI::MXNet
(`mx->nd->corrcoef`) y Chart::Plotly (heatmap/scatter).

## Objetivo
Calcular covarianza y coeficiente de correlación de Pearson entre las features candidatas
(indicadores) para seleccionar las más informativas y descartar las redundantes antes de
alimentar el HMM (spec 0011).

## Problema
Muchos indicadores aportan información solapante. Incluir features redundantes mete ruido y
aumenta el error. Pearson cuantifica la relación lineal y permite podar features.

## Comportamiento esperado

### Procedimiento (a implementar manual para entender, y con `corrcoef` para producción)
1. Media de cada variable.
2. Centrar: `X - media(X)`.
3. Producto parcial por fila: `(X0i - μX0)·(X1i - μX1)`.
4. Sumar los productos.
5. Covarianza muestral = `Σ / (n-1)` (el `-1` corrige el sesgo muestral).
6. Varianza de cada variable = `Σ(X-μ)² / (n-1)`; desvío = `√varianza`.
7. Pearson = `cov(X0,X1) / (desv(X0)·desv(X1))`.
- Rango `[-1, 1]`. |r|≈1 ⇒ alta correlación (redundante/solapante); |r|≈0 ⇒ independiente.

### Aplicación
- Calcular Pearson entre predictoras entre sí (para detectar redundancia) y entre cada predictora
  y la etiqueta Y (para medir poder predictivo).
- Elegir features informativas, descartar ruido/redundancia.
- **Normalizar vs estandarizar antes de calcular:** el profesor lo deja como ejercicio abierto.
  Implementar ambos (minmax y mean/std) y comparar resultados (en sus ejemplos la matriz de
  correlación sale igual normalizando o estandarizando — confirmar/experimentar).

### Visualización (Chart::Plotly)
- **Heatmap** de la matriz de correlación (simétrica, diagonal de unos; colorscale tipo YlOrRd).
- **Scatter** de puntos por clase con colores distintos (ver separabilidad).
- NO graficar X vs Y directamente cuando Y es categórica (0/1/2): no aporta; para eso el heatmap.

### Código de referencia (del PDF, Perl/MXNet)
```perl
my $corrcoef = mx->nd->corrcoef($normalized->transpose());
# heatmap con Chart::Plotly::Trace::Heatmap (x=>$header, y=>$header, z=>$corrcoef->aspdl)
```

## Fuera de alcance
- PCA, K-means, EM (otros temas de la Unidad 5; specs separadas si se requieren).
- El entrenamiento del HMM (spec 0011).

## Criterios de aceptación
- El cálculo manual reproduce el ejemplo de clase (x0=[1..5], x1=[2,4,5,4,5] → Pearson ≈ 0.7746).
- `corrcoef` sobre un dataset (p. ej. Iris) coincide con la matriz de referencia del PDF.
- Heatmap y scatter se generan correctamente.

## Casos límite
- Varianza cero (columna constante): Pearson indefinido; manejar sin dividir por cero.
- Normalización con min=max.

## Plan de verificación
- Verificar MXNet (`docs/SETUP_FEDORA35.md`).
- Test contra el ejemplo manual de clase y la matriz Iris del PDF.
