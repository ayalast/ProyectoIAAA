# Spec 0007: DIY Custom Strategy Builder

Fuente: PDF Fase 2 §6 (Tabla 3). Clases 06-15/06-16 (supertrend, range filter mencionados de pasada).
Packages: `Market/Indicators/Strategy_Builder.pm` (cálculo) + `Market/Overlays/Strategy_Builder.pm` (render).

## Objetivo
Constructor de estrategias que procesa en tiempo real reglas de entrada/salida combinando
indicadores técnicos y de volumen.

## Problema
El proyecto necesita un módulo configurable que combine varios indicadores de tendencia/rango y
zonas de oferta/demanda como base de señales, sobre las "Zonas de Alta Reacción" (spec 0006).

## Comportamiento esperado
Componentes (Tabla 3 del PDF):
- **SuperTrend:** cálculo y actualización dinámica por vela cerrada en base al multiplicador ATR.
- **HalfTrend:** determinación dinámica de la dirección de tendencia y filtros de reversión.
- **Range Filter:** suavizado dinámico del precio para aislar fases de acumulación/distribución.
- **Supply Zones:** persistencia en memoria de bloques de órdenes de venta validados por volumen.
- **Demand Zones:** persistencia en memoria de bloques de órdenes de compra validados por volumen.
- Las reglas de entrada/salida combinan estos componentes; se procesan vela a vela (compatibles
  con Replay) y se dibujan como overlay activable.

## Fuera de alcance
- Backtesting con métricas de PnL (no exigido por el PDF).
- Ejecución de órdenes reales.
- (El profesor mencionó "supertrend/filter range" como posiblemente opcionales "si avanza bien";
  aquí se especifican porque el PDF los lista en la Tabla 3. Confirmar prioridad con el profesor.)

## Criterios de aceptación
- SuperTrend, HalfTrend y Range Filter calculan y se actualizan por vela cerrada (ATR para SuperTrend).
- Supply/Demand zones persisten en memoria y se validan por volumen.
- El builder combina componentes en reglas y las visualiza como overlay on/off; respeta Replay.

## Casos límite
- ATR no disponible al inicio (warm-up del SuperTrend).
- Zonas solapadas o invalidadas por ruptura.

## Plan de verificación
- `perl -I. -c` de ambos módulos.
- Comparación visual con SuperTrend/HalfTrend/Range Filter de TradingView.
