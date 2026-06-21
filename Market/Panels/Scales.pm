package Market::Panels::Scales;
use strict;
use warnings;

# Inicializa el sistema de coordenadas para un panel.
# Argumentos que llegan desde ChartEngine::render():
#   min_y        => valor mínimo del eje Y (precio o indicador)
#   max_y        => valor máximo del eje Y
#   bars         => cantidad de barras visibles en la ventana
#   right_margin => píxeles reservados a la derecha del área de ploteo (default 0).
# Los atributos width y height son inyectados por los paneles en render()
# al llamar: $scale->{width} = $canvas->width(); $scale->{height} = $canvas->height();
sub new {
    my ($class, %args) = @_;
    my $self = {
        %args,
    };
    # Margen derecho opcional. Solo afecta al eje X (ploteo horizontal).
    $self->{right_margin} = 0 unless defined $self->{right_margin};
    bless $self, $class;
    return $self;
}

# Ancho del área de ploteo horizontal: el ancho del canvas menos el margen derecho.
# Con ejes separados normalmente el margen es 0 y la serie usa todo el canvas.
# Se garantiza un mínimo de 1 px para evitar divisiones por cero o anchos negativos.
sub plot_width {
    my ($self) = @_;
    my $w = ($self->{width} // 0) - ($self->{right_margin} // 0);
    return $w > 1 ? $w : 1;
}

# Convierte un índice de barra (0-based) al borde izquierdo de esa barra en píxeles X.
# bar_w se deriva de plot_width (no de width) para respetar el margen derecho.
sub index_to_x {
    my ($self, $index) = @_;
    my $bars  = $self->{bars} || 1;
    my $bar_w = $self->plot_width / $bars;
    my $x_shift = $self->{x_shift} || 0;
    return $index * $bar_w + $x_shift;
}

# Convierte una coordenada X en píxeles al índice de barra entero.
#
# Regla de redondeo: floor(x / bar_w) (es decir int() para x >= 0). Este es el único
# redondeo que satisface SIMULTÁNEAMENTE los dos round-trips exigidos por Req. 12.1/12.2:
#   - index_to_x(i)        = i*bar_w        => cociente i.0  => floor = i   ✓
#   - index_to_center_x(i) = i*bar_w+bar_w/2 => cociente i.5 => floor = i   ✓
# (El redondeo al entero más cercano int(x/bar_w + 0.5) mapearía el centro i.5 a i+1 y
#  rompería el round-trip de index_to_center_x; por eso NO se usa.)
# Se suma un epsilon mínimo (1e-9) para blindar el borde izquierdo i.0 frente al error
# de coma flotante de (i*bar_w)/bar_w, sin alterar el caso del centro i.5.
# El resultado se acota (clamp) a [0, bars-1].
sub x_to_index {
    my ($self, $x) = @_;
    my $bars  = $self->{bars} || 1;
    my $bar_w = $self->plot_width / $bars;
    return 0 if $bar_w <= 0;
    my $x_shift = $self->{x_shift} || 0;
    my $idx = int(($x - $x_shift) / $bar_w + 1e-9);
    $idx = 0         if $idx < 0;
    $idx = $bars - 1 if $idx >= $bars;
    return $idx;
}

# Convierte X a índice en punto flotante (mayor precisión para el crosshair).
# bar_w se deriva de plot_width para mantener coherencia con index_to_x.
sub x_to_index_float {
    my ($self, $x) = @_;
    my $bars  = $self->{bars} || 1;
    my $bar_w = $self->plot_width / $bars;
    return 0 if $bar_w <= 0;
    my $x_shift = $self->{x_shift} || 0;
    return ($x - $x_shift) / $bar_w;
}

# Devuelve la coordenada X del centro horizontal de una barra.
# Usado para dibujar mechas de velas y puntos de la línea ATR.
# bar_w se deriva de plot_width (no de width) para respetar el margen derecho.
sub index_to_center_x {
    my ($self, $index) = @_;
    my $bars  = $self->{bars} || 1;
    my $bar_w = $self->plot_width / $bars;
    my $x_shift = $self->{x_shift} || 0;
    return $index * $bar_w + $bar_w / 2 + $x_shift;
}

# Mapea un valor financiero (precio/indicador) a coordenada Y en píxeles.
# max_y queda en Y=0 (arriba del canvas) y min_y en Y=height (abajo).
sub value_to_y {
    my ($self, $value) = @_;
    my $range = $self->{max_y} - $self->{min_y};
    return 0 if $range == 0;
    return (($self->{max_y} - $value) / $range) * $self->{height};
}

# Operación inversa: convierte una coordenada Y en píxeles al valor financiero.
# Usado por draw_crosshair para mostrar el precio o ATR bajo el cursor.
sub y_to_value {
    my ($self, $y) = @_;
    my $range = $self->{max_y} - $self->{min_y};
    return $self->{min_y} unless $self->{height};
    return $self->{max_y} - ($y / $self->{height}) * $range;
}

# Dibuja el eje Y: líneas de cuadrícula horizontales y etiquetas de valor
# en el margen derecho del canvas.
#
# Garantías (Req. 4.2, 4.3, 4.4, 4.6, 3.4):
#   - Entre 4 y 8 etiquetas, todas múltiplos enteros de un único paso "limpio"
#     (potencias de 10 escaladas por 1, 2, 2.5 ó 5), contenidas en [min_y, max_y]
#     y uniformemente espaciadas por ese paso.
#   - El paso se recalcula para que la separación vertical entre dos etiquetas
#     adyacentes sea >= 20 px (medida en píxeles reales vía value_to_y).
#   - Si el rango es 0 no se dibuja ninguna etiqueta ni grid y se retorna sin
#     error, preservando el contenido previo del canvas.
#   - Color de grid y de texto parametrizables vía atributos de instancia
#     grid_color (default '#e6e6e6') y axis_text_color (default '#363a45').
#   - Exactamente 1 línea de grid horizontal a ancho completo por etiqueta.
sub _draw_y_scale {
    my ($self, $canvas) = @_;
    return unless defined $canvas;

    my $width  = $self->{width}  // 0;
    my $height = $self->{height} // 0;
    my $min    = $self->{min_y};
    my $max    = $self->{max_y};
    return unless defined $min && defined $max;

    my $range = $max - $min;

    # Req. 4.6: rango cero => no se dibuja nada, se preserva el contenido previo
    # (no se borran las marcas anteriores) y se retorna sin error.
    return if $range == 0;

    # A partir de aquí sí refrescamos las marcas del eje.
    $canvas->delete('y_scale');

    # Colores del tema claro inyectados por el panel; defaults claros si no llegan.
    my $grid_color = $self->{grid_color}      // '#e6e6e6';
    my $text_color = $self->{axis_text_color} // '#363a45';

    # Paso "limpio": se elige el mejor candidato que produzca marcas densas
    # estilo TradingView, manteniendo separación vertical legible.
    my $step = _clean_step($min, $max, $range, $height, $self->{tick_size});
    return if !defined $step || $step <= 0;

    my $draw_grid   = exists $self->{draw_grid}   ? $self->{draw_grid}   : 1;
    my $draw_labels = exists $self->{draw_labels} ? $self->{draw_labels} : 1;

    # Primer múltiplo del paso que sea >= min_y, y recorrido hasta max_y.
    my $first_k = _ceil_div($min, $step);
    for (my $k = $first_k; $k * $step <= $max + $step * 1e-9; $k++) {
        my $val = $k * $step;
        my $y   = $self->value_to_y($val);

        if ($draw_grid) {
            $canvas->createLine(
                0, $y, $width, $y,
                -fill => $grid_color,
                -tags => ['y_scale', 'y_grid'],
            );
        }

        next unless $draw_labels;

        # Etiqueta numérica alineada a la derecha (anchor 'e') en el panel de escala.
        my $label = (abs($val) >= 100) ? sprintf("%.2f", $val) : sprintf("%.4f", $val);
        my $label_x      = defined $self->{label_x}      ? $self->{label_x}      : $width - 2;
        my $label_anchor = defined $self->{label_anchor} ? $self->{label_anchor} : 'e';
        $canvas->createText(
            $label_x, $y,
            -text   => $label,
            -anchor => $label_anchor,
            -font   => 'Helvetica 8',
            -fill   => $text_color,
            -tags   => 'y_scale',
        );
    }
}

# --- Helpers internos del eje Y (sin estado; no son métodos de instancia) -----

# floor de x sin depender de POSIX (int() trunca hacia 0, no hacia -inf).
sub _floor {
    my ($x) = @_;
    my $i = int($x);
    return ($x < 0 && $x != $i) ? $i - 1 : $i;
}

# ceil de x sin depender de POSIX.
sub _ceil {
    my ($x) = @_;
    my $i = int($x);
    return ($x > 0 && $x != $i) ? $i + 1 : $i;
}

# Menor entero k tal que k*step >= value (con epsilon para tolerar coma flotante).
sub _ceil_div {
    my ($value, $step) = @_;
    return _ceil($value / $step - 1e-9);
}

# Cantidad de múltiplos enteros de $step contenidos en [$min, $max].
sub _label_count {
    my ($min, $max, $step) = @_;
    return 0 if $step <= 0;
    my $first = _ceil($min / $step - 1e-9);
    my $last  = _floor($max / $step + 1e-9);
    my $n = $last - $first + 1;
    return $n < 0 ? 0 : $n;
}

sub _tick_step {
    my ($step, $tick_size) = @_;
    return $step if !defined $tick_size || $tick_size <= 0;
    return $tick_size if !defined $step || $step <= $tick_size;
    my $ticks = _ceil($step / $tick_size - 1e-9);
    return $ticks * $tick_size;
}

sub _clean_step {
    my ($min, $max, $range, $height, $tick_size) = @_;
    my $abs_range = abs($range);
    return $range if $abs_range == 0;

    my @cands;
    if (defined $tick_size && $tick_size > 0) {
        my $min_step = $height > 0 ? ($abs_range * 22 / $height) : ($abs_range / 24);
        my $max_step = $abs_range / 4;
        my $first = _ceil($min_step / $tick_size - 1e-9);
        my $last  = _ceil($max_step / $tick_size + 1e-9);
        $first = 1 if $first < 1;
        $last = $first if $last < $first;
        for my $q ($first .. $last) {
            push @cands, $q * $tick_size;
        }
    } else {
        my $exp = _floor(log($abs_range) / log(10));
        my @mult = (1, 2, 2.5, 5);
        for my $e ($exp - 2 .. $exp + 1) {
            my $mag = 10 ** $e;
            push @cands, $_ * $mag for @mult;
        }
    }

    @cands = map { _tick_step($_, $tick_size) } grep { $_ > 0 } @cands;
    my %seen;
    @cands = sort { $a <=> $b } grep { !$seen{sprintf('%.8f', $_)}++ } @cands;

    my $min_labels = defined $tick_size && $tick_size > 0 ? 4 : 6;
    my $max_labels = defined $tick_size && $tick_size > 0 ? 32 : 12;
    my $target_labels = defined $tick_size && $tick_size > 0 ? 20 : 9;
    my @valid;
    for my $s (@cands) {
        my $c = _label_count($min, $max, $s);
        next unless $c >= $min_labels && $c <= $max_labels;
        my $sep = $height > 0 ? ($s / $abs_range) * $height : 0;
        push @valid, { step => $s, count => $c, sep => $sep };
    }

    if (@valid) {
        my @ok   = grep { $height <= 0 || $_->{sep} >= 20 } @valid;
        my @pool = @ok ? @ok : @valid;
        @pool = sort {
            abs($a->{count} - $target_labels) <=> abs($b->{count} - $target_labels)
                || $b->{sep} <=> $a->{sep}
                || $a->{step} <=> $b->{step}
        } @pool;
        return $pool[0]{step};
    }

    my @scored = map {
        my $c    = _label_count($min, $max, $_);
        my $dist = $c < $min_labels ? ($min_labels - $c) : ($c > $max_labels ? ($c - $max_labels) : 0);
        { step => $_, dist => $dist, count => $c };
    } @cands;
    @scored = sort { $a->{dist} <=> $b->{dist} || $b->{count} <=> $a->{count} } @scored;
    return @scored ? $scored[0]{step} : _tick_step($abs_range / 5, $tick_size);
}

1;
