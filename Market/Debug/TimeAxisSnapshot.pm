package Market::Debug::TimeAxisSnapshot;
use strict;
use warnings;

use Time::Moment;
use Market::Panels::Scales;

# Módulo de diagnóstico removible.
# No renderiza ni muta la app: replica las mismas conversiones de coordenadas que
# ChartEngine/PricePanel para describir exactamente qué se dibuja en pantalla.

sub capture {
    my ($class, $engine, %opts) = @_;

    my ($start, $end) = $engine->compute_window();
    my $bars = $end >= $start ? $end - $start + 1 : 0;
    $bars = 1 if $bars < 1;

    my $right_margin = $opts{right_margin};
    $right_margin = 0 unless defined $right_margin;

    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => $right_margin,
    );
    $scale->{width} = _canvas_width($engine, $engine->{price_canvas});
    $scale->{x_shift} = $engine->{ctrl_zoom_x_shift} || 0;

    my $plot_w = $scale->plot_width();
    my $bar_w  = $bars > 0 ? $plot_w / $bars : 1;
    $bar_w = 1 if $bar_w <= 0;

    my $labels = $engine->compute_intraday_labels();
    my (@all, @visible, @hidden);
    for my $l (@$labels) {
        my $global = $start + $l->{index};
        my $x = $scale->index_to_center_x($l->{index});
        my $row = {
            text       => $l->{text},
            index      => $l->{index},
            global     => $global,
            timestamp  => $engine->{market_data}->get_timestamp($global),
            x          => $x,
            x_rounded  => int($x + 0.5),
            is_date    => $l->{is_date} ? 1 : 0,
            grid       => exists $l->{grid}  ? ($l->{grid}  ? 1 : 0) : 1,
            label      => exists $l->{label} ? ($l->{label} ? 1 : 0) : 1,
            draw_grid  => ((exists $l->{grid} ? $l->{grid} : 1) && (exists $l->{label} ? $l->{label} : 1)) ? 1 : 0,
        };
        push @all, $row;
        if ($row->{label}) { push @visible, $row; }
        else               { push @hidden,  $row; }
    }

    my @visible_hours = grep { $_->{text} =~ /^\d{2}:\d{2}$/ } @visible;
    my $cadence = _dominant_hour_cadence(\@visible_hours);
    my @gaps = _visible_timestamp_gaps($engine, $start, $end);

    # spec 0000j: label_deltas and grid_spacing_stats for visual spacing validation.
    my @label_deltas;
    for my $i (1 .. $#visible) {
        my $left  = $visible[$i - 1];
        my $right = $visible[$i];
        my $dx = $right->{x} - $left->{x};
        # Detect gap exceptions: weekend or session gaps where dx is much larger.
        # A gap exception is when left and right are both dates AND the calendar
        # day difference is > 1 (indicating a weekend/holiday gap).
        my $is_gap_exception = 0;
        if ($left->{is_date} && $right->{is_date}) {
            my $left_ts  = $left->{timestamp};
            my $right_ts = $right->{timestamp};
            if (defined $left_ts && defined $right_ts) {
                my $ltm = eval { Time::Moment->from_string($left_ts) };
                my $rtm = eval { Time::Moment->from_string($right_ts) };
                if ($ltm && $rtm) {
                    my $day_diff = $rtm->day_of_year - $ltm->day_of_year;
                    $day_diff += 366 if $day_diff < 0; # year wrap
                    $is_gap_exception = 1 if $day_diff > 1;
                }
            }
        }
        push @label_deltas, {
            left_text       => $left->{text},
            right_text      => $right->{text},
            dx              => sprintf("%.2f", $dx),
            dx_raw          => $dx,
            left_ts         => $left->{timestamp},
            right_ts        => $right->{timestamp},
            left_global     => $left->{global},
            right_global    => $right->{global},
            is_gap_exception => $is_gap_exception,
        };
    }

    # Grid spacing stats: regular deltas only (exclude gap exceptions).
    my @regular_dx = map { $_->{dx_raw} } grep { !$_->{is_gap_exception} } @label_deltas;
    my $grid_spacing_stats;
    if (@regular_dx >= 2) {
        my @sorted = sort { $a <=> $b } @regular_dx;
        my $min = $sorted[0];
        my $max = $sorted[-1];
        my $median = $sorted[int(@sorted / 2)];
        my $ratio = ($min > 0) ? ($max / $min) : 0;
        $grid_spacing_stats = {
            min_regular_dx    => sprintf("%.2f", $min),
            max_regular_dx    => sprintf("%.2f", $max),
            median_regular_dx => sprintf("%.2f", $median),
            ratio_regular_dx  => sprintf("%.2f", $ratio),
            count             => scalar(@regular_dx),
        };
    }

    my $snapshot = {
        kind         => 'time_axis_snapshot',
        version      => 1,
        timeframe    => eval { $engine->{market_data}->{active_tf} } || '1m',
        start_index  => $start,
        end_index    => $end,
        visible_bars => $bars,
        canvas_width => $scale->{width},
        plot_width   => $plot_w,
        right_margin => $right_margin,
        bar_w        => $bar_w,
        x_shift      => $scale->{x_shift},
        first_ts     => $engine->{market_data}->get_timestamp($start),
        last_ts      => $engine->{market_data}->get_timestamp($end),
        cadence_min  => $cadence,
        label_count  => scalar(@visible),
        hidden_candidate_count => scalar(@hidden),
        labels_text  => join(' | ', map { $_->{text} } @visible),
        labels       => \@visible,
        hidden_labels => \@hidden,
        all_candidates => \@all,
        gaps         => \@gaps,
        label_deltas       => \@label_deltas,
        grid_spacing_stats => $grid_spacing_stats,
    };

    $snapshot->{summary} = summary_text($snapshot);
    return $snapshot;
}

sub capture_range {
    my ($class, $engine, %opts) = @_;

    my $md = $engine->{market_data};
    my %restore = (
        active_tf         => eval { $md->{active_tf} },
        visible_bars      => $engine->{visible_bars},
        offset            => $engine->{offset},
        ctrl_zoom_x_shift => $engine->{ctrl_zoom_x_shift},
        canvas_w          => eval { $engine->{price_canvas}->{w} },
    );

    my $ok = eval {
        if (defined $opts{timeframe}) {
            if ($md->can('set_timeframe')) { $md->set_timeframe($opts{timeframe}); }
            else { $md->{active_tf} = $opts{timeframe}; }
        }

        if (defined $opts{canvas_width} && $engine->{price_canvas} && ref($engine->{price_canvas}) eq 'TestCanvas') {
            $engine->{price_canvas}->{w} = $opts{canvas_width};
        }
        elsif (defined $opts{canvas_width} && $engine->{price_canvas} && exists $engine->{price_canvas}->{w}) {
            $engine->{price_canvas}->{w} = $opts{canvas_width};
        }

        my $total = $md->size();
        my ($start, $end);
        if (defined $opts{start_index} || defined $opts{end_index}) {
            $start = defined $opts{start_index} ? $opts{start_index} : 0;
            $end   = defined $opts{end_index}   ? $opts{end_index}   : $total - 1;
        }
        elsif (defined $opts{start_ts} || defined $opts{end_ts}) {
            $start = defined $opts{start_ts} ? _find_index_at_or_after($md, $opts{start_ts}) : 0;
            $end   = defined $opts{end_ts}   ? _find_index_at_or_before($md, $opts{end_ts}) : $total - 1;
        }
        elsif (defined $opts{visible_bars}) {
            $end = $total - 1 - ($opts{offset} || 0);
            $start = $end - $opts{visible_bars} + 1;
        }
        else {
            ($start, $end) = $engine->compute_window();
        }

        $start = 0 if !defined($start) || $start < 0;
        $end = $total - 1 if !defined($end) || $end >= $total;
        $end = $start if $end < $start;

        $engine->{visible_bars} = defined $opts{visible_bars} ? $opts{visible_bars} : ($end - $start + 1);
        $engine->{visible_bars} = 1 if $engine->{visible_bars} < 1;
        $engine->{offset} = $total - 1 - $end;
        $engine->{ctrl_zoom_x_shift} = defined $opts{x_shift} ? $opts{x_shift} : 0;

        my $snap = $class->capture($engine, %opts);
        $snap->{requested} = { %opts };
        return $snap;
    };
    my $err = $@;

    $md->{active_tf} = $restore{active_tf} if defined $restore{active_tf};
    $engine->{visible_bars} = $restore{visible_bars};
    $engine->{offset} = $restore{offset};
    $engine->{ctrl_zoom_x_shift} = $restore{ctrl_zoom_x_shift};
    if (defined $restore{canvas_w} && $engine->{price_canvas} && exists $engine->{price_canvas}->{w}) {
        $engine->{price_canvas}->{w} = $restore{canvas_w};
    }

    die $err if $err;
    return $ok;
}

sub summary_text {
    my ($s) = @_;
    my @lines = (
        "TIME_AXIS_DEBUG v$s->{version}",
        "tf=$s->{timeframe} visible_bars=$s->{visible_bars} start=$s->{start_index} end=$s->{end_index}",
        "first_ts=" . ($s->{first_ts} // '') . " last_ts=" . ($s->{last_ts} // ''),
        sprintf("canvas=%s plot=%.3f bar_w=%.6f x_shift=%.3f cadence_min=%s labels=%d hidden=%d",
            $s->{canvas_width}, $s->{plot_width}, $s->{bar_w}, $s->{x_shift},
            defined $s->{cadence_min} ? $s->{cadence_min} : 'undef',
            $s->{label_count}, $s->{hidden_candidate_count}),
        "labels=" . ($s->{labels_text} // ''),
    );
    # spec 0000j: include grid spacing stats in summary when available.
    if ($s->{grid_spacing_stats}) {
        my $gss = $s->{grid_spacing_stats};
        push @lines, sprintf("grid_spacing: min=%s max=%s median=%s ratio=%s count=%d",
            $gss->{min_regular_dx}, $gss->{max_regular_dx}, $gss->{median_regular_dx},
            $gss->{ratio_regular_dx}, $gss->{count});
    }
    return join("\n", @lines);
}

sub _find_index_at_or_after {
    my ($md, $target_ts) = @_;
    my $target = eval { Time::Moment->from_string($target_ts) };
    return 0 unless $target;
    for my $i (0 .. $md->size() - 1) {
        my $ts = $md->get_timestamp($i);
        next unless defined $ts;
        my $tm = eval { Time::Moment->from_string($ts) };
        next unless $tm;
        return $i if $tm->epoch >= $target->epoch;
    }
    return $md->size() - 1;
}

sub _find_index_at_or_before {
    my ($md, $target_ts) = @_;
    my $target = eval { Time::Moment->from_string($target_ts) };
    return $md->size() - 1 unless $target;
    my $last = 0;
    for my $i (0 .. $md->size() - 1) {
        my $ts = $md->get_timestamp($i);
        next unless defined $ts;
        my $tm = eval { Time::Moment->from_string($ts) };
        next unless $tm;
        return $last if $tm->epoch > $target->epoch;
        $last = $i;
    }
    return $last;
}

sub _canvas_width {
    my ($engine, $canvas) = @_;
    my $w = eval { $engine->_canvas_width($canvas) };
    return $w if defined $w && $w > 0;
    return 1;
}

sub _dominant_hour_cadence {
    my ($hours) = @_;
    return undef unless @$hours >= 2;

    my @mins;
    for my $v (@$hours) {
        next unless $v->{text} =~ /^(\d{2}):(\d{2})$/;
        push @mins, int($1) * 60 + int($2);
    }
    return undef unless @mins >= 2;

    my @diffs;
    for my $i (1 .. $#mins) {
        my $d = $mins[$i] - $mins[$i - 1];
        $d += 1440 if $d <= 0;
        push @diffs, $d;
    }
    my %count;
    $count{$_}++ for @diffs;
    my ($cadence) = sort { $count{$b} <=> $count{$a} || $a <=> $b } keys %count;
    return $cadence;
}

sub _visible_timestamp_gaps {
    my ($engine, $start, $end) = @_;
    my @gaps;
    my ($prev_i, $prev_ts, $prev_tm);
    for my $i ($start .. $end) {
        my $ts = $engine->{market_data}->get_timestamp($i);
        next unless defined $ts;
        my $tm = eval { Time::Moment->from_string($ts) };
        next unless $tm;
        if ($prev_tm) {
            my $delta = $tm->epoch - $prev_tm->epoch;
            if ($delta > 60 * 20) {
                push @gaps, {
                    from_index => $prev_i,
                    to_index   => $i,
                    from_ts    => $prev_ts,
                    to_ts      => $ts,
                    seconds    => $delta,
                    minutes    => $delta / 60,
                };
            }
        }
        ($prev_i, $prev_ts, $prev_tm) = ($i, $ts, $tm);
    }
    return @gaps;
}

1;
