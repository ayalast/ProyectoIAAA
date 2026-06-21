use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::ATR;
use Market::IndicatorManager;
use Market::Panels::Scales;

sub add_rows {
    my ($md, @rows) = @_;
    for my $row (@rows) {
        $md->add_candle($row);
    }
}

my $md = Market::MarketData->new();
add_rows(
    $md,
    [ '2026-04-01T00:00:00-05:00', 10, 12,  9, 11, 100 ],
    [ '2026-04-01T00:01:00-05:00', 11, 13, 10, 12, 150 ],
    [ '2026-04-01T00:02:00-05:00', 12, 14, 11, 13, 200 ],
    [ '2026-04-01T00:03:00-05:00', 13, 15, 12, 14, 250 ],
    [ '2026-04-01T00:04:00-05:00', 14, 16, 13, 15, 300 ],
    [ '2026-04-01T00:05:00-05:00', 15, 17, 14, 16, 350 ],
);
$md->build_tf_candles('5m');
$md->set_timeframe('5m');

is($md->size, 2, '5m aggregation creates expected number of buckets');
is_deeply($md->get_candle(0), [ '2026-04-01T00:00:00-05:00', 10, 16, 9, 15, 1000 ], 'first 5m OHLCV bucket is correct');
is_deeply($md->get_candle(1), [ '2026-04-01T00:05:00-05:00', 15, 17, 14, 16, 350 ], 'partial 5m bucket is preserved');

my $atr_md = Market::MarketData->new();
add_rows(
    $atr_md,
    [ '2026-04-01T00:00:00-05:00', 10, 12, 10, 11, 1 ],
    [ '2026-04-01T00:01:00-05:00', 11, 13, 10, 12, 1 ],
    [ '2026-04-01T00:02:00-05:00', 12, 15, 11, 14, 1 ],
    [ '2026-04-01T00:03:00-05:00', 14, 16, 13, 15, 1 ],
);
my $atr = Market::Indicators::ATR->new(3);
for my $i (0 .. $atr_md->last_index) {
    $atr->update_last($atr_md, $i);
}
my $values = $atr->get_values;
is($values->[0], undef, 'ATR warm-up value 1 is undef');
is($values->[1], undef, 'ATR warm-up value 2 is undef');
is(sprintf('%.6f', $values->[2]), '3.000000', 'ATR first average matches expected TR mean');
is(sprintf('%.6f', $values->[3]), '3.000000', 'ATR Wilder update remains correct');

my $manager = Market::IndicatorManager->new();
$manager->register('ATR', Market::Indicators::ATR->new(3));
for my $i (0 .. $atr_md->last_index) {
    $manager->update_last($atr_md, $i);
}
is_deeply([ map { defined $_ ? sprintf('%.6f', $_) : undef } @{ $manager->get('ATR') } ], [ undef, undef, '3.000000', '3.000000' ], 'IndicatorManager delegates ATR updates');
$manager->reset_all();
is_deeply($manager->get('ATR'), [], 'IndicatorManager reset_all clears ATR values');

my $scale = Market::Panels::Scales->new(bars => 10, right_margin => 0);
$scale->{width} = 100;
is(sprintf('%.6f', $scale->index_to_x(3)), '30.000000', 'Scales index_to_x maps left edge');
is(sprintf('%.6f', $scale->index_to_center_x(3)), '35.000000', 'Scales index_to_center_x maps center');
is($scale->x_to_index(35), 3, 'Scales x_to_index maps center back to same index');
is($scale->x_to_index(-100), 0, 'Scales clamps x below range');
is($scale->x_to_index(999), 9, 'Scales clamps x above range');

done_testing;
