package Market::IndicatorManager;
use strict;
use warnings;

sub new {
    my ($class) = @_;
    my $self = {
        indicators => {},
    };
    bless $self, $class;
    return $self;
}

sub register {
    my ($self, $name, $indicator) = @_;
    die "register: name is required"      unless defined $name && length $name;
    die "register: indicator is required" unless defined $indicator;
    die "register: indicator '$name' does not implement update_last"
        unless $indicator->can('update_last');
    die "register: indicator '$name' does not implement get_values"
        unless $indicator->can('get_values');

    $self->{indicators}->{$name} = $indicator;
    return $self;
}

sub update_last {
    my ($self, $market_data) = @_;
    return unless defined $market_data;

    for my $name (keys %{ $self->{indicators} }) {
        $self->{indicators}->{$name}->update_last($market_data);
    }
    return;
}

sub get {
    my ($self, $name) = @_;
    my $indicator = $self->{indicators}->{$name};
    return undef unless $indicator;
    return $indicator->get_values();
}

sub slice_array {
    my ($self, $name, $start, $end) = @_;
    my $values = $self->get($name);
    return [] unless $values && @$values;

    $start = 0         if !defined $start || $start < 0;
    $end   = $#$values if !defined $end   || $end > $#$values;
    return [] if $start > $end;

    return [ @{$values}[$start .. $end] ];
}

sub reset_all {
    my ($self) = @_;
    for my $name (keys %{ $self->{indicators} }) {
        my $indicator = $self->{indicators}->{$name};
        $indicator->reset() if $indicator->can('reset');
    }
    return;
}

1;
