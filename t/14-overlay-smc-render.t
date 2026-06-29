use strict;
use warnings;
use Test::More;

use lib '.';
use Market::OverlayManager;
use Market::Overlays::Base;
use Market::Overlays::SMC_Structures;
use Market::Panels::Scales;
use Market::Debug::IndicatorSnapshot;

# =============================================================================
# Task 0008: Overlay SMC_Structures — render verificable por ops de Canvas.
#
# El cálculo (Indicators::SMC_Structures) ya se valida en t/09. Aquí probamos
# SOLO la capa de render (Overlays::SMC_Structures) con un TestIndicator que
# devuelve items prefijados del contrato (docs/PHASE2_DEBUG_CONTRACT.md), de
# forma determinista y sin Tk.
#
# TestCanvas registra TODAS las ops: delete / createLine / createRectangle /
# createText. Cada op lleva los -tags que el overlay pasó (siempre `ov_smc`).
# =============================================================================

my $D = 'Market::Debug::IndicatorSnapshot';

# --- TestCanvas que registra operaciones (incluye createRectangle) ---
{
    package TestCanvas;
    sub new { bless { w => 900, h => 600, ops => [] }, shift }
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
    sub createRectangle {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ createRectangle => @args ];
        return scalar @{ $self->{ops} };
    }
    sub createText {
        my ($self, @args) = @_;
        push @{ $self->{ops} }, [ createText => @args ];
        return scalar @{ $self->{ops} };
    }
}

# --- TestIndicator: devuelve items prefijados del contrato (mock del cálculo) ---
# Implementa solo los getters que el overlay consume. Es un stub puro.
{
    package TestIndicator;
    sub new {
        my ($class, %items) = @_;
        return bless { %items }, $class;
    }
    sub get_pivots    { shift->{pivots}    || [] }
    sub get_events    { shift->{events}    || [] }
    sub get_fvg       { shift->{fvgs}      || [] }
    sub get_fibonacci { shift->{fibs}      || [] }
    sub get_major     { shift->{major}     || [] }
}

# --- helper: extraer el tag de una op (último -tags => ...) ---
sub op_tag {
    my ($op) = @_;
    my @a = @$op;
    for my $i (0 .. $#a - 1) {
        return $a[$i + 1] if defined $a[$i] && $a[$i] eq '-tags';
    }
    return undef;
}

# --- helper: construir un Scales con rango de precio conocido ---
sub make_scales {
    my ($min_p, $max_p, $bars) = @_;
    $min_p //= 5;
    $max_p //= 25;
    $bars  //= 12;
    my $s = Market::Panels::Scales->new(
        min_y => $min_p, max_y => $max_p, bars => $bars, right_margin => 0
    );
    $s->{width}  = 900;
    $s->{height} = 600;
    return $s;
}

# =============================================================================
# Test 1: Contrato + registro en OverlayManager + tag `ov_smc`.
# =============================================================================
{
    my $ind = TestIndicator->new();
    my $ov  = Market::Overlays::SMC_Structures->new(indicator => $ind, theme => {});
    ok(Market::Overlays::Base->validate($ov), 'overlay SMC pasa validacion de contrato');
    is($ov->tag(), 'ov_smc', 'tag del overlay SMC = ov_smc');
    ok($ov->is_visible(), 'overlay visible por defecto');

    my $mgr = Market::OverlayManager->new();
    $mgr->register('smc', $ov);
    my @active = $mgr->each_active();
    is(scalar(@active), 1, 'OverlayManager lista el overlay SMC registrado');
    is($active[0]->tag(), 'ov_smc', 'overlay registrado con tag ov_smc');
}

# =============================================================================
# Test 2: cada item visible produce >=1 op con tag ov_smc.
# Fixture de items del contrato: BOS, CHoCH_true, CHoCH_false, FVG_up, fib_0.618,
# major_high, major_low, y un pivot HH.
# =============================================================================
{
    my $ind = TestIndicator->new(
        pivots => [ { index => 1, type => 'HH', price => 20 } ],
        events => [
            { index => 3, type => 'BOS',         dir => 'up',   price => 18 },
            { index => 4, type => 'CHoCH_true',  dir => 'down', price => 10 },
            { index => 5, type => 'CHoCH_false', dir => 'down', price => 12 },
        ],
        fvgs => [ { index => 6, type => 'FVG_up', hi => 16, lo => 14, mitig => 0 } ],
        fibs => [ { index => 7, type => 'fib_0.618', price => 13 } ],
        major => [
            { index => 7, type => 'major_high', price => 20 },
            { index => 7, type => 'major_low',  price => 10 },
        ],
    );
    my $ov     = Market::Overlays::SMC_Structures->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 12);

    # ventana [0, 10] incluye todos los items
    $ov->compute_visible(undef, $ind, 0, 10);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);

    my @draw_ops = grep { $_->[0] ne 'delete' } @{ $canvas->{ops} };
    # 1 pivot + 3 events + 1 fvg + 1 fib + 2 major = 8 items esperados
    ok(scalar(@draw_ops) >= 8, 'draw produce >= 8 ops (una por item)');

    # TODAS las ops de draw llevan el tag ov_smc
    my $all_tagged = 1;
    for my $op (@draw_ops) {
        my $t = op_tag($op);
        unless (defined $t && (!ref($t) ? $t eq 'ov_smc' : grep { $_ eq 'ov_smc' } @$t)) {
            $all_tagged = 0;
            last;
        }
    }
    ok($all_tagged, 'todas las ops de draw llevan el tag ov_smc');

    # Cada familia produce su tipo de op:
    # - createText para pivotes y eventos (etiquetas)
    # - createLine para major y fibonacci
    # - createRectangle para FVG
    my %by_kind;
    for my $op (@draw_ops) { $by_kind{ $op->[0] }++; }
    ok($by_kind{createRectangle} >= 1, 'el FVG produce un createRectangle (caja)');
    ok($by_kind{createText} >= 4, 'pivot + 3 eventos producen createText');
    ok($by_kind{createLine} >= 3, 'major x2 + fib producen createLine');

    # BOS y CHoCH_true vs CHoCH_false tienen etiqueta/distincion: los textos
    # estan presentes. createText($x,$y,-text=>$v,...): el valor va en [4].
    my @texts = map { $_->[0] eq 'createText' ? $_->[4] : () } @draw_ops;
    my %text_seen = map { $_ => 1 } @texts;
    ok($text_seen{'BOS'}, 'etiqueta BOS presente');
    ok($text_seen{'CHoCH'}, 'etiqueta CHoCH (true/false) presente');
}

# =============================================================================
# Test 3: FVG con mayor mitig produce una caja (rectangulo) MAS PEQUENA.
# Comparamos dos casos: mitig=0 (gap intacto, hi-lo grande) vs mitig alto
# (hi-lo recortado). El rectangulo dibujado refleja (hi - lo) escalado, asi que
# la altura del rectangulo es menor cuando hay mas mitigacion.
# =============================================================================
{
    my $scales = make_scales(5, 25, 12);

    # Caso 1: FVG sin mitigar. hi=16, lo=14 -> altura en precio = 2.
    my $ind1 = TestIndicator->new(
        fvgs => [ { index => 6, type => 'FVG_up', hi => 16, lo => 14, mitig => 0 } ],
    );
    my $ov1 = Market::Overlays::SMC_Structures->new(indicator => $ind1, theme => {});
    my $c1  = TestCanvas->new();
    $ov1->compute_visible(undef, $ind1, 0, 10);
    $c1->{ops} = [];
    $ov1->draw($c1, $scales);
    my @rects1 = grep { $_->[0] eq 'createRectangle' } @{ $c1->{ops} };
    is(scalar(@rects1), 1, 'FVG sin mitig: una caja');
    my ($x0a, $y0a, $x1a, $y1a) = @{ $rects1[0] }[1..4];
    my $h1 = abs($y1a - $y0a);

    # Caso 2: FVG muy mitigado. hi=15, lo=14.6 -> altura en precio = 0.4 (menor).
    my $ind2 = TestIndicator->new(
        fvgs => [ { index => 6, type => 'FVG_up', hi => 15, lo => 14.6, mitig => 0.8 } ],
    );
    my $ov2 = Market::Overlays::SMC_Structures->new(indicator => $ind2, theme => {});
    my $c2  = TestCanvas->new();
    $ov2->compute_visible(undef, $ind2, 0, 10);
    $c2->{ops} = [];
    $ov2->draw($c2, $scales);
    my @rects2 = grep { $_->[0] eq 'createRectangle' } @{ $c2->{ops} };
    is(scalar(@rects2), 1, 'FVG mitigado: una caja');
    my ($x0b, $y0b, $x1b, $y1b) = @{ $rects2[0] }[1..4];
    my $h2 = abs($y1b - $y0b);

    diag("FVG alto caja_h=$h1 px; FVG mitigado caja_h=$h2 px");
    ok($h2 < $h1, 'FVG con mayor mitig produce caja mas pequena (h2 < h1)');
}

# =============================================================================
# Test 4: Replay guard. Con replay_idx = end, el overlay no debe recibir ni
# dibujar items con index > end. Se verifica de dos formas:
#   (a) IndicatorSnapshot->replay_violations(visible_items, end) == 0
#   (b) ninguna op de draw se genera para items de index > end
# =============================================================================
{
    my $ind = TestIndicator->new(
        pivots => [
            { index => 3,  type => 'HH', price => 20 },   # <= end (visible)
            { index => 12, type => 'LL', price => 6  },   # > end (futuro, fuera)
        ],
        events => [],
        fvgs   => [],
        fibs   => [],
        major  => [],
    );
    my $ov     = Market::Overlays::SMC_Structures->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 20);
    my $replay_idx = 5;

    # compute_visible con end = replay_idx (como hace ChartEngine.compute_window
    # cuando Replay esta activo). El filtro interno index <= end descarta idx=12.
    $ov->compute_visible(undef, $ind, 0, $replay_idx);

    # (a) replay guard sobre los items que el overlay dibujara
    my $vis = $ov->visible_items();
    is(scalar($D->replay_violations($vis, $replay_idx)), 0,
       'replay guard: ningun item visible tiene index > replay_idx');
    # solo el pivot idx=3 (<=5) sobrevive; el idx=12 fue filtrado
    my @pivots_vis = grep { $_->{type} eq 'HH' || $_->{type} eq 'LL' } @$vis;
    is(scalar(@pivots_vis), 1, 'replay guard: solo el pivot idx=3 (<=replay_idx) es visible');
    is($pivots_vis[0]->{index}, 3, 'replay guard: el pivot visible es el idx=3, no el idx=12');

    # (b) draw no genera ops para el item futuro (idx=12)
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    my @texts = map { $_->[0] eq 'createText' ? $_ : () } @{ $canvas->{ops} };
    # createText($x,$y,-text=>$v,...): valor de texto en [4].
    my @ll_texts = grep { defined $_->[4] && $_->[4] eq 'LL' } @texts;
    is(scalar(@ll_texts), 0, 'replay guard: draw NO dibuja la etiqueta LL del idx=12 (futuro)');
}

# =============================================================================
# Test 5: set_visible(0) -> draw no produce ops; clear borra solo su tag.
# =============================================================================
{
    my $ind = TestIndicator->new(
        major => [ { index => 0, type => 'major_high', price => 20 } ],
    );
    my $ov     = Market::Overlays::SMC_Structures->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    my $scales = make_scales();

    $ov->compute_visible(undef, $ind, 0, 5);
    $ov->set_visible(0);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    my @draw_ops_hidden = grep { $_->[0] ne 'delete' } @{ $canvas->{ops} };
    is(scalar(@draw_ops_hidden), 0, 'set_visible(0): draw no produce ops');

    # clear solo borra el tag ov_smc
    $ov->set_visible(1);
    $canvas->{ops} = [];
    $ov->clear($canvas);
    my @del = grep { $_->[0] eq 'delete' } @{ $canvas->{ops} };
    ok(scalar(@del) >= 1, 'clear produce al menos un delete');
    my $del_tag = $del[0][1];
    is($del_tag, 'ov_smc', 'clear borra el tag ov_smc (no otros)');
}

# =============================================================================
# Test 6: fib_0.618 destacado (estilo distinto del resto de niveles fib).
# El overlay dibuja 0.618 con width=2 y color de acento; los demas con width=1.
# =============================================================================
{
    my $ind = TestIndicator->new(
        fibs => [
            { index => 7, type => 'fib_0.236', price => 9  },
            { index => 7, type => 'fib_0.618', price => 13 },
            { index => 7, type => 'fib_0.786', price => 15 },
        ],
    );
    my $ov     = Market::Overlays::SMC_Structures->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 12);
    $ov->compute_visible(undef, $ind, 0, 10);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);

    # 3 createLine (uno por nivel fib)
    my @lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    is(scalar(@lines), 3, 'fibonacci: 3 niveles -> 3 lineas');

    # Extraer el -width de cada linea
    my %width_by_y;
    for my $ln (@lines) {
        my @a = @$ln;
        my ($y) = ($a[2]);  # segundo Y (y2 = y1 = y)
        my $w = 1;
        for my $i (0 .. $#a - 1) {
            if (defined $a[$i] && $a[$i] eq '-width') { $w = $a[$i + 1]; last; }
        }
        $width_by_y{$y} = $w;
    }
    # el y de fib_0.618 (price=13) en rango [5,25], height=600:
    #   y = (25-13)/(25-5) * 600 = 12/20*600 = 360
    my $y618 = $scales->value_to_y(13);
    is($width_by_y{$y618}, 2, 'fib_0.618 dibujada con width=2 (destacada)');
    # los demas niveles usan width=1
    my $y236 = $scales->value_to_y(9);
    is($width_by_y{$y236}, 1, 'fib_0.236 dibujada con width=1 (no destacada)');
}

# =============================================================================
# Test 7: compute_range refleja la ventana recibida (no recorre todo el historial).
# =============================================================================
{
    my $ind = TestIndicator->new(
        pivots => [ { index => 50, type => 'HH', price => 20 } ],
    );
    my $ov = Market::Overlays::SMC_Structures->new(indicator => $ind, theme => {});
    $ov->compute_visible(undef, $ind, 40, 60);
    is_deeply($ov->compute_range(), [40, 60], 'compute_visible registra la ventana [40,60]');
    # el pivot idx=50 esta dentro -> visible; si pidieramos ventana [0,10], fuera
    $ov->compute_visible(undef, $ind, 0, 10);
    my $vis = $ov->visible_items();
    is(scalar(@$vis), 0, 'ventana [0,10]: pivot idx=50 queda fuera (no se dibuja)');
}

# =============================================================================
# Test 8: los overlays reciben indices GLOBALES, pero Scales dibuja indices
# LOCALES de la ventana visible. Un item idx=50 en ventana [40,60] debe caer
# en la barra local 10, no en X de barra global 50 (bug visual 0019).
# =============================================================================
{
    my $ind = TestIndicator->new(
        pivots => [ { index => 50, type => 'HH', price => 20 } ],
    );
    my $ov     = Market::Overlays::SMC_Structures->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 21); # ventana inclusiva [40,60] => 21 barras

    $ov->compute_visible(undef, $ind, 40, 60);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);

    my @texts = grep { $_->[0] eq 'createText' && defined $_->[4] && $_->[4] eq 'HH' } @{ $canvas->{ops} };
    is(scalar(@texts), 1, 'SMC local-index: dibuja una etiqueta HH visible');
    my $expected_x = $scales->index_to_center_x(10); # 50 - 40
    is($texts[0]->[1], $expected_x, 'SMC local-index: idx global 50 se dibuja como local 10');
}

# =============================================================================
# Test 9: dibujo de lineas entrecortadas (BOS/CHoCH) si viene start_index
# =============================================================================
{
    my $ind = TestIndicator->new(
        events => [
            { index => 5, type => 'BOS', dir => 'up', price => 15, start_index => 2 }
        ]
    );
    my $ov     = Market::Overlays::SMC_Structures->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 10); # ventana [0, 9]

    $ov->compute_visible(undef, $ind, 0, 9);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);

    my @lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    is(scalar(@lines), 1, 'BOS con start_index: crea una linea para representar el breakout');
    
    my @texts = grep { $_->[0] eq 'createText' && defined $_->[4] && $_->[4] eq 'BOS' } @{ $canvas->{ops} };
    is(scalar(@texts), 1, 'BOS con start_index: crea un texto BOS');
    my $expected_mid_x = ($scales->index_to_center_x(2) + $scales->index_to_center_x(5)) / 2;
    ok(abs($texts[0]->[1] - $expected_mid_x) < 0.001, 'BOS con start_index: texto centrado en el medio de la linea');
}

done_testing();
