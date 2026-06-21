# Spec 0001: Temporalidades extendidas (1m … W)

Fuente: PDF Fase 2 §3 "Temporalidades y Sistema Replay". Clase 06-15.

## Objetivo
Ampliar las temporalidades soportadas de las actuales {1m, 5m, 15m} a la lista completa:
**1m, 5m, 15m, 1h, 2h, 4h, D (diario), W (semanal)**.

## Problema
Fase 1 solo agrega 5m/15m desde 1m. El análisis SMC/liquidez de Fase 2 necesita marcos
superiores (HTF) para identificar estructura "limpia" y proyectarla sobre marcos inferiores
(LTF). Sin 1h/4h/D/W no se puede cumplir la jerarquía multi-temporal del PDF.

## Usuarios afectados
El operador que cambia de temporalidad; los módulos SMC y Liquidez (consumen velas de varios TF).

## Comportamiento esperado
- `MarketData` construye y cachea velas para todas las temporalidades a partir del 1m.
- La agregación respeta **fronteras reales de reloj** (igual que ya hace 5m/15m con
  `_bucket_timestamp`): p. ej. 1h agrupa `:00–:59`, D agrupa por día calendario, W por semana.
- Cambiar el TF activo recalcula indicadores (vía `IndicatorManager::reset_all` + recálculo).
- Los niveles calculados en TF mayores deben poder **habilitarse opcionalmente** en ventanas de
  menor temporalidad (1m/5m/15m) para dar contexto macro (esto lo consume la UI, spec 0010, y
  los overlays, spec 0003/0004/0005).

## Fuera de alcance
- El render de niveles HTF sobre LTF (eso es de overlays + UI).
- Sesiones de mercado y feriados (la data es continua de marzo 2026).

## Criterios de aceptación
- `MarketData` expone las 8 temporalidades y devuelve slices correctos para cada una.
- La cantidad de velas agregadas cuadra: nº de velas D ≈ días con datos; W ≈ semanas.
- Una vela de TF mayor abarca exactamente las sub-velas de su intervalo de reloj (test contra 1m).
- No se rompe el comportamiento existente de 1m/5m/15m.

## Casos límite
- Intervalos incompletos al inicio/fin del dataset (primera semana parcial): incluir la vela
  parcial con las velas disponibles, marcada como tal si hace falta.
- Cambios de día/semana a medianoche y límites de mes.
- Gaps en la data (faltan minutos): la agregación usa las velas presentes, no inventa.

## Plan de verificación
- `perl -I. -c Market/MarketData.pm`.
- Test manual: contar velas por TF y comparar con agregación de referencia sobre el CSV.
- (Recomendado) test `.t` que agregue un tramo conocido de 1m a 1h/D y verifique OHLCV.
