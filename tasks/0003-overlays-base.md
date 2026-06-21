# Task 0003: Patrón base de Overlays + registro

## Spec relacionada
`specs/0003-overlays-base.md`

## Objetivo
Crear la carpeta `Market/Overlays/` con un contrato uniforme de overlay y un registro que
`ChartEngine` itera en cada render. Incluir un overlay de ejemplo mínimo que valide el patrón.

## Archivos probablemente relevantes
- Nuevo: `Market/Overlays/Base.pm` (o documentar el contrato como convención) — define la interfaz.
- Nuevo: `Market/Overlays/Example.pm` (overlay trivial de prueba, p. ej. una línea horizontal en el
  último close visible) — se elimina o se deja como referencia.
- Nuevo o en ChartEngine: `Market/OverlayManager.pm` (registro: `register`, `each_active`,
  `set_visible($name,$bool)`, `draw_all($scales)`, `clear_all`).
- `Market/ChartEngine.pm` (invocar el registro en `render`, respetando `replay_idx`).
- `Market/Panels/Scales.pm` (los overlays usan sus conversiones datos↔píxeles).

## Pasos
1. Definir el contrato de overlay (métodos): `new(%args)`, `set_visible($bool)`, `is_visible`,
   `compute_visible($market_data,$indicator,$start,$end)`, `draw($scales)`, `clear()`. Cada overlay
   usa un **tag de Canvas propio** (namespaced, p. ej. `"ov_example"`) para poder limpiar solo lo suyo.
2. Implementar `OverlayManager`: registra overlays por nombre, itera los activos, delega draw/clear.
3. En `ChartEngine.render`: tras dibujar paneles, llamar `OverlayManager.draw_all($scales)` con el
   rango visible (`start,end` de `compute_window`) y respetando `replay_idx` (task 0002).
4. Implementar `Overlays/Example.pm` bajo el contrato (dibuja algo simple solo en velas visibles) y
   registrarlo para validar on/off.
5. Asegurar que `compute_visible` solo procesa la ventana visible + un pequeño contexto, NO las
   ~29888 velas.

## Criterios de aceptación
- Existe `Market/Overlays/` con el contrato y un overlay de ejemplo funcional.
- `set_visible` muestra/oculta el overlay sin afectar velas ni otros overlays.
- Cada overlay limpia solo sus ítems (tags propios).
- El cómputo es proporcional a las velas visibles (no recorre todo el historial por frame).

## Verificación por debug (OBLIGATORIA)
Crear `t/13-overlays-base.t` (sin GUI real; usar un `TestCanvas` que registre operaciones como en
`t/07`):
1. registrar el overlay de ejemplo y afirmar que `OverlayManager->each_active` lo lista;
2. `set_visible(0)` → `draw_all` no produce ops de ese overlay; `set_visible(1)` → sí;
3. afirmar que `clear()` solo borra el tag propio (`ov_example`), no otros;
4. afirmar que `compute_visible` recibe `(start,end)` y procesa **solo** ese rango (medible: pasar
   un rango pequeño dentro de un dataset grande y comprobar que no recorre todo el historial);
5. con `replay_idx` definido, `compute_visible` no entrega elementos de índice > tope.

## Comandos de verificación
```bash
wsl -d Fedora35 -- bash -lc "cd ~/Documents/ProyectoIA/ProyectoIAAA && perl -I. -c Market/OverlayManager.pm && perl -I. -c Market/Overlays/Example.pm && perl -I. -c Market/ChartEngine.pm && perl -I. -c market.pl && prove -l t"
```

## Estado
**Arrancable ya** (no depende de 0000g ni de 0001).

## Qué no tocar
- `Market/Debug/` (solo arquitecto).
- Los indicadores de cálculo (SMC/Liquidez vienen en sus tasks).
- La lógica de paneles existente (PricePanel/ATRPanel) salvo el punto de invocación del registro.
