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

sub visible_labels {
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

# 0000f: day labels on the intraday axis should be compact day-of-month
# numbers like "15", not "15 Apr". Month/year context is reserved for
# higher-weight labels.
my @day15 = full_day(15);
my $day_chart = chart_for(timestamps => \@day15, width => 1200, visible_bars => 1440, tf => '1m');
my $day_labels = $day_chart->compute_intraday_labels();
my @day_date_texts = map { $_->{text} } grep { $_->{is_date} } @$day_labels;
ok(grep({ $_ eq '15' } @day_date_texts), 'day label is compact "15" not "15 Apr"');
ok(!grep({ /Apr/ } @day_date_texts), 'intraday day labels do not include month name');

# 0000f: at a midnight boundary the day anchor shows as "15" (day number),
# not "00:00" (the time at midnight). The day label replaces the time label
# at the same index, per TradingView/Supercharts behavior.
my @midnight_span = (
    minute_range(14, 23, 45, 23, 59),
    minute_range(15, 0, 0, 1, 20),
);
my $midnight_chart = chart_for(timestamps => \@midnight_span, width => 600, visible_bars => scalar(@midnight_span), tf => '1m');
my $midnight_labels = $midnight_chart->compute_intraday_labels();
my $midnight_visible = visible_labels($midnight_labels);
my @midnight_texts = map { $_->{text} } @$midnight_visible;
ok(grep({ $_ eq '15' } @midnight_texts), 'day anchor "15" appears at midnight boundary');
ok(!grep({ $_ eq '00:00' } @midnight_texts), 'midnight is shown as day "15" not "00:00"');

# 0000f: nearby hours should not displace the day anchor. At close zoom
# the day label "15" must remain visible alongside 5m time labels.
my @close_zoom = (
    minute_range(14, 23, 50, 23, 59),
    minute_range(15, 0, 0, 0, 15),
);
my $close_chart = chart_for(timestamps => \@close_zoom, width => 500, visible_bars => scalar(@close_zoom), tf => '1m');
my $close_labels = $close_chart->compute_intraday_labels();
my $close_visible = visible_labels($close_labels);
my @close_texts = map { $_->{text} } @$close_visible;
ok(grep({ $_ eq '15' } @close_texts), 'day anchor "15" visible at close zoom near midnight');
ok(grep({ /^23:5[05]$/ } @close_texts), 'close zoom shows 5m time labels before midnight');
ok(grep({ /^00:0[05]$/ } @close_texts), 'close zoom shows 5m time labels after midnight');

# 0000f: all visible labels must have integer indices (no synthetic/fractional).
my @fractional = grep { abs($_->{index} - int($_->{index})) > 1e-9 } @$midnight_labels;
is(scalar @fractional, 0, 'all labels have integer candle indices');

# 0000f: crosshair label agrees with bottom axis at the same X coordinate.
my @day20 = full_day(20);
my $xchart = chart_for(timestamps => \@day20, width => 1200, visible_bars => 240, offset => 480, tf => '1m');
my $xlabels = visible_labels($xchart->compute_intraday_labels());
my ($lab13) = grep { $_->{text} eq '13:00' } @$xlabels;
ok(defined $lab13, 'fixture has visible 13:00 label');
my $xs = label_xs([$lab13], 240, 1200, 0);
$xchart->{last_mouse_x} = $xs->[0];
like($xchart->_crosshair_time_label() || '', qr/\b13:00\z/, 'crosshair label agrees with axis label at same X');

# 0000f: cadence progression at varying zoom levels for 1m timeframe.
# Close zoom should show 5m cadence, medium zoom 30m or 1h, far zoom 90m or 3h.
my @day29 = full_day(29);

# Close: bar_w=20, min_indices=4 → 5m labels visible
my $zc = chart_for(timestamps => \@day29, width => 1200, visible_bars => 60, offset => 1380, tf => '1m');
my $zc_vis = visible_labels($zc->compute_intraday_labels());
my @zc_texts = map { $_->{text} } @$zc_vis;
my $has_5m = grep { /^(\d{2}):(\d[05])$/ && $2 ne '00' } @zc_texts;
ok($has_5m, 'close zoom shows 5m cadence (non-hour time labels)');

# Medium: bar_w=2.5, min_indices=26 → 30m visible, 15m not
my $zm = chart_for(timestamps => \@day29, width => 1200, visible_bars => 480, offset => 960, tf => '1m');
my $zm_vis = visible_labels($zm->compute_intraday_labels());
my @zm_texts = map { $_->{text} } @$zm_vis;
my $has_30m = grep { /^(\d{2}):(00|30)$/ } @zm_texts;
ok($has_30m, 'medium zoom shows 30m cadence');

# Far: bar_w=0.83, min_indices=78 → 3h visible, 1h not
my $zf = chart_for(timestamps => \@day29, width => 1200, visible_bars => 1440, offset => 0, tf => '1m');
my $zf_vis = visible_labels($zf->compute_intraday_labels());
my @zf_texts = map { $_->{text} } @$zf_vis;
my $has_3h = grep { /^(0[369]|12|15|18|21):00$/ } @zf_texts;
ok($has_3h, 'far zoom shows 3h cadence');

done_testing;
