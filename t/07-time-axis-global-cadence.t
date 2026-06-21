use strict;
use warnings;
use Test::More;

use lib '.';
use Market::ChartEngine;
use Market::MarketData;
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

sub ts_date {
    my ($year, $month, $day, $hour, $minute) = @_;
    return sprintf('%04d-%02d-%02dT%02d:%02d:00-05:00', $year, $month, $day, $hour, $minute);
}

sub session_15m {
    my ($year, $month, $day, $from_h, $from_m, $to_h, $to_m) = @_;
    my @ts;
    my $from = $from_h * 60 + $from_m;
    my $to   = $to_h   * 60 + $to_m;
    for (my $mm = $from; $mm <= $to; $mm += 15) {
        push @ts, ts_date($year, $month, $day, int($mm / 60), $mm % 60);
    }
    return @ts;
}

sub nq_cme_15m_apr29_to_may1 {
    return (
        session_15m(2026, 4, 29, 15, 0, 15, 45),
        session_15m(2026, 4, 29, 17, 0, 23, 45),
        session_15m(2026, 4, 30,  0, 0, 15, 45),
        session_15m(2026, 4, 30, 17, 0, 23, 45),
        ts_date(2026, 5, 1, 0, 0),
    );
}

# 0000h: fixture con Apr 29 desde 00:00 para que la cadencia sea 3h (no 90m)
# y el plan tenga gap 12:00->18:00 que densificar con 14:30.
sub nq_cme_15m_apr29_full_to_may1 {
    return (
        session_15m(2026, 4, 29,  0, 0, 15, 45),
        session_15m(2026, 4, 29, 17, 0, 23, 45),
        session_15m(2026, 4, 30,  0, 0, 15, 45),
        session_15m(2026, 4, 30, 17, 0, 23, 45),
        ts_date(2026, 5, 1, 0, 0),
    );
}

sub nq_cme_15m_apr24_to_may1 {
    return (
        session_15m(2026, 4, 24,  0, 0, 15, 45),
        session_15m(2026, 4, 26, 17, 0, 23, 45),
        session_15m(2026, 4, 27,  0, 0, 15, 45),
        session_15m(2026, 4, 27, 17, 0, 23, 45),
        session_15m(2026, 4, 28,  0, 0, 15, 45),
        session_15m(2026, 4, 28, 17, 0, 23, 45),
        session_15m(2026, 4, 29,  0, 0, 15, 45),
        session_15m(2026, 4, 29, 17, 0, 23, 45),
        session_15m(2026, 4, 30,  0, 0, 15, 45),
        session_15m(2026, 4, 30, 17, 0, 23, 45),
        ts_date(2026, 5, 1, 0, 0),
    );
}

sub nq_cme_15m_apr20_to_may1 {
    return (
        session_15m(2026, 4, 20,  3, 0, 15, 45),
        session_15m(2026, 4, 20, 17, 0, 23, 45),
        session_15m(2026, 4, 21,  0, 0, 15, 45),
        session_15m(2026, 4, 21, 17, 0, 23, 45),
        session_15m(2026, 4, 22,  0, 0, 15, 45),
        session_15m(2026, 4, 22, 17, 0, 23, 45),
        session_15m(2026, 4, 23,  0, 0, 15, 45),
        session_15m(2026, 4, 23, 17, 0, 23, 45),
        session_15m(2026, 4, 24,  0, 0, 15, 45),
        session_15m(2026, 4, 26, 17, 0, 23, 45),
        session_15m(2026, 4, 27,  0, 0, 15, 45),
        session_15m(2026, 4, 27, 17, 0, 23, 45),
        session_15m(2026, 4, 28,  0, 0, 15, 45),
        session_15m(2026, 4, 28, 17, 0, 23, 45),
        session_15m(2026, 4, 29,  0, 0, 15, 45),
        session_15m(2026, 4, 29, 17, 0, 23, 45),
        session_15m(2026, 4, 30,  0, 0, 15, 45),
        session_15m(2026, 4, 30, 17, 0, 23, 45),
        ts_date(2026, 5, 1, 0, 0),
    );
}

sub chart_from_real_april_csv_plus_may {
    my (%args) = @_;
    my $md = Market::MarketData->new;
    open my $fh, '<', 'Data/2026_03.csv' or die "Data/2026_03.csv: $!";
    <$fh>;
    while (my $line = <$fh>) {
        chomp $line;
        my @f = split /,/, $line;
        next unless @f >= 6;
        $md->add_candle([ @f[0 .. 5] ]);
    }
    close $fh;
    $md->add_candle([ ts_date(2026, 5, 1, 0, 0), 1, 2, 0, 1, 1 ]);
    $md->build_timeframes;
    $md->set_timeframe($args{tf} || '15m');
    return bless {
        market_data       => $md,
        price_canvas      => TestCanvas->new($args{width} || 1900, 400),
        visible_bars      => defined $args{visible_bars} ? $args{visible_bars} : 20,
        offset            => defined $args{offset} ? $args{offset} : 0,
        ctrl_zoom_x_shift => defined $args{x_shift} ? $args{x_shift} : 0,
    }, 'Market::ChartEngine';
}

sub visible_labels {
    my ($labels) = @_;
    return [ grep { ($_->{grid} // 0) && ($_->{label} // 1) } @$labels ];
}

sub visible_texts {
    my ($labels) = @_;
    return [ map { $_->{text} } @{ visible_labels($labels) } ];
}

sub label_xs {
    my ($labels, $bars, $width, $x_shift) = @_;
    my $scale = Market::Panels::Scales->new(bars => $bars, right_margin => 0);
    $scale->{width} = $width;
    $scale->{x_shift} = $x_shift || 0;
    return [ map { $scale->index_to_center_x($_->{index}) } @$labels ];
}

# 0000g: A multi-day fixture with gaps must not produce an irregular mix of
# days and hours. The sequence DAY|HOUR|DAY|DAY|HOUR must not appear in
# the middle of the visible labels.
my @three_days = (full_day(14), full_day(15), full_day(16));
my $multi_chart = chart_for(timestamps => \@three_days, width => 1200, visible_bars => scalar(@three_days), tf => '1m');
my $multi_labels = visible_labels($multi_chart->compute_intraday_labels());
my @multi_texts = map { $_->{text} } @$multi_labels;

# Check: no DAY|HOUR|DAY|DAY|HOUR pattern in middle segments.
sub has_day_hour_day_day_hour {
    my (@texts) = @_;
    for my $i (0 .. $#texts - 4) {
        my ($a, $b, $c, $d, $e) = @texts[$i .. $i+4];
        # DAY is a pure number, HOUR is HH:MM
        my $is_day = sub { $_[0] =~ /^\d+$/ && $_[0] !~ /:/ };
        my $is_hour = sub { $_[0] =~ /^\d{2}:\d{2}$/ };
        return 1 if $is_day->($a) && $is_hour->($b) && $is_day->($c) && $is_day->($d) && $is_hour->($e);
    }
    return 0;
}

ok(!has_day_hour_day_day_hour(@multi_texts), 'multi-day fixture does not produce DAY|HOUR|DAY|DAY|HOUR pattern');

# 0000g: if multiple internal days are shown, each comparable segment should
# have a comparable number of hours between day anchors.
sub day_segment_hour_counts {
    my (@texts) = @_;
    my @counts;
    my $current = 0;
    for my $t (@texts) {
        if ($t =~ /^\d+$/ && $t !~ /:/) {
            push @counts, $current if $current > 0 || @counts;
            $current = 0;
        }
        else {
            $current++;
        }
    }
    push @counts, $current if $current > 0;
    return @counts;
}

my @segment_counts = day_segment_hour_counts(@multi_texts);
if (@segment_counts > 1) {
    my $max = (sort { $a <=> $b } @segment_counts)[-1];
    my $min = (sort { $a <=> $b } @segment_counts)[0];
    # All internal segments should have comparable hours (not 0 vs many)
    my @internal = @segment_counts[1 .. $#segment_counts - 1];
    if (@internal) {
        my $has_hours = grep { $_ > 0 } @internal;
        my $has_zero = grep { $_ == 0 } @internal;
        ok(!$has_hours || !$has_zero, 'internal day segments have comparable hour counts (no 0 vs many mix)');
    }
    else {
        ok(1, 'single segment - no consistency issue');
    }
}
else {
    ok(1, 'single or no day segment - consistency trivially satisfied');
}

# 0000g: all visible labels must have integer indices.
my @fractional = grep { abs($_->{index} - int($_->{index})) > 1e-9 } @$multi_labels;
is(scalar @fractional, 0, 'all visible labels have integer candle indices');

# 0000g: crosshair label agrees with bottom axis at same X coordinate.
my @day20 = full_day(20);
my $xchart = chart_for(timestamps => \@day20, width => 1200, visible_bars => 240, offset => 480, tf => '1m');
my $xlabels = visible_labels($xchart->compute_intraday_labels());
my ($lab13) = grep { $_->{text} eq '13:00' } @$xlabels;
ok(defined $lab13, 'fixture has visible 13:00 label');
if ($lab13) {
    my $xs = label_xs([$lab13], 240, 1200, 0);
    $xchart->{last_mouse_x} = $xs->[0];
    like($xchart->_crosshair_time_label() || '', qr/\b13:00\z/, 'crosshair label agrees with axis label at same X');
}
else {
    ok(0, 'crosshair label agrees with axis label at same X');
}

# 0000g: at a zoom level where multiple days are visible with hours, the
# cadence should be uniform. Check that hour labels follow a single cadence.
my @five_days = (full_day(13), full_day(14), full_day(15), full_day(16), full_day(17));
my $wide_chart = chart_for(timestamps => \@five_days, width => 1800, visible_bars => scalar(@five_days), tf => '1m');
my $wide_labels = visible_labels($wide_chart->compute_intraday_labels());
my @wide_texts = map { $_->{text} } @$wide_labels;

# Extract just the hour labels and check they follow a uniform cadence.
my @hours = grep { /^\d{2}:\d{2}$/ } @wide_texts;
if (@hours >= 2) {
    my %minute_set;
    for my $h (@hours) {
        my ($hr, $min) = split /:/, $h;
        $minute_set{int($hr) * 60 + int($min)} = 1;
    }
    my @mins = sort { $a <=> $b } keys %minute_set;
    # Check that the minutes follow a single modular cadence
    my $cadence_ok = 1;
    if (@mins >= 2) {
        my $gcd = $mins[1] - $mins[0];
        for my $i (1 .. $#mins) {
            my $diff = $mins[$i] - $mins[$i-1];
            $gcd = _gcd($gcd, $diff) if $diff > 0;
        }
        # All minutes should be multiples of the cadence
        for my $m (@mins) {
            if ($cadence_ok && $gcd > 0 && $m % $gcd != 0) {
                $cadence_ok = 0;
            }
        }
    }
    ok($cadence_ok, 'hour labels follow a uniform modular cadence across the window');
}
else {
    ok(1, 'not enough hour labels to test cadence uniformity');
}

sub _gcd {
    my ($a, $b) = @_;
    while ($b) {
        ($a, $b) = ($b, $a % $b);
    }
    return $a;
}

# 0000g: the plan should prefer Modo A (days + hours) over daily-only.
# At a moderate zoom with multiple days, hours should appear between days.
my @mod_a_days = (full_day(20), full_day(21), full_day(22));
my $mod_a_chart = chart_for(timestamps => \@mod_a_days, width => 1200, visible_bars => scalar(@mod_a_days), tf => '1m');
my $mod_a_labels = visible_labels($mod_a_chart->compute_intraday_labels());
my @mod_a_texts = map { $_->{text} } @$mod_a_labels;
my $has_both_days_and_hours = (grep { /^\d+$/ && !/:/ } @mod_a_texts) && (grep { /^\d{2}:\d{2}$/ } @mod_a_texts);
ok($has_both_days_and_hours, 'Modo A: window shows both day anchors and hour labels');

# 0000g: caso visual calibrado contra TradingView/Supercharts.
# NQ1!/CME, 15m, UTC-5, ventana 2026-04-29 15:00 -> 2026-05-01 00:00.
# TradingView muestra una cadencia dominante de 90m, con gaps de sesión comprimidos
# por índice lógico y sin inventar labels 16:00/16:15/16:30/16:45.
my @nq = nq_cme_15m_apr29_to_may1();
my $nq_chart = chart_for(timestamps => \@nq, width => 900, visible_bars => 20, tf => '15m');
my $nq_snapshot = $nq_chart->debug_time_axis_snapshot(
    timeframe    => '15m',
    start_ts     => '2026-04-29T15:00:00-05:00',
    end_ts       => '2026-05-01T00:00:00-05:00',
    canvas_width => 1400,
);
my $expected_nq = '15:00 | 18:00 | 19:30 | 21:00 | 22:30 | 30 | 01:30 | 03:00 | 04:30 | 06:00 | 07:30 | 09:00 | 10:30 | 12:00 | 13:30 | 15:00 | 18:00 | 19:30 | 21:00 | 22:30 | May';
is($nq_snapshot->{labels_text}, $expected_nq, 'NQ1 15m medium zoom matches TradingView 90m cadence labels');
is($nq_snapshot->{cadence_min}, 90, 'debug snapshot reports dominant 90m cadence');
ok($nq_snapshot->{summary} =~ /TIME_AXIS_DEBUG/, 'debug snapshot includes removable textual summary');
my @invented_16 = grep { $_->{text} =~ /^16:/ } @{ $nq_snapshot->{all_candidates} };
is(scalar(@invented_16), 0, 'CME session gap does not invent 16:xx labels');

# 0000g: TradingView permite anchors de día pegados por gaps comprimidos
# (p.ej. 26|27 tras weekend/session close) sin caer a modo diario puro.
my @nq_wide = nq_cme_15m_apr24_to_may1();
my $nq_wide_chart = chart_for(timestamps => \@nq_wide, width => 900, visible_bars => 20, tf => '15m');
my $nq_wide_snapshot = $nq_wide_chart->debug_time_axis_snapshot(
    timeframe    => '15m',
    start_ts     => '2026-04-24T00:00:00-05:00',
    end_ts       => '2026-05-01T00:00:00-05:00',
    canvas_width => 1900,
);
my $expected_wide = '24 | 06:00 | 12:00 | 26 | 27 | 06:00 | 12:00 | 18:00 | 28 | 06:00 | 12:00 | 18:00 | 29 | 06:00 | 12:00 | 18:00 | 30 | 06:00 | 12:00 | 18:00 | May';
is($nq_wide_snapshot->{labels_text}, $expected_wide, 'NQ1 15m wide zoom keeps 6h cadence despite compressed 26|27 gap');
is($nq_wide_snapshot->{cadence_min}, 360, 'wide zoom reports dominant 6h cadence');

# Regression: el rango anterior 90m debe seguir intacto al agregar la excepción date-date.
is($nq_snapshot->{labels_text}, $expected_nq, 'NQ1 90m calibrated range remains unchanged after wide-gap fix');

# 0000g: zoom más alejado confirmado contra TradingView. El plan usa cadencia
# escasa con enriquecimiento generalista de huecos (HOUR12/HOUR6/HOUR3 reales),
# no cae a modo diario y no hardcodea fechas específicas.
my @nq_sparse = nq_cme_15m_apr20_to_may1();
my $nq_sparse_chart = chart_for(timestamps => \@nq_sparse, width => 900, visible_bars => 20, tf => '15m');
my $nq_sparse_snapshot = $nq_sparse_chart->debug_time_axis_snapshot(
    timeframe    => '15m',
    start_ts     => '2026-04-20T03:00:00-05:00',
    end_ts       => '2026-05-01T00:00:00-05:00',
    canvas_width => 1900,
);
my $expected_sparse = '03:00 | 12:00 | 21 | 12:00 | 22 | 12:00 | 23 | 12:00 | 24 | 26 | 03:00 | 12:00 | 28 | 12:00 | 29 | 12:00 | 30 | 12:00 | May';
is($nq_sparse_snapshot->{labels_text}, $expected_sparse, 'NQ1 sparse wide zoom matches confirmed TradingView labels');

# Regression: el rango 6h 24->May debe seguir intacto después del ajuste sparse.
is($nq_wide_snapshot->{labels_text}, $expected_wide, 'NQ1 6h wide range remains unchanged after sparse zoom fix');

# 0000g: zoom máximo confirmado contra TradingView. Con bar spacing muy bajo,
# TradingView cambia a calendario mensual/días sin horas: MONTH | DAY... | MONTH.
# Se usa el CSV real de abril y un punto lógico de May porque el dataset local
# termina el 30 de abril.
my $nq_calendar_chart = chart_from_real_april_csv_plus_may(width => 1900, tf => '15m');
my $nq_calendar_snapshot = $nq_calendar_chart->debug_time_axis_snapshot(
    timeframe    => '15m',
    start_ts     => '2026-04-01T00:00:00-05:00',
    end_ts       => '2026-05-01T00:00:00-05:00',
    canvas_width => 1900,
);
# 0000j: La referencia visual nueva supersede el esperado conservador anterior.
# TradingView muestra calendario denso sin domingos de sesión parcial nocturna:
# Apr | 2 | 3 | 7 | 8 | 9 | 10 | 13 | 14 | 15 | 16 | 17 | 20 | 21 | 22 | 23 | 24 | 27 | 28 | 29 | 30 | May
# Días 5, 12, 19, 26 (domingos con primera vela >= 17:00) se filtran como anchors
# débiles. Días 3, 10, 17, 24 (viernes con cierre temprano) se mantienen porque
# empiezan a medianoche (sesión diurna completa). La regla es general.
my $expected_calendar = 'Apr | 2 | 3 | 7 | 8 | 9 | 10 | 13 | 14 | 15 | 16 | 17 | 20 | 21 | 22 | 23 | 24 | 27 | 28 | 29 | 30 | May';
is($nq_calendar_snapshot->{labels_text}, $expected_calendar, 'NQ1 max zoom calendar filters nocturnal partial sessions, matches TradingView');
my @calendar_hours = grep { /^\d{2}:\d{2}$/ } @{ $nq_calendar_snapshot->{labels} ? [ map { $_->{text} } @{ $nq_calendar_snapshot->{labels} } ] : [] };
is(scalar(@calendar_hours), 0, 'max zoom calendar mode does not show hour labels');

# Regression: sparse days+hours range must remain unchanged after calendar zoom.
is($nq_sparse_snapshot->{labels_text}, $expected_sparse, 'NQ1 sparse wide range remains unchanged after calendar zoom fix');

# -------------------------------------------------------------------------
# 0000h: Densificación adaptativa y umbral correcto de calendario.
# -------------------------------------------------------------------------

# T1: Densificación 14:30 en rango 29 -> May.
# TradingView muestra 14:30 entre 12:00 y 18:00 cuando la cadencia dominante
# es 3h. La app debe insertar 14:30 (candidato real) para rellenar el hueco
# grande, no hardcodear la hora.
my @nq_densify = nq_cme_15m_apr29_full_to_may1();
my $nq_densify_chart = chart_for(timestamps => \@nq_densify, width => 900, visible_bars => 20, tf => '15m');
my $nq_densify_snapshot = $nq_densify_chart->debug_time_axis_snapshot(
    timeframe    => '15m',
    start_ts     => '2026-04-29T00:00:00-05:00',
    end_ts       => '2026-05-01T00:00:00-05:00',
    canvas_width => 1400,
);
my $expected_densify = '29 | 03:00 | 06:00 | 09:00 | 12:00 | 14:30 | 18:00 | 21:00 | 30 | 03:00 | 06:00 | 09:00 | 12:00 | 14:30 | 18:00 | 21:00 | May';
is($nq_densify_snapshot->{labels_text}, $expected_densify,
   '0000h T1: 3h cadence with 14:30 densification matches TradingView');
ok($nq_densify_snapshot->{cadence_min} == 180,
   '0000h T1: dominant cadence is 180m (3h) before densification');

# Verify 14:30 is a real candidate (not synthetic/fractional).
my @densify_1430 = grep { $_->{text} eq '14:30' } @{ $nq_densify_snapshot->{labels} };
is(scalar(@densify_1430), 2, '0000h T1: exactly two 14:30 labels (Apr 29 and Apr 30)');
for my $l (@densify_1430) {
    ok($l->{index} == int($l->{index}),
       '0000h T1: 14:30 label has integer index (not synthetic)');
}

# T2: No calendario prematuro en rango 23 -> May.
# TradingView todavía muestra horas entre días en este zoom. La app no debe
# caer a solo días. Usamos el CSV real para mayor realismo.
my $nq_no_calendar_chart = chart_from_real_april_csv_plus_may(width => 1900, tf => '15m');
my $nq_no_calendar_snapshot = $nq_no_calendar_chart->debug_time_axis_snapshot(
    timeframe    => '15m',
    start_ts     => '2026-04-23T00:00:00-05:00',
    end_ts       => '2026-05-01T00:00:00-05:00',
    canvas_width => 1400,
);
my @nc_hours = grep { $_->{text} =~ /^\d{2}:\d{2}$/ } @{ $nq_no_calendar_snapshot->{labels} };
ok(scalar(@nc_hours) >= 3,
   '0000h T2: 23->May range shows hours between days (not premature calendar)');
my @nc_days = grep { $_->{text} =~ /^\d+$/ && $_->{text} !~ /:/ } @{ $nq_no_calendar_snapshot->{labels} };
ok(scalar(@nc_days) >= 3 && scalar(@nc_hours) >= 3,
   '0000h T2: 23->May range shows both days and hours (Modo A, not daily-only)');

# Regression: existing 90m case must still pass after densification.
is($nq_snapshot->{labels_text}, $expected_nq,
   '0000h regression: 90m calibrated range unchanged after densification');

# -------------------------------------------------------------------------
# 0000j: Filtrar anchors de sesión parcial nocturna en calendario mensual.
# -------------------------------------------------------------------------

# T1: Snapshot mensual filtra domingos parciales nocturnos (5, 12, 19, 26).
# Ya tenemos $nq_calendar_snapshot de 0000i (mismo rango). Verificamos que los
# días nocturnos no aparezcan y que los días regulares cercanos sí aparezcan.
my @cal_texts = split /\s*\|\s*/, $nq_calendar_snapshot->{labels_text};
ok(!grep({ $_ eq '5' } @cal_texts),  '0000j T1: nocturnal partial session day 5 filtered from calendar');
ok(!grep({ $_ eq '12' } @cal_texts), '0000j T1: nocturnal partial session day 12 filtered from calendar');
ok(!grep({ $_ eq '19' } @cal_texts), '0000j T1: nocturnal partial session day 19 filtered from calendar');
ok(!grep({ $_ eq '26' } @cal_texts), '0000j T1: nocturnal partial session day 26 filtered from calendar');
ok(grep({ $_ eq '13' } @cal_texts),  '0000j T1: regular day 13 present after filtering day 12');
ok(grep({ $_ eq '20' } @cal_texts),  '0000j T1: regular day 20 present after filtering day 19');
ok(grep({ $_ eq '27' } @cal_texts),  '0000j T1: regular day 27 present after filtering day 26');

# T2: No filtrar viernes/cierres parciales tempranos (3, 10, 17, 24).
# Estos días empiezan a medianoche (sesión diurna) aunque terminen temprano.
ok(grep({ $_ eq '3' } @cal_texts),  '0000j T2: early-close day 3 preserved (starts at midnight)');
ok(grep({ $_ eq '10' } @cal_texts), '0000j T2: early-close day 10 preserved (starts at midnight)');
ok(grep({ $_ eq '17' } @cal_texts), '0000j T2: early-close day 17 preserved (starts at midnight)');
ok(grep({ $_ eq '24' } @cal_texts), '0000j T2: early-close day 24 preserved (starts at midnight)');

# T3: Espaciado horizontal/grid casi equidistante.
# El snapshot ahora expone label_deltas y grid_spacing_stats.
ok(defined $nq_calendar_snapshot->{grid_spacing_stats},
   '0000j T3: snapshot exposes grid_spacing_stats');
my $gss = $nq_calendar_snapshot->{grid_spacing_stats};
if ($gss) {
    my $ratio = $gss->{ratio_regular_dx};
    # Regular deltas should be near-uniform (ratio <= 2.0).
    # The 3->7 weekend gap is excluded as a gap exception.
    ok(defined $ratio && $ratio <= 2.0,
       sprintf('0000j T3: regular grid spacing ratio %.2f <= 2.0 (near-equidistant)', $ratio // -1));

    # Verify gap exceptions are the weekend jumps (3->7, 10->13, 17->20, 24->27).
    my @gap_exc = grep { $_->{is_gap_exception} } @{$nq_calendar_snapshot->{label_deltas}};
    ok(scalar(@gap_exc) >= 3,
       '0000j T3: at least 3 gap exceptions detected (weekend jumps)');
}

# T4: No romper zoom calendario denso de 0000i — sigue siendo denso, no sparse.
ok(scalar(@cal_texts) >= 20,
   '0000j T4: calendar remains dense (>= 20 labels), not sparse');

done_testing;
