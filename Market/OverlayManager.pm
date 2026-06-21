package Market::OverlayManager;
use strict;
use warnings;

# Market::OverlayManager — registro de overlays (spec 0003).
#
# Registra overlays por nombre, itera los activos, delega draw/clear.
# ChartEngine lo invoca en render() tras dibujar paneles, respetando replay_idx.

sub new {
    my ($class) = @_;
    my $self = {
        overlays => {},  # name => overlay_instance
    };
    bless $self, $class;
    return $self;
}

# register($name, $overlay) — registra un overlay.
sub register {
    my ($self, $name, $overlay) = @_;
    die "register: name is required" unless defined $name && length $name;
    die "register: overlay is required" unless defined $overlay;
    $self->{overlays}->{$name} = $overlay;
    return $self;
}

# unregister($name) — elimina un overlay del registro.
sub unregister {
    my ($self, $name) = @_;
    delete $self->{overlays}->{$name};
    return $self;
}

# get($name) — retorna el overlay por nombre.
sub get {
    my ($self, $name) = @_;
    return $self->{overlays}->{$name};
}

# each_active — retorna lista de overlays visibles, ordenada por nombre.
sub each_active {
    my ($self) = @_;
    return grep { $_->is_visible() }
           map  { $self->{overlays}->{$_} }
           sort keys %{ $self->{overlays}};
}

# all — retorna todos los overlays registrados, ordenada por nombre.
sub all {
    my ($self) = @_;
    return map { $self->{overlays}->{$_} } sort keys %{ $self->{overlays} };
}

# set_visible($name, $bool) — activa/desactiva un overlay por nombre.
sub set_visible {
    my ($self, $name, $bool) = @_;
    my $ov = $self->{overlays}->{$name};
    return unless $ov;
    $ov->set_visible($bool);
    return $self;
}

# compute_all($market_data, $indicator, $start, $end) — prepara datos para
# todos los overlays activos. respeta replay_idx: $end ya viene truncado
# por ChartEngine.compute_window cuando Replay está activo.
sub compute_all {
    my ($self, $market_data, $start, $end) = @_;
    for my $ov ($self->all()) {
        $ov->compute_visible($market_data, undef, $start, $end);
    }
    return $self;
}

# draw_all($canvas, $scales) — dibuja todos los overlays activos.
sub draw_all {
    my ($self, $canvas, $scales) = @_;
    for my $ov ($self->each_active()) {
        $ov->draw($canvas, $scales);
    }
    return $self;
}

# clear_all($canvas) — borra todos los overlays (visibles o no).
sub clear_all {
    my ($self, $canvas) = @_;
    for my $ov ($self->all()) {
        $ov->clear($canvas);
    }
    return $self;
}

1;
