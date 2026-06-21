use strict;
use warnings;
use Test::More;

use lib '.';
use Time::Moment;
use Market::ChartEngine;

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
    sub createLine { my ($self, @args) = @_; push @{ $self->{ops} }, [ createLine => @args ]; return scalar @{ $self->{ops} }; }
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
    package StubPanel;
    sub new { bless { scale => undef }, shift }
    sub set_scale { my ($self, $scale) = @_; $self->{scale} = $scale; }
    sub draw_crosshair { return; }
    sub render { return; }
    sub render_last_visible_price { return; }
}

{
    package StubIndicators;
    sub new { bless {}, shift }
    sub slice_array { my ($self, $name, $start, $end) = @_; return [ (undef) x ($end - $start + 1) ]; }
}

sub chart_for {
    my (%args) = @_;
    my $price_canvas = TestCanvas->new($args{width} || 450, 600);
    my $md = TestMarketData->new($args{timestamps}, $args{tf} || '1m');
    return bless {
        market_data       => $md,
        indicator_manager => StubIndicators->new,
        price_canvas      => $price_canvas,
        atr_canvas        => TestCanvas->new($args{width} || 450, 200),
        price_panel       => StubPanel->new,
        atr_panel         => StubPanel->new,
        visible_bars      => defined $args{visible_bars} ? $args{visible_bars} : scalar(@{ $args{timestamps} }),
        offset            => defined $args{offset} ? $args{offset} : 0,
        ctrl_zoom_x_shift => 0,
        is_auto_scale     => 1,
        is_atr_auto_scale => 1,
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

sub label_texts {
    my ($labels) = @_;
    return map { $_->{text} } grep { $_->{grid} } @$labels;
}

# 0000c: TradingView's bottom crosshair label includes date AND time, e.g.
# "Wed 17 Jun '26 16:16". The previous accepted date-only format remains as the
# prefix but is no longer sufficient for the visible crosshair label.
my $crosshair_chart = chart_for(timestamps => [ '2026-04-23T09:31:00-05:00' ], width => 100, visible_bars => 1);
$crosshair_chart->{last_mouse_x} = 50;
is($crosshair_chart->_crosshair_time_label(), q{Thu 23 Apr '26 09:31}, 'crosshair bottom label includes date and HH:MM');

# 0000e supersedes the synthetic-gap part of 0000c: every visible time-axis
# label/grid must correspond to an actual data index so the crosshair label and the
# bottom axis never disagree. Do not invent a 16:30 label if there is no candle or
# whitespace point at that logical index.
my @gap_90m = (
    minute_range(29, 13, 30, 15, 0),
    minute_range(29, 18, 0, 21, 30),
);
my $gap_chart = chart_for(timestamps => \@gap_90m, width => 450, visible_bars => scalar(@gap_90m), tf => '1m');
is($gap_chart->_time_axis_interval_minutes(1, 450 / scalar(@gap_90m)), 90, 'fixture is in 90m axis mode');
my @gap_texts = label_texts($gap_chart->compute_intraday_labels());
ok(grep({ $_ eq '15:00' } @gap_texts), '90m gap fixture includes real 15:00 boundary');
ok(!grep({ $_ eq '16:30' } @gap_texts), '90m gap fixture does not synthesize 16:30 without a data point');
ok(grep({ $_ eq '18:00' } @gap_texts), '90m gap fixture includes real 18:00 after the gap');

# 0000c: horizontal panning should have sub-bar precision. A drag smaller than one
# candle width must still update the horizontal x shift so candles visibly slide and
# can be partially clipped at viewport edges, instead of jumping only after int(delta/bar_w).
my @drag_ts = map { ts_at(29, 6, $_) } 30 .. 39;
my $drag_chart = chart_for(timestamps => \@drag_ts, width => 1000, visible_bars => 2, offset => 0, tf => '1m');
$drag_chart->_start_horizontal_drag($drag_chart->{price_canvas}, 100, 10);
$drag_chart->_on_horizontal_drag($drag_chart->{price_canvas}, 200, 10); # 100px < bar_w=500px
ok(abs(($drag_chart->{ctrl_zoom_x_shift} || 0)) > 0, 'sub-bar horizontal drag records a non-zero x shift');
is($drag_chart->{offset}, 0, 'sub-bar horizontal drag does not change integer offset before crossing a full bar');

# Time-axis drag is zoom, not pan; this guard documents that smooth panning belongs
# to price/ATR horizontal drag, while the bottom axis drag keeps its current zoom role.
ok($drag_chart->{visible_bars} == 2, 'price/ATR horizontal drag does not change zoom level');

done_testing;
