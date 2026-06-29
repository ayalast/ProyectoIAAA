package Market::Overlays::Liquidity;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::Liquidity — render de estructuras de liquidez
# (spec 0005 / task 0012 — Tabla 2 del PDF)
# =============================================================================
#
# Capa de RENDER sobre el Canvas. Consume el indicador de cálculo
# Market::Indicators::Liquidity (NO calcula nada) y dibuja, según la Tabla 2:
#
#   | Elemento    | Estilo                          | Color        | Etiqueta    |
#   |-------------|---------------------------------|--------------|-------------|
#   | BSL         | horizontal discontinua/punteada | Rojo         | BSL         |
#   | SSL         | horizontal discontinua/punteada | Verde        | SSL         |
#   | EQH         | línea que conecta los máximos   | Configurable | EQH         |
#   | EQL         | línea que conecta los mínimos   | Configurable | EQL         |
#   | Sweep Up    | marcador / línea de quiebre     | Rojo         | SWEEP ↑     |
#   | Sweep Down  | marcador / línea de quiebre     | Verde        | SWEEP ↓     |
#   | Liquidity Grab | destacado de rechazo rápido  | Naranja      | LQ GRAB     |
#   | Liquidity Run  | extensión de ruptura        | Azul         | LQ RUN      |
#
# CONTRATO DE OVERLAY (task 0003 / Overlays::Base):
#   new(%args)         — recibe `indicator` (Indicators::Liquidity), `theme` opcional.
#   set_visible($bool) — activa/desactiva TODO el overlay.
#   is_visible         — bool.
#   compute_visible($market_data, $indicator, $start, $end) — pide al indicador
#                        los niveles/eventos de la ventana [start, end] y los
#                        filtra por index <= end (respeta replay_idx).
#   draw($canvas, $scales) — dibuja en el Canvas usando Scales.
#   clear($canvas)     — borra sus ítems del Canvas (tag `ov_liq`).
#   tag                — retorna el tag namespaced (`ov_liq`).
#
# TOGGLES INDIVIDUALES: set_element_visible($element, $bool) activa/desactiva
# una familia concreta. $element ∈ {BSL, SSL, EQH, EQL, SWEEP, GRAB, RUN}.
# SWEEP agrupa SWEEP_UP y SWEEP_DOWN. EQH/EQL usan colores configurables vía
# tema (claves `liq_eqh`, `liq_eql`).
#
# TAGS DE CANVAS: todo lo que dibuja lleva el tag `ov_liq`, de forma que
# clear($canvas) lo elimina sin tocar a otros overlays ni a las velas.
# =============================================================================

# Familias de elementos dibujables y su mapeo de tipos del contrato.
my %ELEMENT_TYPES = (
    BSL    => [qw(BSL)],
    SSL    => [qw(SSL)],
    EQH    => [qw(EQH)],
    EQL    => [qw(EQL)],
    SWEEP  => [qw(SWEEP_UP SWEEP_DOWN)],
    GRAB   => [qw(GRAB)],
    RUN    => [qw(RUN)],
);

sub new {
    my ($class, %args) = @_;
    die "Overlays::Liquidity->new: requiere 'indicator' (Indicators::Liquidity)"
        unless defined $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 1,
        # Toggles individuales por familia (todos visibles por defecto).
        _elem_visible => { map { $_ => 1 } keys %ELEMENT_TYPES },
        # Items visibles, separados por familia para draw().
        _levels => [],
        _events => [],
        _compute_range => undef,
        _replay_idx    => undef,
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_liq' }

sub set_visible {
    my ($self, $bool) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible {
    my ($self) = @_;
    return $self->{visible};
}

# set_element_visible($element, $bool) — toggle individual de una familia.
sub set_element_visible {
    my ($self, $element, $bool) = @_;
    return $self unless defined $element && exists $ELEMENT_TYPES{$element};
    $self->{_elem_visible}{$element} = $bool ? 1 : 0;
    return $self;
}

# is_element_visible($element) — bool de visibilidad de una familia.
sub is_element_visible {
    my ($self, $element) = @_;
    return 0 unless defined $element && exists $ELEMENT_TYPES{$element};
    return $self->{_elem_visible}{$element};
}

# compute_visible($market_data, $indicator, $start, $end)
#
# Pide al indicador los niveles (BSL/SSL/EQH/EQL) y eventos (SWEEP/GRAB/RUN) ya
# calculados y los filtra por la ventana visible [start, end]. $end ya viene
# truncado por ChartEngine.compute_window cuando Replay está activo; respetar
# `index <= end` equivale a respetar replay_idx. El overlay NO alimenta al
# indicador: eso es responsabilidad de ChartEngine antes de renderizar.
sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $start //= 0;
    $end   //= 0;
    $self->{_compute_range} = [$start, $end];
    $self->{_replay_idx}    = $end;

    my $ind = defined $indicator ? $indicator : $self->{indicator};

    my $levels = $ind->can('get_levels') ? $ind->get_levels() : [];
    my $events = $ind->can('get_events') ? $ind->get_events() : [];
    
    # Nivel de liquidez se dibuja horizontalmente; se mantiene mientras esté en pantalla
    my $filtered_levels = _levels_window_filter($levels, $start, $end);
    $self->{_levels} = _recent($filtered_levels, 40);
    
    # Eventos son etiquetas en el punto de ruptura, usamos filtro estándar
    $self->{_events} = _recent(_window_filter($events, $start, $end), 30);

    return $self;
}

# Mantiene los $n items más recientes (mayor index), preservando orden ascendente.
sub _recent {
    my ($items, $n) = @_;
    return $items unless defined $n && @$items > $n;
    my @sorted = sort { ($b->{index} // 0) <=> ($a->{index} // 0) } @$items;
    my @keep = @sorted[0 .. $n - 1];
    return [ sort { ($a->{index} // 0) <=> ($b->{index} // 0) } @keep ];
}

# Filtra niveles de liquidez según solapamiento con la ventana visible.
sub _levels_window_filter {
    my ($levels, $start, $end) = @_;
    return [] unless defined $levels;
    my @filtered;
    for my $lvl (@$levels) {
        next unless defined $lvl->{index};
        
        # El nivel debe iniciar antes o durante la ventana actual
        next if $lvl->{index} > $end;
        
        # Si fue barrido, su final debe ser en o después del inicio de la ventana
        if (defined $lvl->{swept_index}) {
            next if $lvl->{swept_index} < $start;
        }
        
        push @filtered, $lvl;
    }
    return \@filtered;
}

# Filtra items por index dentro de [start, end]. Un item sin index se descarta.
sub _window_filter {
    my ($items, $start, $end) = @_;
    return [] unless defined $items;
    return [ grep { defined $_->{index} && $_->{index} >= $start && $_->{index} <= $end } @$items ];
}

sub _local_index {
    my ($self, $index) = @_;
    my $range = $self->{_compute_range};
    my $start = $range ? ($range->[0] // 0) : 0;
    return $index - $start;
}

# --- helpers de tema (defaults de la Tabla 2, override por tema inyectado) ------

sub _color {
    my ($self, $key, $default) = @_;
    return $self->{theme}{$key} // $default;
}

# draw($canvas, $scales) — dibuja las estructuras visibles con tag `ov_liq`.
sub draw {
    my ($self, $canvas, $scales) = @_;
    return unless $self->{visible};
    return unless $canvas && $scales;
    return unless defined $scales->{height} && $scales->{height} > 0;

    $self->clear($canvas);

    my $tag = $self->tag();
    my $w   = $scales->{width} || $scales->plot_width();
    my $ev  = $self->{_elem_visible};

    # --- BSL / SSL: líneas horizontales punteadas (rojo / verde) --------------
    for my $lvl (@{ $self->{_levels} }) {
        next unless defined $lvl->{index} && defined $lvl->{price};
        my $type = $lvl->{type};
        if ($type eq 'BSL' && $ev->{BSL}) {
            $self->_draw_hline_label($canvas, $scales, $tag, $w,
                $lvl, 'BSL',
                $self->_color('liq_bsl', '#ef5350'),
                $self->_color('liq_bsl_label', '#ef5350'),
            );
        } elsif ($type eq 'SSL' && $ev->{SSL}) {
            $self->_draw_hline_label($canvas, $scales, $tag, $w,
                $lvl, 'SSL',
                $self->_color('liq_ssl', '#26a69a'),
                $self->_color('liq_ssl_label', '#26a69a'),
            );
        }
    }

    # --- EQH / EQL: línea que conecta los dos pivotes del par -----------------
    # Los EQH/EQL vienen de a pares (mismo type, dos index). Se conectan con una
    # línea entre ambos puntos. Color configurable (Tabla 2).
    if ($ev->{EQH} || $ev->{EQL}) {
        for my $type (qw(EQH EQL)) {
            next unless $ev->{$type};
            my @pair = grep { defined $_->{type} && $_->{type} eq $type } @{ $self->{_levels} };
            $self->_draw_pair_line($canvas, $scales, $tag, $type, \@pair);
        }
    }

    # --- Eventos: SWEEP_UP / SWEEP_DOWN / GRAB / RUN --------------------------
    for my $e (@{ $self->{_events} }) {
        next unless defined $e->{index} && defined $e->{type};
        my $type = $e->{type};

        if ($type eq 'SWEEP_UP' && $ev->{SWEEP}) {
            $self->_draw_event_marker($canvas, $scales, $tag, $e,
                "SWEEP \x{2191}",
                $self->_color('liq_sweep_up', '#ef5350'),
            );
        } elsif ($type eq 'SWEEP_DOWN' && $ev->{SWEEP}) {
            $self->_draw_event_marker($canvas, $scales, $tag, $e,
                "SWEEP \x{2193}",
                $self->_color('liq_sweep_down', '#26a69a'),
            );
        } elsif ($type eq 'GRAB' && $ev->{GRAB}) {
            $self->_draw_event_marker($canvas, $scales, $tag, $e,
                'LQ GRAB',
                $self->_color('liq_grab', '#ff9800'),
            );
        } elsif ($type eq 'RUN' && $ev->{RUN}) {
            $self->_draw_event_marker($canvas, $scales, $tag, $e,
                'LQ RUN',
                $self->_color('liq_run', '#2962ff'),
            );
        }
    }

    return $self;
}

# _draw_hline_label: línea horizontal punteada + etiqueta de texto al inicio.
sub _draw_hline_label {
    my ($self, $canvas, $scales, $tag, $w, $lvl, $label, $line_color, $text_color) = @_;
    my $price = $lvl->{price};
    my $y = $scales->value_to_y($price);
    
    my $x_start = $scales->index_to_center_x($self->_local_index($lvl->{index}));
    my $x_end = $w;
    if (defined $lvl->{swept_index}) {
        $x_end = $scales->index_to_center_x($self->_local_index($lvl->{swept_index}));
    }
    
    return if $x_end < 0;

    $canvas->createLine(
        $x_start, $y, $x_end, $y,
        -fill  => $line_color,
        -dash  => [4, 4],
        -width => 1,
        -tags  => $tag,
    );
    $canvas->createText(
        $x_start + 4, $y,
        -text   => $label,
        -anchor => 'w',
        -font   => 'Helvetica 8 bold',
        -fill   => $text_color,
        -tags   => $tag,
    );
    return;
}

# _draw_pair_line: conecta los pivotes de un par (EQH/EQL) con una línea.
sub _draw_pair_line {
    my ($self, $canvas, $scales, $tag, $type, $items) = @_;
    return unless @$items >= 2;
    my @sorted = sort { ($a->{index} // 0) <=> ($b->{index} // 0) } @$items;
    my $color = $self->_color($type eq 'EQH' ? 'liq_eqh' : 'liq_eql',
                             $type eq 'EQH' ? '#ab47bc' : '#7e57c2');
    my $label_color = $self->_color($type eq 'EQH' ? 'liq_eqh_label' : 'liq_eql_label',
                                    $color);

    my $first = $sorted[0];
    my $last  = $sorted[-1];
    
    my $x_start = $scales->index_to_center_x($self->_local_index($first->{index}));
    my $y = $scales->value_to_y($first->{price});
    my $x_end = $scales->{width} || $scales->plot_width();
    
    # Encontrar el BSL/SSL correspondiente al primer y último pivote para obtener su swept_index
    my $swept_idx;
    for my $lvl (@{ $self->{_levels} }) {
        next unless defined $lvl->{price} && abs($lvl->{price} - $first->{price}) < 0.0001;
        next unless grep { $_->{index} == $lvl->{index} } @sorted;
        if (defined $lvl->{swept_index}) {
            $swept_idx = $lvl->{swept_index};
            last;
        }
    }
    if (defined $swept_idx) {
        $x_end = $scales->index_to_center_x($self->_local_index($swept_idx));
    }
    
    return if $x_end < 0;

    $canvas->createLine(
        $x_start, $y, $x_end, $y,
        -fill  => $color,
        -dash  => [2, 3],
        -width => 2,
        -tags  => $tag,
    );

    # Etiqueta sobre el punto medio de los extremos del par.
    my $x1 = $scales->index_to_center_x($self->_local_index($first->{index}));
    my $x2 = $scales->index_to_center_x($self->_local_index($last->{index}));
    my $x_mid = ($x1 + $x2) / 2;
    $canvas->createText(
        $x_mid, $type eq 'EQH' ? $y - 6 : $y + 6,
        -text   => $type,
        -anchor => $type eq 'EQH' ? 's' : 'n',
        -font   => 'Helvetica 8 bold',
        -fill   => $label_color,
        -tags   => $tag,
    );
    return;
}

# _draw_event_marker: marcador de evento (línea vertical de quiebre + etiqueta).
# Se traza una línea vertical breve en la vela del evento a la altura del nivel
# roto, y la etiqueta de la Tabla 2.
sub _draw_event_marker {
    my ($self, $canvas, $scales, $tag, $e, $label, $color) = @_;
    my $x = $scales->index_to_center_x($self->_local_index($e->{index}));
    
    my $price = $e->{extreme} // $e->{price};
    my $y = defined $price ? $scales->value_to_y($price) : 0;
    my $dir = $e->{dir} // 'up';

    if ($dir eq 'up') {
        # BSL: Línea vertical que va hacia arriba desde el High de la vela.
        $canvas->createLine(
            $x, $y, $x, $y - 20,
            -fill  => $color,
            -width => 2,
            -tags  => $tag,
        );
        $canvas->createText(
            $x, $y - 24,
            -text   => $label,
            -anchor => 's',
            -font   => 'Helvetica 8 bold',
            -fill   => $color,
            -tags   => $tag,
        );
    } else {
        # SSL: Línea vertical que va hacia abajo desde el Low de la vela.
        $canvas->createLine(
            $x, $y, $x, $y + 20,
            -fill  => $color,
            -width => 2,
            -tags  => $tag,
        );
        $canvas->createText(
            $x, $y + 24,
            -text   => $label,
            -anchor => 'n',
            -font   => 'Helvetica 8 bold',
            -fill   => $color,
            -tags   => $tag,
        );
    }
    return;
}

# clear($canvas) — borra solo los ítems de este overlay (tag `ov_liq`).
sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    $canvas->delete($self->tag());
    return $self;
}

# --- helpers para tests -------------------------------------------------------
# compute_range: retorna [start, end] recibido en compute_visible.
sub compute_range {
    my ($self) = @_;
    return $self->{_compute_range};
}

# visible_items: retorna todos los items que el overlay dibujará en draw(),
# combinados (para replay guard vía IndicatorSnapshot->replay_violations).
sub visible_items {
    my ($self) = @_;
    return [
        @{ $self->{_levels} },
        @{ $self->{_events} },
    ];
}

1;
