package Market::Panels::ATRPanel;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
l
    my $self = {
        %args,
        crosshair_objects => []
    };
    bless $self, $class;
    return $self;
}

# Inicializa la lista de objetos del crosshair.
sub _init_crosshair {
    my ($self) = @_;
    $self->{crosshair_objects} = [];
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

    $canvas->delete('atr_line');
    $canvas->delete('atr_last_label');
    $canvas->delete('y_scale');

    return if !@$visible_values;

    # Inyectar dimensiones del canvas en el objeto scale
    $scale->{width}  = $canvas->width();
    $scale->{height} = $canvas->height();

    $scale->_draw_y_scale($canvas);

    my @points;
    $self->{_last_value} = undef;

    for (my $i = 0; $i < @$visible_values; $i++) {
        my $val = $visible_values->[$i];
        next if !defined $val;

        my $x = $scale->index_to_x($i);
        my $y = $scale->value_to_y($val);

        push @points, ($x, $y);
        $self->{_last_value} = $val;
    }

    if (@points >= 4) {
        $canvas->createLine(@points, -fill => 'blue', -width => 1.5, -tags => 'atr_line');
    }

    $self->render_last_visible_value($canvas);
}

# Muestra la etiqueta del último valor visible del ATR en el margen derecho.
sub render_last_visible_value {
    my ($self, $canvas) = @_;

    $canvas->delete('atr_last_label');

    my $scale = $self->{scale};
    return unless defined $scale;
    return unless defined $self->{_last_value};

    my $val   = $self->{_last_value};
    my $y     = $scale->value_to_y($val);
    my $w     = $scale->{width};
    my $label = sprintf("%.4f", $val);

    $canvas->createRectangle(
        $w - 68, $y - 7, $w, $y + 7,
        -fill    => '#1e1e2e',
        -outline => '#2196f3',
        -tags    => 'atr_last_label',
    );
    $canvas->createText(
        $w - 66, $y,
        -text   => $label,
        -anchor => 'w',
        -font   => 'Helvetica 9 bold',
        -fill   => '#ffffff',
        -tags   => 'atr_last_label',
    );
}

# Dibuja el crosshair sincronizado en el sub-panel del ATR.
# La coordenada X es la misma que en PricePanel (sincronización temporal).
sub draw_crosshair {
    my ($self, $x, $y) = @_;

    my $canvas = $self->{canvas};
    return unless defined $canvas;

    $canvas->delete('atr_crosshair');

    $canvas->createLine(
        $x, 0, $x, $self->{height},
        -fill => 'gray',
        -dash => '.',
        -tags => 'atr_crosshair',
    ) if defined $x;

    $canvas->createLine(
        0, $y, $self->{width}, $y,
        -fill => 'gray',
        -dash => '.',
        -tags => 'atr_crosshair',
    ) if defined $y;
}

1;
