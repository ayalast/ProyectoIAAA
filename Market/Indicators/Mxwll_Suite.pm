package Market::Indicators::Mxwll_Suite;
use strict;
use warnings;

# =============================================================================
# Market::Indicators::Mxwll_Suite — port del "Mxwll Suite" (Mxwll Capital)
# =============================================================================
#
# CONTRATO DE DESACOPLE (como el resto de indicadores Fase 2):
#   Calculo PURO (sin Tk, sin coordenadas). Lee OHLCV de MarketData via
#   get_candle/update_last. Expone get_values() -> hashref con listas de
#   estructuras que el overlay (Market::Overlays::Mxwll_Suite) dibuja.
#
# FEATURES PORTADAS (deterministas sobre OHLCV, paridad con el .pine):
#   1. calculatePivots(length): FSM "intraCalc" -> pivotes causales confirmados
#      `length` barras despues (igual concepto que el leg de LuxAlgo).
#      - Externos: extSens (def 25) -> HH/HL/LH/LL + order blocks.
#      - Internos: intSens (def 3)  -> I-BoS / I-CHoCH.
#   2. drawStructureExt: etiquetas HH/HL/LH/LL, BOS/CHoCH por ruptura de
#      close sobre el ultimo swing (upaxis/dnaxis) con memoria de tendencia
#      (`moving`): CHoCH si cambia de caracter, BoS si continua.
#   3. Order Blocks (swing blocks): caja en cada swing, mitigada cuando el
#      precio cierra a traves de ella. Se conservan los `showLast` mas recientes.
#   4. drawStructureInternals: I-BoS / I-CHoCH con intSens.
#   5. Area of Interest (AOE): zonas sobre/bajo el max/min de los ultimos 50
#      cierres/aperturas, con grosor ATR(14).
#   6. Auto Fibs: linea entre el ultimo swing alto y bajo + niveles
#      0.236/0.382/0.5/0.618/0.786.
#   7. Fair Value Gaps (FVG): hueco de 3 velas (alcista: low[0] > high[2];
#      bajista: high[0] < low[2]), mitigado cuando el precio lo rellena.
#
# NO PORTADO (depende de reloj en tiempo real / sesiones NY, sin sentido en un
#   replay de CSV historico): tabla de sesiones (New York/Asia/London), volumen
#   rolling 4H/1D con percentiles, y el sombreado de fondo por horario.
#
# CONTRATO IndicatorManager: update_last / get_values / reset.
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = {
        ext_sens   => $opts{ext_sens}   // 25,   # externals sensitivity
        int_sens   => $opts{int_sens}   // 3,    # internals sensitivity
        fib_sens   => $opts{fib_sens}   // 25,   # calculatePivots(25) para fibs
        show_last  => $opts{show_last}  // 10,   # max order blocks por lado
        aoe_lookback => $opts{aoe_lookback} // 50,
        atr_period   => $opts{atr_period}   // 14,
        fib_ratios   => $opts{fib_ratios}   // [0.236, 0.382, 0.5, 0.618, 0.786],

        _highs  => [],
        _lows   => [],
        _opens  => [],
        _closes => [],

        # ATR(14) para el grosor de las zonas AOE.
        _atr_vals => [],
        _tr_sum   => 0,
        _atr_last => undef,

        # FSM de pivotes por proposito (cada call-site del .pine tiene su `var`).
        _leg => { ext => 0, int => 0, fib => 0 },

        # Estructura externa (drawStructureExt / bigData).
        _ext => {
            upaxis => undef, upaxis2 => undef,
            dnaxis => undef, dnaxis2 => undef,
            upside => 1, downside => 1, moving => 0,
        },
        # Estructura interna (drawStructureInternals / keyValues).
        _int => {
            upaxis => undef, upaxis2 => undef,
            dnaxis => undef, dnaxis2 => undef,
            upside => 0, downside => 0, moving => 0,
        },

        _swings     => [],   # { index, price, label HH/HL/LH/LL, dir }
        _structures => [],   # { from, to, price, label, dir, internal }
        _high_blocks => [],  # { index, top, bottom, active }
        _low_blocks  => [],  # { index, top, bottom, active }
        _fvgs       => [],   # { index, top, bottom, dir, active }

        _last_index => -1,
    };
    bless $self, $class;
    return $self;
}

sub reset {
    my ($self) = @_;
    $self->{_highs}  = [];
    $self->{_lows}   = [];
    $self->{_opens}  = [];
    $self->{_closes} = [];
    $self->{_atr_vals} = [];
    $self->{_tr_sum}   = 0;
    $self->{_atr_last} = undef;
    $self->{_leg} = { ext => 0, int => 0, fib => 0 };
    $self->{_ext} = {
        upaxis => undef, upaxis2 => undef, dnaxis => undef, dnaxis2 => undef,
        upside => 1, downside => 1, moving => 0,
    };
    $self->{_int} = {
        upaxis => undef, upaxis2 => undef, dnaxis => undef, dnaxis2 => undef,
        upside => 0, downside => 0, moving => 0,
    };
    $self->{_swings}      = [];
    $self->{_structures}  = [];
    $self->{_high_blocks} = [];
    $self->{_low_blocks}  = [];
    $self->{_fvgs}        = [];
    $self->{_last_index}  = -1;
    return;
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

    $self->{_opens}->[$index]  = $open;
    $self->{_highs}->[$index]  = $high;
    $self->{_lows}->[$index]   = $low;
    $self->{_closes}->[$index] = $close;

    $self->_update_atr($index, $high, $low, $close);

    # 1. Estructura externa (HH/HL/LH/LL + BOS/CHoCH + order blocks).
    my ($big_up, $big_dn) = $self->_detect_pivot('ext', $self->{ext_sens}, $index);
    $self->_update_structure($index, $close, $big_up, $big_dn, $self->{_ext},
                             0, $self->{ext_sens});

    # 2. Estructura interna (I-BoS / I-CHoCH).
    my ($small_up, $small_dn) = $self->_detect_pivot('int', $self->{int_sens}, $index);
    $self->_update_structure($index, $close, $small_up, $small_dn, $self->{_int},
                             1, $self->{int_sens});

    # 3. Mitigacion de order blocks y FVG con la vela actual.
    $self->_cleanse_blocks($close);
    $self->_detect_fvg($index, $high, $low);
    $self->_mitigate_fvg($index, $high, $low);

    $self->{_last_index} = $index;
    return;
}

# --- ATR(Wilder) para grosor de AOE ------------------------------------------
sub _update_atr {
    my ($self, $index, $high, $low, $close) = @_;
    my $p = $self->{atr_period};
    my $tr = $high - $low;
    if ($index > 0) {
        my $pc = $self->{_closes}->[$index - 1];
        if (defined $pc) {
            my $a = abs($high - $pc);
            my $b = abs($low  - $pc);
            $tr = $a if $a > $tr;
            $tr = $b if $b > $tr;
        }
    }
    if ($index < $p) {
        $self->{_tr_sum} += $tr;
        $self->{_atr_last} = $self->{_tr_sum} / ($index + 1);
    } else {
        my $prev = $self->{_atr_last} // $tr;
        $self->{_atr_last} = ($prev * ($p - 1) + $tr) / $p;
    }
    $self->{_atr_vals}->[$index] = $self->{_atr_last};
    return;
}

# --- calculatePivots(length): pivote causal confirmado `length` barras despues
# Devuelve ($topSwing, $botSwing): el precio del pivote si en ESTE index se
# confirma (transicion de leg), o 0 si no. El indice del pivote es $index-length.
sub _detect_pivot {
    my ($self, $key, $length, $index) = @_;
    return (0, 0) if $index <= $length + 1;

    my $j  = $index - $length;
    my $H  = $self->{_highs};
    my $L  = $self->{_lows};
    my $cHi = $H->[$j];
    my $cLo = $L->[$j];
    return (0, 0) unless defined $cHi && defined $cLo;

    # up = max(high[j+1..index]); dn = min(low[j+1..index]).
    my ($up, $dn);
    for my $i ($j + 1 .. $index) {
        my $h = $H->[$i];
        my $l = $L->[$i];
        next unless defined $h && defined $l;
        $up = $h if !defined $up || $h > $up;
        $dn = $l if !defined $dn || $l < $dn;
    }
    return (0, 0) unless defined $up && defined $dn;

    my $prev = $self->{_leg}{$key};
    my $cur  = $prev;
    if    ($cHi > $up) { $cur = 0; }
    elsif ($cLo < $dn) { $cur = 1; }
    $self->{_leg}{$key} = $cur;

    my $top = ($cur == 0 && $prev != 0) ? $cHi : 0;
    my $bot = ($cur == 1 && $prev != 1) ? $cLo : 0;
    return ($top, $bot);
}

# --- drawStructureExt / drawStructureInternals -------------------------------
# $st: hashref de estado (_ext o _int). $internal: 0/1. $sens: sensibilidad
# (para ubicar el bar del pivote = $index - $sens).
sub _update_structure {
    my ($self, $index, $close, $big_up, $big_dn, $st, $internal, $sens) = @_;
    my $prev_close = $index > 0 ? $self->{_closes}->[$index - 1] : undef;
    my $piv_idx = $index - $sens;

    if ($big_up) {
        $st->{upside} = 1;
        my $label = (defined $st->{upaxis} && $big_up > $st->{upaxis}) ? 'HH' : 'LH';
        push @{ $self->{_swings} }, {
            index => $piv_idx, price => $big_up, label => $label,
            dir => 'up', internal => $internal,
        } unless $internal;   # HH/LH labels solo para externos (showHHLH)
        if (!$internal) {
            push @{ $self->{_high_blocks} }, {
                index => $piv_idx, top => $big_up, bottom => $big_up * 0.998, active => 1,
            };
        }
        $st->{upaxis}  = $big_up;
        $st->{upaxis2} = $piv_idx;
    }

    if ($big_dn) {
        $st->{downside} = 1;
        my $label = (defined $st->{dnaxis} && $big_dn < $st->{dnaxis}) ? 'LL' : 'HL';
        push @{ $self->{_swings} }, {
            index => $piv_idx, price => $big_dn, label => $label,
            dir => 'down', internal => $internal,
        } unless $internal;
        if (!$internal) {
            push @{ $self->{_low_blocks} }, {
                index => $piv_idx, top => $big_dn * 1.002, bottom => $big_dn, active => 1,
            };
        }
        $st->{dnaxis}  = $big_dn;
        $st->{dnaxis2} = $piv_idx;
    }

    return unless defined $prev_close;

    # BOS / CHoCH alcista: crossover(close, upaxis).
    if (defined $st->{upaxis}
        && $prev_close <= $st->{upaxis} && $close > $st->{upaxis}
        && $st->{upside} != 0) {
        my $tag = ($st->{moving} < 0)
            ? ($internal ? 'I-CHoCH' : 'CHoCH')
            : ($internal ? 'I-BoS'   : 'BoS');
        push @{ $self->{_structures} }, {
            from => $st->{upaxis2}, to => $index, price => $st->{upaxis},
            label => $tag, dir => 'up', internal => $internal,
        };
        $st->{upside} = 0;
        $st->{moving} = 1;
    }

    # BOS / CHoCH bajista: crossunder(close, dnaxis).
    if (defined $st->{dnaxis}
        && $prev_close >= $st->{dnaxis} && $close < $st->{dnaxis}
        && $st->{downside} != 0) {
        my $tag = ($st->{moving} > 0)
            ? ($internal ? 'I-CHoCH' : 'CHoCH')
            : ($internal ? 'I-BoS'   : 'BoS');
        push @{ $self->{_structures} }, {
            from => $st->{dnaxis2}, to => $index, price => $st->{dnaxis},
            label => $tag, dir => 'down', internal => $internal,
        };
        $st->{downside} = 0;
        $st->{moving} = -1;
    }

    return;
}

# --- Order blocks: mitigacion + recorte a show_last --------------------------
sub _cleanse_blocks {
    my ($self, $close) = @_;
    # High blocks: se invalidan cuando close >= top.
    @{ $self->{_high_blocks} } =
        grep { $_->{active} && $close < $_->{top} } @{ $self->{_high_blocks} };
    # Low blocks: se invalidan cuando close <= bottom.
    @{ $self->{_low_blocks} } =
        grep { $_->{active} && $close > $_->{bottom} } @{ $self->{_low_blocks} };

    my $keep = $self->{show_last};
    if ($keep && @{ $self->{_high_blocks} } > $keep) {
        @{ $self->{_high_blocks} } = @{ $self->{_high_blocks} }[ -$keep .. -1 ];
    }
    if ($keep && @{ $self->{_low_blocks} } > $keep) {
        @{ $self->{_low_blocks} } = @{ $self->{_low_blocks} }[ -$keep .. -1 ];
    }
    return;
}

# --- FVG de 3 velas ----------------------------------------------------------
# Alcista: low[i] > high[i-2]  (hueco entre vela actual y la de 2 atras).
# Bajista: high[i] < low[i-2].
sub _detect_fvg {
    my ($self, $index, $high, $low) = @_;
    return if $index < 2;
    my $h2 = $self->{_highs}->[$index - 2];
    my $l2 = $self->{_lows}->[$index - 2];
    return unless defined $h2 && defined $l2;

    if ($low > $h2) {
        push @{ $self->{_fvgs} }, {
            index => $index - 1, top => $low, bottom => $h2,
            dir => 'up', active => 1,
        };
    } elsif ($high < $l2) {
        push @{ $self->{_fvgs} }, {
            index => $index - 1, top => $l2, bottom => $high,
            dir => 'down', active => 1,
        };
    }
    return;
}

sub _mitigate_fvg {
    my ($self, $index, $high, $low) = @_;
    # PERF: _fvgs mantiene SOLO gaps activos (un FVG mitigado no se reactiva y
    # get_values ya filtra por active), asi que al mitigar lo eliminamos del
    # array. Evita reescanear gaps muertos cada vela (antes O(N^2) acumulado).
    # Salida identica: get_values devuelve los mismos FVG activos, en orden.
    @{ $self->{_fvgs} } = grep {
        !( ($_->{dir} eq 'up'   && $low  <= $_->{bottom})
        || ($_->{dir} eq 'down' && $high >= $_->{top}) )
    } @{ $self->{_fvgs} };
    return;
}

# --- Area of Interest: zonas sobre/bajo el max/min de los ultimos N closes/opens
sub _compute_aoe {
    my ($self) = @_;
    my $n = $self->{aoe_lookback};
    my $last = $self->{_last_index};
    return undef if $last < $n;

    my ($maxH, $minL);
    for my $i ($last - $n + 1 .. $last) {
        my $c = $self->{_closes}->[$i];
        my $o = $self->{_opens}->[$i];
        next unless defined $c && defined $o;
        my $hi = $c > $o ? $c : $o;
        my $lo = $c < $o ? $c : $o;
        $maxH = $hi if !defined $maxH || $hi > $maxH;
        $minL = $lo if !defined $minL || $lo < $minL;
    }
    return undef unless defined $maxH && defined $minL;
    my $atr = $self->{_atr_last} // 0;
    return {
        from_index => $last - $n + 1,
        high_top    => $maxH + $atr, high_bottom => $maxH,
        low_top     => $minL,        low_bottom  => $minL - $atr,
    };
}

# --- Auto Fibs: linea entre el ultimo swing alto y bajo + niveles ------------
sub _compute_fibs {
    my ($self) = @_;
    my $ext = $self->{_ext};
    return undef unless defined $ext->{upaxis} && defined $ext->{dnaxis}
                     && defined $ext->{upaxis2} && defined $ext->{dnaxis2};

    my ($x1, $y1, $x2, $y2);
    # La pierna mas reciente define la direccion (upaxis2 vs dnaxis2).
    if ($ext->{upaxis2} >= $ext->{dnaxis2}) {
        # Ultimo pivote fue alto: pierna baja->alta.
        $x1 = $ext->{dnaxis2}; $y1 = $ext->{dnaxis};
        $x2 = $ext->{upaxis2}; $y2 = $ext->{upaxis};
    } else {
        $x1 = $ext->{upaxis2}; $y1 = $ext->{upaxis};
        $x2 = $ext->{dnaxis2}; $y2 = $ext->{dnaxis};
    }
    my $span = $y2 - $y1;
    my @levels;
    for my $r (@{ $self->{fib_ratios} }) {
        push @levels, { ratio => $r, price => $y1 + $span * $r };
    }
    return { x1 => $x1, y1 => $y1, x2 => $x2, y2 => $y2, levels => \@levels };
}

# =============================================================================
# API publica
# =============================================================================
sub get_values {
    my ($self) = @_;
    return {
        swings      => $self->{_swings},
        structures  => $self->{_structures},
        high_blocks => [ grep { $_->{active} } @{ $self->{_high_blocks} } ],
        low_blocks  => [ grep { $_->{active} } @{ $self->{_low_blocks} } ],
        fvgs        => [ grep { $_->{active} } @{ $self->{_fvgs} } ],
        aoe         => $self->_compute_aoe(),
        fibs        => $self->_compute_fibs(),
    };
}

1;
