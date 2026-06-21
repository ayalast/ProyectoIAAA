# Spec 0000: Pulido Fase 1 — eje temporal y etiqueta TradingView del crosshair

> Estado posterior: la etiqueta del crosshair (`Thu 23 Apr '26`) quedó aceptada. El criterio de "grid temporal equidistante" de esta spec fue reemplazado por `specs/0000b-time-axis-tradingview-scale.md`, porque la observación contra TradingView confirmó que debe priorizar fronteras reales de reloj/calendario.

Fuente: rúbrica/validación Fase 1, `../Requisitos_Proyecto_2do_Bimestre.md` secciones 4 y 17, y observación visual del usuario contra TradingView.

## Objetivo

Cerrar los detalles pendientes de paridad TradingView antes de empezar Fase 2: la etiqueta inferior del crosshair debe mostrar fecha completa estilo TradingView y las marcas/líneas verticales del eje temporal inferior deben quedar equidistantes para un zoom dado.

## Problema

La Fase 1 está cerca del 100%, pero quedan dos fallos visuales importantes:

1. La etiqueta negra bajo el crosshair actualmente se comporta como etiqueta de hora corta; debe verse como TradingView: día de semana, día calendario, mes y año.
2. En el panel inferior de fechas/horas, al cambiar zoom las marcas de periodo pueden quedar con separaciones visuales inconsistentes. Para un zoom fijo, cada línea vertical de fondo que nace del eje temporal debe estar separada por la misma distancia horizontal de la anterior y la siguiente.

Estos detalles conviene resolver antes de implementar overlays de Fase 2, porque Replay, SMC, liquidez, Volume Profile y VWAP dependen de una escala X confiable y legible.

## Comportamiento esperado

### Etiqueta inferior del crosshair

- Al mover el crosshair, la caja negra inferior debe mostrar el timestamp de la vela bajo el cursor en formato TradingView:
  - Ejemplo exacto esperado: `Thu 23 Apr '26`.
  - Componentes: día de semana abreviado, día del mes, mes abreviado, apóstrofo + año de dos dígitos.
  - Idioma visual: abreviaturas en inglés, igual a TradingView (`Mon`, `Tue`, `Wed`, `Thu`, `Fri`, `Sat`, `Sun`; `Jan`..`Dec`).
- La etiqueta debe quedar visualmente en el eje temporal inferior, alineada verticalmente con la línea del crosshair, con caja negra y texto blanco.
- No debe romper la etiqueta de precio del eje Y ni el crosshair sincronizado entre panel de precio y ATR.

### Eje temporal y líneas verticales equidistantes

- Para un zoom dado, todas las marcas visibles del eje temporal inferior que generan línea vertical de grid deben tener el mismo paso en índices de vela.
- Al cambiar zoom, el paso puede cambiar, pero dentro de ese zoom debe ser constante.
- La distancia entre líneas verticales debe ser uniforme en píxeles, tolerancia máxima: 1 px por redondeo.
- Las etiquetas pueden alternar entre hora, día o mes según densidad/zoom, pero no se deben insertar líneas extra fuera del ritmo uniforme solo por cambio de fecha.
- La escala X sigue siendo por índice de vela, no por tiempo continuo: gaps nocturnos/fin de semana no crean huecos visuales.

## Fuera de alcance

- No implementar nuevas temporalidades de Fase 2.
- No implementar Replay, overlays, SMC ni liquidez.
- No refactorizar masivamente `ChartEngine.pm`.
- No cambiar el modelo de datos ni el CSV.

## Criterios de aceptación

- Con el crosshair sobre una vela del 23 de abril de 2026, la etiqueta inferior muestra `Thu 23 Apr '26` o el equivalente correcto para esa fecha.
- La etiqueta se ve en el eje temporal inferior, no flotando de forma confusa dentro del panel de precio.
- En 1m/5m/15m, para cualquier zoom probado, las líneas verticales visibles del fondo están equidistantes entre sí.
- Cambiar zoom recalcula el paso de marcas sin dejar saltos irregulares dentro del mismo zoom.
- Las velas mantienen separación uniforme por índice y siguen alineadas con grid/crosshair.
- `perl -I. -c` pasa en los módulos tocados.

## Casos límite

- Ventanas muy comprimidas con miles de velas visibles: reducir cantidad de etiquetas, pero mantener grid uniforme.
- Zoom extremo con pocas velas visibles: no solapar etiquetas; si hay que ocultar texto, no ocultar/romper la uniformidad del grid.
- Timestamps no parseables: omitir etiqueta o degradar limpio, sin romper render.
- Crosshair en espacios en blanco laterales: no mostrar fecha falsa fuera del rango real de datos.

## Plan de verificación

- Sintaxis:
  - `perl -I. -c Market/ChartEngine.pm`
  - `perl -I. -c Market/Panels/PricePanel.pm` si se toca.
  - `perl -I. -c Market/Panels/Scales.pm` si se toca.
  - `perl -I. -c market.pl` si se toca.
- Prueba manual WSLg:
  1. Abrir `perl -I. market.pl`.
  2. Mover crosshair sobre varias velas y verificar formato `Thu 23 Apr '26`.
  3. Probar zoom in/out en 1m, 5m y 15m.
  4. Verificar visualmente que las líneas verticales del grid son equidistantes en cada zoom.
  5. Comparar lado a lado con TradingView en el mismo tramo.
