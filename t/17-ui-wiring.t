use strict;
use warnings;
use Test::More;

use lib '.';
use Market::UI::Callbacks;
use Market::ReplayController;

# =============================================================================
# Task 0004: cableado de la barra de controles de Fase 2 (spec 0010).
#
# La UI Tk no se testa headless (`use Tk; MainWindow->new` requiere servidor
# gráfico). Pero las ACCIONES de la barra están factorizadas en
# Market::UI::Callbacks (sin Tk), así que aquí verificamos con mocks que cada
# callback invoca exactamente al método correcto del ChartEngine /
# ReplayController / OverlayManager / overlay de liquidez, sin abrir ventana.
#
# Estrategia: un MockChart que registra cada llamada (método + argumentos) y
# delega el ReplayController a un controlador REAL sobre un MarketData mock,
# para probar también el cableado start/step/play/pause/exit. El mock $mw
# ejecuta `after($ms,$cb)` inmediatamente (loop de un tick) para que play/
# fast_fwd recorran su path de reprogramación.
#
# Lo que verifica este test (criterios de aceptación de la task):
#   1. timeframes() retorna exactamente las 8 TF en orden (1m..W).
#   2. Los callbacks de TF invocan $chart->set_timeframe($tf) con el valor
#      correcto para las 8 temporalidades y sincronizan active_tf.
#   3. Los 7 botones de Replay invocan el método correcto del ReplayController
#      (start/play/pause/step_forward/step_backward/fast_forward/exit) y
#      disparan request_render (re-render tras cada acción).
#   4. Play/Fast Fwd usan after() sobre $mw (el mock lo registra).
#   5. Cada toggle de overlay invoca overlay_manager->set_visible($name,$on)
#      sin afectar a los demás.
#   6. Cada toggle de elemento de liquidez invoca liq_overlay->set_element_visible.
#   7. El toggle HTF alterna su estado ($htf_enabled) y pide re-render.
# =============================================================================

# --- MockMarketData: dataset sintético de N velas 1m ---
{
    package MockMarketData;
    sub new {
        my ($class, $n) = @_;
        my @data;
        for my $i (0 .. $n - 1) {
            push @data, [sprintf('2026-04-01T00:%02d:00-05:00', $i % 60),
                         100 + $i, 110 + $i, 95 + $i, 105 + $i, 100];
        }
        return bless { data => \@data }, $class;
    }
    sub size { scalar @{ shift->{data} } }
}

# --- MockLiqOverlay: registra set_element_visible / set_visible ---
{
    package MockLiqOverlay;
    sub new {
        my ($class) = @_;
        return bless { elem_calls => [], visible => 1, elem => {} }, $class;
    }
    sub set_visible { my ($s,$b) = @_; $s->{visible} = $b ? 1 : 0; $s }
    sub set_element_visible {
        my ($s, $elem, $bool) = @_;
        push @{ $s->{elem_calls} }, [ $elem, $bool ? 1 : 0 ];
        $s->{elem}{$elem} = $bool ? 1 : 0;
        return $s;
    }
}

# --- MockOverlayManager: registra set_visible por nombre ---
{
    package MockOverlayManager;
    sub new { bless { vis_calls => [], states => {} }, shift }
    sub set_visible {
        my ($s, $name, $bool) = @_;
        push @{ $s->{vis_calls} }, [ $name, $bool ? 1 : 0 ];
        $s->{states}{$name} = $bool ? 1 : 0;
        return $s;
    }
}

# --- MockMW: MainWindow stub. after($ms,$cb) ejecuta el callback un número
# limitado de veces (simula N ticks del loop) y registra las llamadas. El límite
# evita recursión infinita cuando el callback se reprograma a sí mismo (play). ---
{
    package MockMW;
    sub new {
        my ($class, $max) = @_;
        return bless { after_calls => 0, fired => 0, max => $max // 1 }, $class;
    }
    sub after {
        my ($s, $ms, $cb) = @_;
        $s->{after_calls}++;
        return if $s->{fired} >= $s->{max};
        return unless ref($cb) eq 'CODE';
        $s->{fired}++;
        $cb->();   # tick inmediato (limitado a max)
        return;
    }
}

# --- MockChart: registra set_timeframe / request_render; expone el
# ReplayController REAL + managers mock + liq_overlay mock + market_data mock.
# visible_bars fijo para que el cálculo del índice inicial de replay sea
# determinista. ---
{
    package MockChart;
    sub new {
        my ($class, %a) = @_;
        my $md = $a{market_data} || MockMarketData->new(100);
        return bless {
            market_data       => $md,
            replay_controller => Market::ReplayController->new(market_data => $md),
            overlay_manager   => $a{overlay_manager} || MockOverlayManager->new(),
            liq_overlay       => $a{liq_overlay} || MockLiqOverlay->new(),
            visible_bars      => $a{visible_bars} || 20,
            _calls            => [],
            _tf               => [],
        }, $class;
    }
    sub set_timeframe {
        my ($s, $tf) = @_;
        push @{ $s->{_tf} }, $tf;
        push @{ $s->{_calls} }, [ set_timeframe => $tf ];
        return;
    }
    sub request_render {
        my ($s) = @_;
        push @{ $s->{_calls} }, [ 'request_render' ];
        return;
    }
    sub tf_calls    { shift->{_tf} }
    sub render_count { scalar grep { $_->[0] eq 'request_render' } @{ shift->{_calls} } }
}

# Helper: un MockMW que NO ejecuta el callback (para probar que play/fast_fwd
# SÍ llaman after sin disparar efectos secundarios no deseados en otras aserciones).
{
    package MockMWNoop;
    sub new { bless { after_calls => 0 }, shift }
    sub after { shift->{after_calls}++; return }
}

# =============================================================================
# Test 1: timeframes() retorna exactamente las 8 TF en orden.
# =============================================================================
is_deeply([ Market::UI::Callbacks->timeframes() ],
          [qw(1m 5m 15m 1h 2h 4h D W)],
          'timeframes() retorna las 8 TF en orden (1m..W)');
is(scalar(Market::UI::Callbacks->timeframes()), 8, 'son exactamente 8 TF');

# =============================================================================
# Test 2: callbacks de TF invocan set_timeframe con el valor correcto para las 8
# y sincronizan $active_tf compartido.
# =============================================================================
{
    my $chart   = MockChart->new();
    my $active_tf = '1m';
    my %vars = ( active_tf => \$active_tf );

    for my $tf (Market::UI::Callbacks->timeframes()) {
        my $cb = Market::UI::Callbacks->make_tf_callback($chart, $tf, \%vars);
        $cb->();
    }
    is_deeply($chart->tf_calls(),
              [qw(1m 5m 15m 1h 2h 4h D W)],
              'los 8 callbacks de TF llaman set_timeframe con los valores correctos en orden');
    is($active_tf, 'W',
       'make_tf_callback sincroniza $active_tf con el último TF seleccionado (W)');
}

# =============================================================================
# Test 3: Inicio Replay invoca replay_controller->start y dispara re-render.
# =============================================================================
{
    my $chart   = MockChart->new(market_data => MockMarketData->new(100));
    my $replay_on = 0;
    my %vars = ( replay_on => \$replay_on );
    my $rc = $chart->{replay_controller};

    ok(!$rc->is_active(), 'replay inactivo antes de Inicio');
    my $cb = Market::UI::Callbacks->make_replay_start($chart, \%vars);
    $cb->();

    ok($rc->is_active(), 'Inicio Replay activa el controlador');
    ok(defined $rc->current_index(), 'Inicio fija un replay_idx');
    is($replay_on, 1, 'Inicio marca replay_on=1');
    ok($chart->render_count() >= 1, 'Inicio dispara re-render');

    # Índice inicial esperado = last(99) - visible_bars(20) = 79.
    is($rc->current_index(), 79, 'Inicio arranca en last - visible_bars = 79');
}

# =============================================================================
# Test 4: Play invoca replay_controller->play y usa after() sobre $mw; el tick
# hace step_forward + re-render. Verifica además que Pause detiene.
# =============================================================================
{
    my $chart   = MockChart->new(market_data => MockMarketData->new(100));
    my $mw    = MockMW->new();        # after ejecuta el callback (un tick)
    my $replay_on = 0;
    my %vars = ( replay_on => \$replay_on );
    my $rc = $chart->{replay_controller};

    # Arrancamos primero (Play arranca solo si no está activo, pero para
    # aislar el efecto de play medimos desde un idx conocido).
    $rc->start(50);
    my $before = $rc->current_index();
    is($before, 50, 'replay parado en idx 50 antes de Play');

    my $cb = Market::UI::Callbacks->make_replay_play($chart, $mw, \%vars);
    $cb->();

    ok($rc->{playing}, 'Play deja el controlador en playing=1');
    ok($mw->{after_calls} >= 1, 'Play programa al menos un after() sobre $mw');
    # El mock MockMW ejecuta el tick inmediato → step_forward avanza 1.
    is($rc->current_index(), 51, 'el tick de Play avanza 1 vela (50->51)');
    ok($chart->render_count() >= 1, 'Play dispara re-render');

    # Pause detiene la reproducción.
    my $pause = Market::UI::Callbacks->make_replay_pause($chart, \%vars);
    $pause->();
    ok(!$rc->{playing}, 'Pause deja playing=0');
}

# =============================================================================
# Test 5: Pause invoca pause y re-render (sin $mw).
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $rc = $chart->{replay_controller};
    $rc->start(10);
    $rc->{playing} = 1;
    my $render_before = $chart->render_count();
    my $cb = Market::UI::Callbacks->make_replay_pause($chart, {});
    $cb->();
    ok(!$rc->{playing}, 'Pause detiene playing');
    ok($chart->render_count() > $render_before, 'Pause dispara re-render');
}

# =============================================================================
# Test 6: Step Forward avanza exactamente 1 y re-render.
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $rc = $chart->{replay_controller};
    $rc->start(40);
    my $cb = Market::UI::Callbacks->make_replay_step_fwd($chart);
    $cb->();
    is($rc->current_index(), 41, 'Step > avanza exactamente 1 (40->41)');
    ok($chart->render_count() >= 1, 'Step > dispara re-render');

    # Step funciona aunque el replay no estuviera activo (lo arranca).
    $rc->exit();
    ok(!$rc->is_active(), 'replay inactivo tras exit');
    $cb->();
    ok($rc->is_active(), 'Step > arranca el replay si no estaba activo');
}

# =============================================================================
# Test 7: Step Back retrocede exactamente 1 y re-render.
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $rc = $chart->{replay_controller};
    $rc->start(40);
    my $cb = Market::UI::Callbacks->make_replay_step_back($chart);
    $cb->();
    is($rc->current_index(), 39, 'Step < retrocede exactamente 1 (40->39)');
    ok($chart->render_count() >= 1, 'Step < dispara re-render');
}

# =============================================================================
# Test 8: Fast Fwd avanza N velas (default 10), usa after(), re-render, clamp.
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $mw    = MockMWNoop->new();   # no ejecuta tick: solo verifica after()
    my $rc = $chart->{replay_controller};
    $rc->start(10);
    my $cb = Market::UI::Callbacks->make_replay_fast_fwd($chart, $mw, {});
    $cb->();
    is($rc->current_index(), 20, 'Fast >> avanza 10 velas (10->20)');
    ok($chart->render_count() >= 1, 'Fast >> dispara re-render');

    # Clamp al último índice: start(95) + fast(10) => clamp a 99.
    $rc->start(95);
    $cb->();
    is($rc->current_index(), 99, 'Fast >> clampa al último índice (95+10->99)');
}

# =============================================================================
# Test 9: Exit Replay desactiva el controlador (tope = last) y re-render, y
# sincroniza replay_on=0.
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(100));
    my $replay_on = 1;
    my %vars = ( replay_on => \$replay_on );
    my $rc = $chart->{replay_controller};
    $rc->start(50);
    ok($rc->is_active(), 'replay activo antes de Exit');
    my $cb = Market::UI::Callbacks->make_replay_exit($chart, \%vars);
    $cb->();
    ok(!$rc->is_active(), 'Exit desactiva el controlador');
    is($rc->current_index(), undef, 'Exit deja current_index undef (tope = last)');
    is($replay_on, 0, 'Exit marca replay_on=0');
    ok($chart->render_count() >= 1, 'Exit dispara re-render');
}

# =============================================================================
# Test 10: cada toggle de overlay invoca overlay_manager->set_visible($name,$on)
# sin afectar a los demás overlays (aislamiento).
# =============================================================================
{
    my $mgr   = MockOverlayManager->new();
    my $chart = MockChart->new(overlay_manager => $mgr, market_data => MockMarketData->new(50));

    # SMC off
    my $smc_cb = Market::UI::Callbacks->make_overlay_toggle($chart, 'smc');
    $smc_cb->(0);
    # Liq on
    my $liq_cb = Market::UI::Callbacks->make_overlay_toggle($chart, 'liq');
    $liq_cb->(1);
    # SMC on de nuevo
    $smc_cb->(1);

    is_deeply($mgr->{vis_calls},
              [ ['smc', 0], ['liq', 1], ['smc', 1] ],
              'overlay_manager->set_visible recibe (nombre, bool) en orden');
    is($mgr->{states}{smc}, 1, 'estado final smc = on (no afectado por liq)');
    is($mgr->{states}{liq}, 1, 'estado final liq = on (no afectado por smc)');
    ok($chart->render_count() >= 3, 'cada toggle de overlay dispara re-render');
}

# =============================================================================
# Test 11: cada toggle de elemento de liquidez invoca
# liq_overlay->set_element_visible($elem,$on) para los 7 elementos.
# =============================================================================
{
    my $liq   = MockLiqOverlay->new();
    my $chart = MockChart->new(liq_overlay => $liq, market_data => MockMarketData->new(50));

    my @elems = qw(BSL SSL EQH EQL SWEEP GRAB RUN);
    for my $elem (@elems) {
        my $cb = Market::UI::Callbacks->make_liq_element_toggle($chart, $elem);
        $cb->(1);
    }
    # Desactivar BSL y SWEEP para comprobar aisamiento por elemento.
    Market::UI::Callbacks->make_liq_element_toggle($chart, 'BSL')->(0);
    Market::UI::Callbacks->make_liq_element_toggle($chart, 'SWEEP')->(0);

    my @seen = map { $_->[0] } @{ $liq->{elem_calls} };
    my %uniq; $uniq{$_}++ for @seen;
    for my $elem (@elems) {
        ok(exists $uniq{$elem}, "toggle de elemento $elem llama set_element_visible");
    }
    is($liq->{elem}{BSL},   0, 'BSL desactivado de forma aislada');
    is($liq->{elem}{SWEEP}, 0, 'SWEEP desactivado de forma aislada');
    is($liq->{elem}{SSL},   1, 'SSL no afectado por BSL/SWEEP');
    is($liq->{elem}{RUN},   1, 'RUN no afectado por BSL/SWEEP');
    ok($chart->render_count() >= 1, 'toggle de elemento dispara re-render');
}

# =============================================================================
# Test 12: toggle HTF alterna $htf_enabled y pide re-render (cableado preparado).
# =============================================================================
{
    my $chart = MockChart->new(market_data => MockMarketData->new(50));
    my $htf_enabled = 0;
    my %vars = ( htf_enabled => \$htf_enabled );
    my $cb = Market::UI::Callbacks->make_htf_toggle($chart, \%vars);

    $cb->(1);
    is($htf_enabled, 1, 'HTF on => htf_enabled=1');
    ok($chart->render_count() >= 1, 'HTF on dispara re-render');

    $cb->(0);
    is($htf_enabled, 0, 'HTF off => htf_enabled=0');
}

# =============================================================================
# Test 13: las factorías validan sus argumentos (no crean callbacks sin $chart).
# Protege contra un cableado olvidado en market.pl.
# =============================================================================
{
    eval { Market::UI::Callbacks->make_tf_callback(undef, '1m', {}); };
    like($@, qr'requiere \$chart', 'make_tf_callback sin $chart muere claro')
        or diag("got: $@");
    eval { Market::UI::Callbacks->make_overlay_toggle(MockChart->new(), undef); };
    like($@, qr'requiere \$name', 'make_overlay_toggle sin $name muere claro')
        or diag("got: $@");
    eval { Market::UI::Callbacks->make_replay_play(undef); };
    like($@, qr'requiere \$chart', 'make_replay_play sin $chart muere claro')
        or diag("got: $@");
}

done_testing();
