#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use Tk;

use lib '.';
use Market::MarketData;
use Market::IndicatorManager;
use Market::Indicators::ATR;
use Market::ChartEngine;
use Market::UI::Callbacks;   # factorías de callbacks de la barra (TF/Replay/Overlays)

print "========== LAUNCHING FINANCIAL CHARTING ENGINE (Tk) ==========\n";

# ==========================================
# 1. DATOS E INDICADORES BASE (solo lo de Fase 1 para arranque instantáneo)
# ==========================================
# task 0018 (F3): el arranque solo precomputa lo imprescindible para pintar como
# en Fase 1 (velas + ATR). SMC/Liquidity se alimentan BAJO DEMANDA dentro de
# ChartEngine cuando el usuario activa su capa; aquí NO se registran ni se
# alimentan (antes había un SMC extra que duplicaba el cómputo sobre 29888 velas).
my $market_data = Market::MarketData->new();
my $indicator_manager = Market::IndicatorManager->new();
$indicator_manager->register('ATR', Market::Indicators::ATR->new(14));

my $archivo_csv = 'Data/2026_03.csv';
print "[*] Leyendo base de datos histórica...\n";
open my $fh, '<', $archivo_csv or die "CRÍTICO: No se pudo abrir $archivo_csv: $!";
my $header = <$fh>;
while (my $linea = <$fh>) {
    chomp $linea;
    my @columnas = split /,/, $linea;
    $market_data->add_candle(\@columnas);
}
close $fh;

print "[*] Construyendo temporalidades...\n";
$market_data->build_timeframes();
$market_data->set_timeframe('1m');
for (my $i = 0; $i < $market_data->size(); $i++) {
    $indicator_manager->update_last($market_data, $i);   # ATR es O(1)/vela
}

# ==========================================
# 2. VENTANA PRINCIPAL
# ==========================================
my $mw = MainWindow->new;
$mw->title("Plataforma de Gráficos Financieros - Motor de Charting Tk");
$mw->minsize(900, 600);

my $sw = eval { $mw->screenwidth }  || 1280;
my $sh = eval { $mw->screenheight } || 800;
my $screen_ok = ($sw >= 800 && $sw <= 10000 && $sh >= 600 && $sh <= 10000);
if ($screen_ok) {
    my $usable_w = $sw - 16;  my $usable_h = $sh - 96;
    $usable_w = 1280 if $usable_w < 1280;
    $usable_h = 720  if $usable_h < 720;
    $mw->geometry("${usable_w}x${usable_h}+0+0");
} else {
    $mw->geometry('1280x720+50+50');
}
$mw->deiconify; $mw->raise; $mw->focusForce;

# ==========================================
# PALETA DE TEMA CLARO
# ==========================================
my %theme = (
    bg => '#ffffff', grid => '#e6e6e6', date_grid => '#c4c9d1',
    axis_text => '#363a45', bull => '#26a69a', bear => '#ef5350',
    atr_line => '#2962ff', crosshair_line => '#9598a1',
    label_bg => '#363a45', label_fg => '#ffffff',
    last_price_bg => '#363a45', last_price_fg => '#ffffff',
);

my $time_axis_height = 18;
my $right_axis_width = 60;
my $atr_axis_width   = 48;

# ==========================================
# 3. LAYOUT: barra compacta abajo, chart arriba
# ==========================================
my $frame_controles = $mw->Frame(-relief => 'raised', -bd => 1)
    ->pack(-side => 'bottom', -fill => 'x');

my $chart_frame = $mw->Frame(-background => $theme{bg})->pack(-side => 'top', -expand => 1, -fill => 'both');

my $price_frame = $chart_frame->Frame(-background => $theme{bg})->pack(-side => 'top', -expand => 1, -fill => 'both');
my $price_axis_canvas = $price_frame->Canvas(
    -width => $right_axis_width, -background => $theme{bg},
    -relief => 'sunken', -bd => 1, -cursor => 'sb_v_double_arrow'
)->pack(-side => 'right', -fill => 'y');
my $price_canvas = $price_frame->Canvas(
    -background => $theme{bg}, -relief => 'sunken', -bd => 1, -cursor => 'crosshair'
)->pack(-side => 'left', -expand => 1, -fill => 'both');

my $time_frame = $chart_frame->Frame(-background => $theme{bg})->pack(-side => 'top', -fill => 'x');
$time_frame->Canvas(
    -width => $right_axis_width, -height => $time_axis_height, -background => $theme{bg},
    -relief => 'sunken', -bd => 1, -highlightthickness => 0
)->pack(-side => 'right', -fill => 'y');
my $time_axis_canvas = $time_frame->Canvas(
    -height => $time_axis_height, -background => $theme{bg}, -relief => 'sunken',
    -bd => 1, -highlightthickness => 0, -cursor => 'sb_h_double_arrow'
)->pack(-side => 'left', -expand => 1, -fill => 'x');

my $atr_frame = $chart_frame->Frame(-background => $theme{bg})->pack(-side => 'top', -fill => 'x');
my $atr_axis_canvas = $atr_frame->Canvas(
    -width => $atr_axis_width, -height => 140, -background => $theme{bg}, -relief => 'sunken', -bd => 1
)->pack(-side => 'right', -fill => 'y');
$atr_frame->Frame(
    -width => $right_axis_width - $atr_axis_width, -height => 140, -background => $theme{bg},
)->pack(-side => 'right', -fill => 'y');
my $atr_canvas = $atr_frame->Canvas(
    -height => 140, -background => $theme{bg}, -relief => 'sunken', -bd => 1, -cursor => 'crosshair'
)->pack(-side => 'left', -expand => 1, -fill => 'x');

# ==========================================
# 4. MOTOR ORQUESTADOR
# ==========================================
my $scale_mode = 'auto';
my $atr_scale_mode = 'auto';
my $active_tf = '1m';
my $htf_enabled = 0;
my $replay_on   = 0;
my %ui_vars = (
    active_tf => \$active_tf, htf_enabled => \$htf_enabled, replay_on => \$replay_on,
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

# Estado de visibilidad de capas (overlays OFF por defecto — task 0018 F4).
my $vis_smc = 0;
my $vis_liq = 0;
my %vis_elem = map { $_ => 1 } qw(BSL SSL EQH EQL SWEEP GRAB RUN);

# Callbacks (factorías testeadas headless). F1: SIEMPRE pasamos el valor de la
# -variable explícito al callback (Tk no lo pasa solo en -command).
my $cb_smc = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'smc');
my $cb_liq = Market::UI::Callbacks->make_overlay_toggle($chart_engine, 'liq');
my %cb_elem = map { $_ => Market::UI::Callbacks->make_liq_element_toggle($chart_engine, $_) }
              qw(BSL SSL EQH EQL SWEEP GRAB RUN);
my $cb_htf = Market::UI::Callbacks->make_htf_toggle($chart_engine, \%ui_vars);
my %tf_cb  = map { $_ => Market::UI::Callbacks->make_tf_callback($chart_engine, $_, \%ui_vars) }
             Market::UI::Callbacks->timeframes();

# ============================================================================
# 5. BARRA DE CONTROLES INLINE (todo en la MISMA ventana) — task 0018b
# ============================================================================
# IMPORTANTE: NO se usa menubar nativo ($mw->Menu/-menu) ni Optionmenu. Bajo
# WSLg ambos abren ventanas X separadas (popups), que aparecen en posiciones
# erráticas, se traban o no cargan. Todos los controles van inline con widgets
# que NO crean ventanas: Radiobutton, Checkbutton, Button. La barra se organiza
# en dos filas para no saturar.
my $row1 = $frame_controles->Frame()->pack(-side => 'top', -fill => 'x', -pady => 1);
my $row2 = $frame_controles->Frame()->pack(-side => 'top', -fill => 'x', -pady => 1);

# --- Fila 1: Temporalidad (8 radiobuttons, sin popup) ---
my $tf_box = $row1->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
$tf_box->Label(-text => 'TF:')->pack(-side => 'left', -padx => 3);
for my $tf (Market::UI::Callbacks->timeframes()) {
    $tf_box->Radiobutton(
        -text => Market::UI::Callbacks->tf_label($tf),
        -value => $tf, -variable => \$active_tf,
        -indicatoron => 0, -padx => 4, -pady => 1,
        -command => sub { $tf_cb{$tf}->(); },
    )->pack(-side => 'left', -padx => 1);
}

# --- Fila 1: Capas (SMC / Liquidez completas) ---
my $cap_box = $row1->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
$cap_box->Label(-text => 'Capas:')->pack(-side => 'left', -padx => 3);
$cap_box->Checkbutton(-text => 'SMC', -variable => \$vis_smc,
    -command => sub { $cb_smc->($vis_smc ? 1 : 0); })->pack(-side => 'left');
$cap_box->Checkbutton(-text => 'Liquidez', -variable => \$vis_liq,
    -command => sub { $cb_liq->($vis_liq ? 1 : 0); })->pack(-side => 'left');

# --- Fila 1: Elementos de liquidez (sub-filtros) ---
my $elem_box = $row1->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
$elem_box->Label(-text => 'Liq:')->pack(-side => 'left', -padx => 3);
for my $elem (qw(BSL SSL EQH EQL SWEEP GRAB RUN)) {
    $elem_box->Checkbutton(-text => $elem, -variable => \$vis_elem{$elem},
        -command => sub { $cb_elem{$elem}->($vis_elem{$elem} ? 1 : 0); })->pack(-side => 'left');
}

# --- Fila 1: HTF ---
$row1->Checkbutton(-text => 'HTF sobre LTF', -variable => \$htf_enabled,
    -command => sub { $cb_htf->($htf_enabled ? 1 : 0); })->pack(-side => 'left', -padx => 6);

# --- Fila 2: Precio Auto/Manual ---
my $price_box = $row2->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
$price_box->Label(-text => 'Precio:')->pack(-side => 'left', -padx => 3);
$price_box->Radiobutton(-text => 'Auto', -value => 'auto', -variable => \$scale_mode,
    -indicatoron => 0, -padx => 5, -command => sub { $chart_engine->set_scale_mode('auto') })->pack(-side => 'left', -padx => 1);
$price_box->Radiobutton(-text => 'Manual', -value => 'manual', -variable => \$scale_mode,
    -indicatoron => 0, -padx => 5, -command => sub { $chart_engine->set_scale_mode('manual') })->pack(-side => 'left', -padx => 1);

# --- Fila 2: ATR Auto/Manual ---
my $atr_box = $row2->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
$atr_box->Label(-text => 'ATR:')->pack(-side => 'left', -padx => 3);
$atr_box->Radiobutton(-text => 'Auto', -value => 'auto', -variable => \$atr_scale_mode,
    -indicatoron => 0, -padx => 5, -command => sub { $chart_engine->set_atr_scale_mode('auto') })->pack(-side => 'left', -padx => 1);
$atr_box->Radiobutton(-text => 'Manual', -value => 'manual', -variable => \$atr_scale_mode,
    -indicatoron => 0, -padx => 5, -command => sub { $chart_engine->set_atr_scale_mode('manual') })->pack(-side => 'left', -padx => 1);

# --- Fila 2: Reset Vista (siempre accesible — F5) ---
$row2->Button(-text => 'Reset Vista', -command => sub { $chart_engine->reset_view() })
    ->pack(-side => 'left', -padx => 10);

# --- Fila 2: Replay (7 controles, sin popup) + estado ---
my $rep_box = $row2->Frame(-relief => 'groove', -bd => 2)->pack(-side => 'left', -padx => 4);
$rep_box->Label(-text => 'Replay:')->pack(-side => 'left', -padx => 3);
my %rep_btn = (
    'Inicio' => Market::UI::Callbacks->make_replay_start($chart_engine, \%ui_vars),
    'Play'   => Market::UI::Callbacks->make_replay_play($chart_engine, $mw, \%ui_vars),
    'Pause'  => Market::UI::Callbacks->make_replay_pause($chart_engine, \%ui_vars),
    '>'      => Market::UI::Callbacks->make_replay_step_fwd($chart_engine),
    '<'      => Market::UI::Callbacks->make_replay_step_back($chart_engine),
    '>>'     => Market::UI::Callbacks->make_replay_fast_fwd($chart_engine, $mw, \%ui_vars),
    'Salir'  => Market::UI::Callbacks->make_replay_exit($chart_engine, \%ui_vars),
);
for my $lbl ('Inicio', 'Play', 'Pause', '<', '>', '>>', 'Salir') {
    $rep_box->Button(-text => $lbl, -command => $rep_btn{$lbl}, -padx => 3)
        ->pack(-side => 'left', -padx => 1);
}

# ==========================================
# 7. RENDER INICIAL + LOOP
# ==========================================
print "[*] Abriendo ventana...\n";
$mw->update;
my $maximized = eval { $mw->state('zoomed'); 1 };
$maximized ||= eval { $mw->attributes('-zoomed', 1); 1 };
$mw->update if $maximized;
$mw->after(200, sub {
    print "[*] Render inicial (Fase 1: velas + ATR; capas bajo demanda)...\n";
    $chart_engine->render();
    $mw->after(200,  sub { $chart_engine->request_render(); });
    $mw->after(800,  sub { $chart_engine->request_render(); });
});

MainLoop;
