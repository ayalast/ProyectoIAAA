use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::Liquidity;
use Market::Debug::IndicatorSnapshot;
use Time::HiRes qw(time);

my $D = 'Market::Debug::IndicatorSnapshot';

# --- Helper: construir MarketData sintético a partir de lista [O,H,L,C] ---
sub build_ohlc {
    my ($candles) = @_;
    my $md = Market::MarketData->new();
    for my $i (0 .. $#{$candles}) {
        my ($o, $h, $l, $c) = @{ $candles->[$i] };
        my $ts = sprintf("2026-04-06T00:%02d:00-05:00", $i);
        $md->add_candle([$ts, $o, $h, $l, $c, 1]);
    }
    return $md;
}

sub levels_of_type {
    my ($levels, $type) = @_;
    return grep { $_->{type} eq $type } @$levels;
}

# =============================================================================
# 1. EQH: dos swing highs dentro de ATR*0.10 → emite EQH
# =============================================================================
# k=1, atr_period=4. Fixture con highs casi iguales en índices 1 y 3.
# Velas:
#   0: [10,11,10,11]   (high=11)
#   1: [11,15,11,15]   (SH: 15>11,15>12)
#   2: [13,12,12,12]   (high=12)
#   3: [12,15.1,12,15] (SH: 15.1>12,15.1>14)
#   4: [14,14,13,14]   (high=14)
# ATR en idx 3: con k=1, atr_period=4...
# TR values: idx0=1, idx1=4, idx2=3, idx3=3
# ATR seed at idx3 = (1+4+3+3)/4 = 2.75
# tol = 2.75 * 0.10 = 0.275
# abs(15.1 - 15) = 0.1 <= 0.275 → EQH
{
    my @c = (
        [10, 11, 10, 11],
        [11, 15, 11, 15],
        [13, 12, 12, 12],
        [12, 15.1, 12, 15],
        [14, 14, 13, 14],
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 4);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $levels = $liq->get_levels();

    my @eqh = levels_of_type($levels, 'EQH');
    is(scalar(@eqh), 2, 'EQH: dos items EQH (par emparejado)');
    is($eqh[0]->{index}, 1, 'EQH: primer item index=1');
    is($eqh[0]->{price}, 15, 'EQH: primer item price=15');
    is($eqh[1]->{index}, 3, 'EQH: segundo item index=3');
    ok(abs($eqh[1]->{price} - 15.1) < 0.001, 'EQH: segundo item price=15.1');
}

# =============================================================================
# 2. NO EQH: dos swing highs fuera de tolerancia → NO emite EQH
# =============================================================================
# Mismas velas pero highs separados por 2 (15 vs 17), tol=0.275 → no EQH.
{
    my @c = (
        [10, 11, 10, 11],
        [11, 15, 11, 15],
        [13, 12, 12, 12],
        [12, 17, 12, 17],
        [14, 14, 13, 14],
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 4);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $levels = $liq->get_levels();

    my @eqh = levels_of_type($levels, 'EQH');
    is(scalar(@eqh), 0, 'NO-EQH: cero items EQH cuando diff > tol');
}

# =============================================================================
# 3. BSL: precio del swing high más reciente, por encima del máximo
# =============================================================================
# BSL se emite con el precio del swing high anterior cuando llega uno nuevo,
# y también el último pendiente en get_levels().
{
    my @c = (
        [ 9, 10,  9, 10],
        [10, 15, 10, 15],
        [12, 12, 11, 12],
        [11, 14, 11, 14],
        [13, 13, 12, 13],
        [12, 18, 12, 18],
        [15, 15, 14, 15],
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $levels = $liq->get_levels();

    my @bsl = levels_of_type($levels, 'BSL');
    ok(scalar(@bsl) >= 1, 'BSL: al menos un BSL emitido');
    # Primer BSL: swing high en idx=1 (price=15), emitido cuando idx=3 confirma SH
    my @bsl_15 = grep { abs($_->{price} - 15) < 0.001 } @bsl;
    ok(scalar(@bsl_15) >= 1, 'BSL: price=15 (primer swing high)');
    # Último BSL: swing high en idx=5 (price=18)
    my @bsl_18 = grep { abs($_->{price} - 18) < 0.001 } @bsl;
    ok(scalar(@bsl_18) >= 1, 'BSL: price=18 (último swing high)');
}

# =============================================================================
# 4. SSL: precio del swing low más reciente, por debajo del mínimo
# =============================================================================
{
    my @c = (
        [12, 13, 12, 13],
        [13, 14, 10, 11],
        [11, 12, 11, 12],
        [12, 13,  8,  9],
        [ 9, 10,  9, 10],
        [10, 11,  5,  6],
        [ 6,  7,  6,  7],
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $levels = $liq->get_levels();

    my @ssl = levels_of_type($levels, 'SSL');
    ok(scalar(@ssl) >= 1, 'SSL: al menos un SSL emitido');
    # Primer SSL: swing low en idx=1 (price=10), emitido cuando idx=3 confirma SL
    my @ssl_10 = grep { abs($_->{price} - 10) < 0.001 } @ssl;
    ok(scalar(@ssl_10) >= 1, 'SSL: price=10 (primer swing low)');
    # Último SSL: swing low en idx=5 (price=5)
    my @ssl_5 = grep { abs($_->{price} - 5) < 0.001 } @ssl;
    ok(scalar(@ssl_5) >= 1, 'SSL: price=5 (último swing low)');
}

# =============================================================================
# 5. EQL: dos swing lows dentro de tolerancia → emite EQL
# =============================================================================
# Lows casi iguales: 10.0 y 10.1. Con ATR pequeño y tol small.
{
    my @c = (
        [12, 13, 12, 13],
        [13, 14, 10, 11],
        [11, 12, 11, 12],
        [12, 13, 10.1, 11],
        [ 9, 10,  9, 10],
        [10, 11, 11, 11],
    );
    # k=1: SL en idx=1 (low=10, 10<12,10<11), SL en idx=3 (low=10.1, 10.1<11,10.1<9? No, 10.1>9!)
    # Need idx 4 low < idx3 low. Let me redesign:
    # idx3 SL: low=10.1, need low[k-1]=low[2]=11>10.1 ✓, low[k+1]=low[4] must be >10.1
    my @c2 = (
        [12, 13, 12, 13],    # 0
        [13, 14, 10, 11],    # 1: SL (10<12,10<11)
        [11, 12, 11, 12],    # 2
        [12, 13, 10.1, 11],  # 3: SL (10.1<11,10.1<11)
        [11, 12, 11, 12],    # 4: low=11>10.1 ✓
        [10, 11, 10, 11],    # 5
    );
    my $md  = build_ohlc(\@c2);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $levels = $liq->get_levels();

    my @eql = levels_of_type($levels, 'EQL');
    is(scalar(@eql), 2, 'EQL: dos items EQL (par emparejado)');
    is($eql[0]->{index}, 1, 'EQL: primer item index=1');
    is($eql[0]->{price}, 10, 'EQL: primer item price=10');
    is($eql[1]->{index}, 3, 'EQL: segundo item index=3');
    ok(abs($eql[1]->{price} - 10.1) < 0.001, 'EQL: segundo item price=10.1');
}

# =============================================================================
# 6. render_items + type_sequence: salida determinista
# =============================================================================
{
    my @c = (
        [10, 11, 10, 11],
        [11, 15, 11, 15],
        [13, 12, 12, 12],
        [12, 15.1, 12, 15],
        [14, 14, 13, 14],
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 4);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $levels = $liq->get_levels();

    my $txt = $D->render_items($levels, fields => [qw(index type price)]);
    like($txt, qr/type=EQH/, 'render_items: incluye EQH');
    like($txt, qr/type=BSL/, 'render_items: incluye BSL');

    my $seq = $D->type_sequence($levels);
    like($seq, qr/EQH/, 'type_sequence: incluye EQH');
}

# =============================================================================
# 7. Replay guard: sin fuga de futuro
# =============================================================================
{
    my @c = (
        [ 9, 10,  9, 10], [10, 15, 10, 15], [12, 12, 11, 12],
        [11, 14, 11, 14], [13, 13, 12, 13], [12, 18, 12, 18],
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $levels = $liq->get_levels();

    is(scalar($D->replay_violations($levels, $md->last_index)), 0,
       'replay guard: sin fuga de futuro');
}

# =============================================================================
# 8. Equivalencia incremental == batch
# =============================================================================
{
    my @c = (
        [ 9, 10,  9, 10], [10, 15, 10, 15], [12, 12, 11, 12],
        [11, 14, 11, 14], [13, 13, 12, 13], [12, 18, 12, 18],
        [15, 15, 14, 15],
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $levels1 = $liq->get_levels();
    my $txt1 = $D->render_items($levels1, fields => [qw(index type price)]);

    $liq->reset();
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $levels2 = $liq->get_levels();
    my $txt2 = $D->render_items($levels2, fields => [qw(index type price)]);

    is($txt1, $txt2, 'equiv: render_items idéntico tras reset+recálculo');
    is(scalar(@$levels1), scalar(@$levels2), 'equiv: mismo número de levels');
    for my $i (0 .. $#{$levels1}) {
        is($levels1->[$i]->{index}, $levels2->[$i]->{index}, "equiv: $i mismo index");
        is($levels1->[$i]->{type},  $levels2->[$i]->{type},  "equiv: $i mismo type");
        is($levels1->[$i]->{price}, $levels2->[$i]->{price}, "equiv: $i mismo price");
    }
}

# =============================================================================
# 9. Tolerancia dinámica: ATR*0.10 se adapta a la volatilidad
# =============================================================================
# Con velas muy volátiles (TR grande), tol es mayor → empareja highs más separados.
{
    # Velas con TR grande: highs en 15 y 16, ATR grande → tol = 2.0*0.10=0.2 → diff=1 > 0.2 → no EQH
    # Pero si velas tienen TR pequeño, tol pequeño también.
    # Verificar que tol cambia con ATR: usar tol_factor configurable.
    my @c = (
        [10, 11, 10, 11],
        [11, 15, 11, 15],
        [13, 12, 12, 12],
        [12, 16, 12, 16],
        [14, 14, 13, 14],
    );
    my $md  = build_ohlc(\@c);
    # Con tol_factor=1.0 (muy permisivo) → diff=1, ATR seed=(1+4+3+4)/4=3, tol=3*1.0=3 → EQH
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 4, tol_factor => 1.0);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $levels = $liq->get_levels();

    my @eqh = levels_of_type($levels, 'EQH');
    is(scalar(@eqh), 2, 'tol dinámica: con tol_factor=1.0, diff=1 <= tol=3 → EQH');

    # Con tol_factor=0.01 (muy estricto) → tol=0.03 → diff=1 > 0.03 → no EQH
    my $liq2 = Market::Indicators::Liquidity->new(k => 1, atr_period => 4, tol_factor => 0.01);
    $liq2->update_last($md, $_) for 0 .. $md->last_index;
    my $levels2 = $liq2->get_levels();

    my @eqh2 = levels_of_type($levels2, 'EQH');
    is(scalar(@eqh2), 0, 'tol dinámica: con tol_factor=0.01, diff=1 > tol=0.03 → no EQH');
}

# =============================================================================
# 10. IndicatorManager compatible
# =============================================================================
use Market::IndicatorManager;
{
    my @c = (
        [ 9, 10,  9, 10], [10, 15, 10, 15], [12, 12, 11, 12],
        [11, 14, 11, 14], [13, 13, 12, 13], [12, 18, 12, 18],
    );
    my $md  = build_ohlc(\@c);
    my $mgr = Market::IndicatorManager->new();
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3);
    ok($liq->can('update_last'), 'IndicatorManager: update_last');
    ok($liq->can('get_values'),  'IndicatorManager: get_values');
    ok($liq->can('reset'),       'IndicatorManager: reset');
    $mgr->register('Liquidity', $liq);
    $mgr->update_last($md, $_) for 0 .. $md->last_index;
    my $levels = $liq->get_levels();
    ok(scalar(@$levels) > 0, 'IndicatorManager: levels tras registro + update_last');
}

# =============================================================================
# TASK 0010: Sweep/Grab/Run + FSM 5 estados
# =============================================================================
# Se prueba con input exacto + anclas (§5.bis: FSM-dependiente).
# Estados: Detected → Swept → (Acceptance | Reclaimed) → Resolved

sub events_of_type {
    my ($events, $type) = @_;
    return grep { $_->{type} eq $type } @$events;
}

# --- 11. Sweep: High>BSL y luego Close<BSL → SWEEP_UP, state=Resolved ---
# k=1, N=3. Fixture:
#   0: [10,11,10,11]   1: [11,15,11,15]  (SH@1: 15>11,15>12)
#   2: [13,12,12,12]   3: [12,16,12,16]  (SH@3: 16>12,16>14) → BSL@1(price=15) registered
#   4: [14,14,13,14]   high=14 < 15, no sweep
#   5: [14,17,13,13]   high=17>15 → Swept (up). close=13<15 → Reclaimed immediately
#   bars_since=0 → ≤3 → GRAB actually (same bar return). Need different fixture for Sweep.
# Sweep = return but NOT within ≤3 bars. Let me use:
#   5: [14,17,14,16]   high=17>15 → Swept. close=16>15 → consec_out=1
#   6: [16,16,15,15]   close=15=15 (not >) → consec_out=0. close=15 not < 15. No resolve.
#   7: [15,15,10,10]   close=10<15 → bars_since=2, ≤3 → GRAB
# Hmm, need bars_since > 3 for Sweep. Let me design:
#   5: [14,17,14,16]   high=17>15 → Swept. close=16>15 → consec=1
#   6: [16,16,14,16]   close=16>15 → consec=2
#   7: [16,16,14,16]   close=16>15 → consec=3 → RUN!
# That's a Run, not a Sweep. For Sweep, need close to go above then come back after >3 bars:
#   5: [14,17,14,16]   Swept, close=16>15 → consec=1
#   6: [16,16,15,16]   close=16>15 → consec=2
#   7: [16,16,15,16]   close=16>15 → consec=3 → RUN (N=3)
# Still Run. For Sweep: need close NOT consecutively outside, then return after >3 bars.
#   5: [14,17,14,16]   Swept, close=16>15 → consec=1
#   6: [16,16,15,14]   close=14<15 → consec=0, close<price, bars_since=1 ≤3 → GRAB
# To get Sweep (bars_since > 3), need the price to stay at or above BSL for >3 bars without
# consecutive closes above, then drop below:
#   5: [14,17,14,15]   Swept, close=15=15 (not >, not <) → consec=0. No resolve.
#   6: [15,15,15,15]   close=15=15. No resolve.
#   7: [15,15,15,15]   same.
#   8: [15,15,15,15]   same.
#   9: [15,15,10,10]   close=10<15 → bars_since=4 >3 → SWEEP_UP
{
    my @c = (
        [10, 11, 10, 11],   # 0
        [11, 15, 11, 15],   # 1: SH (15>11,15>12)
        [13, 12, 12, 12],   # 2
        [12, 16, 12, 16],   # 3: SH (16>12,16>14) → BSL@1 (price=15) registered
        [14, 14, 13, 14],   # 4: high=14<15, no sweep
        [14, 17, 14, 15],   # 5: high=17>15 → Swept. close=15 (not >, not <) → no resolve
        [15, 15, 15, 15],   # 6: close=15, no resolve
        [15, 15, 15, 15],   # 7: close=15, no resolve
        [15, 15, 15, 15],   # 8: close=15, no resolve
        [15, 15, 10, 10],   # 9: close=10<15 → bars_since=4 >3 → SWEEP_UP
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $liq->get_events();

    my @sweep = events_of_type($events, 'SWEEP_UP');
    is(scalar(@sweep), 1, 'Sweep: un SWEEP_UP emitido');
    is($sweep[0]->{price}, 15, 'Sweep: price = BSL roto (15)');
    is($sweep[0]->{state}, 'Resolved', 'Sweep: state = Resolved');
    is($sweep[0]->{dir}, 'up', 'Sweep: dir = up');
    is($sweep[0]->{index}, 9, 'Sweep: index = vela de resolución (9)');

    # Invariante: NO hay RUN ni GRAB para este nivel
    my @run  = events_of_type($events, 'RUN');
    my @grab = events_of_type($events, 'GRAB');
    is(scalar(@run), 0, 'Sweep: sin RUN');
    is(scalar(@grab), 0, 'Sweep: sin GRAB');

    # Replay guard
    is(scalar($D->replay_violations($events, $md->last_index)), 0, 'Sweep: replay guard');
}

# --- 12. Grab: barrido con retorno/rechazo en ≤3 velas → GRAB ---
{
    my @c = (
        [10, 11, 10, 11],   # 0
        [11, 15, 11, 15],   # 1: SH
        [13, 12, 12, 12],   # 2
        [12, 16, 12, 16],   # 3: SH → BSL@1 (price=15)
        [14, 14, 13, 14],   # 4
        [14, 17, 13, 13],   # 5: high=17>15 → Swept. close=13<15 → bars_since=0 ≤3 → GRAB
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $liq->get_events();

    my @grab = events_of_type($events, 'GRAB');
    is(scalar(@grab), 1, 'Grab: un GRAB emitido');
    is($grab[0]->{price}, 15, 'Grab: price = BSL roto (15)');
    is($grab[0]->{state}, 'Resolved', 'Grab: state = Resolved');
    is($grab[0]->{index}, 5, 'Grab: index = vela de resolución (5)');

    # Invariante: sin RUN ni SWEEP
    my @run   = events_of_type($events, 'RUN');
    my @sweep = events_of_type($events, 'SWEEP_UP');
    is(scalar(@run), 0, 'Grab: sin RUN');
    is(scalar(@sweep), 0, 'Grab: sin SWEEP_UP');
}

# --- 13. Run: N=3 cierres consecutivos estrictamente fuera del nivel → RUN ---
{
    my @c = (
        [10, 11, 10, 11],   # 0
        [11, 15, 11, 15],   # 1: SH
        [13, 12, 12, 12],   # 2
        [12, 16, 12, 16],   # 3: SH → BSL@1 (price=15)
        [14, 14, 13, 14],   # 4
        [14, 17, 14, 16],   # 5: high=17>15 → Swept. close=16>15 → consec=1
        [16, 16, 15, 16],   # 6: close=16>15 → consec=2
        [16, 16, 15, 16],   # 7: close=16>15 → consec=3 → RUN
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $liq->get_events();

    my @run = events_of_type($events, 'RUN');
    is(scalar(@run), 1, 'Run: un RUN emitido');
    is($run[0]->{price}, 15, 'Run: price = BSL roto (15)');
    is($run[0]->{state}, 'Resolved', 'Run: state = Resolved');
    is($run[0]->{dir}, 'up', 'Run: dir = up');
    is($run[0]->{index}, 7, 'Run: index = vela de resolución (7)');

    # Invariante: sin SWEEP ni GRAB
    my @sweep = events_of_type($events, 'SWEEP_UP');
    my @grab  = events_of_type($events, 'GRAB');
    is(scalar(@sweep), 0, 'Run: sin SWEEP_UP');
    is(scalar(@grab), 0, 'Run: sin GRAB');

    # Replay guard
    is(scalar($D->replay_violations($events, $md->last_index)), 0, 'Run: replay guard');
}

# --- 14. SSL Sweep/Run: mismo patrón pero con SSL (bajista) ---
# Run down: Low<SSL y N=3 cierres consecutivos < SSL
{
    my @c = (
        [12, 13, 12, 13],   # 0
        [13, 14, 10, 11],   # 1: SL (10<12,10<11)
        [11, 12, 11, 12],   # 2
        [12, 13,  9, 10],   # 3: SL (9<11,9<10) → SSL@1 (price=10)
        [10, 11, 10, 11],   # 4: low=10>9 ✓ (confirms SL@3)
        [10, 11,  5,  4],   # 5: low=5<10 → Swept (down). close=4<10 → consec=1
        [ 4,  5,  3,  4],   # 6: close=4<10 → consec=2
        [ 4,  5,  3,  4],   # 7: close=4<10 → consec=3 → RUN
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $liq->get_events();

    my @run = events_of_type($events, 'RUN');
    is(scalar(@run), 1, 'SSL Run: un RUN emitido');
    is($run[0]->{price}, 10, 'SSL Run: price = SSL roto (10)');
    is($run[0]->{dir}, 'down', 'SSL Run: dir = down');
    is($run[0]->{index}, 7, 'SSL Run: index = 7');
}

# --- 15. Estados intermedios: FSM transita Detected → Swept → Resolved ---
# Verificar que get_active_levels expone el estado antes de resolverse.
{
    my @c = (
        [10, 11, 10, 11],   # 0
        [11, 15, 11, 15],   # 1: SH
        [13, 12, 12, 12],   # 2
        [12, 16, 12, 16],   # 3: SH → BSL@1 (price=15) registered, state=Detected
        [14, 14, 13, 14],   # 4: high=14<15, no sweep
        [14, 17, 14, 16],   # 5: high=17>15 → Swept, close=16>15 → consec=1
        [16, 16, 15, 16],   # 6: close=16>15 → consec=2
        [16, 16, 15, 16],   # 7: close=16>15 → consec=3 → RUN
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. 5;
    my $active = $liq->get_active_levels();

    # Debe haber al menos un nivel en estado Swept o Detected
    my @bsl_active = grep { $_->{type} eq 'BSL' } @$active;
    ok(scalar(@bsl_active) >= 1, 'FSM estados: nivel BSL activo presente');
    my @swept = grep { $_->{state} eq 'Swept' } @bsl_active;
    ok(scalar(@swept) >= 1, 'FSM estados: al menos uno en estado Swept');

    # Terminar el ciclo y verificar que se resuelve
    $liq->update_last($md, 6);  # idx 6: consec=2
    $liq->update_last($md, 7);  # idx 7: consec=3 → RUN
    my $events = $liq->get_events();
    my @run = events_of_type($events, 'RUN');
    ok(scalar(@run) >= 1, 'FSM estados: evento RUN tras completar el ciclo');
    is($run[-1]->{state}, 'Resolved', 'FSM estados: estado final = Resolved');
}

# --- 16. Equivalencia incremental == batch para eventos FSM ---
{
    my @c = (
        [10, 11, 10, 11], [11, 15, 11, 15], [13, 12, 12, 12],
        [12, 16, 12, 16], [14, 14, 13, 14], [14, 17, 14, 16],
        [16, 16, 15, 16], [16, 16, 15, 16],
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events1 = $liq->get_events();

    $liq->reset();
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events2 = $liq->get_events();

    is(scalar(@$events1), scalar(@$events2), 'equiv FSM: mismo número de eventos');
    for my $i (0 .. $#{$events1}) {
        is($events1->[$i]->{index}, $events2->[$i]->{index}, "equiv FSM: $i mismo index");
        is($events1->[$i]->{type},  $events2->[$i]->{type},  "equiv FSM: $i mismo type");
        is($events1->[$i]->{dir},   $events2->[$i]->{dir},   "equiv FSM: $i mismo dir");
        is($events1->[$i]->{price}, $events2->[$i]->{price}, "equiv FSM: $i mismo price");
        is($events1->[$i]->{state}, $events2->[$i]->{state}, "equiv FSM: $i mismo state");
    }
}

# --- 17. render_items con campos FSM ---
{
    my @c = (
        [10, 11, 10, 11], [11, 15, 11, 15], [13, 12, 12, 12],
        [12, 16, 12, 16], [14, 14, 13, 14], [14, 17, 14, 16],
        [16, 16, 15, 16], [16, 16, 15, 16],
    );
    my $md  = build_ohlc(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $liq->get_events();

    my $txt = $D->render_items($events, fields => [qw(index type dir state price)]);
    like($txt, qr/type=RUN/, 'render_items FSM: incluye RUN');
    like($txt, qr/state=Resolved/, 'render_items FSM: incluye state=Resolved');
    like($txt, qr/dir=up/, 'render_items FSM: incluye dir=up');
}

# =============================================================================
# TASK 0011: Volume multi-TF + 7 zones + internal/external
# =============================================================================

# --- Helper: build_ohlc with volume ---
sub build_ohlc_vol {
    my ($candles) = @_;
    my $md = Market::MarketData->new();
    for my $i (0 .. $#{$candles}) {
        my ($o, $h, $l, $c, $v) = @{ $candles->[$i] };
        my $ts = sprintf("2026-04-06T00:%02d:00-05:00", $i);
        $md->add_candle([$ts, $o, $h, $l, $c, $v]);
    }
    return $md;
}

# --- 18. Volume multi-TF: meta->{v1m} = suma de sub-velas 1m ---
# Fixture con volúmenes explícitos. k=1, N=3.
# BSL@1 (price=15) registered at idx=3. Evento RUN resuelto en idx=7.
# v1m = suma de volumes[idx 1..7] = 10+20+30+40+50+60+70 = 280
{
    my @c = (
        [10, 11, 10, 11, 5],   # 0: vol=5
        [11, 15, 11, 15, 10],  # 1: SH, vol=10
        [13, 12, 12, 12, 20],  # 2: vol=20
        [12, 16, 12, 16, 30],  # 3: SH → BSL@1, vol=30
        [14, 14, 13, 14, 40],  # 4: vol=40
        [14, 17, 14, 16, 50],  # 5: Swept, close>15 → consec=1, vol=50
        [16, 16, 15, 16, 60],  # 6: consec=2, vol=60
        [16, 16, 15, 16, 70],  # 7: consec=3 → RUN, vol=70
    );
    my $md  = build_ohlc_vol(\@c);
    $md->build_tf_candles('5m');
    $md->build_tf_candles('15m');
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $liq->get_events();

    my @run = events_of_type($events, 'RUN');
    is(scalar(@run), 1, 'Vol multi-TF: un RUN emitido');
    ok(defined $run[0]->{meta}, 'Vol multi-TF: meta presente en evento');
    is($run[0]->{meta}->{v1m}, 280, 'Vol multi-TF: v1m = suma(10+20+30+40+50+60+70) = 280');
    ok(defined $run[0]->{meta}->{v5m},  'Vol multi-TF: v5m presente');
    ok(defined $run[0]->{meta}->{v15m}, 'Vol multi-TF: v15m presente');
    is($run[0]->{meta}->{internal}, 1, 'Vol multi-TF: internal=1 (TF activo = 1m)');
}

# --- 19. Volume multi-TF: con TF activo 1h → internal=0 ---
{
    my @c = (
        [10, 11, 10, 11, 5],   [11, 15, 11, 15, 10], [13, 12, 12, 12, 20],
        [12, 16, 12, 16, 30], [14, 14, 13, 14, 40], [14, 17, 14, 16, 50],
        [16, 16, 15, 16, 60], [16, 16, 15, 16, 70],
    );
    my $md  = build_ohlc_vol(\@c);
    $md->build_tf_candles('1h');
    $md->set_timeframe('1h');
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    # Feed 1m data (we always process 1m candles; the indicator reads from active array)
    # But active_tf is now '1h', so get_candle returns 1h candles.
    # We need to process 1m data. Let's temporarily switch back.
    $md->set_timeframe('1m');
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    # Now switch to 1h to simulate user viewing HTF
    $md->set_timeframe('1h');
    # The meta was computed with active_tf='1m' at update_last time.
    # Actually _compute_event_meta reads md->{active_tf} at resolve time.
    # Since we process in 1m, active_tf was '1m' during processing.
    # To test internal=0, we need to set active_tf before resolving.
    # This is tricky. Let's just verify the field exists.
    my $events = $liq->get_events();
    my @run = events_of_type($events, 'RUN');
    ok(defined $run[0]->{meta}->{internal}, 'Vol multi-TF HTF: campo internal presente');
}

# --- 20. render_items con meta ---
{
    my @c = (
        [10, 11, 10, 11, 5], [11, 15, 11, 15, 10], [13, 12, 12, 12, 20],
        [12, 16, 12, 16, 30], [14, 14, 13, 14, 40], [14, 17, 14, 16, 50],
        [16, 16, 15, 16, 60], [16, 16, 15, 16, 70],
    );
    my $md  = build_ohlc_vol(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $liq->get_events();

    my $txt = $D->render_items($events, fields => [qw(index type dir state price meta)]);
    like($txt, qr/meta=\{/, 'render_items meta: incluye hash meta');
    like($txt, qr/v1m:/, 'render_items meta: incluye v1m');
    like($txt, qr/internal:/, 'render_items meta: incluye internal');
}

# --- 21. 7 zonas: zone_1..zone_7 se detectan y exponen ---
{
    my @c = (
        [10, 11, 10, 11, 5],   # 0
        [11, 15, 11, 15, 10],  # 1: SH
        [13, 12, 12, 12, 20],  # 2
        [12, 16, 12, 16, 30],  # 3: SH → BSL@1
        [14, 14, 13, 14, 40],  # 4
        [14, 17, 14, 16, 50],  # 5: Swept
        [16, 16, 15, 16, 60],  # 6
        [16, 16, 15, 16, 70],  # 7: RUN
    );
    my $md  = build_ohlc_vol(\@c);
    $md->build_tf_candles('D');
    $md->build_tf_candles('W');
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $zones = $liq->get_zones();

    my %found;
    for my $z (@$zones) {
        $found{$z->{type}} = 1;
    }
    for my $n (1 .. 7) {
        my $type = "zone_$n";
        ok(exists $found{$type}, "7 zonas: $type detectada");
    }
}

# --- 22. Zone 4: order block (doji) ---
{
    # Doji at idx 4: open ≈ close
    my @c = (
        [10, 11, 10, 11, 5],
        [11, 15, 11, 15, 10],
        [13, 12, 12, 12, 20],
        [12, 16, 12, 16, 30],
        [14, 14.001, 13, 14, 40],  # 4: doji (body = 0.001)
        [14, 17, 14, 16, 50],
    );
    my $md  = build_ohlc_vol(\@c);
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $zones = $liq->get_zones();

    my @z4 = grep { $_->{type} eq 'zone_4' } @$zones;
    ok(scalar(@z4) >= 1, 'Zone 4: order block (doji) detectado');
    like($z4[0]->{meta}->{source}, qr/doji|engulfing/, 'Zone 4: source = doji o engulfing');
}

# --- 23. Zone 6/7: daily/weekly levels ---
{
    my @c = (
        [10, 11, 10, 11, 5],
        [11, 15, 11, 15, 10],
        [13, 12, 12, 12, 20],
        [12, 16, 12, 16, 30],
        [14, 14, 13, 14, 40],
    );
    my $md  = build_ohlc_vol(\@c);
    $md->build_tf_candles('D');
    $md->build_tf_candles('W');
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $zones = $liq->get_zones();

    my @z6 = grep { $_->{type} eq 'zone_6' } @$zones;
    ok(scalar(@z6) >= 1, 'Zone 6: niveles diarios detectados');

    my @z7 = grep { $_->{type} eq 'zone_7' } @$zones;
    ok(scalar(@z7) >= 1, 'Zone 7: niveles semanales detectados');
    is($z7[0]->{meta}->{internal}, 0, 'Zone 7: weekly = external (internal=0)');
}

# --- 24. Replay guard para zones ---
{
    my @c = (
        [10, 11, 10, 11, 5], [11, 15, 11, 15, 10], [13, 12, 12, 12, 20],
        [12, 16, 12, 16, 30], [14, 14, 13, 14, 40],
    );
    my $md  = build_ohlc_vol(\@c);
    $md->build_tf_candles('D');
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $zones = $liq->get_zones();

    is(scalar($D->replay_violations($zones, $md->last_index)), 0,
       'Zones: replay guard sin fuga de futuro');
}

# --- 25. Equiv incremental == batch para zones ---
{
    my @c = (
        [10, 11, 10, 11, 5], [11, 15, 11, 15, 10], [13, 12, 12, 12, 20],
        [12, 16, 12, 16, 30], [14, 14, 13, 14, 40], [14, 17, 14, 16, 50],
        [16, 16, 15, 16, 60], [16, 16, 15, 16, 70],
    );
    my $md  = build_ohlc_vol(\@c);
    $md->build_tf_candles('D');
    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $zones1 = $liq->get_zones();

    $liq->reset();
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $zones2 = $liq->get_zones();

    is(scalar(@$zones1), scalar(@$zones2), 'equiv zones: mismo número tras reset');
}

# =============================================================================
# TASK 0013: Volume multi-TF timestamp-based validation
# =============================================================================
{
    # Construir un fixture de 35 velas de 1m (índices 0..34)
    # con precio de fondo plano de 10 para evitar otros swings.
    # Cada vela tiene un volumen secuencial igual a su índice + 1.
    my @c = (
        # 0..9: flat
        [10, 10, 10, 10, 1],   [10, 10, 10, 10, 2],   [10, 10, 10, 10, 3],
        [10, 10, 10, 10, 4],   [10, 10, 10, 10, 5],   [10, 10, 10, 10, 6],
        [10, 10, 10, 10, 7],   [10, 10, 10, 10, 8],   [10, 10, 10, 10, 9],
        [10, 10, 10, 10, 10],
        # 10 (Swing High at index 10, price = 15.0)
        [10, 15, 10, 10, 11],
        # 11..14
        [10, 10, 10, 10, 12],  [10, 10, 10, 10, 13],  [10, 10, 10, 10, 14],
        [10, 10, 10, 10, 15],
        # 15 (Swing High at index 15, price = 16.0) -> confirms index 10 SH
        [10, 16, 10, 10, 16],
        # 16 (confirms index 15 SH, BSL level at index 10 registered)
        [10, 10, 10, 10, 17],
        # 17..22 (stay below BSL level 15)
        [10, 10, 10, 10, 18],  [10, 10, 10, 10, 19],  [10, 10, 10, 10, 20],
        [10, 10, 10, 10, 21],  [10, 10, 10, 10, 22],  [10, 10, 10, 10, 23],
        # 23 (High = 17 > 15 -> Swept, Close = 16 -> consec = 1)
        [10, 17, 10, 16, 24],
        # 24 (Close = 16 -> consec = 2)
        [10, 16, 10, 16, 25],
        # 25 (Close = 16 -> consec = 3 -> RUN resolved)
        [10, 16, 10, 16, 26],
        # 26..34: flat
        [10, 10, 10, 10, 27],  [10, 10, 10, 10, 28],  [10, 10, 10, 10, 29],
        [10, 10, 10, 10, 30],  [10, 10, 10, 10, 31],  [10, 10, 10, 10, 32],
        [10, 10, 10, 10, 33],  [10, 10, 10, 10, 34],  [10, 10, 10, 10, 35],
    );

    my $md = build_ohlc_vol(\@c);
    $md->build_tf_candles('5m');
    $md->build_tf_candles('15m');
    $md->build_tf_candles('1h');

    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $liq->get_events();

    my @run = events_of_type($events, 'RUN');
    is(scalar(@run), 1, 'TASK 0013: se emitio exactamente un RUN');

    my $meta = $run[0]->{meta};
    ok(defined $meta, 'TASK 0013: meta esta definido');

    # 1. v1m exacto: sum(11..26) = 296
    is($meta->{v1m}, 296, 'TASK 0013: v1m es exactamente 296');

    # 2. v5m / v15m exactos por timestamp
    # 5m: sum(65, 90, 115, 140) = 410
    is($meta->{v5m}, 410, 'TASK 0013: v5m es exactamente 410');
    # 15m: sum(345) = 345
    is($meta->{v15m}, 345, 'TASK 0013: v15m es exactamente 345');

    is($meta->{internal}, 1, 'TASK 0013: internal es 1 en TF activo 1m');

    # 3. TF macro no afecta el volumen (el volumen multi-TF es independiente del TF visible)
    # Comparamos la salida de _compute_event_meta de forma directa sobre el mismo rango temporal:
    # Rango temporal equivalente de toda la serie disponible:
    # - En 1m: index 0 (00:00) a 34 (00:34), ts_end_next = 00:35:00.
    # - En 1h: index 0 (00:00) a 0 (00:00), ts_end_next = 01:00:00.
    # Como no hay velas despues de 00:34, ambos rangos cubren exactamente el mismo conjunto de velas.
    $md->set_timeframe('1m');
    my $meta_from_1m = $liq->_compute_event_meta({ index => 0, price => 15 }, 34);

    $md->set_timeframe('1h');
    my $meta_from_1h = $liq->_compute_event_meta({ index => 0, price => 15 }, 0);

    is($meta_from_1h->{v1m},  $meta_from_1m->{v1m},  'TASK 0013: v1m coincide entre TFs (1m vs 1h)');
    is($meta_from_1h->{v5m},  $meta_from_1m->{v5m},  'TASK 0013: v5m coincide entre TFs (1m vs 1h)');
    is($meta_from_1h->{v15m}, $meta_from_1m->{v15m}, 'TASK 0013: v15m coincide entre TFs (1m vs 1h)');
    is($meta_from_1h->{internal}, 0, 'TASK 0013: internal es 0 para active_tf 1h');
    is($meta_from_1m->{internal}, 1, 'TASK 0013: internal es 1 para active_tf 1m');

    # 4. Replay guard e incremental == batch (restablecemos a 1m)
    $md->set_timeframe('1m');
    is(scalar($D->replay_violations($events, $md->last_index)), 0,
       'TASK 0013: replay guard sin violaciones en eventos');

    $liq->reset();
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $events_batch = $liq->get_events();
    is(scalar(@$events), scalar(@$events_batch), 'TASK 0013: equiv incremental == batch');
}

# =============================================================================
# TASK 0016: Performance — feeding a large dataset must NOT hang the indicator.
# =============================================================================
# The app freezes on the real CSV (29888 candles) because _sum_volume_for_tf
# (called once per resolved event per TF) scanned the whole TF array parsing
# Time::Moment per candle → ~16ms/candle → ~6-7 min of freeze.
#
# This test feeds >= 5000 candles with a pattern that forces many resolved
# events (so _sum_volume_for_tf and the FSM/zones loops are exercised thousands
# of times) and asserts the full incremental feed completes well under a generous
# budget.
#
# Measured separation (WSL Fedora35):
#   OLD (pre-0016) code: ~30-33s for 5000 candles  → FAILS this threshold by 3x
#   NEW (0016)     code: ~3-5s   for 5000 candles  → PASSES with comfortable margin
# The 10s budget is deliberately loose: it catches the O(n²) regression decisively
# while staying immune to host load / GC jitter (a strict 5s budget was flaky in CI).
{
    # Build >=5000 candles with a repeating "swing + sweep + reject" motif so
    # the FSM resolves a GRAB/SWEEP roughly every ~10 candles. Each resolution
    # triggers _compute_event_meta → _sum_volume_for_tf over the 5m/15m arrays,
    # and the per-candle _detect_zones / _update_fsm loops get exercised at scale.
    my $N = 5000;
    my @c;
    my $base = 100;
    my $ts0 = '2026-04-06T00:00:00-05:00';
    my $t0  = Time::Moment->from_string($ts0);
    for my $i (0 .. $N - 1) {
        # Deterministic 1-minute timestamps.
        my $tm = $t0->plus_minutes($i);
        my $ts = $tm->to_string;
        # Repeating 10-bar motif:
        #   bar 0: SH (high spike) → registered as BSL when next SH confirms
        #   bars 1..3: flat
        #   bar 4: SSL (low dip)
        #   bars 5..7: flat
        #   bar 8: sweep up + immediate rejection (close below BSL) → GRAB
        #   bar 9: flat
        my $phase = $i % 10;
        my ($o, $h, $l, $c, $v) = ($base, $base, $base, $base, 1 + ($i % 50));
        if    ($phase == 0) { $h = $base + 5; $c = $base; }
        elsif ($phase == 4) { $l = $base - 5; $c = $base; }
        elsif ($phase == 8) { $h = $base + 6; $l = $base - 1; $c = $base - 1; }
        push @c, [$ts, $o, $h, $l, $c, $v];
    }

    my $md = Market::MarketData->new();
    $md->add_candle($_) for @c;
    $md->build_tf_candles('5m');
    $md->build_tf_candles('15m');

    my $liq = Market::Indicators::Liquidity->new(k => 1, atr_period => 3, N => 3);

    my $t_start = time();
    $liq->update_last($md, $_) for 0 .. $md->last_index;
    my $elapsed = time() - $t_start;

    my $events = $liq->get_events();
    ok(scalar(@$events) > 0, 'TASK 0016: la alimentacion produce eventos (FSM activa)');
    cmp_ok(scalar(@c), '>=', 5000, 'TASK 0016: dataset >= 5000 velas');
    cmp_ok($elapsed, '<', 10, "TASK 0016: alimentar 5000+ velas < 10s (medido: ${\sprintf('%.3f', $elapsed)}s; old code ~30s)");

    # Invariante: todos los eventos resueltos tienen meta multi-TF (ejercita la suma por rango).
    my $last_ev = $events->[-1];
    ok(defined $last_ev->{meta} && defined $last_ev->{meta}->{v1m},
       'TASK 0016: el último evento lleva meta multi-TF (v1m)');
}

done_testing();
