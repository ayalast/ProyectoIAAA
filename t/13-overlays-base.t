use strict;
use warnings;
use Test::More;

use lib '.';
use Market::OverlayManager;
use Market::Overlays::Base;
use Market::Overlays::Example;
use Market::Panels::Scales;

# --- TestCanvas que registra operaciones ---
{
    package TestCanvas;
    sub new { bless { w => 900, h => 600, ops => [] }, shift }
    sub geometry { '900x600' }
    sub Width { shift->{w} }
    sub Height { shift->{h} }
    sub after { return; }
    sub configure { return; }
    sub delete {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ delete => @args ];
        return;
    }
    sub createLine {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ createLine => @args ];
        return scalar @{ $self->{ops} };
    }
    sub createText {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ createLine => @args ];
        return scalar @{ $self->{ops} };
    }
}

# --- TestMarketData con dataset grande (1000 velas) ---
{
    package TestMarketData;
    sub new {
        my ($class, $n) = @_;
        my @data;
        for my $i (0 .. $n - 1) {
            push @data, [sprintf('2026-04-%02dT00:00:00-05:00', $i + 1),
                         100 + $i, 110 + $i, 95 + $i, 105 + $i, 200];
        }
        return bless { data => \@data, active_tf => '1m' }, $class;
    }
    sub size { scalar @{ shift->{data} } }
    sub last_index { shift->size - 1 }
    sub get_candle { my ($self, $i) = @_; return $self->{data}->[$i]; }
    sub get_timestamp { my ($self, $i) = @_; my $r = $self->get_candle($i); return $r ? $r->[0] : undef; }
}

# ===========================================================================
# Test 1: registrar el overlay de ejemplo y afirmar que each_active lo lista.
# ===========================================================================
my $canvas = TestCanvas->new();
my $ov = Market::Overlays::Example->new(canvas => $canvas, theme => {});
my $mgr = Market::OverlayManager->new();
$mgr->register('example', $ov);

my @active = $mgr->each_active();
is(scalar(@active), 1, 'each_active lista el overlay registrado');
is($active[0]->tag(), 'ov_example', 'overlay registrado tiene tag ov_example');

# Validar contrato base
ok(Market::Overlays::Base->validate($ov), 'overlay ejemplo pasa validación de contrato');

# ===========================================================================
# Test 2: set_visible(0) → draw_all no produce ops; set_visible(1) → sí.
# ===========================================================================
my $md = TestMarketData->new(1000);
my $scale = Market::Panels::Scales->new(min_y => 90, max_y => 120, bars => 20, right_margin => 0);
$scale->{width} = 900;
$scale->{height} = 600;

# compute_visible en rango pequeño [50, 70]
$ov->compute_visible($md, undef, 50, 70);

# Visible = 0: draw_all no debe producir createLine
$ov->set_visible(0);
$canvas->{ops} = [];
$mgr->draw_all($canvas, $scale);
my $hidden_ops = scalar grep { $_->[0] eq 'createLine' } @{$canvas->{ops}};
is($hidden_ops, 0, 'set_visible(0): draw_all no produce createLine ops');

# Visible = 1: draw_all debe producir createLine
$ov->set_visible(1);
$canvas->{ops} = [];
$mgr->draw_all($canvas, $scale);
my $visible_ops = scalar grep { $_->[0] eq 'createLine' } @{$canvas->{ops}};
ok($visible_ops >= 1, 'set_visible(1): draw_all produce createLine ops');

# ===========================================================================
# Test 3: clear() solo borra el tag propio (ov_example), no otros.
# ===========================================================================
$canvas->{ops} = [];
$ov->clear($canvas);
my @delete_ops = grep { $_->[0] eq 'delete' } @{$canvas->{ops}};
ok(scalar(@delete_ops) >= 1, 'clear produce al menos un delete');
my $tags_deleted = [ map { $_->[1] } @delete_ops ];
ok(grep({ $_ eq 'ov_example' } @$tags_deleted), 'clear borra tag ov_example');
ok(!grep({ $_ eq 'other_tag' } @$tags_deleted), 'clear no borra tags ajenos');

# ===========================================================================
# Test 4: compute_visible recibe (start,end) y procesa SOLO ese rango.
# ===========================================================================
$ov->compute_visible($md, undef, 50, 70);
my $range = $ov->compute_range();
is_deeply($range, [50, 70], 'compute_visible recibe exactamente [50, 70]');

# Verificar que el last_close corresponde al índice 70 (no al 999)
# Candle 70: close = 105 + 70 = 175
is($ov->{_last_close}, 175, 'compute_visible procesa rango [50,70], no todo el historial');

# Con un rango distinto [100, 110]:
$ov->compute_visible($md, undef, 100, 110);
is($ov->{_last_close}, 105 + 110, 'compute_visible procesa rango [100,110], no todo el historial');

# ===========================================================================
# Test 5: con replay_idx definido, compute_all no entrega elementos > tope.
# El OverlayManager.compute_all recibe start,end ya truncados por
# ChartEngine.compute_window cuando Replay está activo. Simulamos eso
# pasando un end truncado directamente.
# ===========================================================================
$ov->set_visible(1);
$mgr->compute_all($md, 0, 50);  # end=50, como si replay_idx=50
is($ov->{_last_close}, 105 + 50, 'con replay truncando end=50, compute_all procesa hasta idx 50');

# Si pasamos end=10, no debe leer más allá
$mgr->compute_all($md, 0, 10);
is($ov->{_last_close}, 105 + 10, 'con end=10, compute_all procesa hasta idx 10');

# ===========================================================================
# Test 6: overlay activo con ventana vacía (sin datos en el rango): no dibuja, no falla.
# ===========================================================================
my $empty_md = TestMarketData->new(0) if 0;  # no se puede con 0, usar rango fuera
$ov->compute_visible($md, undef, 2000, 2010);  # rango fuera del dataset (1000 velas)
is($ov->{_last_close}, undef, 'ventana fuera de rango: last_close undef, no falla');
$canvas->{ops} = [];
$ov->draw($canvas, $scale);
my $empty_ops = scalar grep { $_->[0] eq 'createLine' } @{$canvas->{ops}};
is($empty_ops, 0, 'ventana sin datos: draw no produce createLine');

done_testing();
