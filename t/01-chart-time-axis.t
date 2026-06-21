use strict;
use warnings;
use Test::More;

use lib '.';
use Time::Moment;
use Market::ChartEngine;
use Market::Panels::PricePanel;
use Market::Panels::Scales;

{
    package TestCanvas;
    sub new {
        my ($class, $w, $h) = @_;
        return bless { w => $w || 900, h => $h || 600, ops => [] }, $class;
    }
    sub geometry {
        my ($self) = @_;
        return $self->{w} . 'x' . $self->{h};
    }
    sub Width  { return shift->{w}; }
    sub Height { return shift->{h}; }
    sub delete { my ($self, @args) = @_; push @{ $self->{ops} }, [ delete => @args ]; return; }
    sub lower  { my ($self, @args) = @_; push @{ $self->{ops} }, [ lower  => @args ]; return; }
    sub raise  { my ($self, @args) = @_; push @{ $self->{ops} }, [ raise  => @args ]; return; }
    sub createLine      { my ($self, @args) = @_; push @{ $self->{ops} }, [ createLine      => @args ]; return scalar @{ $self->{ops} }; }
    sub createText      { my ($self, @args) = @_; push @{ $self->{ops} }, [ createText      => @args ]; return scalar @{ $self->{ops} }; }
    sub createRectangle { my ($self, @args) = @_; push @{ $self->{ops} }, [ createRectangle => @args ]; return scalar @{ $self->{ops} }; }
}

{
    package TestMarketData;
    sub new {
        my ($class, $timestamps, $tf) = @_;
        my @data = map { [ $_, 1, 2, 0, 1, 1 ] } @$timestamps;
        return bless { data => { $tf || '1m' => \@data }, active_tf => $tf || '1m' }, $class;
    }
    sub size {
        my ($self) = @_;
        return scalar @{ $self->{data}->{ $self->{active_tf} } };
    }
    sub last_index { shift->size - 1 }
    sub get_candle {
        my ($self, $i) = @_;
        return $self->{data}->{ $self->{active_tf} }->[$i];
    }
    sub get_timestamp {
        my ($self, $i) = @_;
        my $row = $self->get_candle($i);
        return $row ? $row->[0] : undef;
    }
}

sub chart_for {
    my (%args) = @_;
    my $md = TestMarketData->new($args{timestamps}, $args{tf} || '1m');
    return bless {
        market_data       => $md,
        price_canvas      => TestCanvas->new($args{width} || 450, 600),
        visible_bars      => defined $args{visible_bars} ? $args{visible_bars} : scalar(@{ $args{timestamps} }),
        offset            => defined $args{offset} ? $args{offset} : 0,
        ctrl_zoom_x_shift => 0,
    }, 'Market::ChartEngine';
}

sub ts_at {
    my ($day, $hour, $minute) = @_;
    return sprintf('2026-04-%02dT%02d:%02d:00-05:00', $day, $hour, $minute);
}

sub one_minute_day {
    my ($day) = @_;
    my @ts;
    for my $h (0 .. 23) {
        for my $m (0 .. 59) {
            push @ts, ts_at($day, $h, $m);
        }
    }
    return @ts;
}

sub five_minute_day {
    my ($day) = @_;
    my @ts;
    for my $h (0 .. 23) {
        for (my $m = 0; $m < 60; $m += 5) {
            push @ts, ts_at($day, $h, $m);
        }
    }
    return @ts;
}

sub timestamps_with_session_gap {
    my @ts;
    push @ts, map { ts_at(1, 0, $_) } 0 .. 19;
    push @ts, map { ts_at(1, 1, $_) } 0 .. 24;
    return @ts;
}

sub label_texts {
    my ($labels) = @_;
    return map { $_->{text} } grep { $_->{grid} && $_->{label} } @$labels;
}

# Crosshair formatter accepted in task 0000. These tests must never regress.
my $chart = chart_for(timestamps => [ '2026-04-23T09:31:00-05:00' ], width => 100);
my $tm = Time::Moment->from_string('2026-04-23T09:31:00-05:00');
is($chart->_crosshair_date_label($tm), q{Thu 23 Apr '26}, 'crosshair date label matches TradingView format');

my @weekday_cases = (
    [ '2026-04-20T00:00:00-05:00', q{Mon 20 Apr '26} ],
    [ '2026-04-21T00:00:00-05:00', q{Tue 21 Apr '26} ],
    [ '2026-04-22T00:00:00-05:00', q{Wed 22 Apr '26} ],
    [ '2026-04-23T00:00:00-05:00', q{Thu 23 Apr '26} ],
    [ '2026-04-24T00:00:00-05:00', q{Fri 24 Apr '26} ],
    [ '2026-04-25T00:00:00-05:00', q{Sat 25 Apr '26} ],
    [ '2026-04-26T00:00:00-05:00', q{Sun 26 Apr '26} ],
);
for my $case (@weekday_cases) {
    my ($iso, $expected) = @$case;
    is($chart->_crosshair_date_label(Time::Moment->from_string($iso)), $expected, "weekday mapping for $iso");
}

# 0000b: the interval ladder must include the TradingView-observed 90m step for 5m/15m
# and skip 12h for 5m before daily labels.
is($chart->_time_axis_interval_minutes(5, 6), 90, '5m ladder degrades 1h -> 90m before 3h');
is($chart->_time_axis_interval_minutes(5, 2), 360, '5m ladder reaches 6h before daily labels');
is($chart->_time_axis_interval_minutes(5, 0.8), 1440, '5m ladder jumps from 6h to daily, not 12h');
is($chart->_time_axis_interval_minutes(15, 20), 90, '15m ladder degrades 1h -> 90m before 3h');
is($chart->_time_axis_interval_minutes(15, 0.4), 4320, '15m ladder supports very-far 3-day spacing');

# 0000b: after a session/data gap, ticks must stay on real clock boundaries, not on
# anchor+n*stride_bars. The old task 0000 behavior produced 01:10 here; TradingView-style
# behavior must mark 01:00 and 01:15.
my @gap_ts = timestamps_with_session_gap();
my $gap_chart = chart_for(timestamps => \@gap_ts, width => 450, visible_bars => scalar(@gap_ts), tf => '1m');
my $gap_labels = $gap_chart->compute_intraday_labels();
my @gap_texts = label_texts($gap_labels);
ok(grep({ $_ eq '01:00' } @gap_texts), 'gap fixture includes real 01:00 boundary');
ok(grep({ $_ eq '01:15' } @gap_texts), 'gap fixture includes real 01:15 boundary');
ok(!grep({ $_ eq '01:10' } @gap_texts), 'gap fixture does not drift to stride-derived 01:10');

# 0000b: the first visible candle must not become a date label merely because it is the
# first item in the current viewport. Here the viewport starts at 09:00 with earlier
# global candles available, so the first label is a time boundary, not "01 Apr".
my @day_ts = one_minute_day(1);
my $midday_chart = chart_for(
    timestamps    => \@day_ts,
    width         => 1200,
    visible_bars  => 120,
    offset        => 780, # total 1440, end 10:59, start 09:00
    tf            => '1m',
);
my $midday_labels = $midday_chart->compute_intraday_labels();
my ($first_visible_label) = grep { $_->{index} == 0 && $_->{label} } @$midday_labels;
ok(defined $first_visible_label, 'viewport starting at 09:00 has a visible first boundary label');
is($first_visible_label->{text}, '09:00', 'first visible boundary at mid-day is shown as HH:MM');
is($first_visible_label->{is_date}, 0, 'first visible boundary at mid-day is not a date label');

# 0000b: on 5m, observed TradingView behavior reaches 6h spacing: day/start, 06:00,
# 12:00, 18:00, next day/start. The old 12h-only degradation misses 06:00/18:00.
my @five_ts = five_minute_day(16);
my $five_chart = chart_for(timestamps => \@five_ts, width => 576, visible_bars => scalar(@five_ts), tf => '5m');
my $five_labels = $five_chart->compute_intraday_labels();
my @five_texts = label_texts($five_labels);
ok(grep({ $_ eq '06:00' } @five_texts), '5m far zoom includes 06:00 on 6h spacing');
ok(grep({ $_ eq '12:00' } @five_texts), '5m far zoom includes 12:00 on 6h spacing');
ok(grep({ $_ eq '18:00' } @five_texts), '5m far zoom includes 18:00 on 6h spacing');

# 0000b UX guard: date/day labels are visually emphasized compared to hour labels.
my $axis_canvas = TestCanvas->new(400, 50);
my $panel = Market::Panels::PricePanel->new(canvas => $axis_canvas, theme => {});
my $scale = Market::Panels::Scales->new(bars => 10, right_margin => 0);
$scale->{width} = 400;
$scale->{height} = 50;
$panel->set_scale($scale);
$panel->draw_time_axis($axis_canvas, [
    { index => 1, text => '16 Apr', is_date => 1, grid => 0, label => 1 },
    { index => 2, text => '06:00',  is_date => 0, grid => 0, label => 1 },
]);
my %font_for;
for my $op (@{ $axis_canvas->{ops} }) {
    next unless $op->[0] eq 'createText';
    my @args = @$op[1 .. $#$op];
    my ($text, $font);
    for (my $i = 0; $i < @args; $i++) {
        $text = $args[$i + 1] if defined $args[$i] && $args[$i] eq '-text';
        $font = $args[$i + 1] if defined $args[$i] && $args[$i] eq '-font';
    }
    $font_for{$text} = $font if defined $text;
}
like($font_for{'16 Apr'} || '', qr/bold/, 'date labels are bold/emphasized');
unlike($font_for{'06:00'} || '', qr/bold/, 'hour labels remain regular weight');

done_testing;
