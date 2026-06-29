use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::AnchoredVWAP;
use Market::Overlays::AnchoredVWAP;

sub build_ohlc {
    my ($candles) = @_;
    my $md = Market::MarketData->new();
    for my $i (0 .. $#{$candles}) {
        my ($o, $h, $l, $c, $v) = @{ $candles->[$i] };
        $v //= 10;
        my $ts = sprintf("2026-04-06T00:%02d:00-05:00", $i);
        $md->add_candle([$ts, $o, $h, $l, $c, $v]);
    }
    return $md;
}

{
    my @c = (
        [10, 12, 9, 11, 100],
        [11, 15, 10, 14, 200],
        [14, 18, 13, 17, 300],
        [17, 22, 16, 21, 400],
    );
    my $md = build_ohlc(\@c);
    my $vwap = Market::Indicators::AnchoredVWAP->new();

    for my $i (0 .. $md->last_index) {
        $vwap->update_last($md, $i);
    }

    my $vals = $vwap->get_values();
    ok(defined $vals, 'AnchoredVWAP values defined');
    is(scalar(@$vals), 4, '4 VWAP values computed');
    ok($vals->[3]->{value} > 10, 'VWAP value is reasonable');
}

done_testing();
