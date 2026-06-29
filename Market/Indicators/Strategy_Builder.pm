package Market::Indicators::Strategy_Builder;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::Strategy_Builder
# 
# Technical strategy builder engine implementing:
#   1. SuperTrend (ATR multiplier trend tracking)
#   2. HalfTrend (Directional trend & channel reversal filters)
#   3. Range Filter (Price smoothing for accumulation/distribution)
#   4. Supply & Demand Zones (Volume-validated order blocks)
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $st_period  = $opts{st_period}  // 10;
    my $st_factor  = $opts{st_factor}  // 3.0;
    my $ht_amplitude= $opts{ht_amplitude}// 2;
    my $rf_period  = $opts{rf_period}  // 14;
    my $rf_mult    = $opts{rf_mult}    // 2.0;

    my $self = {
        st_period    => $st_period,
        st_factor    => $st_factor,
        ht_amplitude => $ht_amplitude,
        rf_period    => $rf_period,
        rf_mult      => $rf_mult,
        _highs       => [],
        _lows        => [],
        _closes      => [],
        _volumes     => [],
        _atr_vals    => [],
        _tr_sum      => 0,
        _supertrend  => [], # { value => num, dir => 1/-1 }
        _halftrend   => [], # { value => num, dir => 1/-1, high_band => num, low_band => num }
        _rangefilter => [], # { value => num, dir => 1/-1, high_band => num, low_band => num }
        _supply_zones=> [], # { index => idx, hi => num, lo => num, vol => num, active => 1/0 }
        _demand_zones=> [], # { index => idx, hi => num, lo => num, vol => num, active => 1/0 }
        _market_data => undef,
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_highs}        = [];
    $self->{_lows}         = [];
    $self->{_closes}       = [];
    $self->{_volumes}      = [];
    $self->{_atr_vals}     = [];
    $self->{_tr_sum}       = 0;
    $self->{_supertrend}   = [];
    $self->{_halftrend}    = [];
    $self->{_rangefilter}  = [];
    $self->{_supply_zones} = [];
    $self->{_demand_zones} = [];
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

    # 1. Update ATR
    $self->_update_atr($index, $high, $low, $close);

    # 2. Update SuperTrend
    $self->_update_supertrend($index, $high, $low, $close);

    # 3. Update HalfTrend
    $self->_update_halftrend($index, $high, $low, $close);

    # 4. Update Range Filter
    $self->_update_rangefilter($index, $high, $low, $close);

    # 5. Update Supply & Demand Zones
    $self->_update_supply_demand($index, $high, $low, $close, $vol);

    return;
}

sub _update_atr {
    my ($self, $index, $high, $low, $close) = @_;
    my $p = $self->{st_period};
    my $tr = $high - $low;
    if ($index > 0) {
        my $prev_close = $self->{_closes}->[$index - 1];
        my $tr1 = abs($high - $prev_close);
        my $tr2 = abs($low - $prev_close);
        $tr = $tr1 if $tr1 > $tr;
        $tr = $tr2 if $tr2 > $tr;
    }
    if ($index < $p) {
        $self->{_tr_sum} += $tr;
        $self->{_atr_vals}->[$index] = $self->{_tr_sum} / ($index + 1);
    } else {
        my $prev_atr = $self->{_atr_vals}->[$index - 1];
        $self->{_atr_vals}->[$index] = ($prev_atr * ($p - 1) + $tr) / $p;
    }
}

sub _update_supertrend {
    my ($self, $index, $high, $low, $close) = @_;
    my $atr = $self->{_atr_vals}->[$index] // 0;
    my $hl2 = ($high + $low) / 2;
    my $basic_ub = $hl2 + ($self->{st_factor} * $atr);
    my $basic_lb = $hl2 - ($self->{st_factor} * $atr);

    if ($index == 0) {
        $self->{_supertrend}->[$index] = {
            value => $basic_ub,
            dir   => -1,
            ub    => $basic_ub,
            lb    => $basic_lb,
        };
        return;
    }

    my $prev = $self->{_supertrend}->[$index - 1];
    my $prev_close = $self->{_closes}->[$index - 1];

    my $final_ub = ($basic_ub < $prev->{ub} || $prev_close > $prev->{ub}) ? $basic_ub : $prev->{ub};
    my $final_lb = ($basic_lb > $prev->{lb} || $prev_close < $prev->{lb}) ? $basic_lb : $prev->{lb};

    my $dir = $prev->{dir};
    if ($prev->{dir} == -1 && $close > $final_ub) {
        $dir = 1; # Bullish reversal
    } elsif ($prev->{dir} == 1 && $close < $final_lb) {
        $dir = -1; # Bearish reversal
    }

    my $st_val = ($dir == 1) ? $final_lb : $final_ub;
    $self->{_supertrend}->[$index] = {
        value => $st_val,
        dir   => $dir,
        ub    => $final_ub,
        lb    => $final_lb,
    };
}

sub _update_halftrend {
    my ($self, $index, $high, $low, $close) = @_;
    if ($index == 0) {
        $self->{_halftrend}->[$index] = { value => $close, dir => 1, high_band => $high, low_band => $low };
        return;
    }
    my $prev = $self->{_halftrend}->[$index - 1];
    my $atr  = $self->{_atr_vals}->[$index] // 1;
    my $dev  = $atr * 0.5;

    my $dir = $prev->{dir};
    my $val = $prev->{value};

    if ($dir == 1) {
        if ($low < $prev->{low_band}) {
            $dir = -1;
            $val = $high;
        } else {
            $val = $low if $low > $val;
        }
    } else {
        if ($high > $prev->{high_band}) {
            $dir = 1;
            $val = $low;
        } else {
            $val = $high if $high < $val;
        }
    }

    $self->{_halftrend}->[$index] = {
        value     => $val,
        dir       => $dir,
        high_band => $val + $dev,
        low_band  => $val - $dev,
    };
}

sub _update_rangefilter {
    my ($self, $index, $high, $low, $close) = @_;
    if ($index == 0) {
        $self->{_rangefilter}->[$index] = { value => $close, dir => 1 };
        return;
    }
    my $prev = $self->{_rangefilter}->[$index - 1];
    my $atr  = $self->{_atr_vals}->[$index] // 1;
    my $rng  = $atr * $self->{rf_mult};

    my $val = $prev->{value};
    my $dir = $prev->{dir};

    if ($close > $val + $rng) {
        $val = $close - $rng;
        $dir = 1;
    } elsif ($close < $val - $rng) {
        $val = $close + $rng;
        $dir = -1;
    }

    $self->{_rangefilter}->[$index] = { value => $val, dir => $dir };
}

sub _update_supply_demand {
    my ($self, $index, $high, $low, $close, $vol) = @_;
    return if $index < 2;

    # Check for strong volume expansion imbalance (Supply / Demand zones)
    my $prev_vol = $self->{_volumes}->[$index - 1] // 1;
    my $is_high_vol = ($vol > 1.5 * $prev_vol);

    if ($is_high_vol && $close > $self->{_highs}->[$index - 1]) {
        # Demand Zone (Buy order block)
        push @{ $self->{_demand_zones} }, {
            index  => $index - 1,
            hi     => $self->{_highs}->[$index - 1],
            lo     => $self->{_lows}->[$index - 1],
            vol    => $vol,
            active => 1,
        };
    } elsif ($is_high_vol && $close < $self->{_lows}->[$index - 1]) {
        # Supply Zone (Sell order block)
        push @{ $self->{_supply_zones} }, {
            index  => $index - 1,
            hi     => $self->{_highs}->[$index - 1],
            lo     => $self->{_lows}->[$index - 1],
            vol    => $vol,
            active => 1,
        };
    }

    # Mitigate active zones. PERF: _demand_zones/_supply_zones mantienen SOLO
    # zonas activas (una zona nunca se re-activa, y get_values ya filtra por
    # active), asi que al mitigar las eliminamos del array. Esto evita reescanear
    # zonas muertas en cada vela (antes O(N^2) acumulado sobre arrays que solo
    # crecen). Salida identica: get_values devuelve las mismas zonas activas.
    @{ $self->{_demand_zones} } =
        grep { $close >= $_->{lo} } @{ $self->{_demand_zones} };
    @{ $self->{_supply_zones} } =
        grep { $close <= $_->{hi} } @{ $self->{_supply_zones} };
}

sub get_values {
    my ($self) = @_;
    return {
        supertrend   => $self->{_supertrend},
        halftrend    => $self->{_halftrend},
        rangefilter  => $self->{_rangefilter},
        supply_zones => [ grep { $_->{active} } @{ $self->{_supply_zones} } ],
        demand_zones => [ grep { $_->{active} } @{ $self->{_demand_zones} } ],
    };
}

1;
