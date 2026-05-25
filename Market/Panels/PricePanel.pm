package Market::Panels::PricePanel;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        %args,
    };
    bless $self, $class;
    return $self;
}

# Inicializa los IDs de los objetos Tk del crosshair en undef.
sub _init_crosshair_objects {
    my ($self) = @_;
    $self->{_ch_vline}    = undef;
    $self->{_ch_hline}    = undef;
    $self->{_ch_label}    = undef;
    $self->{_ch_label_bg} = undef;
}

# Redondeo auxiliar al entero más cercano.
sub round {
    my ($self, $value) = @_;
    return 0 unless defined $value;
    return int($value + ($value >= 0 ? 0.5 : -0.5));
}

# Calcula el rango de precios (min, max) de las velas visibles para escalar el eje Y.
# Recibe arrayref de velas [ts, open, high, low, close, vol].
# Devuelve (min_price, max_price) con un padding del 2%.
sub get_y_range {
    my ($self, $data) = @_;
    return (20000, 30000) if !$data || !@$data;

    my $min = $data->[0]->[3];
    my $max = $data->[0]->[2];

    for my $candle (@$data) {
        next unless defined $candle;
        $min = $candle->[3] if $candle->[3] < $min;
        $max = $candle->[2] if $candle->[2] > $max;
    }

    my $padding = ($max - $min) * 0.02 || 1;
    return ($min - $padding, $max + $padding);
}

# Asigna el objeto Scales a este panel.
sub set_scale {
    my ($self, $scale) = @_;
    $self->{scale} = $scale;
}

# Dibuja todas las velas japonesas visibles sobre el canvas Tk.
# Inyecta width/height del canvas en el objeto scale antes de usarlo.
# Guarda la última vela en $self->{_last_candle} para render_last_visible_price.
sub render {
    my ($self, $canvas, $data, $scale) = @_;

    $canvas->delete('candle');
    $canvas->delete('price_label');
    $canvas->delete('y_scale');

    return if !$data || !@$data;

    # Inyectar dimensiones del canvas en el objeto scale
    $scale->{width}  = $canvas->width();
    $scale->{height} = $canvas->height();

    # Guardar la última vela para render_last_visible_price
    $self->{_last_candle} = $data->[-1];

    my $total  = scalar(@$data);
    my $bar_w  = ($total > 0) ? ($scale->{width} / $total) : 1;
    my $half   = ($bar_w * 0.6) / 2;

    for (my $i = 0; $i < $total; $i++) {
        my $candle = $data->[$i];
        next unless defined $candle;

        my ($ts, $open, $high, $low, $close, $vol) = @$candle;

        my $cx  = $scale->index_to_center_x($i);
        my $y_o = $scale->value_to_y($open);
        my $y_h = $scale->value_to_y($high);
        my $y_l = $scale->value_to_y($low);
        my $y_c = $scale->value_to_y($close);

        # Verde para velas alcistas, rojo para bajistas
        my $color = ($close >= $open) ? '#26a69a' : '#ef5350';

        # Mecha: línea delgada entre high y low
        $canvas->createLine(
            $cx, $y_h, $cx, $y_l,
            -fill  => '#aaaaaa',
            -width => 1,
            -tags  => 'candle',
        );

        # Cuerpo: rectángulo entre open y close
        my $top    = ($y_o < $y_c) ? $y_o : $y_c;
        my $bottom = ($y_o > $y_c) ? $y_o : $y_c;
        $bottom = $top + 1 if ($bottom - $top) < 1;

        $canvas->createRectangle(
            $cx - $half, $top,
            $cx + $half, $bottom,
            -fill    => $color,
            -outline => $color,
            -tags    => 'candle',
        );
    }

    $scale->_draw_y_scale($canvas);
    $self->render_last_visible_price($canvas);
}

# Dibuja la etiqueta con el precio de cierre de la última vela visible
# en el margen derecho del canvas a la altura del precio.
sub render_last_visible_price {
    my ($self, $canvas) = @_;

    $canvas->delete('price_label');
    my $scale = $self->{scale};
    return unless defined $scale && defined $self->{_last_candle};

    my $close = $self->{_last_candle}->[4];
    return unless defined $close;

    my $y     = $scale->value_to_y($close);
    my $w     = $scale->{width};
    my $label = sprintf("%.2f", $close);

    $canvas->createRectangle(
        $w - 68, $y - 7, $w, $y + 7,
        -fill    => '#1e3a5f',
        -outline => '#5599cc',
        -tags    => 'price_label',
    );
    $canvas->createText(
        $w - 66, $y,
        -text   => $label,
        -anchor => 'w',
        -font   => 'Helvetica 9 bold',
        -fill   => '#ffffff',
        -tags   => 'price_label',
    );
}

# Dibuja el crosshair en este panel. Si x o y son undef, borra el crosshair.
# La coordenada X es compartida con el ATRPanel para sincronización temporal.
sub draw_crosshair {
    my ($self, $x, $y) = @_;

    my $canvas = $self->{canvas};
    return unless defined $canvas;

    $canvas->delete('price_crosshair');
    return unless defined $x;

    my $w = $canvas->width();
    my $h = $canvas->height();

    # Línea vertical (sincronizada con ATRPanel)
    $canvas->createLine(
        $x, 0, $x, $h,
        -fill  => '#cccccc',
        -dash  => [4, 4],
        -width => 1,
        -tags  => 'price_crosshair',
    );

    # Línea horizontal y etiqueta de precio bajo el cursor
    if (defined $y) {
        $canvas->createLine(
            0, $y, $w, $y,
            -fill  => '#cccccc',
            -dash  => [4, 4],
            -width => 1,
            -tags  => 'price_crosshair',
        );

        my $scale = $self->{scale};
        if (defined $scale) {
            my $value = $scale->y_to_value($y);
            my $label = sprintf("%.2f", $value);

            $canvas->createRectangle(
                $w - 68, $y - 7, $w, $y + 7,
                -fill    => '#333344',
                -outline => '#cccccc',
                -tags    => 'price_crosshair',
            );
            $canvas->createText(
                $w - 66, $y,
                -text   => $label,
                -anchor => 'w',
                -font   => 'Helvetica 9 bold',
                -fill   => '#ffffff',
                -tags   => 'price_crosshair',
            );
        }
    }
}

# Dibuja las etiquetas de tiempo en el eje X inferior del panel de precios.
# Recibe arrayref de { index => N, text => 'HH:MM' } desde ChartEngine.
sub draw_time_axis {
    my ($self, $canvas, $timestamps) = @_;

    $canvas->delete('time_axis');
    return unless $timestamps && @$timestamps;

    my $scale = $self->{scale};
    return unless defined $scale;

    my $h = $canvas->height();

    for my $item (@$timestamps) {
        my $idx  = $item->{index};
        my $text = $item->{text};
        next unless defined $idx && defined $text;

        my $x = $scale->index_to_center_x($idx);

        # Línea de referencia vertical tenue
        $canvas->createLine(
            $x, 0, $x, $h,
            -fill => '#222222',
            -tags => 'time_axis',
        );

        # Etiqueta horaria
        $canvas->createText(
            $x, $h - 2,
            -text   => $text,
            -anchor => 's',
            -font   => 'Helvetica 8',
            -fill   => '#888888',
            -tags   => 'time_axis',
        );
    }
}

1;
