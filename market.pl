#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Tk;

use lib '.';
use Market::MarketData;
use Market::IndicatorManager;
use Market::Indicators::ATR;
use Market::Indicators::SMC_Structures;
use Market::ChartEngine;
use Market::UI::Callbacks;   # task 0004: factorías de callbacks de la barra (TF/Replay/Overlays)

print "========== LAUNCHING FINANCIAL CHARTING ENGINE (Tk) ==========\n";
print "[*] Build visual: WSLg geometry sync fix v2\n";

# ==========================================
# 1. INICIALIZAR GESTOR DE DATOS E INDICADORES
# ==========================================
my $market_data = Market::MarketData->new();
my $indicator_manager = Market::IndicatorManager->new();
my $atr_indicator = Market::Indicators::ATR->new(14); # ATR de 14 periodos clásico

$indicator_manager->register('ATR', $atr_indicator);
$indicator_manager->register('SMC', Market::Indicators::SMC_Structures->new(k => 3));

# ==========================================
# 2. CARGAR HISTÓRICO Y SIMULAR STREAMING PARA ATR
# ==========================================
my $archivo_csv = 'Data/2026_03.csv';
print "[*] Leyendo base de datos histórica y calculando indicadores...\n";
open my $fh, '<', $archivo_csv or die "CRÍTICO: No se pudo abrir $archivo_csv: $!";
my $header = <$fh>;

while (my $linea = <$fh>) {
    chomp $linea;
    my @columnas = split /,/, $linea;
    
    # Añadimos la vela al gestor de datos
    $market_data->add_candle(\@columnas);
    
}
close $fh;

print "[*] Construyendo temporalidades de 5m y 15m...\n";
$market_data->build_timeframes();
$market_data->set_timeframe('1m');
for (my $i = 0; $i < $market_data->size(); $i++) {
    $indicator_manager->update_last($market_data, $i);
}

# ==========================================
# 3. CONSTRUCCIÓN DE LA INTERFAZ GRÁFICA (PERL-TK)
# ==========================================
my $mw = MainWindow->new;
$mw->title("Plataforma de Gráficos Financieros - Motor de Charting Tk");

# Tamaño mínimo de la ventana principal.
$mw->minsize(800, 600);

# Geometría inicial de respaldo. Más abajo se pide maximizar la ventana al gestor
# de ventanas para abrirla como ventana completa, sin cambiar el layout interno.
my $sw = eval { $mw->screenwidth }  || 1280;
my $sh = eval { $mw->screenheight } || 800;
my $screen_ok = ($sw >= 800 && $sw <= 10000 && $sh >= 600 && $sh <= 10000);

if ($screen_ok) {
    my $usable_w = $sw - 16;
    my $usable_h = $sh - 96;
    $usable_w = 1280 if $usable_w < 1280;
    $usable_h = 720  if $usable_h < 720;
    $mw->geometry("${usable_w}x${usable_h}+0+0");
} else {
    warn "[!] Tk reportó pantalla inválida (${sw}x${sh}); usando geometría segura.\n";
    $mw->geometry('1280x720+50+50');
}

$mw->deiconify;
$mw->raise;
$mw->focusForce;

# ==========================================
# PALETA DE TEMA CLARO (hash léxico, NO global de paquete)
# Inyectada a ChartEngine y transportada a los paneles/escalas.
# ==========================================
my %theme = (
    bg             => '#ffffff',
    grid           => '#e6e6e6',
    date_grid      => '#c4c9d1',
    axis_text      => '#363a45',
    bull           => '#26a69a',
    bear           => '#ef5350',
    atr_line       => '#2962ff',
    crosshair_line => '#9598a1',
    label_bg       => '#363a45',
    label_fg       => '#ffffff',
    last_price_bg  => '#363a45',
    last_price_fg  => '#ffffff',
);

my $time_axis_height = 18;
my $right_axis_width = 60;
my $atr_axis_width   = 48;

# ORDEN CORRECTO: controles fijos abajo; zona de chart arriba.

# 1. Controles (siempre visibles al fondo).
# La barra se divide en cajas con relief => 'groove' (mismo estilo que Fase 1)
# para agrupar y no saturar: Timeframe | Overlays | HTF | (spacer) | Replay | Reset | Escalas.
my $frame_controles = $mw->Frame()->pack(-side => 'bottom', -fill => 'x', -pady => 2);

# 2. Contenedor del chart: precio, eje temporal y ATR.
my $chart_frame = $mw->Frame(-background => $theme{bg})->pack(-side => 'top', -expand => 1, -fill => 'both');

# 3. Panel superior de Velas con eje de precios independiente a la derecha.
my $price_frame = $chart_frame->Frame(-background => $theme{bg})->pack(-side => 'top', -expand => 1, -fill => 'both');
my $price_axis_canvas = $price_frame->Canvas(
    -width      => $right_axis_width,
    -background => $theme{bg},
    -relief     => 'sunken',
    -bd         => 1,
    -cursor     => 'sb_v_double_arrow'
)->pack(-side => 'right', -fill => 'y');
my $price_canvas = $price_frame->Canvas(
    -background => $theme{bg},
    -relief     => 'sunken',
    -bd         => 1,
    -cursor     => 'crosshair'
)->pack(-side => 'left', -expand => 1, -fill => 'both');

# 4. Eje temporal independiente, inmediatamente debajo del gráfico principal.
my $time_frame = $chart_frame->Frame(-background => $theme{bg})->pack(-side => 'top', -fill => 'x');
$time_frame->Canvas(
    -width      => $right_axis_width,
    -height     => $time_axis_height,
    -background => $theme{bg},
    -relief     => 'sunken',
    -bd         => 1,
    -highlightthickness => 0
)->pack(-side => 'right', -fill => 'y');
my $time_axis_canvas = $time_frame->Canvas(
    -height     => $time_axis_height,
    -background => $theme{bg},
    -relief     => 'sunken',
    -bd         => 1,
    -highlightthickness => 0,
    -cursor     => 'sb_h_double_arrow'
)->pack(-side => 'left', -expand => 1, -fill => 'x');

# 5. Panel inferior ATR debajo del eje temporal, con eje derecho alineado.
my $atr_frame = $chart_frame->Frame(-background => $theme{bg})->pack(-side => 'top', -fill => 'x');
my $atr_axis_canvas = $atr_frame->Canvas(
    -width      => $atr_axis_width,
    -height     => 140,
    -background => $theme{bg},
    -relief     => 'sunken',
    -bd         => 1
)->pack(-side => 'right', -fill => 'y');
$atr_frame->Frame(
    -width      => $right_axis_width - $atr_axis_width,
    -height     => 140,
    -background => $theme{bg},
)->pack(-side => 'right', -fill => 'y');
my $atr_canvas = $atr_frame->Canvas(
    -height     => 140,
    -background => $theme{bg},
    -relief     => 'sunken',
    -bd         => 1,
    -cursor     => 'crosshair'
)->pack(-side => 'left', -expand => 1, -fill => 'x');

# ==========================================
# 4. INSTANCIAR EL MOTOR ORQUESTADOR (CHART ENGINE)
# ==========================================
my $scale_mode = 'auto';
my $atr_scale_mode = 'auto';
my $active_tf = '1m';
# task 0004: estado de UI compartido con los callbacks de la barra (Callbacks.pm).
# Referencias para que las factorías puedan leer/escribir el estado del menú.
my $htf_enabled = 0;   # toggle "Niveles HTF sobre LTF" (preparado; proyección futura)
my $replay_on   = 0;   # refleja si el modo Replay está activo (pintado en la UI)
my %ui_vars = (
    active_tf   => \$active_tf,
    htf_enabled => \$htf_enabled,
    replay_on   => \$replay_on,
);

my $chart_engine = Market::ChartEngine->new(
    market_data       => $market_data,
    indicator_manager => $indicator_manager,
    price_canvas      => $price_canvas,
    price_axis_canvas => $price_axis_canvas,
    atr_canvas        => $atr_canvas,
    atr_axis_canvas   => $atr_axis_canvas,
    time_axis_canvas  => $time_axis_canvas,
    scale_mode_callback => sub { $scale_mode = $_[0] },
    atr_scale_mode_callback => sub { $atr_scale_mode = $_[0] },
    theme             => \%theme
);

$mw->Tk::bind('<Configure>', sub { $chart_engine->request_render(); });

# ============================================================================
# BARRA DE CONTROLES — Fase 2 (task 0004).
# Reemplaza los Radiobutton de TF por un menú desplegable (Optionmenu) con las
# 8 temporalidades (spec 0001) y añade las cajas de Replay, Overlays y HTF.
# Cada acción se construye con factorías de Market::UI::Callbacks (testeadas
# headless con mocks); aquí solo se construyen widgets y se enchufan.
# ============================================================================

# --- Caja 1: TIMEFRAME (menú desplegable, reemplaza los Radiobutton) ---------
my $tf_controls = $frame_controles->Frame(-relief => 'groove', -bd => 2)
    ->pack(-side => 'left', -padx => 6, -pady => 2);
$tf_controls->Label(-text => "TF:")->pack(-side => 'left', -padx => 4);
# Las 8 temporalidades vienen del módulo (fuente de verdad); el Optionmenu las
# lista en orden. Al cambiar llama al callback de TF, que invoca set_timeframe.
my @tf_list = Market::UI::Callbacks->timeframes();
my @tf_options = map { Market::UI::Callbacks->tf_label($_) } @tf_list;
# Optionmenu enlaza su -textvariable a $active_tf y, al seleccionar, llama al
# -command con la etiqueta elegida. Mapeamos etiqueta -> TF y delegamos al
# callback de cada TF (uno por TF para que el test pueda verificar los 8).
my %label_to_tf = map { Market::UI::Callbacks->tf_label($_) => $_ } @tf_list;
my %tf_cb = map { $_ => Market::UI::Callbacks->make_tf_callback($chart_engine, $_, \%ui_vars) } @tf_list;
$tf_controls->Optionmenu(
    -options    => [ map { [ $_ => $_ ] } @tf_options ],  # [label, value]
    -textvariable => \$active_tf,
    -command    => sub {
        my ($label) = @_;
        my $tf = $label_to_tf{$label} || $label;
        my $cb = $tf_cb{$tf} or return;
        $cb->();
    },
)->pack(-side => 'left', -padx => 2);
# Sincroniza el texto del Optionmenu con el TF activo inicial.
$active_tf = Market::UI::Callbacks->tf_label('1m');


my $price_scale_controls = $frame_controles->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 14, -pady => 2);
$price_scale_controls->Label(-text => "Precio: ")->pack(-side => 'left', -padx => 6);
$price_scale_controls->Radiobutton(
    -text     => 'Auto',
    -value    => 'auto',
    -variable => \$scale_mode,
    -command  => sub { $chart_engine->set_scale_mode('auto') },
)->pack(-side => 'left', -padx => 2);
$price_scale_controls->Radiobutton(
    -text     => 'Manual',
    -value    => 'manual',
    -variable => \$scale_mode,
    -command  => sub { $chart_engine->set_scale_mode('manual') },
)->pack(-side => 'left', -padx => 2);

# ============================================================================
# Caja 2: OVERLAYS / CAPAS (spec 0010 §3). Toggles individuales por overlay.
# SMC (ov_smc) y Liquidez (ov_liq) son conmutadores completos. La liquidez
# además expone toggles por elemento (BSL/SSL/EQH/EQL/SWEEP/GRAB/RUN) vía
# set_element_visible. Strategy/Volume/VWAP quedan como placeholders
# deshabilitados hasta que existan sus overlays (specs futuras).
# Cada toggle usa un estado local (Checkbutton con -variable propia) y llama
# a la factoría correspondiente, que solo cambia visibilidad + pide re-render.
# ============================================================================
my $ov_controls = $frame_controles->Frame(-relief => 'groove', -bd => 2)
    ->pack(-side => 'left', -padx => 6, -pady => 2);
$ov_controls->Label(-text => "Capas:")->pack(-side => 'left', -padx => 4);

# Estado de cada toggle (1 = visible). Empiezan visibles para SMC y Liq porque
# los overlays nacen visibles por defecto (Overlays/*.pm: visible => 1).
my $vis_smc = 1;
my $vis_liq = 1;
my %vis_elem = map { $_ => 1 } qw(BSL SSL EQH EQL SWEEP GRAB RUN);

# SMC completo (BOS/CHoCH/FVG/Fib/Major).
$ov_controls->Checkbutton(
    -text     => 'SMC',
    -variable => \$vis_smc,
    -command  => Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'smc'),
)->pack(-side => 'left', -padx => 2);

# Liquidez completo (BSL/SSL/EQH/EQL/SWEEP/GRAB/RUN).
$ov_controls->Checkbutton(
    -text     => 'Liquidez',
    -variable => \$vis_liq,
    -command  => Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'liq'),
)->pack(-side => 'left', -padx => 2);

# Sub-fila de elementos de liquidez en un frame propio para no saturar.
my $liq_elem_frame = $ov_controls->Frame()->pack(-side => 'left', -padx => 2);
for my $elem (qw(BSL SSL EQH EQL SWEEP GRAB RUN)) {
    $liq_elem_frame->Checkbutton(
        -text     => $elem,
        -variable => \$vis_elem{$elem},
        -command  => Market::UI::Callbacks->make_liq_element_toggle($chart_engine, $elem),
    )->pack(-side => 'left', -padx => 1);
}

# Placeholders deshabilitados (overlays aún no existen). Quedan visibles pero
# inactivos para mostrar la hoja de ruta de Fase 2 sin romper la barra.
$ov_controls->Checkbutton(-text => 'Strategy', -state => 'disabled')->pack(-side => 'left', -padx => 2);
$ov_controls->Checkbutton(-text => 'Volume',   -state => 'disabled')->pack(-side => 'left', -padx => 2);
$ov_controls->Checkbutton(-text => 'VWAP',     -state => 'disabled')->pack(-side => 'left', -padx => 2);

# ============================================================================
# Caja 3: HTF sobre LTF (spec 0010 §4). Toggle preparado: la proyección de
# niveles de mayor temporalidad no existe aún; aquí dejamos el cableado de UI
# para que cuando se implemente solo haya que leer \$htf_enabled.
# ============================================================================
my $htf_controls = $frame_controles->Frame(-relief => 'groove', -bd => 2)
    ->pack(-side => 'left', -padx => 6, -pady => 2);
$htf_controls->Checkbutton(
    -text     => 'Niveles HTF sobre LTF',
    -variable => \$htf_enabled,
    -command  => Market::UI::Callbacks->make_htf_toggle($chart_engine, \%ui_vars),
)->pack(-side => 'left', -padx => 4);

# ============================================================================
# Caja 4: REPLAY (spec 0002, 7 controles del PDF). Cablea cada botón al
# ReplayController (task 0002/0015) y pide re-render. Play usa after() para
# reproducir automáticamente; el resto son acciones puntuales.
# IMPORTANTE: NO reimplementamos el truncado por replay_idx; eso ya lo hace
# ChartEngine.sync_overlay_indicators (task 0015). Aquí solo movemos el índice
# y re-renderizamos.
# La caja Replay va al extremo derecho (junto a Reset/Escalas ATR) por ser
# un bloque de acción secundario respecto a TF/Overlays.
# ============================================================================
my $replay_controls = $frame_controles->Frame(-relief => 'groove', -bd => 2)
    ->pack(-side => 'right', -padx => 6, -pady => 2);
$replay_controls->Label(-text => "Replay:")->pack(-side => 'left', -padx => 4);
$replay_controls->Button(
    -text    => 'Inicio',
    -command => Market::UI::Callbacks->make_replay_start($chart_engine, \%ui_vars),
)->pack(-side => 'left', -padx => 1);
$replay_controls->Button(
    -text    => 'Play',
    -command => Market::UI::Callbacks->make_replay_play($chart_engine, $mw, \%ui_vars),
)->pack(-side => 'left', -padx => 1);
$replay_controls->Button(
    -text    => 'Pause',
    -command => Market::UI::Callbacks->make_replay_pause($chart_engine, \%ui_vars),
)->pack(-side => 'left', -padx => 1);
$replay_controls->Button(
    -text    => 'Step >',
    -command => Market::UI::Callbacks->make_replay_step_fwd($chart_engine),
)->pack(-side => 'left', -padx => 1);
$replay_controls->Button(
    -text    => 'Step <',
    -command => Market::UI::Callbacks->make_replay_step_back($chart_engine),
)->pack(-side => 'left', -padx => 1);
$replay_controls->Button(
    -text    => 'Fast >>',
    -command => Market::UI::Callbacks->make_replay_fast_fwd($chart_engine, $mw, \%ui_vars),
)->pack(-side => 'left', -padx => 1);
$replay_controls->Button(
    -text    => 'Exit',
    -command => Market::UI::Callbacks->make_replay_exit($chart_engine, \%ui_vars),
)->pack(-side => 'left', -padx => 1);

my $atr_scale_controls = $frame_controles->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'right', -padx => 14, -pady => 2);
$frame_controles->Button(-text => "Reset Vista", -command => sub { $chart_engine->reset_view() })->pack(-side => 'right', -padx => 20);
$atr_scale_controls->Label(-text => "ATR: ")->pack(-side => 'left', -padx => 6);
$atr_scale_controls->Radiobutton(
    -text     => 'Auto',
    -value    => 'auto',
    -variable => \$atr_scale_mode,
    -command  => sub { $chart_engine->set_atr_scale_mode('auto') },
)->pack(-side => 'left', -padx => 2);
$atr_scale_controls->Radiobutton(
    -text     => 'Manual',
    -value    => 'manual',
    -variable => \$atr_scale_mode,
    -command  => sub { $chart_engine->set_atr_scale_mode('manual') },
)->pack(-side => 'left', -padx => 2);



# ==========================================
# 5. DISPARAR RENDER Y LOOP GRÁFICO (CON ESTABILIDAD PARA WAYLAND)
# ==========================================
print "[*] Abriendo ventana nativa y delegando control a Tk...\n";

# Le damos a Tk tiempo para mapear la ventana y calcular geometrías reales antes
# del primer render. En WSLg, renderizar demasiado pronto puede dejar escalas viejas.
$mw->update;
my $maximized = eval { $mw->state('zoomed'); 1 };
$maximized ||= eval { $mw->attributes('-zoomed', 1); 1 };
$mw->update if $maximized;
$mw->after(300, sub {
    print "[*] Ejecutando renderizado inicial en los Canvas...\n";
    $chart_engine->render();
    $mw->after(200, sub { $chart_engine->request_render(); });
    $mw->after(800, sub { $chart_engine->request_render(); });
    $mw->after(1500, sub { $chart_engine->request_render(); });
});

# Entregamos el control absoluto sin forzar updates previos
MainLoop;
