# Task 0017: Rendimiento — SMC_Structures se cuelga ~37s en el dataset real

## Severidad: CRÍTICA (junto con 0016, bloquea el arranque de la app)

## Síntoma
Tras resolver Liquidity (task 0016), alimentar SMC_Structures sobre el CSV real (29888 velas)
tarda ~37.6s. El arranque total de la app (SMC + Liquidity en el primer render) es ~48s con la
GUI congelada hasta que termina. La app abre pero no pinta el gráfico hasta pasados ~48s.

## Causa raíz (perfilada por el arquitecto)
Mismo patrón O(n²) que 0016, ahora en `Market/Indicators/SMC_Structures.pm`:

```
SMC feed 8000 velas: 1.98s
  _detect_and_mitigate_fvgs   1.67s (84%)   ← dominante
  resto                       <0.1s cada uno
  _fvgs final: 1621            ← crece sin límite
```

`_detect_and_mitigate_fvgs` recorre `@{ $self->{_fvgs} }` ENTERO en cada vela para mitigar, pero
ese array nunca se poda: los FVG con `_active = 0` (consumidos) se quedan dentro y se siguen
visitando con `next unless $fvg->{_active}` en cada vela futura. Con el dataset real son miles de
FVGs muertos escaneados por vela → O(n²).

## Objetivo
`update_last` de SMC ~O(1) amortizado por vela: alimentar 29888 velas en pocos segundos. Sin
cambiar resultados (los 658 tests verdes, incluida la idempotencia de 0014 y los FVG/fibo de 0007).

## Archivos permitidos
- `Market/Indicators/SMC_Structures.pm`
- `t/09-smc-structures.t` (solo añadir test de cota; NO relajar los existentes)

## Correcciones requeridas

### R1. Podar FVGs inactivos del loop de mitigación
Cuando un FVG se consume (`_active = 0`), sácalo de la lista que recorre
`_detect_and_mitigate_fvgs`. Opciones (elige la más simple que conserve resultados):
- Mantener `_fvgs` solo con los activos (mover los resueltos a un `_fvgs_done` si `get_fvg`/algún
  test los necesita; revisar: hoy `get_fvg` solo devuelve los `_active`, así que los inactivos no
  hacen falta para la salida).
- O compactar la lista periódicamente.
Importante: `get_fvg()` debe seguir devolviendo exactamente los mismos FVGs activos con los mismos
`hi/lo/mitig`, y la mitigación de un FVG aún activo debe seguir calculándose vela a vela igual.

### R2. (si hace falta para la cota) mitigación sin recorrer todos los activos
Si tras R1 el coste sigue siendo alto porque hay muchos FVGs activos simultáneos legítimos,
evalúa indexar/acotar el barrido (p.ej. solo FVGs cuyo rango de precio esté “cerca” de la vela
actual). Solo si es necesario para la cota; no lo añadas preventivamente (YAGNI). Documenta
cualquier heurística y su impacto en resultados (debe ser nulo en los fixtures de test).

### R3. Verifica que no haya otros escaneos crecientes
Revisa que `_check_bos_choch`, `get_pivots`/`_get_effective_majors` y demás no recorran arrays que
crezcan con el historial. El perfil dice que hoy no dominan, pero confirma que ninguno sea O(n) por
vela tras R1.

## Tests requeridos
1. **Cota de rendimiento (NUEVO)** en `t/09`: alimentar >= 8000 velas sintéticas (con formación
   frecuente de FVGs para ejercitar el loop) y afirmar `elapsed < 5s` (umbral holgado, `Time::HiRes`).
   Debe FALLAR con el código actual (~varios segundos y subiendo) y pasar con el fix.
2. **Conservar TODO** 0005/0006/0007/0014: anclas zigzag, BOS/CHoCH, FVG exacto/mitigación
   (`mitig=0.5`, consumo total elimina el FVG), fib_0.618=12.326, idempotencia de getters.
3. `prove -l t` completo en verde.

## Verificación obligatoria
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/Indicators/SMC_Structures.pm && prove -l t"
```
Y medición del feed completo (debe bajar de ~37s a pocos segundos):
```bash
# script temporal que alimente las 29888 velas del CSV y mida tiempo (como hizo el arquitecto)
```

## Qué no tocar
- `Market/Debug/`, `Market/MarketData.pm`, `Data/2026_03.csv`.
- La lógica de detección (zigzag/BOS/CHoCH/FVG/fibo): misma salida, solo más rápido.
- La idempotencia de getters (task 0014): no reintroduzcas mutación de estado al podar.
- Liquidity, overlays, ChartEngine.

## Prompt mínimo para implementor
Implementa `tasks/0017-smc-performance-fix.md`. Mismo patrón O(n²) que ya resolviste en 0016, ahora
en SMC_Structures: `_detect_and_mitigate_fvgs` (84% del tiempo) recorre `_fvgs` entero cada vela y
los FVG inactivos (`_active=0`) nunca se podan → miles de FVGs muertos escaneados por vela. Poda los
FVGs inactivos del loop conservando EXACTA la salida de `get_fvg()` (mismos hi/lo/mitig) y la
mitigación de los activos. Respeta la idempotencia de getters de 0014 (no reintroduzcas mutación).
Añade en t/09 un test de cota (>=8000 velas < 5s) que falle con el código viejo. No toques
Market/Debug/, MarketData.pm, el CSV, Liquidity, overlays ni ChartEngine. Verifica con prove -l t y
midiendo el feed de las 29888 velas (debe bajar de ~37s a pocos segundos).
