# Spec 0000d: Crosshair en eje temporal y control definitivo de ticks/grid en gaps

## Estado

Bloqueante antes de Fase 2. Follow-up obligatorio de `0000c`.

## Contexto

`0000c` corrigió tres puntos importantes:

- crosshair inferior con fecha + hora;
- tick sintético `16:30` dentro de un gap 90m corto;
- paneo horizontal fraccional.

Las pruebas pasaron, pero la validación visual detectó dos regresiones/defectos no cubiertos:

1. La caja negra inferior del crosshair se dibuja en el borde inferior del panel de precio, por encima del eje temporal. En TradingView la caja está integrada en la barra inferior de fechas/horas.
2. La generación de ticks sintéticos es demasiado agresiva en gaps largos o multi-día. Produce muchas líneas verticales y etiquetas de horas dentro de zonas muy estrechas, por ejemplo `15:00`, `07:00`, `23:00` amontonadas. Eso no corresponde a TradingView.

## Objetivo

Cerrar definitivamente la UX del eje temporal de Fase 1 antes de `0001`:

- La etiqueta negra del crosshair debe renderizarse sobre el `time_axis_canvas`, no dentro del `price_canvas`.
- Los ticks sintéticos deben existir solo para gaps intradía cortos y controlados, como `15:00 -> 16:30 -> 18:00` en 90m.
- No se deben sintetizar horas dentro de gaps overnight, weekend o multi-día.
- Las líneas verticales del grid no deben dibujarse para labels ocultos por thinning/solape.

## Diagnóstico técnico

### 1. Crosshair temporal en canvas incorrecto

Actualmente `ChartEngine::_draw_crosshair_all()` llama:

```perl
$self->{price_panel}->draw_crosshair($last_x, $price_y, $time_text);
```

Y `PricePanel::draw_crosshair()` dibuja la caja de tiempo al fondo del `price_canvas`:

```perl
my $top    = $h - $box_h;
my $bottom = $h;
```

Como la UI tiene un `time_axis_canvas` separado debajo del panel de precio, la caja queda arriba del eje temporal, no integrada con él.

### 2. Ticks sintéticos excesivos

En `compute_intraday_labels()`, `0000c` agregó ticks sintéticos entre todo par consecutivo de timestamps parseables:

```perl
for (my $k = $first_k; $k <= $last_k; $k++) {
    ... push @items synthetic boundary ...
}
```

Eso funciona para el caso corto `15:00 -> 18:00` con intervalo 90m, pero falla para gaps grandes:

- noche;
- fin de semana;
- cambios de día;
- grandes saltos de sesión/datos.

Como las velas siguen espaciadas por índice, todas esas fronteras reales del reloj se interpolan dentro de uno o pocos slots de vela. Resultado visual: muchas líneas verticales casi pegadas y horas sin sentido para la zona visible.

### 3. Grid para labels ocultos

`PricePanel::draw_time_axis()` dibuja la línea vertical si `grid=1`, aunque `label=0` por solape:

```perl
if ($draw_grid && $item_grid) { createLine(...) }
next unless $draw_labels && $item_label;
```

Por eso, aunque el thinning oculte textos, las líneas verticales siguen apareciendo y crean bloques de grid muy densos.

## Requisitos funcionales

### R1. Crosshair temporal sobre el eje inferior

- Si existe `time_axis_canvas`, la caja negra con `Dow DD Mon 'YY HH:MM` debe dibujarse ahí.
- No debe dibujarse en el borde inferior del `price_canvas` cuando hay `time_axis_canvas` separado.
- Debe quedar a la misma altura visual que las etiquetas normales del eje temporal.
- Debe conservar clamp horizontal para no salirse por izquierda/derecha.
- Si no existe `time_axis_canvas`, se permite fallback al comportamiento anterior para compatibilidad.

### R2. Ticks sintéticos solo para gaps intradía cortos

- Mantener el caso aceptado de `0000c`: en modo 90m, entre `15:00` y `18:00` debe aparecer `16:30` aunque no exista vela.
- No sintetizar ticks intradía si el gap cruza cambio de día.
- No sintetizar ticks intradía si el número de fronteras intermedias excede un umbral pequeño.
- Recomendación de umbral inicial: máximo 1 frontera sintética por par consecutivo de velas. Si se necesita más, justificarlo y añadir prueba.
- No modificar datos ni crear velas falsas.

### R3. Grid no denso

- Una línea vertical de grid del eje temporal no debe dibujarse para un item cuyo `label` quedó oculto por solape.
- Alternativa aceptable: en `compute_intraday_labels()`, cuando `label=0`, dejar `grid=0` antes de retornar.
- Alternativa preferida por separación render/cálculo: en `PricePanel::draw_time_axis()`, dibujar grid solo si `grid=1` y `label=1`.
- Las fechas/días reales siguen teniendo prioridad visual y negrita.

### R4. No rollback total de 0000c

No conviene revertir todo `0000c` porque sí resolvió:

- formato crosshair con hora;
- paneo fraccional;
- caso corto `16:30` en 90m.

Si aparece bloqueo, revertir solo la parte de ticks sintéticos agresivos y reimplementar con las restricciones de esta spec.

## Criterios de aceptación

- `prove -l t` pasa completo.
- El nuevo test `t/04-chart-time-axis-visual-regressions.t` pasa.
- Crosshair temporal aparece sobre la barra inferior de fechas/horas, no sobre el panel de precio.
- En una zona con gap multi-día no aparecen horas sintéticas como `07:00` o `23:00` comprimidas entre dos velas.
- No aparecen bloques de muchas líneas verticales pegadas causadas por labels ocultos.
- `15:00 -> 16:30 -> 18:00` en 90m sigue funcionando.

## Archivos relevantes

- `Market/ChartEngine.pm`
- `Market/Panels/PricePanel.pm`
- `t/04-chart-time-axis-visual-regressions.t`

## Fuera de alcance

- Fase 2 (`0001` y posteriores).
- `MarketData.pm`.
- Indicadores/overlays/replay.
- Rediseño global de layout Tk.
- Refactor amplio de `ChartEngine.pm`.
