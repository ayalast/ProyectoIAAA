package Market::Indicators::VolumeProfile;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::VolumeProfile
# 
# Advanced Volume Profile indicator computing:
#   - Volume histogram per price bin
#   - Point of Control (POC): Price level with peak volume
#   - Value Area High (VAH) & Value Area Low (VAL): 70% value area boundaries
#   - Modes: 'session', 'structure' (BOS/CHoCH), 'far_past' (contingency fallback)
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $bins_count = $opts{bins_count} // 24;
    my $mode       = $opts{mode}       // 'session'; # session, structure, far_past

    my $self = {
        bins_count  => $bins_count,
        mode        => $mode,
        _highs      => [],
        _lows       => [],
        _closes     => [],
        _volumes    => [],
        _profile    => undef, # { poc => num, vah => num, val => num, bins => [] }
        _market_data=> undef,
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_highs}   = [];
    $self->{_lows}    = [];
    $self->{_closes}  = [];
    $self->{_volumes} = [];
    $self->{_profile} = undef;
    return;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    my $candle = defined $index ? $market_data->get_candle($index) : $market_data->last_candle();
    return unless $candle;

    $self->{_market_data} = $market_data;
    $self->{_highs}->[$index]   = $candle->[2];
    $self->{_lows}->[$index]    = $candle->[3];
    $self->{_closes}->[$index]  = $candle->[4];
    $self->{_volumes}->[$index] = $candle->[5] // 1;

    $self->_recalculate_profile($index);
    return;
}

sub _recalculate_profile {
    my ($self, $end_index) = @_;
    my $start_index = 0;
    if ($self->{mode} eq 'session') {
        $start_index = ($end_index > 100) ? $end_index - 100 : 0;
    } elsif ($self->{mode} eq 'structure') {
        $start_index = ($end_index > 200) ? $end_index - 200 : 0;
    } else {
        $start_index = 0; # Far past fallback
    }

    my $min_p = 1e9;
    my $max_p = -1e9;
    my $total_vol = 0;

    for my $i ($start_index .. $end_index) {
        my $h = $self->{_highs}->[$i];
        my $l = $self->{_lows}->[$i];
        my $v = $self->{_volumes}->[$i];
        next unless defined $h && defined $l;
        $max_p = $h if $h > $max_p;
        $min_p = $l if $l < $min_p;
        $total_vol += $v;
    }

    return if $max_p <= $min_p || $total_vol <= 0;

    my $n_bins = $self->{bins_count};
    my $step = ($max_p - $min_p) / $n_bins;
    my @bins = map { { price => $min_p + ($_ + 0.5)*$step, vol => 0 } } 0 .. $n_bins - 1;

    for my $i ($start_index .. $end_index) {
        my $c = $self->{_closes}->[$i];
        my $v = $self->{_volumes}->[$i];
        next unless defined $c;
        my $b_idx = int(($c - $min_p) / $step);
        $b_idx = 0 if $b_idx < 0;
        $b_idx = $n_bins - 1 if $b_idx >= $n_bins;
        $bins[$b_idx]->{vol} += $v;
    }

    # Find POC (bin with maximum volume)
    my $max_b_vol = -1;
    my $poc_idx = 0;
    for my $b (0 .. $#bins) {
        if ($bins[$b]->{vol} > $max_b_vol) {
            $max_b_vol = $bins[$b]->{vol};
            $poc_idx = $b;
        }
    }
    my $poc = $bins[$poc_idx]->{price};

    # Calculate 70% Value Area (VAH & VAL)
    my $target_va_vol = 0.70 * $total_vol;
    my $accum_vol = $max_b_vol;
    my $low_b  = $poc_idx;
    my $high_b = $poc_idx;

    while ($accum_vol < $target_va_vol && ($low_b > 0 || $high_b < $n_bins - 1)) {
        my $v_down = ($low_b > 0) ? $bins[$low_b - 1]->{vol} : 0;
        my $v_up   = ($high_b < $n_bins - 1) ? $bins[$high_b + 1]->{vol} : 0;

        if ($v_up >= $v_down && $high_b < $n_bins - 1) {
            $high_b++;
            $accum_vol += $v_up;
        } elsif ($low_b > 0) {
            $low_b--;
            $accum_vol += $v_down;
        } else {
            $high_b++;
            $accum_vol += $v_up;
        }
    }

    my $vah = $bins[$high_b]->{price};
    my $val = $bins[$low_b]->{price};

    $self->{_profile} = {
        poc  => $poc,
        vah  => $vah,
        val  => $val,
        bins => \@bins,
    };
}

sub get_values {
    my ($self) = @_;
    return $self->{_profile};
}

1;
