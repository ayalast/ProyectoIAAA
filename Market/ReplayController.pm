package Market::ReplayController;
use strict;
use warnings;

# Market::ReplayController — control del índice-tope de Replay (spec 0002).
#
# Mantiene un replay_idx que ninguna capa (render, indicadores, overlays) puede
# superar. Cuando está activo, compute_window y todo el pipeline ven el dataset
# como si terminara en replay_idx. Sin UI aquí (task 0004).

sub new {
    my ($class, %args) = @_;
    my $self = {
        market_data => $args{market_data},
        active      => 0,
        replay_idx  => undef,
        playing     => 0,
        speed       => $args{speed} || 1,
        _timer_id   => undef,
        _timer_cb   => undef,
    };
    bless $self, $class;
    return $self;
}

# start($idx) — activa Replay con tope en $idx (clamp a [0, last_index]).
sub start {
    my ($self, $idx) = @_;
    my $last = $self->_last_index();
    $idx = 0 if !defined $idx || $idx < 0;
    $idx = $last if defined $last && $idx > $last;
    $self->{active} = 1;
    $self->{replay_idx} = $idx;
    $self->{playing} = 0;
    return $self;
}

# play — inicia reproducción automática via after($ms, $cb).
# $cb es una subrutina que se llama en cada tick; típicamente hace step_forward
# + request_render. El temporizador se guarda para poder cancelarlo con pause.
sub play {
    my ($self, $cb) = @_;
    return unless $self->{active};
    $self->{playing} = 1;
    $self->{_timer_cb} = $cb if defined $cb;
    $self->_schedule_timer();
    return $self;
}

# pause — detiene la reproducción automática.
sub pause {
    my ($self) = @_;
    $self->{playing} = 0;
    $self->_cancel_timer();
    return $self;
}

# step_forward — avanza replay_idx exactamente 1 (clamp al último).
sub step_forward {
    my ($self) = @_;
    return unless $self->{active};
    my $last = $self->_last_index();
    $self->{replay_idx}++ if defined $self->{replay_idx};
    $self->{replay_idx} = $last if defined $last && $self->{replay_idx} > $last;
    return $self->{replay_idx};
}

# step_backward — retrocede replay_idx exactamente 1 (clamp a 0).
sub step_backward {
    my ($self) = @_;
    return unless $self->{active};
    $self->{replay_idx}-- if defined $self->{replay_idx};
    $self->{replay_idx} = 0 if !defined $self->{replay_idx} || $self->{replay_idx} < 0;
    return $self->{replay_idx};
}

# fast_forward — avanza N velas (default: 10 * speed), clamp al último.
sub fast_forward {
    my ($self, $n) = @_;
    return unless $self->{active};
    $n //= 10 * ($self->{speed} || 1);
    my $last = $self->_last_index();
    $self->{replay_idx} += $n;
    $self->{replay_idx} = $last if defined $last && $self->{replay_idx} > $last;
    $self->pause() if defined $self->{replay_idx} && defined $last && $self->{replay_idx} >= $last;
    return $self->{replay_idx};
}

# exit — desactiva Replay y restaura tope = last_index.
sub exit {
    my ($self) = @_;
    $self->pause();
    $self->{active} = 0;
    $self->{replay_idx} = undef;
    return $self;
}

# current_index — retorna replay_idx o undef si no activo.
sub current_index {
    my ($self) = @_;
    return $self->{active} ? $self->{replay_idx} : undef;
}

# is_active — bool.
sub is_active {
    my ($self) = @_;
    return $self->{active} ? 1 : 0;
}

# effective_end($last_index) — retorna el índice efectivo superior para
# compute_window: min(replay_idx, last_index) si activo, o last_index si no.
sub effective_end {
    my ($self, $last_index) = @_;
    return $last_index unless $self->{active} && defined $self->{replay_idx};
    my $end = $self->{replay_idx};
    $end = $last_index if defined $last_index && $end > $last_index;
    return $end;
}

# set_speed($n) — cambia la velocidad de fast_forward.
sub set_speed {
    my ($self, $n) = @_;
    $self->{speed} = $n if defined $n && $n > 0;
    return $self;
}

# --- internals ---

sub _last_index {
    my ($self) = @_;
    return undef unless $self->{market_data};
    my $size = $self->{market_data}->size();
    return $size > 0 ? $size - 1 : 0;
}

sub _schedule_timer {
    my ($self) = @_;
    return unless $self->{playing} && $self->{_timer_cb};
    my $canvas = $self->{market_data};  # placeholder; el timer real se cablea en 0004
    # El temporizador Tk se cablea en task 0004 con after().
    # Aquí dejamos la infraestructura; el callback se invoca manualmente en tests.
}

sub _cancel_timer {
    my ($self) = @_;
    $self->{_timer_id} = undef;
}

1;
