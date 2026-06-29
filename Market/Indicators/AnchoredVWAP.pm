package Market::Indicators::AnchoredVWAP;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::AnchoredVWAP
# 
# Multipivot Anchored VWAP engine supporting session resets (Section 8 PDF)
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $anchor_type = $opts{anchor_type} // 'session';

    my $self = {
        anchor_type => $anchor_type,
        _highs      => [],
        _lows       => [],
        _closes     => [],
        _volumes    => [],
        _vwap       => [], # array of { value => num, anchor_idx => idx }
        _cum_pv     => 0,
        _cum_vol    => 0,
        _anchor_idx => 0,
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
    $self->{_cum_pv}     = 0;
    $self->{_cum_vol}    = 0;
    $self->{_anchor_idx} = 0;
    return;
}

sub set_anchor_index {
    my ($self, $idx) = @_;
    $self->{_anchor_idx} = $idx;
    $self->{_cum_pv}     = 0;
    $self->{_cum_vol}    = 0;
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

    # Check for session boundary anchor reset if anchor_type eq 'session'
    if ($self->{anchor_type} eq 'session' && $index > 0) {
        my $ts = $candle->[0];
        my $prev_ts = $market_data->get_candle($index - 1)->[0];
        if (defined $ts && defined $prev_ts && substr($ts, 0, 10) ne substr($prev_ts, 0, 10)) {
            $self->set_anchor_index($index);
        }
    }

    my $tp = ($high + $low + $close) / 3;
    $self->{_cum_pv}  += ($tp * $vol);
    $self->{_cum_vol} += $vol;

    my $vwap_val = ($self->{_cum_vol} > 0) ? ($self->{_cum_pv} / $self->{_cum_vol}) : $close;
    $self->{_vwap}->[$index] = {
        value      => $vwap_val,
        anchor_idx => $self->{_anchor_idx},
    };
    return;
}

sub get_values {
    my ($self) = @_;
    return $self->{_vwap};
}

1;
