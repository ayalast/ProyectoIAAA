package Market::Indicators::ATR;
use strict;
use warnings;

sub new {
    my ($class, $period) = @_;
    die "ATR period must be a positive integer"
        unless defined $period && $period =~ /^\d+$/ && $period > 0;

    my $self = {
        period      => $period,
        values      => [],
        _tr_sum     => 0,
        _last_close => undef,
        _last_atr   => undef,
        _count      => 0,
    };
    bless $self, $class;
    return $self;
}

sub update_last {
    my ($self, $market_data) = @_;
    my $candle = $market_data->last_candle();
    return unless $candle;

    my $high  = $candle->[2];
    my $low   = $candle->[3];
    my $close = $candle->[4];

    my $tr;
    if (defined $self->{_last_close}) {
        my $prev_close = $self->{_last_close};
        my $hl  = $high - $low;
        my $hpc = abs($high - $prev_close);
        my $lpc = abs($low  - $prev_close);
        $tr = $hl;
        $tr = $hpc if $hpc > $tr;
        $tr = $lpc if $lpc > $tr;
    } else {
        $tr = $high - $low;
    }

    $self->{_count}++;
    my $period = $self->{period};

    if ($self->{_count} < $period) {
        $self->{_tr_sum} += $tr;
        push @{ $self->{values} }, undef;
    }
    elsif ($self->{_count} == $period) {
        $self->{_tr_sum} += $tr;
        my $atr = $self->{_tr_sum} / $period;
        $self->{_last_atr} = $atr;
        push @{ $self->{values} }, $atr;
    }
    else {
        my $atr = ($self->{_last_atr} * ($period - 1) + $tr) / $period;
        $self->{_last_atr} = $atr;
        push @{ $self->{values} }, $atr;
    }

    $self->{_last_close} = $close;
    return;
}

sub get_values {
    my ($self) = @_;
    return $self->{values};
}

sub reset {
    my ($self) = @_;
    $self->{values}      = [];
    $self->{_tr_sum}     = 0;
    $self->{_last_close} = undef;
    $self->{_last_atr}   = undef;
    $self->{_count}      = 0;
    return;
}

1;
