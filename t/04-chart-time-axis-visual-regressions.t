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
    sub raise  { my ($self, @args) = @_; push @{ $self->{ops} }, [ raise  => @args ]; return; }
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
    sub get_slice {
        my ($self, $start, $end) = @_;
        my @slice;
        for my $i ($start .. $end) {
            push @slice, ($i >= 0 && $i < $self->size) ? $self->get_candle($i) : undef;
        }
        return \@slice;
    }
}

{
    package StubATRPanel;
    sub new { bless {}, shift }
    sub draw_crosshair { return; }
    sub get_y_range { return (0, 100); }
    sub set_scale { return; }
    sub render { return; }
    sub render_last_visible_value { return; }
}

{
    package StubIndicators;
    sub new { bless {}, shift }
    sub slice_array { my ($self, $name, $start, $end) = @_; return [ (undef) x ($end - $start + 1) ]; }
}

sub chart_for {
    my (%args) = @_;
    my $price_canvas = TestCanvas->new($args{width} || 450, 600);
    my $time_canvas  = TestCanvas->new($args{width} || 450, 18);
    my $md = TestMarketData->new($args{timestamps}, $args{tf} || '1m');
    my $price_panel = Market::Panels::PricePanel->new(canvas => $price_canvas, theme => {});
    return bless {
        market_data       => $md,
        price_canvas      => $price_canvas,
        time_axis_canvas  => $time_canvas,
        price_panel       => $price_panel,
        atr_panel         => StubATRPanel->new,
        visible_bars      => defined $args{visible_bars} ? $args{visible_bars} : scalar(@{ $args{timestamps} }),
        offset            => defined $args{offset} ? $args{offset} : 0,
        ctrl_zoom_x_shift => 0,
        last_mouse_x      => $args{last_mouse_x},
        last_mouse_y      => $args{last_mouse_y},
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

sub texts_between_index {
    my ($labels, $left, $right) = @_;
    return map { $_->{text} } grep { $_->{index} > $left && $_->{index} < $right } @$labels;
}

sub has_text_op {
    my ($canvas, $expected) = @_;
    for my $op (@{ $canvas->{ops} }) {
        next unless $op->[0] eq 'createText';
        my @args = @$op[1 .. $#$op];
        for (my $i = 0; $i < @args; $i++) {
            return 1 if defined $args[$i] && $args[$i] eq '-text' && defined $args[$i + 1] && $args[$i + 1] eq $expected;
        }
    }
    return 0;
}

# 0000d: with a dedicated time_axis_canvas, TradingView-style crosshair time label
# belongs on the bottom time axis, not floating at the bottom of the price panel.
my $crosshair_chart = chart_for(
    timestamps   => [ '2026-04-24T12:54:00-05:00' ],
    width        => 500,
    visible_bars => 1,
    last_mouse_x => 250,
    last_mouse_y => 100,
);
$crosshair_chart->_draw_crosshair_all();
ok(has_text_op($crosshair_chart->{time_axis_canvas}, q{Fri 24 Apr '26 12:54}), 'crosshair date/time label is drawn on the dedicated time axis canvas');
ok(!has_text_op($crosshair_chart->{price_canvas}, q{Fri 24 Apr '26 12:54}), 'price canvas does not draw the bottom date/time label when time axis canvas exists');

# 0000d: synthetic ticks are allowed for short intraday gaps, but not across day/session
# gaps. A cross-day gap compressed into one candle slot must not create many fractional
# hour labels such as 16:30, 18:00, 19:30, etc. between the two real candles.
my @cross_day_gap = (
    minute_range(25, 14, 30, 15, 0),
    minute_range(26, 17, 0, 17, 30),
);
my $gap_chart = chart_for(timestamps => \@cross_day_gap, width => 75, visible_bars => scalar(@cross_day_gap), tf => '1m');
is($gap_chart->_time_axis_interval_minutes(1, 75 / scalar(@cross_day_gap)), 90, 'cross-day regression fixture is in 90m axis mode');
my $gap_labels = $gap_chart->compute_intraday_labels();
my @synthetic_inside_cross_day_gap = texts_between_index($gap_labels, 30, 31);
is_deeply(\@synthetic_inside_cross_day_gap, [], 'cross-day gap does not synthesize compressed intraday hour labels');

# 0000d: hidden labels must not still draw grid lines. Otherwise thinning hides text but
# leaves a dense block of vertical lines, exactly the visual regression seen in the GUI.
my $axis_canvas = TestCanvas->new(400, 18);
my $panel = Market::Panels::PricePanel->new(canvas => $axis_canvas, theme => {});
my $scale = Market::Panels::Scales->new(bars => 10, right_margin => 0);
$scale->{width} = 400;
$scale->{height} = 18;
$panel->set_scale($scale);
$panel->draw_time_axis($axis_canvas, [
    { index => 1, text => '12:00', is_date => 0, grid => 1, label => 1 },
    { index => 2, text => '13:00', is_date => 0, grid => 1, label => 0 },
]);
my $line_count = scalar grep { $_->[0] eq 'createLine' } @{ $axis_canvas->{ops} };
is($line_count, 1, 'time axis draws grid only for visible labels, not hidden/thinned labels');

# 0000e guard: after adopting TradingView/lightweight-charts-style logical indices,
# do not synthesize labels that have no real data index. The short 90m gap should keep
# real 15:00 and 18:00, but not invent 16:30.
my @short_gap_90m = (
    minute_range(29, 13, 30, 15, 0),
    minute_range(29, 18, 0, 21, 30),
);
my $short_gap_chart = chart_for(timestamps => \@short_gap_90m, width => 450, visible_bars => scalar(@short_gap_90m), tf => '1m');
my @short_gap_texts = map { $_->{text} } grep { $_->{grid} } @{ $short_gap_chart->compute_intraday_labels() };
ok(grep({ $_ eq '15:00' } @short_gap_texts), 'short 90m gap keeps real 15:00');
ok(!grep({ $_ eq '16:30' } @short_gap_texts), 'short 90m gap does not synthesize 16:30 without a data point');
ok(grep({ $_ eq '18:00' } @short_gap_texts), 'short 90m gap keeps real 18:00');

# -------------------------------------------------------------------------
# 0000i: Overscan de render horizontal durante paneo suave.
# -------------------------------------------------------------------------

# TestMarketData with distinct OHLC per candle for overscan verification.
{
    package TestMarketDataOHLC;
    sub new {
        my ($class, $data, $tf) = @_;
        return bless { data => { $tf || '1m' => $data }, active_tf => $tf || '1m' }, $class;
    }
    sub size { my ($self) = @_; return scalar @{ $self->{data}->{ $self->{active_tf} } }; }
    sub last_index { shift->size - 1 }
    sub get_candle { my ($self, $i) = @_; return $self->{data}->{ $self->{active_tf} }->[$i]; }
    sub get_timestamp { my ($self, $i) = @_; my $row = $self->get_candle($i); return $row ? $row->[0] : undef; }
    sub get_slice {
        my ($self, $start, $end) = @_;
        my @slice;
        for my $i ($start .. $end) {
            push @slice, ($i >= 0 && $i < $self->size) ? $self->get_candle($i) : undef;
        }
        return \@slice;
    }
}

sub render_chart_for {
    my (%args) = @_;
    my $w = $args{width} || 1000;
    my $price_canvas = TestCanvas->new($w, 600);
    my $md = TestMarketDataOHLC->new($args{candles}, $args{tf} || '1m');
    my $price_panel = Market::Panels::PricePanel->new(canvas => $price_canvas, theme => {});
    return bless {
        market_data       => $md,
        indicator_manager => StubIndicators->new,
        price_canvas      => $price_canvas,
        atr_canvas        => TestCanvas->new($w, 200),
        price_axis_canvas => TestCanvas->new(60, 600),
        atr_axis_canvas   => TestCanvas->new(60, 200),
        time_axis_canvas  => TestCanvas->new($w, 18),
        price_panel       => $price_panel,
        atr_panel         => StubATRPanel->new,
        visible_bars      => $args{visible_bars} || 2,
        offset            => $args{offset} || 0,
        ctrl_zoom_x_shift => $args{x_shift} || 0,
        is_auto_scale     => 1,
        is_atr_auto_scale => 1,
    }, 'Market::ChartEngine';
}

# Helper: find createRectangle ops with X coordinates intersecting [lo, hi].
sub rects_intersecting_x {
    my ($canvas, $lo, $hi) = @_;
    my @found;
    for my $op (@{ $canvas->{ops} }) {
        next unless $op->[0] eq 'createRectangle';
        my ($x1, $y1, $x2, $y2) = @$op[1 .. 4];
        ($x1, $x2) = ($x2, $x1) if $x1 > $x2;
        push @found, $op if $x2 > $lo && $x1 < $hi;
    }
    return @found;
}

# Helper: find createLine ops (wick) with X coordinate in range [lo, hi].
sub lines_intersecting_x {
    my ($canvas, $lo, $hi) = @_;
    my @found;
    for my $op (@{ $canvas->{ops} }) {
        next unless $op->[0] eq 'createLine';
        next if exists $op->[6] && ref($op->[6]) eq 'HASH'; # skip non-candle lines
        my ($x1, $y1, $x2, $y2) = @$op[1 .. 4];
        my $xc = ($x1 + $x2) / 2;
        push @found, $op if $xc >= $lo && $xc <= $hi;
    }
    return @found;
}

# T3: Overscan izquierdo — ctrl_zoom_x_shift > 0.
# 3 velas, visible_bars=2, ventana lógica [1,2], x_shift=+250.
# La vela global 0 (local -1) debe renderizarse parcialmente a la izquierda.
my @candles_3 = (
    ['2026-04-24T09:00:00-05:00', 100, 110, 95, 105, 10],  # global 0
    ['2026-04-24T09:01:00-05:00', 105, 115, 100, 110, 20], # global 1
    ['2026-04-24T09:02:00-05:00', 110, 120, 105, 115, 30], # global 2
);
my $overscan_left_chart = render_chart_for(
    candles      => \@candles_3,
    width        => 1000,
    visible_bars => 2,
    offset       => 0,
    x_shift      => 250,
);
$overscan_left_chart->render();

# With x_shift=+250, bar_w=500, the overscan candle (global 0, local -1) has
# center_x = -1 * 500 + 250 + 250 = 0. Its body extends from -150 to +150,
# so it intersects the viewport (x > 0).
my @left_overscan_rects = rects_intersecting_x($overscan_left_chart->{price_canvas}, 0, 250);
ok(scalar(@left_overscan_rects) >= 1,
   '0000i T3: overscan left — candle at global 0 renders partially in viewport with x_shift > 0');

# Also verify that without x_shift, the overscan candle is drawn but does NOT
# intersect the viewport (it's off-screen to the left).
my $no_overscan_chart = render_chart_for(
    candles      => \@candles_3,
    width        => 1000,
    visible_bars => 2,
    offset       => 0,
    x_shift      => 0,
);
$no_overscan_chart->render();
# With x_shift=0, candle 0 (local -1) has center_x = -1*500 + 250 = -250.
# Its body extends from -400 to -100, entirely off-screen (x < 0).
my @offscreen_rects = rects_intersecting_x($no_overscan_chart->{price_canvas}, 0, 1000);
# Should be 2 visible candles (global 1 and 2) intersecting viewport.
# The overscan candle (global 0) should NOT intersect.
my $onscreen_rects_no_shift = scalar(@offscreen_rects);
my $onscreen_rects_with_shift = scalar(@left_overscan_rects) + scalar(rects_intersecting_x($overscan_left_chart->{price_canvas}, 250, 1000));
ok($onscreen_rects_with_shift > $onscreen_rects_no_shift,
   '0000i T3: with x_shift > 0, overscan candle enters viewport (more on-screen rects than no-shift)');

# T4: Overscan derecho — ctrl_zoom_x_shift < 0.
# 4 velas, visible_bars=2, ventana lógica [1,2], x_shift=-250.
# La vela global 3 (local 2) debe renderizarse parcialmente a la derecha.
my @candles_4 = (
    ['2026-04-24T09:00:00-05:00', 100, 110, 95, 105, 10],  # global 0
    ['2026-04-24T09:01:00-05:00', 105, 115, 100, 110, 20], # global 1
    ['2026-04-24T09:02:00-05:00', 110, 120, 105, 115, 30], # global 2
    ['2026-04-24T09:03:00-05:00', 115, 125, 110, 120, 40], # global 3
);
my $overscan_right_chart = render_chart_for(
    candles      => \@candles_4,
    width        => 1000,
    visible_bars => 2,
    offset       => 1,
    x_shift      => -250,
);
$overscan_right_chart->render();

# With x_shift=-250, visible window is [1,2]. Candle global 3 (local 2) has
# center_x = 2 * 500 + 250 - 250 = 1000. Its body extends from 850 to 1150,
# so it intersects the right edge (x < 1000).
my @right_overscan_rects = rects_intersecting_x($overscan_right_chart->{price_canvas}, 750, 1001);
ok(scalar(@right_overscan_rects) >= 1,
   '0000i T4: overscan right — candle at global 3 renders partially in viewport with x_shift < 0');

# T5: Crosshair and time axis still use the logical visible window.
# The overscan candle at local -1 should not appear in time axis labels.
my $overscan_time_labels = $overscan_left_chart->compute_intraday_labels();
my @all_label_indices = map { $_->{index} } @$overscan_time_labels;
my $has_negative_index = grep { $_ < 0 } @all_label_indices;
ok(!$has_negative_index,
   '0000i T5: time axis labels do not include overscan (negative) indices');

done_testing;
