package Market::Overlays::Mxwll_Suite;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::Mxwll_Suite — render del "Mxwll Suite"
# =============================================================================
#
# Capa de RENDER (sin calculo). Consume Market::Indicators::Mxwll_Suite via
# get_values() y dibuja con tag `ov_mxwll`. Sigue el contrato de overlay:
#   new / set_visible / is_visible / compute_visible / draw / clear / tag.
#
# ELEMENTOS (toggle individual via set_element_visible):
#   STRUCTURE  — BOS/CHoCH (externos) + I-BoS/I-CHoCH (internos): linea
#                discontinua entre el swing y la ruptura + etiqueta.
#   SWINGS     — etiquetas HH/HL/LH/LL en los pivotes externos.
#   OB         — order blocks: cajas rojas (high) / azules (low), borde fino.
#   FVG        — fair value gaps: cajas amarillas semitransparentes (stipple).
#   AOE        — Area of Interest: zonas sup/inf con stipple.
#   FIBS       — linea de tendencia + niveles fib horizontales.
#
# Colores (paridad con el .pine de Mxwll):
#   bull #14D990, bear #F24968, fvg #F2B807, fib gray/lime/yellow/orange/red.
# =============================================================================

my %ELEMENTS = map { $_ => 1 } qw(STRUCTURE SWINGS OB FVG AOE FIBS);

my @FIB_COLORS = ('#808080', '#00ff00', '#ffff00', '#ffa500', '#ff0000');

sub new {
    my ($class, %args) = @_;
    die "Overlays::Mxwll_Suite->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _elements => { %ELEMENTS },
        _start    => 0,
        _end      => 0,
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_mxwll' }

sub set_visible {
    my ($self, $val) = @_;
    $self->{visible} = $val ? 1 : 0;
    return $self;
}

sub is_visible { $_[0]->{visible} ? 1 : 0 }

sub set_element_visible {
    my ($self, $elem, $bool) = @_;
    return $self unless defined $elem && exists $self->{_elements}{$elem};
    $self->{_elements}{$elem} = $bool ? 1 : 0;
    return $self;
}

sub is_element_visible {
    my ($self, $elem) = @_;
    return 0 unless defined $elem && exists $self->{_elements}{$elem};
    return $self->{_elements}{$elem};
}

sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    $canvas->delete($self->tag());
    return $self;
}

sub _local_index {
    my ($self, $global_idx) = @_;
    return $global_idx - ($self->{_start} // 0);
}

sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $self->{_start} = $start // 0;
    $self->{_end}   = $end   // 0;
    return $self;
}

sub _color {
    my ($self, $key, $default) = @_;
    return $self->{theme}{$key} // $default;
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return $self unless $self->{visible} && $self->{indicator};
    return $self unless $canvas && $scales;
    return $self unless defined $scales->{height} && $scales->{height} > 0;

    $self->clear($canvas);
    my $vals = $self->{indicator}->get_values();
    return $self unless $vals;

    my $tag   = $self->tag();
    my $start = $self->{_start} // 0;
    my $end   = $self->{_end}   // 0;
    my $w     = $scales->{width} || $scales->plot_width();

    # Borde derecho de las cajas/lineas: la ULTIMA vela visible (index $end),
    # no el borde del canvas. Replica TradingView, que corta los dibujos al
    # final de la ultima vela en vez de extenderlos al espacio vacio derecho.
    my $x_right = $scales->index_to_center_x($self->_local_index($end));
    $x_right = $w if $x_right > $w;

    my $bull = $self->_color('mxwll_bull', '#14D990');
    my $bear = $self->_color('mxwll_bear', '#F24968');

    # --- 1. Order blocks (cajas) ---
    if ($self->is_element_visible('OB')) {
        for my $z (@{ $vals->{high_blocks} // [] }) {
            $self->_draw_block($canvas, $scales, $tag, $x_right, $z, $bear);
        }
        for my $z (@{ $vals->{low_blocks} // [] }) {
            $self->_draw_block($canvas, $scales, $tag, $x_right, $z, '#2157f3');
        }
    }

    # --- 2. FVG (cajas amarillas) ---
    if ($self->is_element_visible('FVG')) {
        my $fcol = $self->_color('mxwll_fvg', '#F2B807');
        for my $g (@{ $vals->{fvgs} // [] }) {
            next if $g->{index} > $end;
            my $x0 = $scales->index_to_x($self->_local_index($g->{index}));
            next if $x0 > $x_right;
            my $x1 = $x_right;
            my $yt = $scales->value_to_y($g->{top});
            my $yb = $scales->value_to_y($g->{bottom});
            $canvas->createRectangle(
                $x0, $yt, $x1, $yb,
                -fill    => $fcol,
                -stipple => 'gray25',
                -outline => '',
                -tags    => $tag,
            );
        }
    }

    # --- 3. Area of Interest ---
    if ($self->is_element_visible('AOE') && $vals->{aoe}) {
        my $a = $vals->{aoe};
        my $x0 = $scales->index_to_x($self->_local_index($a->{from_index}));
        $x0 = 0 if $x0 < 0;
        my $x1 = $x_right;
        # zona alta (resistencia)
        $canvas->createRectangle(
            $x0, $scales->value_to_y($a->{high_top}), $x1, $scales->value_to_y($a->{high_bottom}),
            -fill => $bear, -stipple => 'gray12', -outline => '', -tags => $tag,
        );
        $canvas->createText(
            $x0 + 4, $scales->value_to_y($a->{high_top}) + 8,
            -text => 'Area of Interest', -anchor => 'w',
            -font => 'Helvetica 8', -fill => $bear, -tags => $tag,
        );
        # zona baja (soporte)
        $canvas->createRectangle(
            $x0, $scales->value_to_y($a->{low_top}), $x1, $scales->value_to_y($a->{low_bottom}),
            -fill => $bull, -stipple => 'gray12', -outline => '', -tags => $tag,
        );
        $canvas->createText(
            $x0 + 4, $scales->value_to_y($a->{low_bottom}) - 8,
            -text => 'Area of Interest', -anchor => 'w',
            -font => 'Helvetica 8', -fill => $bull, -tags => $tag,
        );
    }

    # --- 4. Auto Fibs ---
    if ($self->is_element_visible('FIBS') && $vals->{fibs}) {
        my $f = $vals->{fibs};
        my $fx1 = $scales->index_to_center_x($self->_local_index($f->{x1}));
        my $fy1 = $scales->value_to_y($f->{y1});
        my $fx2 = $scales->index_to_center_x($self->_local_index($f->{x2}));
        my $fy2 = $scales->value_to_y($f->{y2});
        my $trend_col = ($f->{y2} < $f->{y1}) ? $bear : $bull;
        $canvas->createLine($fx1, $fy1, $fx2, $fy2,
            -fill => $trend_col, -width => 2, -dash => [4,4], -tags => $tag);
        my $i = 0;
        for my $lv (@{ $f->{levels} }) {
            my $y  = $scales->value_to_y($lv->{price});
            my $col = $FIB_COLORS[$i % scalar(@FIB_COLORS)];
            $canvas->createLine($fx2, $y, $x_right, $y,
                -fill => $col, -width => 1, -tags => $tag);
            $canvas->createText($x_right - 2, $y - 5,
                -text => sprintf('%.3f', $lv->{ratio}), -anchor => 'e',
                -font => 'Helvetica 7', -fill => $col, -tags => $tag);
            $i++;
        }
    }

    # --- 5. Estructura (BOS/CHoCH + I-BoS/I-CHoCH) ---
    if ($self->is_element_visible('STRUCTURE')) {
        for my $s (@{ $vals->{structures} // [] }) {
            next if $s->{to} > $end;
            my $xf = $scales->index_to_center_x($self->_local_index($s->{from}));
            my $xt = $scales->index_to_center_x($self->_local_index($s->{to}));
            my $y  = $scales->value_to_y($s->{price});
            next if $xt < 0;
            my $col = $s->{dir} eq 'up' ? $bull : $bear;
            $canvas->createLine($xf, $y, $xt, $y,
                -fill => $col, -width => 1, -dash => [4,4], -tags => $tag);
            my $mid = ($xf + $xt) / 2;
            my $anchor = $s->{dir} eq 'up' ? 's' : 'n';
            my $dy = $s->{dir} eq 'up' ? -3 : 3;
            $canvas->createText($mid, $y + $dy,
                -text => $s->{label}, -anchor => $anchor,
                -font => $s->{internal} ? 'Helvetica 7' : 'Helvetica 8 bold',
                -fill => $col, -tags => $tag);
        }
    }

    # --- 6. Swings HH/HL/LH/LL ---
    if ($self->is_element_visible('SWINGS')) {
        for my $sw (@{ $vals->{swings} // [] }) {
            next if $sw->{index} > $end;
            my $x = $scales->index_to_center_x($self->_local_index($sw->{index}));
            next if $x < 0 || $x > $w;
            my $y = $scales->value_to_y($sw->{price});
            my $col = $sw->{dir} eq 'up' ? $bear : $bull;
            my $anchor = $sw->{dir} eq 'up' ? 's' : 'n';
            my $dy = $sw->{dir} eq 'up' ? -4 : 4;
            $canvas->createText($x, $y + $dy,
                -text => $sw->{label}, -anchor => $anchor,
                -font => 'Helvetica 8 bold', -fill => $col, -tags => $tag);
        }
    }

    return $self;
}

sub _draw_block {
    my ($self, $canvas, $scales, $tag, $right, $z, $color) = @_;
    return if $z->{index} > $self->{_end};
    my $x0 = $scales->index_to_x($self->_local_index($z->{index}));
    my $x1 = $right;
    return if $x1 < 0;
    $x0 = 0 if $x0 < 0;
    my $yt = $scales->value_to_y($z->{top});
    my $yb = $scales->value_to_y($z->{bottom});
    $canvas->createRectangle(
        $x0, $yt, $x1, $yb,
        -fill    => '',
        -outline => $color,
        -width   => 1,
        -tags    => $tag,
    );
    return;
}

1;
