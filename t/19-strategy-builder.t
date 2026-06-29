use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::Strategy_Builder;
use Market::Overlays::Strategy_Builder;

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
        [11, 15, 10, 14, 100],
        [14, 18, 13, 17, 100],
        [17, 22, 16, 21, 500], # Volume expansion
        [21, 25, 20, 24, 100],
    );
    my $md = build_ohlc(\@c);
    my $sb = Market::Indicators::Strategy_Builder->new();

    for my $i (0 .. $md->last_index) {
        $sb->update_last($md, $i);
    }

    my $vals = $sb->get_values();
    ok(defined $vals->{supertrend}, 'SuperTrend computed');
    ok(defined $vals->{halftrend},  'HalfTrend computed');
    ok(defined $vals->{rangefilter},'RangeFilter computed');
    is(scalar(@{ $vals->{supertrend} }), 5, '5 SuperTrend values');
}

done_testing();
