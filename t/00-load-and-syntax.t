use strict;
use warnings;
use Test::More;

use lib '.';

use_ok('Market::MarketData');
use_ok('Market::IndicatorManager');
use_ok('Market::Indicators::ATR');
use_ok('Market::Indicators::SMC_Structures');
use_ok('Market::Indicators::Liquidity');
use_ok('Market::Panels::Scales');
use_ok('Market::ChartEngine');
use_ok('Market::Panels::PricePanel');
use_ok('Market::Panels::ATRPanel');
use_ok('Market::UI::Callbacks');

my @syntax_files = qw(
    market.pl
    Market/MarketData.pm
    Market/IndicatorManager.pm
    Market/Indicators/ATR.pm
    Market/Indicators/SMC_Structures.pm
    Market/Indicators/Liquidity.pm
    Market/Panels/Scales.pm
    Market/ChartEngine.pm
    Market/Panels/PricePanel.pm
    Market/Panels/ATRPanel.pm
    Market/UI/Callbacks.pm
);

for my $file (@syntax_files) {
    my $output = `$^X -I. -c $file 2>&1`;
    is($? >> 8, 0, "$file compila");
    like($output, qr/syntax OK/, "$file reporta syntax OK");
}

done_testing;
