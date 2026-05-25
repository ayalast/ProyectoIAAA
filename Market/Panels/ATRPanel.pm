package Market::Panels::ATRPanel;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        %args,
        crosshair_objetcs => []
    };
    bless $self, $class;
    return $self;
}

sub _init_crosshair {
    my ($self) = @_;

    $self->{crosshair_objects} = [];
}

## Descomentar y eliminar el metodo de abajo cuando los metodos de IndicatorManager se implementen
sub get_y_range {
    my ($self, $visible_values) = @_;
    
    return (0, 100) if !@$visible_values;
    my $min = $visible_values->[0];
    my $max = $visible_values->[0];

    foreach my $val (@$visible_values) {
        next if !defined $val;
        $min = $val if $val < $min;
        $max = $val if $val > $max;
    }

    my $padding = ($max - $min) * 0.05 || 1;
    return ($min - $padding, $max + $padding);
}


sub set_scale {
    my ($self, $scale) = @_;

    $self->{scale} = $scale;
}

## Descomentar y eliminar el metodo de abajo cuando los metodos de IndicatorManager se implementen
sub render {
    my ($self, $canvas, $visible_values, $scale) = @_;

    $canvas->delete('atr_line');
    return if !@$visible_values;

    $scale->_draw_y_scale($canvas);
    my @points;
    for (my $i = 0; $i < @$visible_values; $i++) {
        my $val = $visible_values->[$i];
        next if !defined $val;
        
        my $x = $scale->index_to_x($i);
        my $y = $scale->value_to_y($val);
        
        push @points, ($x, $y);
    }

    if (@points >= 4) {
        $canvas->createLine(@points, -fill => 'blue', -width => 1.5, -tags => 'atr_line');
    }

    $self->render_last_visible_value($canvas);
}


sub render_last_visible_value {
    my ($self, $canvas) = @_;

    $canvas->delete('atr_last_label');
    my $scale = $self->{scale};
}

sub draw_crosshair {
    my ($self, $x, $y) = @_;

    my $canvas = $self->{canvas};
    $canvas->delete('atr_crosshair');

    $canvas->createLine($x, 0, $x, $self->{height}, -fill => 'gray', -dash => '.', -tags => 'atr_crosshair') if defined $x;
    $canvas->createLine(0, $y, $self->{width}, $y, -fill => 'gray', -dash => '.', -tags => 'atr_crosshair') if defined $y;
}
1;