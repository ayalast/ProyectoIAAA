package Market::Panels::ATRPanel;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        %args,
        crosshair_objects => []
    };
    # El tema (paleta clara) se inyecta vía `theme => \%theme` desde ChartEngine.
    # Garantizar robustez: si no llega, dejar un hashref vacío para que las lecturas
    # posteriores (con defaults //) sean seguras.
    $self->{theme} = {} unless defined $self->{theme};
    bless $self, $class;
    return $self;
}

# Inicializa la lista de objetos del crosshair.
sub _init_crosshair {
    my ($self) = @_;
    $self->{crosshair_objects} = [];
}

sub _canvas_size {
    my ($self, $canvas) = @_;
    my ($w, $h) = (0, 0);
    my $geom = eval { $canvas->geometry() };
    if (defined $geom && $geom =~ /^(\d+)x(\d+)/) {
        ($w, $h) = ($1, $2);
    }
    $w ||= eval { $canvas->Width() }  || eval { $canvas->width() }  || 1;
    $h ||= eval { $canvas->Height() } || eval { $canvas->height() } || 1;
    $w = 1 if $w < 1;
    $h = 1 if $h < 1;
    return ($w, $h);
}

# Calcula el rango de valores del ATR visible para escalar el eje Y del sub-panel.
# Devuelve (min, max) con padding del 5%.
sub get_y_range {
    my ($self, $visible_values) = @_;

    return (0, 100) if !@$visible_values;

    my @defined = grep { defined $_ } @$visible_values;
    return (0, 100) unless @defined;

    my $min = $defined[0];
    my $max = $defined[0];

    foreach my $val (@defined) {
        $min = $val if $val < $min;
        $max = $val if $val > $max;
    }

    my $padding = ($max - $min) * 0.05 || 1;
    return ($min - $padding, $max + $padding);
}

# Asigna el objeto Scales a este panel.
sub set_scale {
    my ($self, $scale) = @_;
    $self->{scale} = $scale;
}

# Dibuja la línea del ATR como polilínea sobre el canvas Tk.
# Inyecta width/height del canvas en el objeto scale antes de usarlo.
# Guarda el último valor definido para render_last_visible_value.
sub render {
    my ($self, $canvas, $visible_values, $scale) = @_;

    $canvas->delete('all');

    return if !@$visible_values;

    # Inyectar dimensiones del canvas en el objeto scale
    my ($canvas_w, $canvas_h) = $self->_canvas_size($canvas);
    # ChartEngine puede inyectar un ancho compartido para sincronizar X con precio.
    $scale->{width}  ||= $canvas_w;
    $scale->{height} = $canvas_h;

    # Inyectar colores de eje del tema en la escala antes de dibujar el eje Y.
    # La conversión datos↔píxeles sigue viviendo en Scales; aquí solo se le pasan
    # los colores claros (con defaults seguros si el tema no está disponible).
    $scale->{grid_color}      = $self->{theme}{grid}      // '#e6e6e6';
    $scale->{axis_text_color} = $self->{theme}{axis_text} // '#363a45';

    $scale->_draw_y_scale($canvas);
    $canvas->lower('y_grid');

    # spec 0000i: overscan. draw_start_offset permite índices locales negativos.
    my $draw_offset = $scale->{draw_start_offset} || 0;
    my $visible_count = $scale->{visible_count} || scalar(@$visible_values);

    my @points;
    $self->{_last_value} = undef;

    # Último valor visible (no overscan) para render_last_visible_value.
    my $last_vis_idx = -$draw_offset + $visible_count - 1;
    $last_vis_idx = $#$visible_values if $last_vis_idx > $#$visible_values;
    $last_vis_idx = $#$visible_values if $last_vis_idx < 0;

    my $total = scalar(@$visible_values);
    my $x_bars = $scale->{bars} || $total || 1;
    my $bar_w = ($x_bars > 0) ? ($scale->plot_width() / $x_bars) : 1;

    if ($bar_w < 2) {
        my $plot_w = int($scale->plot_width());
        $plot_w = 1 if $plot_w < 1;
        for my $px (0 .. $plot_w - 1) {
            my $from_local = int($px * $x_bars / $plot_w);
            my $to_local = int((($px + 1) * $x_bars / $plot_w) - 1);
            $to_local = $from_local if $to_local < $from_local;
            my $from = $from_local - $draw_offset;
            my $to = $to_local - $draw_offset;
            $to = $from if $to < $from;
            $to = $total - 1 if $to >= $total;
            $from = 0 if $from < 0;

            my ($sum, $count);
            for my $i ($from .. $to) {
                my $val = $visible_values->[$i];
                next if !defined $val;
                $sum += $val;
                $count++;
            }
            next unless $count;
            push @points, ($px + 0.5, $scale->value_to_y($sum / $count));
        }
        # _last_value from visible window only
        for (my $i = $last_vis_idx; $i >= 0; $i--) {
            if (defined $visible_values->[$i]) {
                $self->{_last_value} = $visible_values->[$i];
                last;
            }
        }
    } else {
        for (my $i = 0; $i < @$visible_values; $i++) {
            my $val = $visible_values->[$i];
            next if !defined $val;

            my $x = $scale->index_to_center_x($i + $draw_offset);
            my $y = $scale->value_to_y($val);

            push @points, ($x, $y);
        }
        # _last_value from visible window only
        for (my $i = $last_vis_idx; $i >= 0; $i--) {
            if (defined $visible_values->[$i]) {
                $self->{_last_value} = $visible_values->[$i];
                last;
            }
        }
    }

    if (@points >= 4) {
        my $atr_color = $self->{theme}{atr_line} // '#2962ff';
        $canvas->createLine(@points, -fill => $atr_color, -width => 1.5, -tags => 'atr_line');
        $canvas->raise('atr_line');
    }

    $self->render_last_visible_value($canvas);
}

# Muestra la etiqueta del último valor visible del ATR en el margen derecho.
sub render_last_visible_value {
    my ($self, $canvas) = @_;

    $canvas->delete('atr_last_label');

    my $scale = $self->{scale};
    return unless defined $scale;
    return if exists $scale->{draw_last_label} && !$scale->{draw_last_label};
    return unless defined $self->{_last_value};

    my $val   = $self->{_last_value};
    my $y     = $scale->value_to_y($val);
    my $w     = $scale->{width};
    my $label = sprintf("%.4f", $val);
    my $label_bg = $self->{theme}{last_price_bg} // '#363a45';
    my $label_fg = $self->{theme}{last_price_fg} // '#ffffff';
    my $line     = $self->{theme}{atr_line}      // '#2962ff';

    $canvas->createRectangle(
        $w - 68, $y - 7, $w, $y + 7,
        -fill    => $label_bg,
        -outline => $line,
        -tags    => 'atr_last_label',
    );
    $canvas->createText(
        $w - 66, $y,
        -text   => $label,
        -anchor => 'w',
        -font   => 'Helvetica 9 bold',
        -fill   => $label_fg,
        -tags   => 'atr_last_label',
    );
}

# Dibuja el crosshair sincronizado en el sub-panel del ATR.
# La coordenada X es la misma que en PricePanel (sincronización temporal): la línea
# vertical en $x queda alineada con el panel de precios. La línea horizontal en $y solo
# se dibuja cuando $y está definido. Ambas usan el color `crosshair_line` del tema claro
# (gris '#9598a1', visible sobre fondo blanco) con default seguro si el tema no se
# inyectó, sustituyendo el antiguo 'gray' hardcodeado. Se conserva el estilo punteado
# (-dash) y el borrado previo de los objetos 'atr_crosshair'.
sub draw_crosshair {
    my ($self, $x, $y) = @_;

    my $canvas = $self->{canvas};
    return unless defined $canvas;

    $canvas->delete('atr_crosshair');

    my ($width, $height) = $self->_canvas_size($canvas);

    # Color del crosshair tomado del tema (con default seguro para tema claro).
    my $crosshair_color = $self->{theme}{crosshair_line} // '#9598a1';

    $canvas->createLine(
        $x, 0, $x, $height,
        -fill => $crosshair_color,
        -dash => '.',
        -tags => 'atr_crosshair',
    ) if defined $x;

    $canvas->createLine(
        0, $y, $width, $y,
        -fill => $crosshair_color,
        -dash => '.',
        -tags => 'atr_crosshair',
    ) if defined $y;
}

1;
