package Market::UI::Callbacks;
use strict;
use warnings;

# =============================================================================
# Market::UI::Callbacks — factorías de callbacks para la barra de controles de
# Fase 2 (spec 0010 / task 0004).
# =============================================================================
#
# Capa de ACCIONES de UI desacoplada de la construcción de widgets Tk. Cada
# factoría recibe las dependencias ($chart, refs de estado, opcionalmente $mw
# para `after`) y devuelve una subrutina lista para enchufar en el `-command`
# / `-onchange` de un widget Tk (Button, Optionmenu, Checkbutton).
#
# Por qué existe este módulo: los callbacks antes estaban inline en market.pl
# como `-command => sub { ... }` dentro de la construcción de widgets. Como
# `use Tk; MainWindow->new` no es ejecutable headless, ese cableado era
# imposible de testear. Extraer las acciones puras (sin Tk) permite que
# t/17-ui-wiring.t verifique con mocks que:
#   - cada callback de TF invoca $chart->set_timeframe($tf) con el valor correcto
#     para las 8 temporalidades (1m,5m,15m,1h,2h,4h,D,W);
#   - cada botón de Replay invoca el método correcto del ReplayController
#     (start/play/pause/step_forward/step_backward/fast_forward/exit) y
#     dispara re-render;
#   - cada toggle de overlay invoca overlay_manager->set_visible / liq->set_element_visible;
#   - el toggle HTF alterna su estado.
#
# REGLA (task 0004 / CONSTITUTION): aquí NO se reimplementa la lógica de
# Replay (el truncado por replay_idx ya lo hace ChartEngine.sync_overlay_indicators
# vía task 0015). Solo se cablea UI → controlador/motor y se pide re-render.
# Tampoco se toca zoom/drag/crosshair de Fase 1.
#
# DEPENDENCIAS INYECTADAS:
#   $chart  : instancia de Market::ChartEngine. Expone:
#               set_timeframe($tf), request_render(), reset_view(),
#               {replay_controller}, {overlay_manager}, {smc_overlay},
#               {liq_overlay}, {market_data}.
#   $mw     : MainWindow Tk (para `after`). En tests se pasa un mock cuyo
#             `after($ms,$cb)` ejecuta $cb inmediatamente (o lo registra).
#   $vars   : hashref con referencias a variables de estado compartidas:
#               active_tf   => \$active_tf,
#               htf_enabled => \$htf_enabled,
#               replay_on   => \$replay_on   (bool pintado en la UI).
# =============================================================================

# Lista de temporalidades válidas (spec 0001). Orden de visualización en el
# menú desplegable: del más fino al más grueso. Es la fuente de verdad del
# Optionmenu de market.pl, así ni un TF se queda fuera por error.
my @TIMEFRAMES = qw(1m 5m 15m 1h 2h 4h D W);

# Etiquetas legibles para el menú desplegable (TF => texto humano).
my %TF_LABEL = (
    '1m'  => '1m',
    '5m'  => '5m',
    '15m' => '15m',
    '1h'  => '1h',
    '2h'  => '2h',
    '4h'  => '4h',
    'D'   => 'D',
    'W'   => 'W',
);

# timeframes() — retorna la lista de TF válidos (orden de visualización).
# Público para que market.pl construya el Optionmenu y el test verifique las 8.
sub timeframes { return @TIMEFRAMES; }

# tf_label($tf) — etiqueta legible de un TF.
sub tf_label {
    my ($class_or_self, $tf) = @_;
    return $TF_LABEL{$tf};
}

# ----------------------------------------------------------------------------
# Timeframe
# ----------------------------------------------------------------------------

# make_tf_callback($chart, $tf, $vars) — callback para seleccionar un TF.
#   1. Llama a $chart->set_timeframe($tf) (recalcula ATR + overlays, reset vista).
#   2. Sincroniza $vars->{active_tf} con el TF seleccionado (estado del menú).
#   3. set_timeframe ya dispara reset_view → request_render; no duplicamos.
sub make_tf_callback {
    my ($class, $chart, $tf, $vars) = @_;
    die "make_tf_callback: requiere \$chart" unless $chart;
    die "make_tf_callback: requiere \$tf"   unless defined $tf;
    my $ref = ref($vars) eq 'HASH' ? $vars->{active_tf} : undef;
    return sub {
        $chart->set_timeframe($tf);
        ${$ref} = $tf if $ref;
    };
}

# ----------------------------------------------------------------------------
# Replay (spec 0002). 7 controles del PDF.
# IMPORTANTE: NO reimplementamos el truncado; el ReplayController +
# ChartEngine.sync_overlay_indicators (task 0015) ya respetan replay_idx.
# Cada callback mueve el índice y pide re-render.
# ----------------------------------------------------------------------------

# _replay($chart) — acceso al ReplayController a través del ChartEngine.
# Desacopla el callback del nombre interno del atributo.
sub _replay {
    my ($chart) = @_;
    return $chart->{replay_controller};
}

# make_replay_start($chart, $vars) — Inicio Replay.
# Arranca el replay en un índice inicial razonable (visible_bars atrás del
# final para que se vean velas previas al puntero) y pide re-render.
sub make_replay_start {
    my ($class, $chart, $vars) = @_;
    die "make_replay_start: requiere \$chart" unless $chart;
    my $ref = ref($vars) eq 'HASH' ? $vars->{replay_on} : undef;
    return sub {
        my $rc = _replay($chart);
        return unless $rc;
        # Índice inicial = último índice - ventana visible, clamp a >= 0.
        # Así arrancamos viendo N velas antes del puntero de replay.
        my $md = $chart->{market_data};
        my $last = (defined $md && $md->can('size')) ? ($md->size() - 1) : 0;
        my $vis = $chart->{visible_bars} || 60;
        my $start_idx = $last - $vis;
        $start_idx = 0 if $start_idx < 0;
        $rc->start($start_idx);
        ${$ref} = 1 if $ref;
        $chart->request_render();
    };
}

# make_replay_play($chart, $mw, $vars) — Play.
# Inicia reproducción automática: en cada tick, step_forward + re-render.
# El temporizador Tk `after($ms, $cb)` se programa desde el controlador y se
# cancela con pause. Aquí solo pasamos el callback de tick; el controlador
# gestiona el id del timer.
sub make_replay_play {
    my ($class, $chart, $mw, $vars) = @_;
    die "make_replay_play: requiere \$chart" unless $chart;
    return sub {
        my $rc = _replay($chart);
        return unless $rc;
        # Si el replay no está activo, lo arrancamos en el último índice
        # visibilizable para que play tenga efecto desde la UI.
        if (!$rc->is_active()) {
            my $md = $chart->{market_data};
            my $last = (defined $md && $md->can('size')) ? ($md->size() - 1) : 0;
            my $vis = $chart->{visible_bars} || 60;
            my $start_idx = $last - $vis;
            $start_idx = 0 if $start_idx < 0;
            $rc->start($start_idx);
        }
        my $tick = sub {
            my $idx = $rc->step_forward();
            $chart->request_render();
            # Si llegamos al final, paramos la reproducción.
            if (!defined $idx || !$rc->is_active()) {
                $rc->pause();
            }
        };
        # $mw puede ser undef en tests; el controlador también guarda el cb.
        $rc->play($tick);
        # Rescheduler: el controlador guarda el cb pero la pieza Tk que
        # reprograma `after` vive aquí (UI), no en el controlador (lógica).
        _schedule_play($chart, $mw, $tick, $rc);
    };
}

# _schedule_play — programa el siguiente tick con after() sobre $mw si existe.
# Si $mw es undef (test headless), no se reprograma: el test invoca el tick
# manualmente. Esto mantiene la lógica de reloj del lado de la UI, no del modelo.
{
    my %_play_active;  # chart_addr => bool, evita reprogramar tras pause/exit.
    sub _schedule_play {
        my ($chart, $mw, $tick, $rc) = @_;
        return unless $mw;  # sin Tk (test) no hay loop de after
        my $key = "$chart";
        $_play_active{$key} = 1;
        my $interval = 80;  # ms entre velas (fase 2: velocidad demo cómoda)
        $mw->after($interval, sub {
            return unless $_play_active{$key};
            return unless $rc->is_active();
            # playing==0 significa que pause/exit detuvo el loop.
            return unless $rc->{playing};
            $tick->();
            return unless $_play_active{$key} && $rc->{playing};
            _schedule_play($chart, $mw, $tick, $rc);
        });
    }
    sub _stop_play_schedule {
        my ($chart) = @_;
        $_play_active{"$chart"} = 0;
    }
}

# make_replay_pause($chart, $vars) — Pause.
sub make_replay_pause {
    my ($class, $chart, $vars) = @_;
    die "make_replay_pause: requiere \$chart" unless $chart;
    return sub {
        my $rc = _replay($chart);
        return unless $rc;
        $rc->pause();
        _stop_play_schedule($chart);
        $chart->request_render();
    };
}

# make_replay_step_fwd($chart) — Step Forward (avanza 1 vela).
sub make_replay_step_fwd {
    my ($class, $chart) = @_;
    die "make_replay_step_fwd: requiere \$chart" unless $chart;
    return sub {
        my $rc = _replay($chart);
        return unless $rc;
        # Si no hay replay activo, arrancamos en el índice visible actual
        # (mismo criterio que play/start) para que step funcione desde la UI.
        if (!$rc->is_active()) {
            my $md = $chart->{market_data};
            my $last = (defined $md && $md->can('size')) ? ($md->size() - 1) : 0;
            my $vis = $chart->{visible_bars} || 60;
            my $start_idx = $last - $vis;
            $start_idx = 0 if $start_idx < 0;
            $rc->start($start_idx);
        }
        $rc->step_forward();
        $chart->request_render();
    };
}

# make_replay_step_back($chart) — Step Back (retrocede 1 vela).
sub make_replay_step_back {
    my ($class, $chart) = @_;
    die "make_replay_step_back: requiere \$chart" unless $chart;
    return sub {
        my $rc = _replay($chart);
        return unless $rc;
        if (!$rc->is_active()) {
            my $md = $chart->{market_data};
            my $last = (defined $md && $md->can('size')) ? ($md->size() - 1) : 0;
            my $vis = $chart->{visible_bars} || 60;
            my $start_idx = $last - $vis;
            $start_idx = 0 if $start_idx < 0;
            $rc->start($start_idx);
        }
        $rc->step_backward();
        $chart->request_render();
    };
}

# make_replay_fast_fwd($chart, $mw, $vars) — Fast Forward.
# Avanza N velas por tick (default 10) y re-render. Usa after() igual que play
# pero con step mayor. $n opcional para tests/velocidades.
sub make_replay_fast_fwd {
    my ($class, $chart, $mw, $vars, $n) = @_;
    die "make_replay_fast_fwd: requiere \$chart" unless $chart;
    $n //= 10;
    return sub {
        my $rc = _replay($chart);
        return unless $rc;
        if (!$rc->is_active()) {
            my $md = $chart->{market_data};
            my $last = (defined $md && $md->can('size')) ? ($md->size() - 1) : 0;
            my $vis = $chart->{visible_bars} || 60;
            my $start_idx = $last - $vis;
            $start_idx = 0 if $start_idx < 0;
            $rc->start($start_idx);
        }
        $rc->fast_forward($n);
        $chart->request_render();
    };
}

# make_replay_exit($chart, $vars) — Exit Replay.
# Desactiva replay (tope vuelve a last_index) y re-render. Sincroniza estado.
sub make_replay_exit {
    my ($class, $chart, $vars) = @_;
    die "make_replay_exit: requiere \$chart" unless $chart;
    my $ref = ref($vars) eq 'HASH' ? $vars->{replay_on} : undef;
    return sub {
        my $rc = _replay($chart);
        return unless $rc;
        $rc->exit();
        _stop_play_schedule($chart);
        ${$ref} = 0 if $ref;
        $chart->request_render();
    };
}

# ----------------------------------------------------------------------------
# Overlays / Capas (spec 0003 / task 0003).
# Cada toggle llama al OverlayManager o al overlay de liquidez. NO toca la
# lógica del overlay; solo cambia visibilidad y pide re-render.
# ----------------------------------------------------------------------------

# make_overlay_toggle($chart, $name) — toggle de un overlay completo por nombre
# de registro ('smc' o 'liq'). Recibe un bool ($on) desde el Checkbutton Tk
# (vinculado a su -variable). El overlay ya filtra el dibujo por index <= end,
# así que el replay_idx se respeta sin acción extra aquí.
sub make_overlay_toggle {
    my ($class, $chart, $name) = @_;
    die "make_overlay_toggle: requiere \$chart" unless $chart;
    die "make_overlay_toggle: requiere \$name"  unless defined $name;
    return sub {
        my ($on) = @_;
        my $mgr = $chart->{overlay_manager};
        return unless $mgr;
        $mgr->set_visible($name, $on ? 1 : 0);
        $chart->request_render();
    };
}

# make_liq_element_toggle($chart, $element) — toggle de una familia concreta de
# liquidez (BSL/SSL/EQH/EQL/SWEEP/GRAB/RUN) vía set_element_visible del overlay.
# La visibilidad general del overlay ov_liq se controla aparte (make_overlay_toggle).
sub make_liq_element_toggle {
    my ($class, $chart, $element) = @_;
    die "make_liq_element_toggle: requiere \$chart"   unless $chart;
    die "make_liq_element_toggle: requiere \$element" unless defined $element;
    return sub {
        my ($on) = @_;
        my $liq = $chart->{liq_overlay};
        return unless $liq && $liq->can('set_element_visible');
        $liq->set_element_visible($element, $on ? 1 : 0);
        $chart->request_render();
    };
}

# ----------------------------------------------------------------------------
# HTF sobre LTF (spec 0010 §4). Toggle preparado: alterna una bandera de estado
# ($vars->{htf_enabled}). La proyección de niveles de mayor temporalidad aún no
# está implementada (tarea futura); aquí dejamos el cableado de UI listo para
# que cuando exista solo haya que leer ese estado.
# ----------------------------------------------------------------------------

sub make_htf_toggle {
    my ($class, $chart, $vars) = @_;
    die "make_htf_toggle: requiere \$chart" unless $chart;
    my $ref = ref($vars) eq 'HASH' ? $vars->{htf_enabled} : undef;
    return sub {
        my ($on) = @_;
        ${$ref} = $on ? 1 : 0 if $ref;
        # No hay proyección HTF todavía; cuando exista, aquí se pedirá
        # recálculo. Por ahora solo re-render para reflejar el cambio de
        # estado en cualquier overlay futuro que lo consuma.
        $chart->request_render();
    };
}

1;
