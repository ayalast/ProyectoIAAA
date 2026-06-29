package Market::Overlays::AnchoredVWAP;
use strict;
use warnings;
use parent 'Market::Overlays::Base';

# =============================================================================
# Market::Overlays::AnchoredVWAP
# 
# Render smooth Anchored VWAP curve across the chart.
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = $class->SUPER::new(%opts);
    $self->{_elements} = {
        VWAP_LINE => 1,
    };
    return $self;
}

sub draw {
    my ($self, $canvas, $scales, $window) = @_;
    return $self unless $self->is_visible() && $self->{indicator};
    return $self unless $canvas && $scales && $window;

    my $tag   = $self->tag();
    my $vwap  = $self->{indicator}->get_values();
    return $self unless $vwap && @$vwap;

    my $start = $window->{start_index} // 0;
    my $end   = $window->{end_index}   // 0;

    for my $i ($start .. $end - 1) {
        next unless defined $vwap->[$i] && defined $vwap->[$i+1];
        next unless defined $vwap->[$i]->{value} && defined $vwap->[$i+1]->{value};

        my $x1 = $scales->index_to_center_x($self->_local_index($i));
        my $x2 = $scales->index_to_center_x($self->_local_index($i+1));
        my $y1 = $scales->value_to_y($vwap->[$i]->{value});
        my $y2 = $scales->value_to_y($vwap->[$i+1]->{value});

        $canvas->createLine(
            $x1, $y1, $x2, $y2,
            -fill  => '#ff9800', # Orange VWAP curve
            -width => 2,
            -tags  => $tag,
        );
    }

    return $self;
}

1;
