package Market::Overlays::SMC_Structures;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::SMC_Structures — render de estructura SMC (spec 0004 / task 0008)
# =============================================================================
#
# Capa de RENDER sobre el Canvas. Consume el indicador de cálculo
# Market::Indicators::SMC_Structures (NO calcula nada) y dibuja:
#   - Etiquetas de pivotes HH/HL/LL/LH.
#   - Etiquetas BOS / CHoCH (true vs false con estilo distinto) en la vela de
#     confirmación.
#   - Líneas horizontales de major high / major low vigentes.
#   - Cajas de FVG (Fair Value Gap) que se reducen al mitigarse: el overlay
#     dibuja la caja con la altura actual (hi - lo), que el indicador ya trae
#     recortada según la mitigación.
#   - Niveles de Fibonacci entre major high/low (0.618 destacado).
#
# CONTRATO DE OVERLAY (task 0003 / Overlays::Base):
#   new(%args)         — recibe `indicator` (Indicators::SMC_Structures),
#                        `theme` opcional.
#   set_visible($bool) — activa/desactiva el overlay.
#   is_visible         — bool.
#   compute_visible($market_data, $indicator, $start, $end) — pide al indicador
#                        los items de la ventana [start, end] + contexto y los
#                        filtra por index <= end (respeta replay_idx).
#   draw($canvas, $scales) — dibuja en el Canvas usando Scales.
#   clear($canvas)     — borra sus ítems del Canvas (tag `ov_smc`).
#   tag                — retorna el tag de Canvas namespaced (`ov_smc`).
#
# RENDIMIENTO (PDF §2): compute_visible solo pide los getters del indicador (que
# son O(1) sobre lo ya calculado) y filtra por la ventana visible. NO recorre
# todo el historial. Los getters del indicador son NO-MUTANTES (task 0014), así
# este overlay puede invocarlos por frame sin corromper la FSM del zigzag.
#
# TAGS DE CANVAS: todo lo que dibuja este overlay lleva el tag `ov_smc`, de forma
# que clear($canvas) lo elimina sin tocar a otros overlays ni a las velas.
# =============================================================================

sub new {
    my ($class, %args) = @_;
    die "Overlays::SMC_Structures->new: requiere 'indicator' (Indicators::SMC_Structures)"
        unless defined $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 1,
        # Items visibles, separados por familia para draw().
        _pivots  => [],
        _events  => [],
        _fvgs    => [],
        _fibs    => [],
        _major   => [],
        _compute_range => undef,
        _replay_idx => undef,
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_smc' }

sub set_visible {
    my ($self, $bool) = @_;
    $self->{visible} = $bool ? 1 : 0;
    return $self;
}

sub is_visible {
    my ($self) = @_;
    return $self->{visible};
}

# compute_visible($market_data, $indicator, $start, $end)
#
# Pide al indicador (el recibido como argumento si viene, si no el del
# constructor) los items ya calculados y los filtra por la ventana visible
# [start, end]. $end ya viene truncado por ChartEngine.compute_window cuando
# Replay está activo, de modo que respetar `index <= end` equivale a respetar
# replay_idx. Se filtra además por `index >= start` para acotar al viewport.
#
# El overlay NO alimenta al indicador (update_last): eso es responsabilidad de
# ChartEngine/IndicatorManager antes de renderizar. Aquí solo se lee.
sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $start //= 0;
    $end   //= 0;
    $self->{_compute_range} = [$start, $end];
    $self->{_replay_idx}    = $end;

    my $ind = defined $indicator ? $indicator : $self->{indicator};

    # Pivotes y eventos son etiquetas locales o líneas acotadas.
    $self->{_pivots} = _recent(_window_filter($ind->get_pivots(), $start, $end), 40);
    $self->{_events} = _recent(_events_window_filter($ind->get_events(), $start, $end), 40);
    
    # FVG, Fib y Major son líneas horizontales o cajas que se extienden al infinito o hasta mitigación,
    # por lo que deben mostrarse si empezaron en cualquier índice <= $end (aunque start_index esté off-screen).
    $self->{_fvgs}   = _recent([ grep { $_->{index} <= $end } @{$ind->get_fvg()} ], 25);
    $self->{_fibs}   = [ grep { $_->{index} <= $end } @{$ind->get_fibonacci()} ];
    $self->{_major}  = [ grep { $_->{index} <= $end } @{$ind->get_major()} ];

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

# Filtra eventos (BOS/CHoCH) comprobando solapamiento de su tramo [start_index, index] con [start, end].
sub _events_window_filter {
    my ($events, $start, $end) = @_;
    return [] unless defined $events;
    my @filtered;
    for my $e (@$events) {
        next unless defined $e->{index};
        my $s_idx = $e->{start_index} // $e->{index};
        next if $s_idx > $end;
        next if $e->{index} < $start;
        push @filtered, $e;
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

# --- helpers de tema (defaults claros, override por el tema inyectado) ----------

sub _color {
    my ($self, $key, $default) = @_;
    return $self->{theme}{$key} // $default;
}

# draw($canvas, $scales) — dibuja todo el contenido visible con tag `ov_smc`.
sub draw {
    my ($self, $canvas, $scales) = @_;
    return unless $self->{visible};
    return unless $canvas && $scales;
    return unless defined $scales->{height} && $scales->{height} > 0;

    $self->clear($canvas);

    my $tag = $self->tag();
    my $w   = $scales->{width} || $scales->plot_width();

    # --- Fibonacci primero (quedan al fondo); 0.618 destacado -----------------
    for my $fib (@{ $self->{_fibs} }) {
        next unless defined $fib->{price};
        my $y = $scales->value_to_y($fib->{price});
        my $is_key = defined $fib->{type} && $fib->{type} eq 'fib_0.618';
        $canvas->createLine(
            0, $y, $w, $y,
            -fill  => $is_key ? $self->_color('smc_fib_key', '#d32f2f')
                              : $self->_color('smc_fib', '#9e9e9e'),
            -dash  => $is_key ? [] : [2, 3],
            -width => $is_key ? 2 : 1,
            -tags  => $tag,
        );
    }

    # --- Major high / low: líneas horizontales vigentes ----------------------
    for my $m (@{ $self->{_major} }) {
        next unless defined $m->{price};
        my $y = $scales->value_to_y($m->{price});
        my $is_high = (defined $m->{type} && $m->{type} eq 'major_high');
        $canvas->createLine(
            0, $y, $w, $y,
            -fill  => $is_high ? $self->_color('smc_major_high', '#26a69a')
                               : $self->_color('smc_major_low', '#ef5350'),
            -width => 2,
            -tags  => $tag,
        );
    }

    # --- FVG: cajas cuya altura refleja la mitigación (hi - lo actual) -------
    for my $fvg (@{ $self->{_fvgs} }) {
        next unless defined $fvg->{hi} && defined $fvg->{lo};
        my $y_hi = $scales->value_to_y($fvg->{hi});
        my $y_lo = $scales->value_to_y($fvg->{lo});
        my $is_up = (defined $fvg->{type} && $fvg->{type} eq 'FVG_up');
        my $x0 = $scales->index_to_x($self->_local_index($fvg->{index}));
        # Rectángulo: (x0, y_hi) -> (w, y_lo). Su altura = |y_hi - y_lo| =
        # (hi - lo) escalado → más pequeño cuanto mayor mitig.
        $canvas->createRectangle(
            $x0, $y_hi, $w, $y_lo,
            -fill    => $is_up ? $self->_color('smc_fvg_up', '#26a69a')
                               : $self->_color('smc_fvg_down', '#ef5350'),
            -outline => $self->_color('smc_fvg_outline', '#787b86'),
            -stipple => 'gray50',
            -tags    => $tag,
        );
    }

    # --- Etiquetas de pivotes HH/HL/LL/LH ------------------------------------
    for my $p (@{ $self->{_pivots} }) {
        next unless defined $p->{index} && defined $p->{type};
        my $x = $scales->index_to_center_x($self->_local_index($p->{index}));
        my $y = defined $p->{price} ? $scales->value_to_y($p->{price}) : 0;
        $canvas->createText(
            $x, $y,
            -text   => $p->{type},
            -anchor => 'n',
            -font   => 'Helvetica 8 bold',
            -fill   => $self->_color('smc_pivot_label', '#363a45'),
            -tags   => $tag,
        );
    }

    # --- Etiquetas BOS / CHoCH (true vs false con estilo distinto) -----------
    for my $e (@{ $self->{_events} }) {
        next unless defined $e->{index} && defined $e->{type};
        next unless $e->{type} =~ /^(?:BOS|CHoCH_(?:true|false))$/;
        
        my $x_end = $scales->index_to_center_x($self->_local_index($e->{index}));
        my $y = defined $e->{price} ? $scales->value_to_y($e->{price}) : 0;
        my ($label, $color);
        my $dir = $e->{dir} // 'up';
        my $dir_color = $dir eq 'up' ? '#26a69a' : '#ef5350';
        if ($e->{type} eq 'BOS') {
            $label = 'BOS';
            $color = $self->{theme}{smc_bos} // $dir_color;
        } elsif ($e->{type} eq 'CHoCH_true') {
            $label = 'CHoCH';
            $color = $self->{theme}{smc_choch_true} // $dir_color;
        } else {
            $label = 'ICHoCH';
            $color = $self->{theme}{smc_choch_false} // $dir_color;
        }

        # Dibuja la línea entrecortada si tiene start_index
        my $x_label = $x_end;
        if (defined $e->{start_index}) {
            my $x_start = $scales->index_to_center_x($self->_local_index($e->{start_index}));
            $canvas->createLine(
                $x_start, $y, $x_end, $y,
                -dash  => [3, 3],
                -fill  => $color,
                -width => 1,
                -tags  => $tag,
            );
            $x_label = ($x_start + $x_end) / 2;
        }

        $canvas->createText(
            $x_label, $y,
            -text   => $label,
            -anchor => 's',
            -font   => 'Helvetica 8 bold',
            -fill   => $color,
            -tags   => $tag,
        );
    }

    return $self;
}

# clear($canvas) — borra solo los ítems de este overlay (tag `ov_smc`).
sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    $canvas->delete($self->tag());
    return $self;
}

# --- helpers para tests -------------------------------------------------------
# compute_range: retorna [start, end] recibido en compute_visible (verifica que
# no recorre todo el historial).
sub compute_range {
    my ($self) = @_;
    return $self->{_compute_range};
}

# visible_items: retorna todos los items que el overlay dibujará en draw(),
# combinados (para replay guard vía IndicatorSnapshot->replay_violations).
sub visible_items {
    my ($self) = @_;
    return [
        @{ $self->{_pivots} },
        @{ $self->{_events} },
        @{ $self->{_fvgs}   },
        @{ $self->{_fibs}   },
        @{ $self->{_major}  },
    ];
}

1;
