use strict;
use warnings;
use Test::More;

use lib '.';
use Market::ChartEngine;
use Market::MarketData;
use Market::ReplayController;
use Market::Debug::IndicatorSnapshot;

# --- TestMarketData: dataset sintético con timestamps 1m ---
{
    package TestMarketData;
    sub new {
        my ($class, $n) = @_;
        my @data;
        for my $i (0 .. $n - 1) {
            my $h = int($i / 60);
            my $m = $i % 60;
            push @data, [sprintf('2026-04-01T%02d:%02d:00-05:00', $h, $m),
                         100 + $i, 101 + $i, 99 + $i, 100 + $i, 100];
        }
        return bless { data => \@data, active_tf => '1m' }, $class;
    }
    sub size { my ($self) = @_; return scalar @{ $self->{data} }; }
    sub last_index { shift->size - 1 }
    sub get_candle { my ($self, $i) = @_; return $self->{data}->[$i]; }
    sub get_timestamp { my ($self, $i) = @_; my $r = $self->get_candle($i); return $r ? $r->[0] : undef; }
    sub get_slice {
        my ($self, $s, $e) = @_;
        my @out;
        for my $i ($s .. $e) {
            push @out, ($i >= 0 && $i < $self->size) ? $self->{data}->[$i] : undef;
        }
        return \@out;
    }
}

# --- TestCanvas mínimo (sin Tk real) ---
{
    package TestCanvas;
    sub new { bless { w => 900, h => 600, ops => [] }, shift }
    sub geometry { '900x600' }
    sub Width { 900 }
    sub Height { 600 }
    sub after { return; }
    sub configure { return; }
    sub delete { return; }
}

# Helper: construir un ChartEngine con dataset de $n velas.
sub build_chart {
    my ($n) = @_;
    $n //= 100;
    my $md = TestMarketData->new($n);
    return bless {
        market_data       => $md,
        price_canvas      => TestCanvas->new(),
        visible_bars      => 20,
        offset            => 0,
        ctrl_zoom_x_shift => 0,
    }, 'Market::ChartEngine';
}

# ===========================================================================
# Test 1: compute_window jamás devuelve end > replay_idx cuando Replay activo.
# ===========================================================================
my $chart = build_chart(100);
my $rc = Market::ReplayController->new(market_data => $chart->{market_data});
$chart->{replay_controller} = $rc;

# Sin replay: end = 99 (última vela)
my ($s, $e) = $chart->compute_window();
is($e, 99, 'sin replay, end = last_index = 99');

# Con replay en idx 50: end no debe pasar de 50
$rc->start(50);
($s, $e) = $chart->compute_window();
ok($e <= 50, 'con replay_idx=50, compute_window end <= 50');

# Con replay en idx 10
$rc->start(10);
($s, $e) = $chart->compute_window();
ok($e <= 10, 'con replay_idx=10, compute_window end <= 10');

# Con replay en idx 0 (primera vela)
$rc->start(0);
($s, $e) = $chart->compute_window();
ok($e <= 0, 'con replay_idx=0, compute_window end <= 0');

# ===========================================================================
# Test 2: step_forward / step_backward mueven exactamente 1; clamp en extremos.
# ===========================================================================
$rc->start(50);
is($rc->current_index(), 50, 'replay inicia en idx 50');

$rc->step_forward();
is($rc->current_index(), 51, 'step_forward avanza exactamente 1');

$rc->step_backward();
is($rc->current_index(), 50, 'step_backward retrocede exactamente 1');

# Clamp al final (idx 99)
$rc->start(99);
$rc->step_forward();
is($rc->current_index(), 99, 'step_forward en último idx clampa a 99');

# Clamp al inicio (idx 0)
$rc->start(0);
$rc->step_backward();
is($rc->current_index(), 0, 'step_backward en idx 0 clampa a 0');

# ===========================================================================
# Test 3: exit restaura tope = last_index.
# ===========================================================================
$rc->start(50);
ok($rc->is_active(), 'replay activo tras start');
$rc->exit();
ok(!$rc->is_active(), 'replay inactivo tras exit');
is($rc->current_index(), undef, 'current_index undef tras exit');

# compute_window debe volver a usar el dataset completo
($s, $e) = $chart->compute_window();
is($e, 99, 'tras exit, compute_window end = last_index = 99');

# ===========================================================================
# Test 4: replay_violations del IndicatorSnapshot detecta items con index > k.
# Esto prueba que el guard está disponible para cuando overlays/indicadores
# se integren en tasks 0008/0012.
# ===========================================================================
my $D = 'Market::Debug::IndicatorSnapshot';
my @items = (
    { index => 5,  type => 'HH', price => 101.50 },
    { index => 10, type => 'HL', price => 100.25 },
    { index => 15, type => 'BOS', dir => 'up', price => 102.00 },
    { index => 20, type => 'LH', price => 101.00 },
    { index => 30, type => 'LL', price => 99.50 },
);

# Con replay_idx=15, los items con index 20 y 30 violan el tope.
my @bad = $D->replay_violations(\@items, 15);
is(scalar(@bad), 2, 'replay_violations detecta 2 items con index > 15');
is_deeply([sort { $a <=> $b} map { $_->{index} } @bad], [20, 30],
          'violaciones en indices 20 y 30');

# Con replay_idx=100, no hay violaciones.
is(scalar($D->replay_violations(\@items, 100)), 0,
   'sin violaciones si replay_idx >= max index');

# ===========================================================================
# Test 5: fast_forward avanza N velas y clamp al final.
# ===========================================================================
$rc->start(10);
$rc->fast_forward(5);
is($rc->current_index(), 15, 'fast_forward(5) desde idx 10 => idx 15');

$rc->start(95);
$rc->fast_forward(10);
is($rc->current_index(), 99, 'fast_forward más allá del final clampa a 99');

# ===========================================================================
# Test 6: start clampa replay_idx a [0, last_index].
# ===========================================================================
$rc->start(-5);
is($rc->current_index(), 0, 'start(-5) clampa a 0');

$rc->start(200);
is($rc->current_index(), 99, 'start(200) clampa a last_index=99');

done_testing();
