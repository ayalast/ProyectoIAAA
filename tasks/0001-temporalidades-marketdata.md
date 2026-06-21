# Task 0001: Temporalidades extendidas en MarketData

## Spec relacionada
`specs/0001-temporalidades-extendidas.md`

## Objetivo
Que `MarketData` soporte las 8 temporalidades (1m,5m,15m,1h,2h,4h,D,W), agregadas desde el 1m por
fronteras reales de reloj, sin romper 1m/5m/15m.

## Archivos probablemente relevantes
- `Market/MarketData.pm` (subs `build_tf_candles`, `_bucket_timestamp`, `build_timeframes`,
  `set_timeframe`, `_active_array`, hash `data`).
- `market.pl` (donde se llama a `build_timeframes` y se pasan los TF a la UI).
- `Market/ChartEngine.pm` (validación de TF, si aplica).

## Pasos
1. Ampliar el hash `data` de `new` para incluir las claves `1h`, `2h`, `4h`, `D`, `W` además de
   `1m`/`5m`/`15m`.
2. Generalizar `_bucket_timestamp` para que, dado un TF, calcule la frontera de reloj correcta:
   - minutos (5,15,60,120,240): truncar al múltiplo de minutos desde medianoche.
   - `D`: truncar a inicio de día (00:00) calendario.
   - `W`: truncar a inicio de semana (definir lunes como inicio; documentar la elección).
3. Generalizar `build_tf_candles` para agregar OHLCV correctamente: Open=primera, High=máx,
   Low=mín, Close=última, Volumen=suma de las sub-velas del bucket.
4. `build_timeframes` construye las 8 series desde 1m.
5. Verificar que `set_timeframe`/`_active_array`/`get_slice`/`size`/`last_candle` funcionan para
   las nuevas claves.

## Criterios de aceptación
- Las 8 temporalidades devuelven slices correctos.
- Una vela 1h contiene exactamente las velas 1m de su hora de reloj (OHLCV correcto).
- El nº de velas D ≈ días con datos; W ≈ semanas. 1m/5m/15m siguen igual que antes.

## Verificación (OBLIGATORIA, no solo `perl -c`)
Crear `t/11-timeframes.t` (cálculo puro, sin Tk):
1. cargar un set sintético de velas 1m de varias horas con OHLCV conocido;
2. `build_timeframes()` y, para una hora de reloj concreta, afirmar que la vela 1h tiene
   Open=primera, High=máx, Low=mín, Close=última, Volumen=suma exactos de sus 60 sub-velas 1m;
3. afirmar `size('D')` ≈ nº de días con datos y `size('W')` ≈ nº de semanas;
4. afirmar que 1m/5m/15m no cambian respecto a antes (mismas longitudes/buckets).
Documentar la elección de inicio de semana (lunes) en un comentario del test.

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/MarketData.pm && perl -I. -c market.pl && prove -l t"
```
Recuerda también ampliar `ChartEngine::set_timeframe` (hoy solo acepta `1m/5m/15m`, ver
`Market/ChartEngine.pm:1621`) para validar los 8 TF.

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- La lógica de render (Panels/ChartEngine) más allá de aceptar los nuevos nombres de TF.
- `Data/2026_03.csv`.
