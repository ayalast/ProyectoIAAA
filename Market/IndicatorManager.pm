package Market::IndicatorManager;
use strict;
use warnings;

# =============================================================================
# Market::IndicatorManager — contenedor de indicadores desacoplados (Capa Indicadores)
# =============================================================================
#
# CONTRATO DE DESACOPLE (Req. 13):
#   Pertenece a la CAPA DE INDICADORES. Es un contenedor genérico que registra y
#   coordina indicadores (p.ej. Market::Indicators::ATR) sin conocer NADA del
#   renderizado:
#     - NO referencia `Tk`, paneles ni coordenadas de pantalla.
#     - NO realiza conversión datos<->píxeles (eso vive solo en Scales.pm).
#     - NO usa variables globales: el registro vive en la instancia ($self).
#   Solo delega en cada indicador registrado (que debe implementar `update_last`
#   y `get_values`, y opcionalmente `reset`).
#
# RECÁLCULO AL CAMBIAR DE TIMEFRAME (Req. 13.4):
#   La VÍA OFICIAL de recálculo cuando cambia la temporalidad activa es:
#
#       reset_all()                      # 1) reinicia todos los indicadores
#       for $i (0 .. size-1):            # 2) recálculo incremental vela por vela
#           update_last($market_data, $i)
#
#   Este flujo lo dispara el orquestador ChartEngine::set_timeframe (ya existente),
#   tras reconstruir las velas de la nueva temporalidad en MarketData. Como cada
#   `update_last` del indicador es O(1) por vela (ver ATR.pm), recalcular N velas
#   cuesta O(N) y reproduce exactamente la serie batch (Req. 13.2, 13.3). El
#   IndicatorManager NO introduce dependencias de render para lograrlo.
#
# Métodos:
#   new                          — inicializa el contenedor vacío.
#   register($name,$indicator)   — registra un indicador (valida su interfaz).
#   update_last($market_data,$i) — propaga la vela a todos los indicadores (O(1) c/u).
#   get($name)                   — serie de valores de un indicador.
#   slice_array($name,$s,$e)     — porción de valores (ventana visible).
#   reset_all                    — reinicia todos los indicadores (al cambiar timeframe).
# =============================================================================

sub new {
    my ($class) = @_;
    my $self = {
        indicators => {},
    };
    bless $self, $class;
    return $self;
}

sub register {
    my ($self, $name, $indicator) = @_;
    die "register: name is required"      unless defined $name && length $name;
    die "register: indicator is required" unless defined $indicator;
    die "register: indicator '$name' does not implement update_last"
        unless $indicator->can('update_last');
    die "register: indicator '$name' does not implement get_values"
        unless $indicator->can('get_values');

    $self->{indicators}->{$name} = $indicator;
    return $self;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    return unless defined $market_data;

    for my $name (keys %{ $self->{indicators} }) {
        $self->{indicators}->{$name}->update_last($market_data, $index);
    }
    return;
}

sub get {
    my ($self, $name) = @_;
    my $indicator = $self->{indicators}->{$name};
    return undef unless $indicator;
    return $indicator->get_values();
}

sub slice_array {
    my ($self, $name, $start, $end) = @_;
    my $values = $self->get($name);
    return [] unless $values && @$values;
    return [] if !defined $start || !defined $end || $start > $end;

    my @slice;
    for my $i ($start .. $end) {
        push @slice, ($i >= 0 && $i <= $#$values) ? $values->[$i] : undef;
    }
    return \@slice;
}

sub reset_all {
    my ($self) = @_;
    # Paso 1 del recálculo al cambiar timeframe (Req. 13.4): reinicia cada
    # indicador. ChartEngine::set_timeframe llama a este método y luego recalcula
    # vela por vela con update_last (paso 2). Sin dependencias de render.
    for my $name (keys %{ $self->{indicators} }) {
        my $indicator = $self->{indicators}->{$name};
        $indicator->reset() if $indicator->can('reset');
    }
    return;
}

1;
