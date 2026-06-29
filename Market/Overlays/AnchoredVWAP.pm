package Market::Overlays::AnchoredVWAP;
use strict;
use warnings;

# =============================================================================
# Market::Overlays::AnchoredVWAP
# 
# Render smooth Anchored VWAP curve across the chart.
# =============================================================================

sub new {
    my ($class, %args) = @_;
    die "Overlays::AnchoredVWAP->new: requiere 'indicator'"
        unless defined $args{indicator};
    my $self = {
        indicator => $args{indicator},
        theme     => $args{theme} || {},
        visible   => exists $args{visible} ? ($args{visible} ? 1 : 0) : 0,
        _elements => {
            VWAP_LINE => 1,
        },
        _start    => 0,
        _end      => 0,
    };
    bless $self, $class;
    return $self;
}

sub set_visible {
    my ($self, $val) = @_;
    $self->{visible} = $val ? 1 : 0;
}

sub is_visible {
    my ($self) = @_;
    return $self->{visible} ? 1 : 0;
}

sub tag {
    return 'ov_vwap';
}

sub clear {
    my ($self, $canvas) = @_;
    return unless $canvas;
    $canvas->delete($self->tag());
}

sub is_element_visible {
    my ($self, $elem) = @_;
    return $self->{_elements}->{$elem} ? 1 : 0;
}

sub _local_index {
    my ($self, $global_idx) = @_;
    return $global_idx - ($self->{_start} // 0);
}

sub compute_visible {
    my ($self, $market_data, $indicator, $start, $end) = @_;
    $self->{_start} = $start // 0;
    $self->{_end}   = $end   // 0;
    return $self;
}

sub draw {
    my ($self, $canvas, $scales) = @_;
    return $self unless $self->is_visible() && $self->{indicator};
    return $self unless $canvas && $scales;

    my $tag   = $self->tag();
    $self->clear($canvas);

    my $vwap  = $self->{indicator}->get_values();
    return $self unless $vwap && @$vwap;

    my $start = $self->{_start} // 0;
    my $end   = $self->{_end}   // 0;

    for my $i ($start .. $end - 1) {
        next if $i < 0 || $i + 1 < 0; # Guard against Perl negative array wrapping
        next unless defined $vwap->[$i] && defined $vwap->[$i+1];
        next unless defined $vwap->[$i]->{value} && defined $vwap->[$i+1]->{value};

        # Do not connect across session resets / anchor changes
        my $anc1 = $vwap->[$i]->{anchor_idx} // 0;
        my $anc2 = $vwap->[$i+1]->{anchor_idx} // 0;
        next if $anc1 != $anc2;

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
