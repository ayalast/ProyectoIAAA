package Market::Indicators::SMC_Structures;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::SMC_Structures — Zigzag FSM + BOS/CHoCH + major (Capa Indicadores)
# =============================================================================
#
# CONTRATO DE DESACOPLE (Req. 13.1):
#   Cálculo PURO (sin Tk, sin coordenadas de pantalla). Lee OHLC de MarketData
#   vía get_candle. Expone get_pivots(), get_events(), get_major() → listas de
#   hashrefs { index, type, ... } que el overlay (task 0008) consume para dibujar.
#
# ALGORITMO:
#   1. Swing detection con profundidad k (default 3):
#      - Swing High en i: High[i] > High[i-k..i-1] y High[i] > High[i+1..i+k].
#      - Swing Low  en i: Low[i]  < Low[i-k..i-1]  y Low[i]  < Low[i+1..i+k].
#   2. FSM del zigzag: mantiene dirección (up/down) y el candidato actual.
#      Cuando se confirma un swing del tipo OPUESTO al candidato actual, se
#      confirma el candidato como pivote (etiquetándolo HH/HL/LL/LH) y se
#      cambia de dirección. Swings del mismo tipo se absorben si son más
#      extremos (garantiza "no saltar extremos relevantes" sin duplicar).
#   3. Trailing extremum: tras el último candidato, se rastrea el mejor extremo
#      opuesto. Al finalizar (get_pivots), se confirma el candidato y el
#      trailing, asegurando que el último movimiento relevante quede etiquetado.
#   4. Major high/low: exactamente uno de cada uno vigente. Se actualizan solo
#      tras CHoCH_true confirmada del nivel opuesto.
#   5. BOS (continuación): cierre de cuerpo > last_hh (uptrend) o < last_ll
#      (downtrend). Si solo la mecha rompe → pending; si la siguiente vela
#      revierte con fuerza → se invalida.
#   6. CHoCH (cambio): verdadero solo si rompe el MAJOR con cierre de cuerpo Y
#      la siguiente vela confirma (se mantiene del mismo lado). Falso
#      (inducement) si rompe solo estructura interna.
#
# CONTRATO IndicatorManager: update_last / get_values / reset.
#   update_last es O(k) por vela (verificación de swing en j=i-k).
#   reset + recálculo vela a vela reproduce el mismo resultado que batch.
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $k = $opts{k} // 3;
    die "SMC_Structures: k must be a positive integer"
        unless defined $k && $k =~ /^\d+$/ && $k > 0;

    my $self = {
        k              => $k,
        _highs         => [],
        _lows          => [],
        _opens         => [],
        _closes        => [],
        _dir           => undef,
        _current       => undef,
        _trailing      => undef,
        _last_high     => undef,
        _last_low      => undef,
        _pivots        => [],
        _values        => [],
        _trend         => undef,
        _major_high    => undef,
        _major_low     => undef,
        _last_hh       => undef,
        _last_ll       => undef,
        _last_hl       => undef,
        _last_lh       => undef,
        _events        => [],
        _pending_bos   => undef,
        _pending_choch => undef,
        _fvgs          => [],
    };
    bless $self, $class;
    return $self;
}

sub update_last {
    my ($self, $market_data, $index) = @_;
    my $candle = defined $index
        ? $market_data->get_candle($index)
        : $market_data->last_candle();
    return unless $candle;

    my $open  = $candle->[1];
    my $high  = $candle->[2];
    my $low   = $candle->[3];
    my $close = $candle->[4];

    $self->{_highs}->[$index]  = $high;
    $self->{_lows}->[$index]   = $low;
    $self->{_opens}->[$index]  = $open;
    $self->{_closes}->[$index] = $close;
    $self->{_values}->[$index] = undef;

    my $k = $self->{k};
    my $j = $index - $k;

    if ($j >= 0) {
        my $is_sh = $self->_is_swing_high($j);
        my $is_sl = $self->_is_swing_low($j);

        if ($is_sh && !$is_sl) {
            $self->_process_swing($j, $self->{_highs}->[$j], 'high');
        } elsif ($is_sl && !$is_sh) {
            $self->_process_swing($j, $self->{_lows}->[$j], 'low');
        } elsif ($is_sh && $is_sl) {
            my $type = (defined $self->{_dir} && $self->{_dir} eq 'down') ? 'high' : 'low';
            $self->_process_swing($j, $type eq 'high' ? $self->{_highs}->[$j] : $self->{_lows}->[$j], $type);
        }
    }

    $self->_track_trailing($index, $high, $low);
    $self->_check_bos_choch($index, $open, $close, $high, $low);
    $self->_detect_and_mitigate_fvgs($index);
    return;
}

sub _is_swing_high {
    my ($self, $j) = @_;
    my $k  = $self->{k};
    my $h  = $self->{_highs};
    return 0 if $j - $k < 0;
    return 0 unless defined $h->[$j];
    for my $n (1 .. $k) {
        return 0 unless defined $h->[$j - $n] && $h->[$j] > $h->[$j - $n];
        return 0 unless defined $h->[$j + $n] && $h->[$j] > $h->[$j + $n];
    }
    return 1;
}

sub _is_swing_low {
    my ($self, $j) = @_;
    my $k  = $self->{k};
    my $l  = $self->{_lows};
    return 0 if $j - $k < 0;
    return 0 unless defined $l->[$j];
    for my $n (1 .. $k) {
        return 0 unless defined $l->[$j - $n] && $l->[$j] < $l->[$j - $n];
        return 0 unless defined $l->[$j + $n] && $l->[$j] < $l->[$j + $n];
    }
    return 1;
}

sub _process_swing {
    my ($self, $j, $price, $swing_type) = @_;

    if (!defined $self->{_dir}) {
        $self->{_current}  = { index => $j, price => $price, type => $swing_type };
        $self->{_dir}      = ($swing_type eq 'high') ? 'down' : 'up';
        $self->{_trailing} = undef;
        return;
    }

    if ($self->{_dir} eq 'down') {
        if ($swing_type eq 'high') {
            if ($price > $self->{_current}->{price}) {
                $self->{_current}  = { index => $j, price => $price, type => 'high' };
                $self->{_trailing} = undef;
            }
        } else {
            $self->_confirm_pivot($self->{_current});
            $self->{_current}  = { index => $j, price => $price, type => 'low' };
            $self->{_dir}      = 'up';
            $self->{_trailing} = undef;
        }
    } else {
        if ($swing_type eq 'low') {
            if ($price < $self->{_current}->{price}) {
                $self->{_current}  = { index => $j, price => $price, type => 'low' };
                $self->{_trailing} = undef;
            }
        } else {
            $self->_confirm_pivot($self->{_current});
            $self->{_current}  = { index => $j, price => $price, type => 'high' };
            $self->{_dir}      = 'down';
            $self->{_trailing} = undef;
        }
    }
    return;
}

sub _label_for {
    my ($cand, $last_high, $last_low) = @_;
    my $label;
    my $new_lh = $last_high;
    my $new_ll = $last_low;

    if ($cand->{type} eq 'high') {
        if (!defined $last_high || $cand->{price} > $last_high) {
            $label = 'HH';
        } else {
            $label = 'LH';
        }
        $new_lh = $cand->{price};
    } else {
        if (!defined $last_low || $cand->{price} < $last_low) {
            $label = 'LL';
        } else {
            $label = 'HL';
        }
        $new_ll = $cand->{price};
    }
    return ($label, $new_lh, $new_ll);
}

sub _confirm_pivot {
    my ($self, $cand) = @_;
    my ($label, $new_lh, $new_ll) = _label_for($cand, $self->{_last_high}, $self->{_last_low});
    
    $self->{_last_high} = $new_lh;
    $self->{_last_low}  = $new_ll;

    if ($cand->{type} eq 'high') {
        if ($label eq 'HH') {
            $self->{_last_hh} = { index => $cand->{index}, price => $cand->{price} };
            if (!defined $self->{_major_high} || $cand->{price} > $self->{_major_high}->{price}) {
                $self->{_major_high} = { index => $cand->{index}, price => $cand->{price} };
            }
        } else {
            $self->{_last_lh} = { index => $cand->{index}, price => $cand->{price} };
        }
    } else {
        if ($label eq 'LL') {
            $self->{_last_ll} = { index => $cand->{index}, price => $cand->{price} };
            if (!defined $self->{_major_low} || $cand->{price} < $self->{_major_low}->{price}) {
                $self->{_major_low} = { index => $cand->{index}, price => $cand->{price} };
            }
        } else {
            $self->{_last_hl} = { index => $cand->{index}, price => $cand->{price} };
        }
    }

    if (!defined $self->{_trend}) {
        $self->{_trend} = ($label eq 'HH' || $label eq 'HL') ? 'up' : 'down';
    }

    my $pivot = { index => $cand->{index}, type => $label, price => $cand->{price} };
    push @{ $self->{_pivots} }, $pivot;
    $self->{_values}->[ $cand->{index} ] = $label;
    return;
}

sub _track_trailing {
    my ($self, $i, $high, $low) = @_;
    return unless defined $self->{_current} && defined $self->{_dir};
    return if $i <= $self->{_current}->{index};

    if ($self->{_dir} eq 'down') {
        if (!defined $self->{_trailing} || $low < $self->{_trailing}->{price}) {
            $self->{_trailing} = { index => $i, price => $low, type => 'low' };
        }
    } else {
        if (!defined $self->{_trailing} || $high > $self->{_trailing}->{price}) {
            $self->{_trailing} = { index => $i, price => $high, type => 'high' };
        }
    }
    return;
}

# =============================================================================
# BOS / CHoCH detection (task 0006)
# =============================================================================

sub _check_bos_choch {
    my ($self, $index, $open, $close, $high, $low) = @_;
    my $just_resolved = 0;

    # --- 1. Resolve pending BOS (wick-only from previous candle) ---
    if ($self->{_pending_bos}) {
        my $p = $self->{_pending_bos};
        if ($p->{dir} eq 'up') {
            if ($close > $p->{level}) {
                push @{ $self->{_events} }, {
                    index => $index, type => 'BOS', dir => 'up', price => $p->{level}
                };
                $self->{_pending_bos} = undef;
                $just_resolved = 1;
            } elsif ($close < $p->{level} && $close < $open) {
                $self->{_pending_bos} = undef;
                $just_resolved = 1;
            }
        } else {
            if ($close < $p->{level}) {
                push @{ $self->{_events} }, {
                    index => $index, type => 'BOS', dir => 'down', price => $p->{level}
                };
                $self->{_pending_bos} = undef;
                $just_resolved = 1;
            } elsif ($close > $p->{level} && $close > $open) {
                $self->{_pending_bos} = undef;
                $just_resolved = 1;
            }
        }
    }

    # --- 2. Resolve pending CHoCH (needs next candle confirmation) ---
    if ($self->{_pending_choch}) {
        my $p = $self->{_pending_choch};
        if ($p->{dir} eq 'down') {
            if ($close < $p->{level}) {
                push @{ $self->{_events} }, {
                    index => $index, type => 'CHoCH_true', dir => 'down', price => $p->{level}
                };
                $self->{_trend} = 'down';
                $self->_update_major_on_choch('down');
                $self->{_pending_choch} = undef;
                $just_resolved = 1;
            } else {
                $self->{_pending_choch} = undef;
                $just_resolved = 1;
            }
        } else {
            if ($close > $p->{level}) {
                push @{ $self->{_events} }, {
                    index => $index, type => 'CHoCH_true', dir => 'up', price => $p->{level}
                };
                $self->{_trend} = 'up';
                $self->_update_major_on_choch('up');
                $self->{_pending_choch} = undef;
                $just_resolved = 1;
            } else {
                $self->{_pending_choch} = undef;
                $just_resolved = 1;
            }
        }
    }

    return if $just_resolved;
    return unless defined $self->{_trend};

    # --- 3. Check new BOS (continuation) and CHoCH (reversal) ---
    if ($self->{_trend} eq 'up') {
        if ($self->{_last_hh}) {
            my $level = $self->{_last_hh}->{price};
            if ($close > $level) {
                push @{ $self->{_events} }, {
                    index => $index, type => 'BOS', dir => 'up', price => $level
                };
            } elsif ($high > $level && $close <= $level) {
                $self->{_pending_bos} = { dir => 'up', level => $level, index => $index };
            }
        }
        if ($self->{_major_low} && $close < $self->{_major_low}->{price}) {
            $self->{_pending_bos} = undef;
            $self->{_pending_choch} = {
                dir => 'down', level => $self->{_major_low}->{price}, index => $index
            };
        } elsif ($self->{_last_hl} && $close < $self->{_last_hl}->{price}
                 && (!$self->{_major_low} || $close >= $self->{_major_low}->{price})) {
            push @{ $self->{_events} }, {
                index => $index, type => 'CHoCH_false', dir => 'down',
                price => $self->{_last_hl}->{price}
            };
        }
    } else {
        if ($self->{_last_ll}) {
            my $level = $self->{_last_ll}->{price};
            if ($close < $level) {
                push @{ $self->{_events} }, {
                    index => $index, type => 'BOS', dir => 'down', price => $level
                };
            } elsif ($low < $level && $close >= $level) {
                $self->{_pending_bos} = { dir => 'down', level => $level, index => $index };
            }
        }
        if ($self->{_major_high} && $close > $self->{_major_high}->{price}) {
            $self->{_pending_bos} = undef;
            $self->{_pending_choch} = {
                dir => 'up', level => $self->{_major_high}->{price}, index => $index
            };
        } elsif ($self->{_last_lh} && $close > $self->{_last_lh}->{price}
                 && (!$self->{_major_high} || $close <= $self->{_major_high}->{price})) {
            push @{ $self->{_events} }, {
                index => $index, type => 'CHoCH_false', dir => 'up',
                price => $self->{_last_lh}->{price}
            };
        }
    }
    return;
}

sub _update_major_on_choch {
    my ($self, $dir) = @_;
    if ($dir eq 'down') {
        if (defined $self->{_current} && $self->{_current}->{type} eq 'high') {
            $self->{_major_high} = { index => $self->{_current}->{index}, price => $self->{_current}->{price} };
        } elsif (defined $self->{_last_hh}) {
            $self->{_major_high} = { %{ $self->{_last_hh} } };
        }
    } else {
        if (defined $self->{_current} && $self->{_current}->{type} eq 'low') {
            $self->{_major_low} = { index => $self->{_current}->{index}, price => $self->{_current}->{price} };
        } elsif (defined $self->{_last_ll}) {
            $self->{_major_low} = { %{ $self->{_last_ll} } };
        }
    }
    return;
}

# =============================================================================
# FVG detection + mitigation (task 0007)
# =============================================================================

sub _detect_and_mitigate_fvgs {
    my ($self, $index) = @_;

    # --- Detect new FVG at (index-2, index-1, index) = (i-1, i, i+1) ---
    if ($index >= 2) {
        my $prev_high = $self->{_highs}->[$index - 2];
        my $next_low  = $self->{_lows}->[$index];
        my $prev_low  = $self->{_lows}->[$index - 2];
        my $next_high = $self->{_highs}->[$index];

        if (defined $prev_high && defined $next_low && $next_low > $prev_high) {
            push @{ $self->{_fvgs} }, {
                index     => $index,
                type      => 'FVG_up',
                hi        => $next_low,
                lo        => $prev_high,
                _orig_hi  => $next_low,
                _orig_lo  => $prev_high,
                mitig     => 0,
                _active   => 1,
            };
        }
        if (defined $prev_low && defined $next_high && $next_high < $prev_low) {
            push @{ $self->{_fvgs} }, {
                index     => $index,
                type      => 'FVG_down',
                hi        => $prev_low,
                lo        => $next_high,
                _orig_hi  => $prev_low,
                _orig_lo  => $next_high,
                mitig     => 0,
                _active   => 1,
            };
        }
    }

    # --- Mitigate active FVGs with current candle ---
    for my $fvg ( @{ $self->{_fvgs} } ) {
        next unless $fvg->{_active};
        next if $fvg->{index} >= $index;

        if ($fvg->{type} eq 'FVG_up') {
            my $cl = $self->{_lows}->[$index];
            if (defined $cl && $cl < $fvg->{hi}) {
                if ($cl <= $fvg->{lo}) {
                    $fvg->{_active} = 0;
                } else {
                    $fvg->{hi} = $cl;
                }
            }
        } else {
            my $ch = $self->{_highs}->[$index];
            if (defined $ch && $ch > $fvg->{lo}) {
                if ($ch >= $fvg->{hi}) {
                    $fvg->{_active} = 0;
                } else {
                    $fvg->{lo} = $ch;
                }
            }
        }

        my $orig = $fvg->{_orig_hi} - $fvg->{_orig_lo};
        if ($orig > 0) {
            $fvg->{mitig} = 1 - ($fvg->{hi} - $fvg->{lo}) / $orig;
        }
    }

    # ponytail: prune inactive FVGs so the mitigation loop stays O(active) not O(total).
    # _active only goes 1→0 (never reactivated); get_fvg() already filters to active only.
    $self->{_fvgs} = [ grep { $_->{_active} } @{ $self->{_fvgs} } ];

    return;
}

# =============================================================================
# Public API
# =============================================================================

sub _get_effective_majors {
    my ($self) = @_;
    my $major_high = $self->{_major_high};
    my $major_low  = $self->{_major_low};

    my $lh = $self->{_last_high};
    my $ll = $self->{_last_low};

    if (defined $self->{_current}) {
        my $cand = $self->{_current};
        my ($label, $new_lh, $new_ll) = _label_for($cand, $lh, $ll);
        $lh = $new_lh;
        $ll = $new_ll;

        if ($cand->{type} eq 'high') {
            if ($label eq 'HH') {
                if (!defined $major_high || $cand->{price} > $major_high->{price}) {
                    $major_high = { index => $cand->{index}, price => $cand->{price} };
                }
            }
        } else {
            if ($label eq 'LL') {
                if (!defined $major_low || $cand->{price} < $major_low->{price}) {
                    $major_low = { index => $cand->{index}, price => $cand->{price} };
                }
            }
        }
    }
    if (defined $self->{_trailing}) {
        my $cand = $self->{_trailing};
        my ($label, $new_lh, $new_ll) = _label_for($cand, $lh, $ll);
        $lh = $new_lh;
        $ll = $new_ll;

        if ($cand->{type} eq 'high') {
            if ($label eq 'HH') {
                if (!defined $major_high || $cand->{price} > $major_high->{price}) {
                    $major_high = { index => $cand->{index}, price => $cand->{price} };
                }
            }
        } else {
            if ($label eq 'LL') {
                if (!defined $major_low || $cand->{price} < $major_low->{price}) {
                    $major_low = { index => $cand->{index}, price => $cand->{price} };
                }
            }
        }
    }
    return ($major_high, $major_low);
}

sub get_pivots {
    my ($self) = @_;
    my @pivs = @{ $self->{_pivots} };

    my $lh = $self->{_last_high};
    my $ll = $self->{_last_low};

    if (defined $self->{_current}) {
        my $cand = $self->{_current};
        my ($label, $new_lh, $new_ll) = _label_for($cand, $lh, $ll);
        $lh = $new_lh;
        $ll = $new_ll;
        push @pivs, { index => $cand->{index}, type => $label, price => $cand->{price} };
    }
    if (defined $self->{_trailing}) {
        my $cand = $self->{_trailing};
        my ($label, $new_lh, $new_ll) = _label_for($cand, $lh, $ll);
        $lh = $new_lh;
        $ll = $new_ll;
        push @pivs, { index => $cand->{index}, type => $label, price => $cand->{price} };
    }
    return \@pivs;
}

sub get_events {
    my ($self) = @_;
    return $self->{_events};
}

sub get_major {
    my ($self) = @_;
    my ($mh, $ml) = $self->_get_effective_majors();
    my @items;
    if (defined $mh) {
        push @items, { index => $mh->{index}, type => 'major_high', price => $mh->{price} };
    }
    if (defined $ml) {
        push @items, { index => $ml->{index}, type => 'major_low', price => $ml->{price} };
    }
    return \@items;
}

sub get_fvg {
    my ($self) = @_;
    my @result;
    for my $fvg ( @{ $self->{_fvgs} } ) {
        next unless $fvg->{_active};
        push @result, {
            index => $fvg->{index},
            type  => $fvg->{type},
            hi    => $fvg->{hi},
            lo    => $fvg->{lo},
            mitig => $fvg->{mitig},
        };
    }
    return \@result;
}

sub get_fibonacci {
    my ($self) = @_;
    my ($mh, $ml) = $self->_get_effective_majors();
    return [] unless defined $mh && defined $ml;

    my $range = $mh->{price} - $ml->{price};
    return [] if $range <= 0;

    my $idx = $mh->{index} > $ml->{index} ? $mh->{index} : $ml->{index};
    my @levels = (0.236, 0.382, 0.5, 0.618, 0.786);
    my @result;
    for my $r (@levels) {
        push @result, {
            index => $idx,
            type  => "fib_$r",
            price => $ml->{price} + $r * $range,
        };
    }
    return \@result;
}

sub get_all_items {
    my ($self) = @_;
    my $pivots = $self->get_pivots();
    my $events = $self->get_events();
    my $majors = $self->get_major();
    my $fvgs   = $self->get_fvg();
    my $fibs   = $self->get_fibonacci();
    return [ @$pivots, @$events, @$majors, @$fvgs, @$fibs ];
}

sub get_values {
    my ($self) = @_;
    my @vals = @{ $self->{_values} };

    my $lh = $self->{_last_high};
    my $ll = $self->{_last_low};

    if (defined $self->{_current}) {
        my $cand = $self->{_current};
        my ($label, $new_lh, $new_ll) = _label_for($cand, $lh, $ll);
        $lh = $new_lh;
        $ll = $new_ll;
        $vals[ $cand->{index} ] = $label;
    }
    if (defined $self->{_trailing}) {
        my $cand = $self->{_trailing};
        my ($label, $new_lh, $new_ll) = _label_for($cand, $lh, $ll);
        $lh = $new_lh;
        $ll = $new_ll;
        $vals[ $cand->{index} ] = $label;
    }
    return \@vals;
}

sub reset {
    my ($self) = @_;
    $self->{_highs}         = [];
    $self->{_lows}          = [];
    $self->{_opens}         = [];
    $self->{_closes}        = [];
    $self->{_dir}           = undef;
    $self->{_current}       = undef;
    $self->{_trailing}      = undef;
    $self->{_last_high}     = undef;
    $self->{_last_low}      = undef;
    $self->{_pivots}        = [];
    $self->{_values}        = [];
    $self->{_trend}         = undef;
    $self->{_major_high}    = undef;
    $self->{_major_low}     = undef;
    $self->{_last_hh}       = undef;
    $self->{_last_ll}       = undef;
    $self->{_last_hl}       = undef;
    $self->{_last_lh}       = undef;
    $self->{_events}        = [];
    $self->{_pending_bos}   = undef;
    $self->{_pending_choch} = undef;
    $self->{_fvgs}          = [];
    return;
}

1;
