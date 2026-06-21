package Market::Overlays::Example;
use strict;
use warnings;

# Market::Overlays::Example — overlay trivial de prueba (spec 0003).
#
# Dibuja una línea horizontal punteada en el precio del último close visible.
# Solo procesa la ventana visible (no recorre todo el historial).
# Se elimina o se deja como referencia; valida el patrón base de overlays.

sub new {
    my ($class, %args) = @_;
    my $self = {
        canvas   => $args{canvas},
        theme    => $args{theme} || {},
        visible  => 1,
        _items   => [],
        _last_close => undef,
        _compute_range => undef,
    };
    bless $self, $class;
    return $self;
}

sub tag { 'ov_example' }

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
# Solo procesa la ventana [start, end]. Guarda el rango para que el test
# pueda verificar que no recorre todo el historial.
sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $self->{_compute_range} = [$start, $end];
    $self->{_last_close} = undef;

    # Buscar el último close definido en la ventana visible.
    for my $i (reverse $start .. $end) {
        next if $i < 0 || $i >= $market_data->size();
        my $candle = $market_data->get_candle($i);
        next unless defined $candle;
        $self->{_last_close} = $candle->[4];  # close
        last;
    }

    return $self;
}

# draw($canvas, $scales) — dibuja línea horizontal en el último close.
sub draw {
    my ($self, $canvas, $scales) = @_;
    return unless $self->{visible};
    return unless defined $self->{_last_close};
    return unless $canvas && $scales;

    $self->clear($canvas);

    my $y = $scales->value_to_y($self->{_last_close});
    my $w = $scales->{width} || 900;

    my $color = $self->{theme}{overlay_example} // '#2962ff';
    $canvas->createLine(
        0, $y, $w, $y,
        -fill  => $color,
        -dash  => [4, 4],
        -width => 1,
        -tags  => $self->tag(),
    );
}

# clear($canvas) — borra solo los ítems de este overlay (tag propio).
sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    $canvas->delete($self->tag());
}

# compute_range — helper para tests: retorna el rango [start, end] que
# compute_visible recibió. Permite verificar que no recorre todo el historial.
sub compute_range {
    my ($self) = @_;
    return $self->{_compute_range};
}

1;
