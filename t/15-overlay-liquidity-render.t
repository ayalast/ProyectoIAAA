use strict;
use warnings;
use Test::More;

use lib '.';
use Market::OverlayManager;
use Market::Overlays::Base;
use Market::Overlays::Liquidity;
use Market::Panels::Scales;
use Market::Debug::IndicatorSnapshot;

# =============================================================================
# Task 0012: Overlay Liquidity — render conforme a la Tabla 2 del PDF.
#
# El cálculo (Indicators::Liquidity) ya se valida en t/10. Aquí probamos SOLO
# la capa de render (Overlays::Liquidity) con un TestIndicator que devuelve
# items prefijados del contrato (docs/PHASE2_DEBUG_CONTRACT.md), de forma
# determinista y sin Tk.
#
# Tabla 2 (lo que se verifica):
#   BSL         rojo   punteado, etiqueta "BSL"
#   SSL         verde  punteado, etiqueta "SSL"
#   EQH/EQL     configurable, línea que conecta los dos pivotes, etiqueta EQH/EQL
#   SWEEP_UP    rojo,  etiqueta "SWEEP ↑"
#   SWEEP_DOWN  verde, etiqueta "SWEEP ↓"
#   GRAB        naranja, etiqueta "LQ GRAB"
#   RUN         azul,  etiqueta "LQ RUN"
# =============================================================================

my $D = 'Market::Debug::IndicatorSnapshot';

# --- TestCanvas que registra operaciones ---
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
{
    package TestIndicator;
    sub new {
        my ($class, %items) = @_;
        return bless { %items }, $class;
    }
    sub get_levels { shift->{levels} || [] }
    sub get_events { shift->{events} || [] }
}

# --- helpers de inspección de ops ---
# Extrae el valor de una clave -key => val de una op (array plano tras el kind).
sub op_arg {
    my ($op, $key) = @_;
    my @a = @$op;
    for my $i (0 .. $#a - 1) {
        return $a[$i + 1] if defined $a[$i] && $a[$i] eq "-$key";
    }
    return undef;
}

# Extrae el tag de una op (-tags => ...). Devuelve '' si no hay.
sub op_tag {
    my ($op) = @_;
    return op_arg($op, 'tags');
}

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

# Items completos del contrato para el test de Tabla 2.
sub tab2_indicator {
    return TestIndicator->new(
        levels => [
            { index => 1, type => 'BSL', price => 20 },
            { index => 2, type => 'SSL', price => 8  },
            { index => 3, type => 'EQH', price => 19 },
            { index => 5, type => 'EQH', price => 19.2 },
            { index => 4, type => 'EQL', price => 9 },
            { index => 6, type => 'EQL', price => 8.9 },
        ],
        events => [
            { index => 7, type => 'SWEEP_UP',   dir => 'up',   price => 20, state => 'Resolved' },
            { index => 8, type => 'SWEEP_DOWN', dir => 'down', price => 8,  state => 'Resolved' },
            { index => 9, type => 'GRAB',       dir => 'up',   price => 20, state => 'Resolved' },
            { index => 10,type => 'RUN',        dir => 'up',   price => 20, state => 'Resolved' },
        ],
    );
}

# =============================================================================
# Test 1: Contrato + registro en OverlayManager + tag `ov_liq`.
# =============================================================================
{
    my $ind = TestIndicator->new();
    my $ov  = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    ok(Market::Overlays::Base->validate($ov), 'overlay Liquidity pasa validacion de contrato');
    is($ov->tag(), 'ov_liq', 'tag del overlay Liquidity = ov_liq');
    ok($ov->is_visible(), 'overlay visible por defecto');

    my $mgr = Market::OverlayManager->new();
    $mgr->register('liq', $ov);
    my @active = $mgr->each_active();
    is(scalar(@active), 1, 'OverlayManager lista el overlay Liquidity registrado');
    is($active[0]->tag(), 'ov_liq', 'overlay registrado con tag ov_liq');

    # Toggles individuales presentes y visibles por defecto
    for my $el (qw(BSL SSL EQH EQL SWEEP GRAB RUN)) {
        ok($ov->is_element_visible($el), "elemento $el visible por defecto");
    }
}

# =============================================================================
# Test 2: Tabla 2 — cada elemento produce ops con tag ov_liq y el color/estilo
# esperado (comparando el argumento -fill / -dash / -text de las ops).
# =============================================================================
{
    my $ind    = tab2_indicator();
    my $ov     = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 14);

    $ov->compute_visible(undef, $ind, 0, 14);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    my @ops = @{ $canvas->{ops} };

    # Todas las ops de draw (no delete) llevan el tag ov_liq.
    my @draw = grep { $_->[0] ne 'delete' } @ops;
    my $all_tagged = 1;
    for my $op (@draw) {
        my $t = op_tag($op);
        unless (defined $t && $t eq 'ov_liq') {
            $all_tagged = 0; last;
        }
    }
    ok($all_tagged, 'todas las ops de draw llevan el tag ov_liq');

    # Helper: textos emitidos.
    my @texts = map { $_->[0] eq 'createText' ? $_->[4] : () } @draw;
    my %text_seen = map { $_ => 1 } @texts;

    # Helper: líneas con su color y (si aplica) dash.
    my @lines = grep { $_->[0] eq 'createLine' } @draw;
    my %color_of_line = map { _line_signature($_) => op_arg($_, 'fill') } @lines;

    # --- BSL: rojo, punteado, etiqueta "BSL" ---
    ok($text_seen{'BSL'}, 'BSL: etiqueta "BSL" presente');
    my @bsl_lines = grep { defined op_arg($_, 'fill') && op_arg($_, 'fill') eq '#ef5350' } @lines;
    ok(scalar(@bsl_lines) >= 1, 'BSL: al menos una linea roja (#ef5350)');
    my $bsl_dashed = 0;
    for my $ln (@bsl_lines) {
        my $dash = op_arg($ln, 'dash');
        $bsl_dashed = 1 if defined $dash && ref($dash) eq 'ARRAY' && @$dash;
    }
    ok($bsl_dashed, 'BSL: linea punteada (-dash definido)');

    # --- SSL: verde, punteado, etiqueta "SSL" ---
    ok($text_seen{'SSL'}, 'SSL: etiqueta "SSL" presente');
    my @ssl_lines = grep { defined op_arg($_, 'fill') && op_arg($_, 'fill') eq '#26a69a' } @lines;
    ok(scalar(@ssl_lines) >= 1, 'SSL: al menos una linea verde (#26a69a)');

    # --- EQH / EQL: etiquetas presentes, color configurable (default morado) ---
    ok($text_seen{'EQH'}, 'EQH: etiqueta "EQH" presente');
    ok($text_seen{'EQL'}, 'EQL: etiqueta "EQL" presente');
    # EQH conecta los dos pivotes (index 3 y 5): hay una createLine entre ellos.
    # Comprobamos que existe al menos una linea con el color default de EQH.
    my @eqh_pair_lines = grep { defined op_arg($_, 'fill') && op_arg($_, 'fill') eq '#ab47bc' } @lines;
    ok(scalar(@eqh_pair_lines) >= 1, 'EQH: linea que conecta los pivotes (color default morado)');
    my @eql_pair_lines = grep { defined op_arg($_, 'fill') && op_arg($_, 'fill') eq '#7e57c2' } @lines;
    ok(scalar(@eql_pair_lines) >= 1, 'EQL: linea que conecta los pivotes (color default morado oscuro)');

    # --- SWEEP_UP: rojo, etiqueta "SWEEP ↑" ---
    ok($text_seen{"SWEEP \x{2191}"}, 'SWEEP_UP: etiqueta "SWEEP ↑" presente');
    my @sweepup = grep { defined op_arg($_, 'fill') && op_arg($_, 'fill') eq '#ef5350' } @lines;
    my $sweepup_red = 0;
    for my $ln (@sweepup) { $sweepup_red = 1 if defined op_arg($ln, 'width') && op_arg($ln, 'width') == 2; }
    # SWEEP_UP produce una linea vertical (width 2, rojo); la contamos entre las rojas de width 2
    ok($sweepup_red, 'SWEEP_UP: marcador rojo (linea width=2, #ef5350)');

    # --- SWEEP_DOWN: verde, etiqueta "SWEEP ↓" ---
    ok($text_seen{"SWEEP \x{2193}"}, 'SWEEP_DOWN: etiqueta "SWEEP ↓" presente');

    # --- GRAB: naranja, etiqueta "LQ GRAB" ---
    ok($text_seen{'LQ GRAB'}, 'GRAB: etiqueta "LQ GRAB" presente');
    my @grab = grep { defined op_arg($_, 'fill') && op_arg($_, 'fill') eq '#ff9800' } @lines;
    ok(scalar(@grab) >= 1, 'GRAB: marcador naranja (#ff9800)');

    # --- RUN: azul, etiqueta "LQ RUN" ---
    ok($text_seen{'LQ RUN'}, 'RUN: etiqueta "LQ RUN" presente');
    my @run = grep { defined op_arg($_, 'fill') && op_arg($_, 'fill') eq '#2962ff' } @lines;
    ok(scalar(@run) >= 1, 'RUN: marcador azul (#2962ff)');
}

# =============================================================================
# Test 3: EQH/EQL colores configurables via tema.
# =============================================================================
{
    my $ind = TestIndicator->new(
        levels => [
            { index => 1, type => 'EQH', price => 19 },
            { index => 3, type => 'EQH', price => 19.2 },
        ],
    );
    my $ov = Market::Overlays::Liquidity->new(
        indicator => $ind,
        theme     => { liq_eqh => '#ff0000', liq_eqh_label => '#ff0000' },
    );
    my $canvas = TestCanvas->new();
    my $scales = make_scales();
    $ov->compute_visible(undef, $ind, 0, 6);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    my @lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    my @eqh = grep { defined op_arg($_, 'fill') && op_arg($_, 'fill') eq '#ff0000' } @lines;
    is(scalar(@eqh), 1, 'EQH: respeta el color configurado por tema (liq_eqh=#ff0000)');
}

# =============================================================================
# Test 4: toggles individuales — set_element_visible(0) oculta SOLO ese elemento.
# =============================================================================
{
    my $ind    = tab2_indicator();
    my $scales = make_scales(5, 25, 14);

    # baseline: contar ops por etiqueta con todo visible.
    my $ov_full = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    $ov_full->compute_visible(undef, $ind, 0, 14);
    my $c_full = TestCanvas->new();
    $ov_full->draw($c_full, $scales);
    my %texts_full;
    for my $op (@{ $c_full->{ops} }) {
        next unless $op->[0] eq 'createText';
        $texts_full{ $op->[4] }++;
    }

    # Ocultar GRAB -> la etiqueta "LQ GRAB" desaparece, las demás se mantienen.
    my $ov = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    $ov->set_element_visible('GRAB', 0);
    ok(!$ov->is_element_visible('GRAB'), 'toggle GRAB desactivado');
    $ov->compute_visible(undef, $ind, 0, 14);
    my $c = TestCanvas->new();
    $ov->draw($c, $scales);
    my %texts_hidden;
    for my $op (@{ $c->{ops} }) {
        next unless $op->[0] eq 'createText';
        $texts_hidden{ $op->[4] }++;
    }
    is($texts_hidden{'LQ GRAB'} // 0, 0, 'toggle GRAB off: etiqueta "LQ GRAB" ausente');
    ok(($texts_hidden{'BSL'} || 0) == ($texts_full{'BSL'} || 0), 'toggle GRAB off: BSL intacto');
    ok(($texts_hidden{'SSL'} || 0) == ($texts_full{'SSL'} || 0), 'toggle GRAB off: SSL intacto');
    ok(($texts_hidden{'LQ RUN'} || 0) == ($texts_full{'LQ RUN'} || 0), 'toggle GRAB off: RUN intacto');

    # Ocultar SWEEP -> tanto "SWEEP ↑" como "SWEEP ↓" desaparecen (familia SWEEP).
    my $ov2 = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    $ov2->set_element_visible('SWEEP', 0);
    $ov2->compute_visible(undef, $ind, 0, 14);
    my $c2 = TestCanvas->new();
    $ov2->draw($c2, $scales);
    my %t2;
    for my $op (@{ $c2->{ops} }) { next unless $op->[0] eq 'createText'; $t2{ $op->[4] }++; }
    is($t2{"SWEEP \x{2191}"} // 0, 0, 'toggle SWEEP off: "SWEEP ↑" ausente');
    is($t2{"SWEEP \x{2193}"} // 0, 0, 'toggle SWEEP off: "SWEEP ↓" ausente');
    ok(($t2{'BSL'} || 0) == ($texts_full{'BSL'} || 0), 'toggle SWEEP off: BSL intacto');

    # set_visible(0) del overlay entero: ninguna op de draw.
    my $ov3 = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    $ov3->set_visible(0);
    $ov3->compute_visible(undef, $ind, 0, 14);
    my $c3 = TestCanvas->new();
    $ov3->draw($c3, $scales);
    my @draw3 = grep { $_->[0] ne 'delete' } @{ $c3->{ops} };
    is(scalar(@draw3), 0, 'set_visible(0): draw no produce ops');
}

# =============================================================================
# Test 5: Replay guard. Con replay_idx = end, el overlay no debe recibir ni
# dibujar items con index > end.
# =============================================================================
{
    my $ind = TestIndicator->new(
        levels => [
            { index => 3,  type => 'BSL', price => 20 },   # <= end (visible)
            { index => 12, type => 'BSL', price => 22 },   # > end (futuro, fuera)
        ],
        events => [
            { index => 4,  type => 'GRAB', dir => 'up', price => 20 },   # <= end
            { index => 11, type => 'RUN',  dir => 'up', price => 20 },   # > end (futuro)
        ],
    );
    my $ov     = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 20);
    my $replay_idx = 5;

    $ov->compute_visible(undef, $ind, 0, $replay_idx);

    # (a) replay guard sobre los items visibles
    my $vis = $ov->visible_items();
    is(scalar($D->replay_violations($vis, $replay_idx)), 0,
       'replay guard: ningun item visible tiene index > replay_idx');

    # solo el BSL idx=3 y GRAB idx=4 sobreviven; idx=12 e idx=11 filtrados
    my @bsl = grep { $_->{type} eq 'BSL' } @$vis;
    is(scalar(@bsl), 1, 'replay guard: solo el BSL idx=3 (<=replay_idx) es visible');
    is($bsl[0]->{index}, 3, 'replay guard: BSL visible es idx=3, no idx=12');
    my @ev = grep { $_->{type} eq 'GRAB' } @$vis;
    is(scalar(@ev), 1, 'replay guard: solo el GRAB idx=4 (<=replay_idx) es visible');
    my @run = grep { $_->{type} eq 'RUN' } @$vis;
    is(scalar(@run), 0, 'replay guard: el RUN idx=11 (futuro) fue filtrado');

    # (b) draw no genera etiquetas para items futuros
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);
    my %t;
    for my $op (@{ $canvas->{ops} }) { next unless $op->[0] eq 'createText'; $t{ $op->[4] }++; }
    is(scalar(grep { /LQ RUN/ } keys %t), 0, 'replay guard: draw NO dibuja "LQ RUN" del idx=11');
}

# =============================================================================
# Test 6: compute_range refleja la ventana recibida (no recorre todo el historial).
# =============================================================================
{
    my $ind = TestIndicator->new(
        levels => [ { index => 50, type => 'BSL', price => 20 } ],
    );
    my $ov = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    $ov->compute_visible(undef, $ind, 40, 60);
    is_deeply($ov->compute_range(), [40, 60], 'compute_visible registra la ventana [40,60]');
    $ov->compute_visible(undef, $ind, 0, 10);
    my $vis = $ov->visible_items();
    is(scalar(@$vis), 0, 'ventana [0,10]: BSL idx=50 queda fuera (no se dibuja)');
}

# =============================================================================
# Test 7: clear borra solo su tag ov_liq.
# =============================================================================
{
    my $ind = TestIndicator->new(
        levels => [ { index => 0, type => 'BSL', price => 20 } ],
    );
    my $ov     = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    $ov->compute_visible(undef, $ind, 0, 5);
    $ov->clear($canvas);
    my @del = grep { $_->[0] eq 'delete' } @{ $canvas->{ops} };
    ok(scalar(@del) >= 1, 'clear produce al menos un delete');
    is($del[0][1], 'ov_liq', 'clear borra el tag ov_liq (no otros)');
}

# =============================================================================
# Test 8: los overlays reciben indices GLOBALES, pero Scales dibuja indices
# LOCALES de la ventana visible. Un evento idx=50 en ventana [40,60] debe caer
# en la barra local 10, no quedar volando fuera del viewport (bug visual 0019).
# =============================================================================
{
    my $ind = TestIndicator->new(
        events => [ { index => 50, type => 'GRAB', dir => 'up', price => 20 } ],
    );
    my $ov     = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 21); # ventana inclusiva [40,60] => 21 barras

    $ov->compute_visible(undef, $ind, 40, 60);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);

    my @texts = grep { $_->[0] eq 'createText' && defined $_->[4] && $_->[4] eq 'LQ GRAB' } @{ $canvas->{ops} };
    is(scalar(@texts), 1, 'Liquidity local-index: dibuja una etiqueta LQ GRAB visible');
    my $expected_x = $scales->index_to_center_x(10); # 50 - 40
    is($texts[0]->[1], $expected_x, 'Liquidity local-index: idx global 50 se dibuja como local 10');
}

# --- helper: firma de una linea para distinguirlas (no usado en asserts finales)
sub _line_signature {
    my ($op) = @_;
    return join(',', $op->[1], $op->[2], $op->[3], $op->[4]);
}

# =============================================================================
# Test 9: dibujo de marcadores de evento (BSL vs SSL) dirigidos hacia afuera
# =============================================================================
{
    my $ind = TestIndicator->new(
        events => [
            { index => 2, type => 'GRAB', dir => 'up',   price => 15, extreme => 18 }, # BSL
            { index => 4, type => 'RUN',  dir => 'down', price => 10, extreme => 8  }, # SSL
        ]
    );
    my $ov     = Market::Overlays::Liquidity->new(indicator => $ind, theme => {});
    my $canvas = TestCanvas->new();
    my $scales = make_scales(5, 25, 10); # ventana [0, 9]

    $ov->compute_visible(undef, $ind, 0, 9);
    $canvas->{ops} = [];
    $ov->draw($canvas, $scales);

    my @lines = grep { $_->[0] eq 'createLine' } @{ $canvas->{ops} };
    is(scalar(@lines), 2, 'Liquidity markers: crea dos lineas de marcador');

    # BSL GRAB (index 2, extreme 18):
    # extreme=18 -> y = value_to_y(18) = 210.
    # dir=up -> va hacia arriba (y - 20) -> Y1=210, Y2=190.
    my @up_lines = grep { $_->[2] == 210 && $_->[4] == 190 } @lines;
    is(scalar(@up_lines), 1, 'Liquidity BSL grab: la linea va hacia arriba desde el High (210 -> 190)');

    # SSL RUN (index 4, extreme 8):
    # extreme=8 -> y = value_to_y(8) = 510.
    # dir=down -> va hacia abajo (y + 20) -> Y1=510, Y2=530.
    my @down_lines = grep { $_->[2] == 510 && $_->[4] == 530 } @lines;
    is(scalar(@down_lines), 1, 'Liquidity SSL run: la linea va hacia abajo desde el Low (510 -> 530)');
}

done_testing();
