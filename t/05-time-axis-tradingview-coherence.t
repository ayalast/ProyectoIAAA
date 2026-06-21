use strict;
use warnings;
use Test::More;

use lib '.';
use Market::ChartEngine;
use Market::Panels::PricePanel;
use Market::Panels::Scales;

{
    package TestCanvas;
    sub new {
        my ($class, $w, $h) = @_;
        return bless { w => $w || 900, h => $h || 600, ops => [] }, $class;
    }
    sub geometry { my ($self) = @_; return $self->{w} . 'x' . $self->{h}; }
    sub Width  { return shift->{w}; }
    sub Height { return shift->{h}; }
    sub pointerx { return undef; }
    sub pointery { return undef; }
    sub after { return; }
    sub configure { return; }
    sub delete { my ($self, @args) = @_; push @{ $self->{ops} }, [ delete => @args ]; return; }
    sub lower  { my ($self, @args) = @_; push @{ $self->{ops} }, [ lower  => @args ]; return; }
    sub createLine { my ($self, @args) = @_; push @{ $self->{ops} }, [ createLine => @args ]; return scalar @{ $self->{ops} }; }
    sub createText { my ($self, @args) = @_; push @{ $self->{ops} }, [ createText => @args ]; return scalar @{ $self->{ops} }; }
    sub createRectangle { my ($self, @args) = @_; push @{ $self->{ops} }, [ createRectangle => @args ]; return scalar @{ $self->{ops} }; }
}

{
    package TestMarketData;
    sub new {
        my ($class, $timestamps, $tf) = @_;
        my @data = map { [ $_, 1, 2, 0, 1, 1 ] } @$timestamps;
        return bless { data => { $tf || '1m' => \@data }, active_tf => $tf || '1m' }, $class;
    }
    sub size { my ($self) = @_; return scalar @{ $self->{data}->{ $self->{active_tf} } }; }
    sub last_index { shift->size - 1 }
    sub get_candle { my ($self, $i) = @_; return $self->{data}->{ $self->{active_tf} }->[$i]; }
    sub get_timestamp { my ($self, $i) = @_; my $row = $self->get_candle($i); return $row ? $row->[0] : undef; }
}

sub chart_for {
    my (%args) = @_;
    my $md = TestMarketData->new($args{timestamps}, $args{tf} || '1m');
    return bless {
        market_data       => $md,
        price_canvas      => TestCanvas->new($args{width} || 600, 400),
        visible_bars      => defined $args{visible_bars} ? $args{visible_bars} : scalar(@{ $args{timestamps} }),
        offset            => defined $args{offset} ? $args{offset} : 0,
        ctrl_zoom_x_shift => defined $args{x_shift} ? $args{x_shift} : 0,
    }, 'Market::ChartEngine';
}

sub ts_at {
    my ($day, $hour, $minute) = @_;
    return sprintf('2026-04-%02dT%02d:%02d:00-05:00', $day, $hour, $minute);
}

sub minute_range {
    my ($day, $from_h, $from_m, $to_h, $to_m) = @_;
    my @ts;
    my $from = $from_h * 60 + $from_m;
    my $to   = $to_h   * 60 + $to_m;
    for my $mm ($from .. $to) {
        push @ts, ts_at($day, int($mm / 60), $mm % 60);
    }
    return @ts;
}

sub full_day {
    my ($day) = @_;
    return minute_range($day, 0, 0, 23, 59);
}

sub visible_grid_labels {
    my ($labels) = @_;
    return [ grep { ($_->{grid} // 0) && ($_->{label} // 1) } @$labels ];
}

sub label_xs {
    my ($labels, $bars, $width, $x_shift) = @_;
    my $scale = Market::Panels::Scales->new(bars => $bars, right_margin => 0);
    $scale->{width} = $width;
    $scale->{x_shift} = $x_shift || 0;
    return [ map { $scale->index_to_center_x($_->{index}) } @$labels ];
}

sub min_gap_px {
    my ($xs) = @_;
    return undef if @$xs < 2;
    my $min;
    for my $i (1 .. $#$xs) {
        my $gap = $xs->[$i] - $xs->[$i - 1];
        $min = $gap if !defined($min) || $gap < $min;
    }
    return $min;
}

# Reference decision from TradingView/lightweight-charts: time axis tick marks are
# attached to logical data indices. Our app must not return fractional/synthetic
# indices because crosshair snapping also works by logical candle index.
my @short_gap_90m = (
    minute_range(29, 13, 30, 15, 0),
    minute_range(29, 18, 0, 21, 30),
);
my $gap_chart = chart_for(timestamps => \@short_gap_90m, width => 450, visible_bars => scalar(@short_gap_90m), tf => '1m');
my $gap_labels = $gap_chart->compute_intraday_labels();
my @fractional = grep { abs($_->{index} - int($_->{index})) > 1e-9 } @$gap_labels;
is(scalar(@fractional), 0, 'time-axis labels are attached only to real integer candle indices');
my @gap_texts = map { $_->{text} } @$gap_labels;
ok(!grep({ $_ eq '16:30' } @gap_texts), 'time axis does not invent 16:30 without a candle/logical index');

# The crosshair label at a visible grid label's X coordinate must resolve to the same
# timestamp text. This catches the user-visible bug where the black crosshair label
# disagrees with the bottom time-axis label.
my @day = full_day(20);
my $chart = chart_for(timestamps => \@day, width => 1200, visible_bars => 240, offset => 480, tf => '1m'); # 12:00..15:59
my $labels = visible_grid_labels($chart->compute_intraday_labels());
my ($label_13) = grep { $_->{text} eq '13:00' } @$labels;
ok(defined $label_13, 'fixture has a visible 13:00 time-axis label');
my $xs = label_xs([$label_13], 240, 1200, 0);
$chart->{last_mouse_x} = $xs->[0];
like($chart->_crosshair_time_label() || '', qr/\b13:00\z/, 'crosshair label agrees with bottom axis label at same X');

# At far intraday zoom the grid should look globally regular. Dates may replace the
# midnight tick text, but they must not be injected as extra off-cadence ticks that
# create short/long visual intervals like the screenshot regression.
my @three_days = (full_day(19), full_day(20), full_day(21));
my $wide_chart = chart_for(timestamps => \@three_days, width => 1800, visible_bars => scalar(@three_days), tf => '1m');
my $wide_labels = visible_grid_labels($wide_chart->compute_intraday_labels());
my $wide_xs = label_xs($wide_labels, scalar(@three_days), 1800, 0);
my $min_gap = min_gap_px($wide_xs);
ok(defined($min_gap) && $min_gap >= 60, 'visible time grid keeps a TradingView-like minimum spacing');

# Consecutive visible grid intervals should be approximately uniform in logical index
# for a continuous same-timeframe fixture. This encodes the "almost equidistant" UX
# requirement for vertical grid lines.
my @indices = map { $_->{index} } @$wide_labels;
my @deltas;
for my $i (1 .. $#indices) {
    push @deltas, $indices[$i] - $indices[$i - 1];
}
my %delta_seen = map { $_ => 1 } @deltas;
ok(scalar(keys %delta_seen) <= 2, 'visible time grid uses one dominant logical cadence, with at most one edge/daily exception');

done_testing;
