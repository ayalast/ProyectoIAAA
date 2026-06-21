# ADR 0002: Referencia oficial TradingView Lightweight Charts para eje temporal

## Estado
Aceptado como referencia técnica para cerrar Fase 1 antes de avanzar a Fase 2.

## Contexto
El usuario comparó la app Perl/Tk contra TradingView en 1 minuto y detectó que el eje temporal inferior aún no se comporta igual: fechas/horas con cadencia visual distinta, grid vertical más pesado o irregular y riesgo de que el crosshair no coincida con la marca inferior.

Para evitar seguir ajustando por intuición, se descargó el código abierto oficial de TradingView Lightweight Charts fuera del repo sincronizado con OneDrive, en ruta temporal corta:

```text
C:\Users\ASUS ROG\AppData\Local\Temp\opencode\lwc
```

Comando usado:

```bash
git clone --depth 1 https://github.com/tradingview/lightweight-charts.git "C:\Users\ASUS ROG\AppData\Local\Temp\opencode\lwc"
```

Esta carpeta es una referencia local, no forma parte del proyecto y no debe copiarse al repo.

## Archivos de referencia

- `src/model/time-scale.ts`
  - `indexToCoordinate`, `coordinateToIndex`, `marks`, `formatDateTime`.
  - La escala X se basa en índice lógico + `barSpacing`.
- `src/model/tick-marks.ts`
  - `TickMark.index`, `TickMark.weight`.
  - `TickMarks.build(spacing, maxWidth, ...)` filtra marcas por separación mínima en índices.
- `src/model/horz-scale-behavior-time/time-scale-point-weight-generator.ts`
  - Genera pesos comparando puntos temporales consecutivos reales.
- `src/model/horz-scale-behavior-time/types.ts`
  - Pesos oficiales: `Minute1`, `Minute5`, `Minute30`, `Hour1`, `Hour3`, `Hour6`, `Hour12`, `Day`, `Month`, `Year`.
- `src/model/horz-scale-behavior-time/horz-scale-behavior-time.ts`
  - Mapea peso temporal a tipo de label (`Time`, `DayOfMonth`, `Month`, `Year`).
  - Nota: el formatter debe devolver texto corto, máximo recomendado 8 caracteres.
- `src/model/horz-scale-behavior-time/default-tick-mark-formatter.ts`
  - Formato de labels: hora `HH:MM`; día del mes numérico; mes corto; año.
- `src/views/time-axis/crosshair-time-axis-view.ts`
  - El crosshair formatea el mismo punto lógico (`appliedIndex`) que usa la escala temporal.
- `src/gui/time-axis-widget.ts`
  - Dibuja labels base y labels de mayor peso en negrita.

## Datos reales usados para calibración visual

El archivo local `Data/2026_03.csv` fue inspeccionado y, aunque su nombre sugiere marzo, contiene datos intradía de **abril 2026**:

- primera vela: `2026-04-01T00:00:00-05:00`;
- última vela: `2026-04-30T23:59:00-05:00`;
- total: `29,888` velas base de 1 minuto;
- zona horaria del CSV: `UTC-5` (`-05:00`), compatible con Bogotá/Quito.

La comparación manual con TradingView se hizo con **NQ1! — NASDAQ 100 E-mini Futures, CME, 15m**, también en `UTC-5`. La captura confirmó que la app y TradingView muestran el mismo tramo de precio alrededor del 30 de abril de 2026.

Hallazgo importante: el dataset no es continuo 24/7. Contiene gaps reales de sesión:

- pausa diaria típica: `15:59 -> 17:00` (`61` minutos);
- fines de semana/cierres largos: viernes hacia domingo `17:00`;
- días completos típicos: `1380` velas de 1m, no `1440`.

En TradingView 15m, el tramo `15:45 -> 17:00` aparece como salto de sesión: **no se inventan velas ni labels `16:00`, `16:15`, `16:30`, `16:45`**. Por tanto, nuestra app debe comprimir esos gaps por índice lógico, igual que TradingView, salvo que en el futuro se implementen whitespace bars explícitos.

## Decisión

El eje temporal de la app debe migrar desde la lógica por `interval_minutes + thinning lineal` hacia un modelo inspirado en `TickMarks`:

1. Las velas, el eje inferior, el grid vertical y el crosshair comparten índice lógico.
2. Los candidatos de labels se construyen desde timestamps reales de velas visibles, más el punto inmediatamente anterior si hace falta para detectar cambio de peso.
3. Cada candidato recibe un peso temporal comparando su timestamp con el anterior:
   - año nuevo > mes nuevo > día nuevo > cruces intradía 12h/6h/3h/1h/30m/5m/1m.
4. Se seleccionan labels por prioridad de peso, de mayor a menor, y por separación mínima en índices/píxeles.
5. Los labels de día en zoom intradía deben ser cortos como TradingView: `15`, `16`, no `15 Apr` salvo que sea necesario por cambio de mes/contexto.
6. Las fechas/días son anchors de mayor peso y deben desplazar a horas cercanas, no insertarse como ticks extra fraccionales.
7. No se aceptan labels fraccionales. Si se desea mostrar tiempos sin vela, debe existir un punto lógico explícito de whitespace conocido por eje y crosshair.
8. El grid vertical debe dibujarse solo para labels visibles y con estilo ligero; el énfasis visual debe estar en el label en negrita, no en una línea vertical mucho más oscura.

## Relación con requisitos del profesor

Esto respeta y refuerza los requisitos de Fase 2:

- La escala horizontal es compartida entre paneles.
- Cada cambio de fecha se trata como anchor de mayor peso y se destaca visualmente.
- Las horas se distribuyen entre anchors según separación lógica/píxel, evitando solapes.
- Replay, SMC, liquidez, FVG, Volume Profile y VWAP dependerán de índices temporales confiables y sin desalineación crosshair/eje.
- No se muestran velas futuras; si en el futuro se dibuja espacio en blanco a la derecha, debe modelarse explícitamente como whitespace lógico o no tener label/crosshair de tiempo.

## Consecuencias

Positivas:
- Reduce ajustes visuales ad hoc.
- Alinea el comportamiento con una implementación oficial abierta de TradingView.
- Prepara una escala X sólida para Replay y overlays de Fase 2.

Negativas:
- Requiere una task follow-up (`0000f`) porque `0000e` pasó tests pero no alcanza equivalencia visual.
- La implementación completa tipo TradingView es más compleja que elegir un intervalo y hacer thinning lineal.

## Próxima acción

Crear/ejecutar `specs/0000f-time-axis-weighted-tickmarks-tradingview.md` y `tasks/0000f-time-axis-weighted-tickmarks-tradingview.md` antes de iniciar `0001`.
