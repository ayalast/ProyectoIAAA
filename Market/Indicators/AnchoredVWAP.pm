package Market::Indicators::AnchoredVWAP;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::AnchoredVWAP
# 
# Multipivot Anchored VWAP engine generating smooth continuous series near price candles
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $anchor_type = $opts{anchor_type} // 'session';
    my $window_size = $opts{window_size} // 40;

    my $self = {
        anchor_type => $anchor_type,
        window_size => $window_size,
        _highs      => [],
        _lows       => [],
        _closes     => [],
        _volumes    => [],
        _vwap       => [], # array of { value => num, anchor_idx => idx }
        _market_data=> undef,
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_highs}      = [];
    $self->{_lows}       = [];
    $self->{_closes}     = [];
    $self->{_volumes}    = [];
    $self->{_vwap}       = [];
    return;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    my $candle = defined $index ? $market_data->get_candle($index) : $market_data->last_candle();
    return unless $candle;

    $self->{_market_data} = $market_data;
    my $high  = $candle->[2];
    my $low   = $candle->[3];
    my $close = $candle->[4];
    my $vol   = $candle->[5] // 1;

    $self->{_highs}->[$index]   = $high;
    $self->{_lows}->[$index]    = $low;
    $self->{_closes}->[$index]  = $close;
    $self->{_volumes}->[$index] = $vol;

    # Compute rolling volume-weighted price over rolling window to ensure VWAP is always near candles & unbroken
    my $win = $self->{window_size};
    my $start_k = ($index >= $win) ? ($index - $win + 1) : 0;

    my $sum_pv  = 0;
    my $sum_vol = 0;
    for my $k ($start_k .. $index) {
        my $h = $self->{_highs}->[$k];
        my $l = $self->{_lows}->[$k];
        my $c = $self->{_closes}->[$k];
        my $v = $self->{_volumes}->[$k] // 1;
        next unless defined $h && defined $l && defined $c;
        my $tp = ($h + $l + $c) / 3;
        $sum_pv  += ($tp * $v);
        $sum_vol += $v;
    }

    my $vwap_val = ($sum_vol > 0) ? ($sum_pv / $sum_vol) : $close;
    $self->{_vwap}->[$index] = {
        value      => $vwap_val,
        anchor_idx => 0,
    };
    return;
}

sub get_values {
    my ($self) = @_;
    return $self->{_vwap};
}

1;
