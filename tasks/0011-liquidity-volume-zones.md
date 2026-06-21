# Task 0011: Liquidity — pesado de volumen multi-temporal + 7 zonas

## Spec relacionada
`specs/0005-liquidez.md` (pesado de volumen, 7 zonas, interna/externa). Depende de tasks 0009, 0001.

## Objetivo
Ampliar `Market/Indicators/Liquidity.pm` para: (a) almacenar en cada evento el volumen
transaccionado en 1m/5m/15m independientemente del TF macro visible, y (b) detectar las 7 zonas de
liquidez del PDF. Clasificar liquidez interna vs externa.

## Archivos probablemente relevantes
- `Market/Indicators/Liquidity.pm`.
- `Market/MarketData.pm` (acceso a sub-velas de 1m/5m/15m — task 0001).
- `docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` §4.4.

## Pasos
1. **Pesado de volumen multi-TF:** para cada evento/nivel, calcular y guardar el volumen agregado de
   las sub-velas de 1m, 5m y 15m que caen en su rango temporal, **aunque** el usuario esté viendo
   1h/4h/D/W. Estos pesos sirven para filtrar niveles institucionales del ruido (volumen pico =
   indicio de zona de liquidez; ~5 toques agotan un nivel — calibrable).
2. **7 zonas de liquidez** (detectores que producen niveles candidatos):
   1. Debajo de equal lows / arriba de equal highs.
   2. Debajo/arriba de swing highs/lows.
   3. Debajo/arriba de trendlines y canales.
   4. Dentro de un order block (doji o engulfing).
   5. Debajo/arriba de soporte/resistencia y niveles de Fibonacci.
   6. Niveles de la vela diaria anterior (H/L/O/C).
   7. Niveles de la vela semanal.
3. **Interna vs externa:** marcar cada nivel como interno (mismo TF activo) o externo (HTF
   proyectado). Exponer el estado de alternancia interna↔externa (con estados intermedios) para el HMM.
4. Cálculo puro e incremental.

## Criterios de aceptación
- Cada evento guarda volúmenes 1m/5m/15m correctos, sin importar el TF macro visible.
- Las 7 zonas se detectan y exponen como niveles candidatos con su tipo.
- Cada nivel queda marcado interno/externo.

## Verificación por debug (OBLIGATORIA)
Lee `docs/PHASE2_DEBUG_CONTRACT.md`. Cada evento lleva `meta => { v1m, v5m, v15m, internal => 0|1 }`;
las 7 zonas como `type` ∈ {`zone_1`..`zone_7`}.

Ampliar `t/10-liquidity.t`:
1. con un dataset donde el TF macro visible es 1h/D, verificar que `meta->{v1m/v5m/v15m}` de un
   evento coincide con la SUMA de las sub-velas del rango (calculada a mano en el test);
2. verificar que cada nivel queda marcado `internal => 0|1` correctamente;
3. verificar que las 7 zonas se detectan y exponen con su `type`.
Comparar vía `render_items(..., fields => [qw(index type meta)])` contra el esperado transcrito.

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Indicators/Liquidity.pm && prove -l t"
```

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- El render (task 0012). La concurrencia con estructura (2ª entrega).
