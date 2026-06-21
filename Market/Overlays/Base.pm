package Market::Overlays::Base;
use strict;
use warnings;

# Market::Overlays::Base — contrato base para todos los overlays de Fase 2.
#
# Cada overlay vive en Market::Overlays/<Nombre>.pm y consume un indicador de
# cálculo de Market::Indicators/<Nombre>.pm (separación cálculo/render).
#
# Contrato uniforme:
#   new(%args)         — recibe canvas, tema, etc.
#   set_visible($bool) — activa/desactiva el overlay.
#   is_visible         — bool.
#   compute_visible($market_data, $indicator, $start, $end) — prepara datos
#                       solo de la ventana visible + contexto. NO recorre todo
#                       el historial (regla de rendimiento PDF §2).
#   draw($canvas, $scales) — dibuja en el Canvas usando Scales.
#   clear($canvas)     — borra sus ítems del Canvas (tags propios).
#   tag                — retorna el tag de Canvas namespaced del overlay.
#
# Esta clase es una convención/rol, no una clase base con herencia.
# Cada overlay implementa estos métodos directamente. Este módulo documenta
# el contrato y provee un helper de validación.

sub validate {
    my ($class, $overlay) = @_;
    die "overlay does not implement set_visible"   unless $overlay->can('set_visible');
    die "overlay does not implement is_visible"    unless $overlay->can('is_visible');
    die "overlay does not implement compute_visible" unless $overlay->can('compute_visible');
    die "overlay does not implement draw"          unless $overlay->can('draw');
    die "overlay does not implement clear"         unless $overlay->can('clear');
    die "overlay does not implement tag"           unless $overlay->can('tag');
    return 1;
}

1;
