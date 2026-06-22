use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::SMC_Structures;
use Market::Debug::IndicatorSnapshot;
use Time::HiRes qw(time);

my $D = 'Market::Debug::IndicatorSnapshot';

# =============================================================================
# Fixture: velas sintéticas deterministas (sin Tk).
# (high, low) por índice 0..8, k=1:
#   (10,9) (12,10) (11,10) (14,11) (13,12) (16,13) (15,12) (12,9) (10,7)
# =============================================================================
sub build_fixture {
    my @hl = (
        [ 10, 9 ],
        [ 12, 10 ],
        [ 11, 10 ],
        [ 14, 11 ],
        [ 13, 12 ],
        [ 16, 13 ],
        [ 15, 12 ],
        [ 12, 9 ],
        [ 10, 7 ],
    );
    my $md = Market::MarketData->new();
    for my $i (0 .. $#hl) {
        my ($h, $l) = @{ $hl[$i] };
        my $ts = sprintf("2026-04-06T00:%02d:00-05:00", $i);
        $md->add_candle([$ts, $l, $h, $l, $h, 1]);
    }
    return $md;
}

# =============================================================================
# 1. Correr el indicador puro vela a vela (update_last)
# =============================================================================
my $md  = build_fixture();
my $smc = Market::Indicators::SMC_Structures->new(k => 1);
$smc->update_last($md, $_) for 0 .. $md->last_index;
my $items = $smc->get_pivots();

# Diagnostic output
diag("type_sequence: " . $D->type_sequence($items));
diag("summary: " . Market::Debug::IndicatorSnapshot::summary_line($items));

# =============================================================================
# 2. Invariante: todo extremo confirmado tiene una de las 4 etiquetas
# =============================================================================
my @valid_types = qw(HH HL LL LH);
my %valid = map { $_ => 1 } @valid_types;
my $all_valid = 1;
for my $it (@$items) {
    my $t = $it->{type} // '?';
    $all_valid = 0 unless $valid{$t};
    ok($valid{$t}, "invariante: index=$it->{index} type=$t es HH/HL/LL/LH");
}
ok($all_valid, 'invariante: todo extremo tiene etiqueta válida (sin ? ni huecos)');

# =============================================================================
# 3. Invariante: no hay dos HH consecutivos sin HL/LL entre medias,
#    ni dos LL sin un LH/HH.
# =============================================================================
my @seq = map { $_->{type} } sort { $a->{index} <=> $b->{index} } @$items;
my $no_dup_hh_ll = 1;
for my $i (0 .. $#seq) {
    next if $i == 0;
    if ($seq[$i] eq 'HH' && $seq[$i-1] eq 'HH') {
        $no_dup_hh_ll = 0;
        diag("VIOLACIÓN: HH HH consecutivos en posición $i-1,$i");
    }
    if ($seq[$i] eq 'LL' && $seq[$i-1] eq 'LL') {
        $no_dup_hh_ll = 0;
        diag("VIOLACIÓN: LL LL consecutivos en posición $i-1,$i");
    }
}
ok($no_dup_hh_ll, 'invariante: no hay dos HH consecutivos ni dos LL consecutivos');

# =============================================================================
# 4. Invariante: en tendencia al alza los máximos crecientes son HH
#    y en el desplome final aparece LL/LH.
# =============================================================================
my @hh = grep { $_->{type} eq 'HH' } @$items;
ok(scalar(@hh) >= 1, 'invariante: hay al menos un HH en la tendencia al alza');

# =============================================================================
# 5. Anclas concretas
# =============================================================================
# Máximo en index=5 (high=16) es HH
my $at5 = undef;
for my $it (@$items) {
    $at5 = $it if $it->{index} == 5;
}
is($at5->{type}, 'HH', 'ancla: index=5 (high=16) es HH');
is($at5->{price}, 16, 'ancla: index=5 price=16');

# Mínimo del desplome (index=8, low=7) es LL
my $at8 = undef;
for my $it (@$items) {
    $at8 = $it if $it->{index} == 8;
}
is($at8->{type}, 'LL', 'ancla: index=8 (low=7) es LL');
is($at8->{price}, 7, 'ancla: index=8 price=7');

# =============================================================================
# 6. Replay guard: sin fuga de futuro para items hasta index 4
# =============================================================================
my @early = grep { $_->{index} <= 4 } @$items;
is(scalar($D->replay_violations(\@early, 4)), 0,
   'replay guard: sin fuga de futuro para items hasta index 4');

# =============================================================================
# 7. Equivalencia incremental == batch
#    reset + recálculo vela a vela reproduce el mismo resultado.
# =============================================================================
$smc->reset();
$smc->update_last($md, $_) for 0 .. $md->last_index;
my $items2 = $smc->get_pivots();

is(scalar(@$items), scalar(@$items2), 'equiv: mismo número de pivots tras reset+recálculo');
for my $i (0 .. $#{$items}) {
    is($items->[$i]->{index}, $items2->[$i]->{index}, "equiv: pivot $i mismo index");
    is($items->[$i]->{type},  $items2->[$i]->{type},  "equiv: pivot $i mismo type");
    is($items->[$i]->{price}, $items2->[$i]->{price}, "equiv: pivot $i mismo price");
}

# =============================================================================
# 8. Registro en IndicatorManager (interfaz compatible)
# =============================================================================
use Market::IndicatorManager;
my $mgr = Market::IndicatorManager->new();
my $smc2 = Market::Indicators::SMC_Structures->new(k => 1);
ok($smc2->can('update_last'), 'IndicatorManager: update_last implementado');
ok($smc2->can('get_values'),  'IndicatorManager: get_values implementado');
ok($smc2->can('reset'),       'IndicatorManager: reset implementado');
$mgr->register('SMC', $smc2);
$mgr->update_last($md, $_) for 0 .. $md->last_index;
my $pivots_via_mgr = $smc2->get_pivots();
ok(scalar(@$pivots_via_mgr) > 0, 'IndicatorManager: pivots tras registro + update_last');
is($D->type_sequence($pivots_via_mgr), $D->type_sequence($items),
   'IndicatorManager: misma secuencia que cálculo directo');

# =============================================================================
# TASK 0006: BOS / CHoCH / major high/low
# =============================================================================
# Se prueba con input exacto + invariantes + anclas (§5.bis del debug contract).
# Los eventos BOS/CHoCH dependen del diseño de la FSM → no se fuerza una cadena
# exacta, se verifican invariantes y anclas concretas.

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

# --- Helper: extraer eventos de un tipo dado ---
sub events_of_type {
    my ($events, $type) = @_;
    return grep { $_->{type} eq $type } @$events;
}

# =============================================================================
# 9. BOS válido: cierre de cuerpo supera el último HH (continuación alcista)
# =============================================================================
# Fixture: uptrend con HH@1 (price=15), LL@2 (price=9), luego close=16 > 15.
# Con k=1: SH@1 (15>10,15>11), SL@2 (9<10,9<10).
{
    my @c = (
        [ 9, 10, 9, 10],    # 0
        [10, 15, 10, 15],   # 1: swing high
        [11, 11, 9, 10],    # 2: swing low
        [10, 14, 10, 14],   # 3: swing high
        [13, 13, 10, 13],   # 4
        [13, 16, 13, 16],   # 5: close=16 > last_hh=15 → BOS up
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $smc->get_events();

    my @bos = events_of_type($events, 'BOS');
    ok(scalar(@bos) >= 1, 'BOS válido: al menos un BOS emitido');
    my @bos_up = grep { $_->{dir} eq 'up' } @bos;
    ok(scalar(@bos_up) >= 1, 'BOS válido: existe BOS up (continuación)');
    my $bos0 = $bos_up[0];
    is($bos0->{price}, 15, 'BOS válido: price = nivel roto (15)');
    is($bos0->{index}, 5,  'BOS válido: index = vela de confirmación (5)');

    # Invariante: no hay CHoCH_true en este fixture (no rompe major)
    my @choch_true = events_of_type($events, 'CHoCH_true');
    is(scalar(@choch_true), 0, 'BOS válido: sin CHoCH_true (no rompe major)');

    # Replay guard
    is(scalar($D->replay_violations($events, 5)), 0, 'BOS válido: replay guard');
}

# =============================================================================
# 10. BOS falso: solo mecha rompe HH, close queda abajo → NO genera BOS
# =============================================================================
# Fixture: mismo setup pero idx 5 tiene high=16>15 pero close=13<=15 (mecha).
# Idx 6 revierte con fuerza (close < open) → pending invalidado.
{
    my @c = (
        [ 9, 10, 9, 10],    # 0
        [10, 15, 10, 15],   # 1
        [11, 11, 9, 10],    # 2
        [10, 14, 10, 14],   # 3
        [13, 13, 10, 13],   # 4
        [13, 16, 10, 13],   # 5: wick=16>15 pero close=13<=15 → pending BOS
        [14, 14, 11, 11],   # 6: close=11<15, close<open → invalida pending
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $smc->get_events();

    # Invariante: NO debe emitirse BOS up por ruptura de mecha invalidada
    my @bos_up = grep { $_->{type} eq 'BOS' && $_->{dir} eq 'up' } @$events;
    my @bos_at_5 = grep { $_->{index} == 5 } @bos_up;
    is(scalar(@bos_at_5), 0, 'BOS falso: NO hay BOS en index=5 (solo mecha)');

    # Invariante: no hay BOS en index=6 (invalidación, no confirmación)
    my @bos_at_6 = grep { $_->{type} eq 'BOS' && $_->{index} == 6 } @$events;
    is(scalar(@bos_at_6), 0, 'BOS falso: NO hay BOS en index=6 (invalidado)');
}

# =============================================================================
# 11. CHoCH_true: close rompe major_low con cuerpo + siguiente vela confirma
# =============================================================================
# Fixture: uptrend con HH@1 (15), LL@2 (9) → major_low=9. Luego close < 9
# y la siguiente vela también cierra < 9 → CHoCH_true down confirmado.
{
    my @c = (
        [ 9, 10, 9, 10],    # 0
        [10, 15, 10, 15],   # 1
        [11, 11, 9, 10],    # 2
        [10, 14, 10, 14],   # 3
        [13, 13, 10, 13],   # 4
        [13, 16, 13, 16],   # 5: BOS up (close=16>15)
        [15, 15, 12, 15],   # 6
        [12,  8,  5,  5],   # 7: close=5 < major_low=9 → pending CHoCH down
        [ 5,  7,  4,  4],   # 8: close=4 < 9 → confirma CHoCH_true down
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $smc->get_events();

    my @choch_true = events_of_type($events, 'CHoCH_true');
    ok(scalar(@choch_true) >= 1, 'CHoCH_true: al menos un CHoCH_true emitido');
    my @choch_down = grep { $_->{dir} eq 'down' } @choch_true;
    ok(scalar(@choch_down) >= 1, 'CHoCH_true: existe CHoCH_true down');
    my $ct = $choch_down[0];
    is($ct->{price}, 9,    'CHoCH_true: price = major_low roto (9)');
    is($ct->{index}, 8,    'CHoCH_true: index = vela de confirmación (8)');

    # Invariante: CHoCH_true requiere confirmación de la siguiente vela
    my @choch_at_7 = grep { $_->{index} == 7 && $_->{type} eq 'CHoCH_true' } @$events;
    is(scalar(@choch_at_7), 0, 'CHoCH_true: NO en index=7 (requiere confirmación)');

    # Major vigente tras CHoCH
    my $majors = $smc->get_major();
    my @mh = grep { $_->{type} eq 'major_high' } @$majors;
    ok(scalar(@mh) == 1, 'CHoCH_true: exactamente un major_high vigente');
    my @ml = grep { $_->{type} eq 'major_low' } @$majors;
    ok(scalar(@ml) == 1, 'CHoCH_true: exactamente un major_low vigente');

    # Replay guard
    is(scalar($D->replay_violations($events, 8)), 0, 'CHoCH_true: replay guard');
}

# =============================================================================
# 12. CHoCH_false: close rompe estructura interna (HL) pero no el major_low
# =============================================================================
# Fixture: uptrend con HH, LL (major_low), HL (internal low > major_low).
# Luego close < HL pero >= major_low → CHoCH_false (inducement).
{
    my @c = (
        [ 9, 10,  9, 10],     # 0
        [10, 15, 10, 15],     # 1: SH
        [11, 11,  8, 10],     # 2: SL (low=8 → LL → major_low=8)
        [10, 14, 10, 14],     # 3: SH
        [ 9.5, 11, 9.5, 11],  # 4: SL (low=9.5 > 8 → HL)
        [14, 17, 14, 17],     # 5: SH
        [14, 14, 11, 14],     # 6: SL (low=11 > 9.5 → HL)
        [16, 20, 16, 20],     # 7: SH
        [18, 18, 13, 18],     # 8
        [16, 16, 10, 10],     # 9: close=10 < last_hl=11 pero >= major_low=8
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $events = $smc->get_events();

    # Ancla: debe existir CHoCH_false
    my @choch_false = events_of_type($events, 'CHoCH_false');
    ok(scalar(@choch_false) >= 1, 'CHoCH_false: al menos un CHoCH_false emitido');
    my @cf_down = grep { $_->{dir} eq 'down' } @choch_false;
    ok(scalar(@cf_down) >= 1, 'CHoCH_false: existe CHoCH_false down (inducement)');

    # Invariante: NO debe existir CHoCH_true (no rompe major)
    my @choch_true = events_of_type($events, 'CHoCH_true');
    is(scalar(@choch_true), 0, 'CHoCH_false: sin CHoCH_true (no rompe major)');

    # Replay guard
    is(scalar($D->replay_violations($events, $md->last_index)), 0,
       'CHoCH_false: replay guard');
}

# =============================================================================
# 13. Invariante global: siempre a lo sumo un major_high y un major_low
# =============================================================================
{
    my @c = (
        [ 9, 10, 9, 10], [10, 15, 10, 15], [11, 11, 9, 10],
        [10, 14, 10, 14], [13, 13, 10, 13], [13, 16, 13, 16],
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $majors = $smc->get_major();

    my @mh = grep { $_->{type} eq 'major_high' } @$majors;
    my @ml = grep { $_->{type} eq 'major_low' } @$majors;
    ok(scalar(@mh) <= 1, 'invariante global: a lo sumo un major_high');
    ok(scalar(@ml) <= 1, 'invariante global: a lo sumo un major_low');
}

# =============================================================================
# 14. Equivalencia incremental == batch para eventos BOS/CHoCH
# =============================================================================
{
    my @c = (
        [ 9, 10, 9, 10], [10, 15, 10, 15], [11, 11, 9, 10],
        [10, 14, 10, 14], [13, 13, 10, 13], [13, 16, 13, 16],
        [15, 15, 12, 15], [12, 8, 5, 5], [5, 7, 4, 4],
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $events1 = $smc->get_events();

    $smc->reset();
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $events2 = $smc->get_events();

    is(scalar(@$events1), scalar(@$events2), 'equiv eventos: mismo número tras reset');
    for my $i (0 .. $#{$events1}) {
        is($events1->[$i]->{index}, $events2->[$i]->{index}, "equiv eventos: $i mismo index");
        is($events1->[$i]->{type},  $events2->[$i]->{type},  "equiv eventos: $i mismo type");
        is($events1->[$i]->{dir},   $events2->[$i]->{dir},   "equiv eventos: $i mismo dir");
        is($events1->[$i]->{price}, $events2->[$i]->{price}, "equiv eventos: $i mismo price");
    }
}

# =============================================================================
# TASK 0007: FVG con mitigación progresiva + Fibonacci
# =============================================================================
# FVG: vector EXACTO cerrado (hi/lo/mitig son matemática pura, §5.bis).
# Fibonacci: los 5 niveles entre major high/low son únicos → exacto.

# --- 15. FVG alcista: hi/lo exactos sin mitigación ---
# Fixture: velas 0,1,2 donde low[2] > high[0] → gap alcista.
# lo = high[0] = 10, hi = low[2] = 12.
{
    my @c = (
        [ 9, 10,  9, 10],   # 0: high=10
        [11, 15, 11, 15],   # 1: impulse candle
        [14, 14, 12, 13],   # 2: low=12 > high[0]=10 → FVG_up
        [13, 16, 13, 16],   # 3: no mitigation (low=13 > hi=12)
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. 2;  # only 3 candles → FVG at index 2
    my $fvgs = $smc->get_fvg();

    my @up = grep { $_->{type} eq 'FVG_up' } @$fvgs;
    is(scalar(@up), 1, 'FVG_up: exactamente un FVG_up detectado');
    is($up[0]->{lo}, 10, 'FVG_up: lo = high[i-1] = 10');
    is($up[0]->{hi}, 12, 'FVG_up: hi = low[i+1] = 12');
    is($up[0]->{mitig}, 0, 'FVG_up: mitig = 0 (sin penetración)');

    # render_items con campos exactos
    my $txt = $D->render_items($fvgs, fields => [qw(index type hi lo mitig)]);
    like($txt, qr/index=2 type=FVG_up hi=12\.00 lo=10\.00 mitig=0\.00/,
         'FVG_up: render_items con hi/lo/mitig exactos');
}

# --- 16. FVG mitigación parcial: velas posteriores recortan el gap ---
# Tras detectar FVG_up (lo=10, hi=12), una vela con low=11 lo recorta.
{
    my @c = (
        [ 9, 10,  9, 10],   # 0
        [11, 15, 11, 15],   # 1
        [14, 14, 12, 13],   # 2: FVG_up lo=10, hi=12
        [13, 16, 11, 16],   # 3: low=11 < hi=12, 11 > lo=10 → hi recortado a 11
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $fvgs = $smc->get_fvg();

    my @up = grep { $_->{type} eq 'FVG_up' } @$fvgs;
    is(scalar(@up), 1, 'FVG mitigación: FVG sigue activo');
    is($up[0]->{hi}, 11, 'FVG mitigación: hi recortado a 11');
    is($up[0]->{lo}, 10, 'FVG mitigación: lo sin cambios (10)');
    # mitig = 1 - (11-10)/(12-10) = 1 - 0.5 = 0.5
    ok(abs($up[0]->{mitig} - 0.5) < 0.001, 'FVG mitigación: mitig = 0.5');
}

# --- 17. FVG consumo total: el gap desaparece de la lista ---
# Tras FVG_up (lo=10, hi=12), una vela con low <= 10 consume todo.
{
    my @c = (
        [ 9, 10,  9, 10],   # 0
        [11, 15, 11, 15],   # 1
        [14, 14, 12, 13],   # 2: FVG_up lo=10, hi=12
        [13, 13,  9, 12],   # 3: low=9 <= lo=10 → fully consumed
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $fvgs = $smc->get_fvg();

    my @up = grep { $_->{type} eq 'FVG_up' } @$fvgs;
    is(scalar(@up), 0, 'FVG consumo: gap eliminado de la lista');

    # Pero el FVG_down podría detectarse si high[3] < low[1]... veamos:
    # high[3]=13, low[1]=11. 13 < 11? No. Sin FVG_down.
}

# --- 18. FVG bajista: high[i+1] < low[i-1] ---
{
    my @c = (
        [12, 14, 12, 13],   # 0: low=12
        [ 9,  9,  5,  6],   # 1: impulse bearish
        [ 4,  6,  4,  5],   # 2: high=6 < low[0]=12 → FVG_down
        [ 5,  7,  5,  7],   # 3: no mitigation (high=7 < lo=6? No, 7 > 6 → partial!)
    );
    # Wait, FVG_down: hi=low[0]=12, lo=high[2]=6. Candle 3: high=7 > lo=6, 7 < hi=12 → partial.
    # Let me make candle 3 not penetrate: high=5
    my @c2 = (
        [12, 14, 12, 13],   # 0: low=12
        [ 9,  9,  5,  6],   # 1
        [ 4,  6,  4,  5],   # 2: high=6 < low[0]=12 → FVG_down, lo=6, hi=12
        [ 5,  5,  4,  5],   # 3: high=5 < lo=6 → no mitigation
    );
    my $md  = build_ohlc(\@c2);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. 2;
    my $fvgs = $smc->get_fvg();

    my @down = grep { $_->{type} eq 'FVG_down' } @$fvgs;
    is(scalar(@down), 1, 'FVG_down: exactamente un FVG_down detectado');
    is($down[0]->{lo}, 6,  'FVG_down: lo = high[i+1] = 6');
    is($down[0]->{hi}, 12, 'FVG_down: hi = low[i-1] = 12');
    is($down[0]->{mitig}, 0, 'FVG_down: mitig = 0');
}

# --- 19. Fibonacci: 5 niveles exactos entre major_high y major_low ---
# Usar fixture del BOS test: HH@1 (price=15), LL@2 (price=8).
# major_high=15, major_low=8, range=7.
# fib_0.618 = 8 + 0.618*7 = 12.326 (clave)
{
    my @c = (
        [ 9, 10,  9, 10],     # 0
        [10, 15, 10, 15],     # 1: HH=15
        [11, 11,  8, 10],     # 2: LL=8
        [10, 14, 10, 14],     # 3
        [13, 13, 10, 13],     # 4
        [13, 16, 13, 16],     # 5: BOS up
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $fibs = $smc->get_fibonacci();

    is(scalar(@$fibs), 5, 'Fibonacci: 5 niveles calculados');

    my %expected = (
        'fib_0.236' => 8 + 0.236 * 7,
        'fib_0.382' => 8 + 0.382 * 7,
        'fib_0.5'   => 8 + 0.5   * 7,
        'fib_0.618' => 8 + 0.618 * 7,
        'fib_0.786' => 8 + 0.786 * 7,
    );

    for my $fib (@$fibs) {
        my $exp = $expected{ $fib->{type} };
        ok(defined $exp, "Fibonacci: tipo $fib->{type} reconocido");
        ok(abs($fib->{price} - $exp) < 0.001,
           "Fibonacci: $fib->{type} price=$fib->{price} ≈ $exp");
    }

    # Ancla clave: fib_0.618
    my @fib618 = grep { $_->{type} eq 'fib_0.618' } @$fibs;
    is(scalar(@fib618), 1, 'Fibonacci: exactamente un fib_0.618');
    ok(abs($fib618[0]->{price} - 12.326) < 0.001,
       'Fibonacci: fib_0.618 = 12.326 (clave)');

    # render_items
    my $txt = $D->render_items($fibs, fields => [qw(index type price)]);
    like($txt, qr/fib_0\.618/, 'Fibonacci: render_items incluye fib_0.618');
}

# --- 20. FVG + Fibonacci: replay guard ---
{
    my @c = (
        [ 9, 10,  9, 10], [10, 15, 10, 15], [11, 11, 8, 10],
        [10, 14, 10, 14], [13, 13, 10, 13], [13, 16, 13, 16],
        [15, 15, 12, 15],
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $fvgs = $smc->get_fvg();
    my $fibs = $smc->get_fibonacci();

    is(scalar($D->replay_violations($fvgs, $md->last_index)), 0,
       'FVG: replay guard sin fuga de futuro');
    is(scalar($D->replay_violations($fibs, $md->last_index)), 0,
       'Fibonacci: replay guard sin fuga de futuro');
}

# --- 21. Equivalencia incremental == batch para FVGs ---
{
    my @c = (
        [ 9, 10,  9, 10], [11, 15, 11, 15], [14, 14, 12, 13],
        [13, 16, 11, 16], [13, 13, 9, 12],
    );
    my $md  = build_ohlc(\@c);
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $fvgs1 = $smc->get_fvg();

    $smc->reset();
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $fvgs2 = $smc->get_fvg();

    is(scalar(@$fvgs1), scalar(@$fvgs2), 'equiv FVG: mismo número tras reset');
    for my $i (0 .. $#{$fvgs1}) {
        is($fvgs1->[$i]->{index}, $fvgs2->[$i]->{index}, "equiv FVG: $i mismo index");
        is($fvgs1->[$i]->{type},  $fvgs2->[$i]->{type},  "equiv FVG: $i mismo type");
        is($fvgs1->[$i]->{hi},    $fvgs2->[$i]->{hi},    "equiv FVG: $i mismo hi");
        is($fvgs1->[$i]->{lo},    $fvgs2->[$i]->{lo},    "equiv FVG: $i mismo lo");
        ok(abs($fvgs1->[$i]->{mitig} - $fvgs2->[$i]->{mitig}) < 0.001,
           "equiv FVG: $i mismo mitig");
    }
}

# =============================================================================
# TASK 0014: Idempotency and Non-mutating Getters Validation
# =============================================================================
{
    # 1. Idempotencia simple: llamar get_pivots() dos veces seguidas devuelve lo mismo
    # y no altera una tercera llamada.
    my $md = build_fixture();
    my $smc = Market::Indicators::SMC_Structures->new(k => 1);
    $smc->update_last($md, $_) for 0 .. $md->last_index;

    my $piv1 = $smc->get_pivots();
    my $piv2 = $smc->get_pivots();
    my $piv3 = $smc->get_pivots();

    is(scalar(@$piv1), scalar(@$piv2), 'Idempotencia simple: get_pivots 1 y 2 tienen la misma cantidad');
    is(scalar(@$piv1), scalar(@$piv3), 'Idempotencia simple: get_pivots 1 y 3 tienen la misma cantidad');

    for my $i (0 .. $#$piv1) {
        is($piv1->[$i]->{index}, $piv2->[$i]->{index}, "Idempotencia simple (1vs2): pivot $i index");
        is($piv1->[$i]->{type},  $piv2->[$i]->{type},  "Idempotencia simple (1vs2): pivot $i type");
        is($piv1->[$i]->{price}, $piv2->[$i]->{price}, "Idempotencia simple (1vs2): pivot $i price");

        is($piv1->[$i]->{index}, $piv3->[$i]->{index}, "Idempotencia simple (1vs3): pivot $i index");
        is($piv1->[$i]->{type},  $piv3->[$i]->{type},  "Idempotencia simple (1vs3): pivot $i type");
        is($piv1->[$i]->{price}, $piv3->[$i]->{price}, "Idempotencia simple (1vs3): pivot $i price");
    }

    # 2. Idempotencia de lectura (Caso A vs Caso B)
    # Caso A: Alimentar y leer solo al final.
    my $smc_a = Market::Indicators::SMC_Structures->new(k => 1);
    $smc_a->update_last($md, $_) for 0 .. $md->last_index;
    my $pivs_a   = $smc_a->get_pivots();
    my $events_a = $smc_a->get_events();
    my $fvgs_a   = $smc_a->get_fvg();
    my $major_a  = $smc_a->get_major();
    my $fibs_a   = $smc_a->get_fibonacci();

    # Caso B: Alimentar llamando a los getters tras CADA update_last (intermedio).
    my $smc_b = Market::Indicators::SMC_Structures->new(k => 1);
    for my $i (0 .. $md->last_index) {
        $smc_b->update_last($md, $i);
        # Llamadas intermedias e idempotentes:
        $smc_b->get_pivots();
        $smc_b->get_events();
        $smc_b->get_major();
        $smc_b->get_fvg();
        $smc_b->get_fibonacci();
    }
    # Consultas finales para comparar
    my $pivs_b   = $smc_b->get_pivots();
    my $events_b = $smc_b->get_events();
    my $fvgs_b   = $smc_b->get_fvg();
    my $major_b  = $smc_b->get_major();
    my $fibs_b   = $smc_b->get_fibonacci();

    # Comparaciones final de A y B (deben ser completamente idénticos)
    is(scalar(@$pivs_a), scalar(@$pivs_b), 'Idempotencia lectura: misma cantidad de pivots final');
    for my $i (0 .. $#$pivs_a) {
        is($pivs_b->[$i]->{index}, $pivs_a->[$i]->{index}, "Idempotencia lectura: pivot $i index coincide");
        is($pivs_b->[$i]->{type},  $pivs_a->[$i]->{type},  "Idempotencia lectura: pivot $i type coincide");
        is($pivs_b->[$i]->{price}, $pivs_a->[$i]->{price}, "Idempotencia lectura: pivot $i price coincide");
    }

    is(scalar(@$events_a), scalar(@$events_b), 'Idempotencia lectura: misma cantidad de eventos final');
    for my $i (0 .. $#$events_a) {
        is($events_b->[$i]->{index}, $events_a->[$i]->{index}, "Idempotencia lectura: evento $i index coincide");
        is($events_b->[$i]->{type},  $events_a->[$i]->{type},  "Idempotencia lectura: evento $i type coincide");
        is($events_b->[$i]->{price}, $events_a->[$i]->{price}, "Idempotencia lectura: evento $i price coincide");
    }

    is(scalar(@$fvgs_a), scalar(@$fvgs_b), 'Idempotencia lectura: misma cantidad de FVGs final');
    for my $i (0 .. $#$fvgs_a) {
        is($fvgs_b->[$i]->{index}, $fvgs_a->[$i]->{index}, "Idempotencia lectura: FVG $i index coincide");
        is($fvgs_b->[$i]->{type},  $fvgs_a->[$i]->{type},  "Idempotencia lectura: FVG $i type coincide");
        is($fvgs_b->[$i]->{hi},    $fvgs_a->[$i]->{hi},    "Idempotencia lectura: FVG $i hi coincide");
        is($fvgs_b->[$i]->{lo},    $fvgs_a->[$i]->{lo},    "Idempotencia lectura: FVG $i lo coincide");
    }

    is(scalar(@$major_a), scalar(@$major_b), 'Idempotencia lectura: misma cantidad de major levels final');
    for my $i (0 .. $#$major_a) {
        is($major_b->[$i]->{index}, $major_a->[$i]->{index}, "Idempotencia lectura: major $i index coincide");
        is($major_b->[$i]->{type},  $major_a->[$i]->{type},  "Idempotencia lectura: major $i type coincide");
        is($major_b->[$i]->{price}, $major_a->[$i]->{price}, "Idempotencia lectura: major $i price coincide");
    }

    is(scalar(@$fibs_a), scalar(@$fibs_b), 'Idempotencia lectura: misma cantidad de Fibonacci levels final');
    for my $i (0 .. $#$fibs_a) {
        is($fibs_b->[$i]->{index}, $fibs_a->[$i]->{index}, "Idempotencia lectura: fibonacci $i index coincide");
        is($fibs_b->[$i]->{type},  $fibs_a->[$i]->{type},  "Idempotencia lectura: fibonacci $i type coincide");
        is($fibs_b->[$i]->{price}, $fibs_a->[$i]->{price}, "Idempotencia lectura: fibonacci $i price coincide");
    }
}

# =============================================================================
# TASK 0017: Performance — feeding a large dataset with frequent FVGs must NOT hang.
# =============================================================================
# _detect_and_mitigate_fvgs iterated the ENTIRE _fvgs array every candle; inactive
# FVGs (_active=0) were never pruned → O(n²). With 8000+ candles forming 1 FVG/candle,
# dead FVGs accumulate linearly → ~50M iterations → ~12s with old code.
#
# Measured separation (WSL Fedora35):
#   OLD (pre-0017) code: ~10-13s for 10000 candles → FAILS 5s threshold by 2x+
#   NEW (0017)     code: <0.5s  for 10000 candles → PASSES with 10x margin
{
    my $N = 10000;
    my $md = Market::MarketData->new();
    # 3-candle cycle that creates 1 FVG per candle from index 2 onward,
    # each consumed by the next candle (exercises the mitigation loop at scale):
    #   3k:   [10,11]  3k+1: [20,21]  3k+2: [15,16]
    for my $i (0 .. $N - 1) {
        my $phase = $i % 3;
        my ($o, $h, $l, $c);
        if    ($phase == 0) { ($o, $h, $l, $c) = (10, 11, 10, 11); }
        elsif ($phase == 1) { ($o, $h, $l, $c) = (20, 21, 20, 21); }
        else                { ($o, $h, $l, $c) = (15, 16, 15, 16); }
        my $ts = sprintf("2026-04-06T%02d:%02d:00-05:00", int($i / 60), $i % 60);
        $md->add_candle([$ts, $o, $h, $l, $c, 1]);
    }

    my $smc = Market::Indicators::SMC_Structures->new(k => 3);
    my $t_start = time();
    $smc->update_last($md, $_) for 0 .. $md->last_index;
    my $elapsed = time() - $t_start;

    my $fvgs = $smc->get_fvg();
    cmp_ok($N, '>=', 8000, 'TASK 0017: dataset >= 8000 velas');
    ok(scalar(@$fvgs) > 0, 'TASK 0017: FVGs detectados (loop de mitigacion ejercitado)');
    cmp_ok($elapsed, '<', 5,
        sprintf("TASK 0017: alimentar %d velas < 5s (medido: %.3fs; old code ~12s)", $N, $elapsed));
}

done_testing();
