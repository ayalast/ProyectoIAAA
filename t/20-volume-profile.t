use strict;
use warnings;
use Test::More;

use lib '.';
use Market::MarketData;
use Market::Indicators::VolumeProfile;
use Market::Overlays::VolumeProfile;

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
        [11, 15, 10, 14, 300],
        [14, 18, 13, 14, 500], # Highest volume around 14
        [14, 16, 12, 14, 400],
        [14, 15, 13, 14, 200],
    );
    my $md = build_ohlc(\@c);
    my $vp = Market::Indicators::VolumeProfile->new();

    for my $i (0 .. $md->last_index) {
        $vp->update_last($md, $i);
    }

    my $vals = $vp->get_values();
    ok(defined $vals, 'VolumeProfile values defined');
    ok(defined $vals->{poc}, 'POC computed');
    ok(defined $vals->{vah}, 'VAH computed');
    ok(defined $vals->{val}, 'VAL computed');
    ok($vals->{vah} >= $vals->{val}, 'VAH >= VAL');
}

done_testing();
