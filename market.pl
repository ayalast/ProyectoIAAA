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

print "========== LAUNCHING FINANCIAL CHARTING ENGINE (Tk) ==========\n";
print "[*] Build visual: WSLg geometry sync fix v2\n";

# ==========================================
# 1. INICIALIZAR GESTOR DE DATOS E INDICADORES
# ==========================================
my $market_data = Market::MarketData->new();
my $indicator_manager = Market::IndicatorManager->new();
my $atr_indicator = Market::Indicators::ATR->new(14); # ATR de 14 periodos clásico

$indicator_manager->register('ATR', $atr_indicator);

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

# 1. Controles (siempre visibles al fondo)
my $frame_controles = $mw->Frame()->pack(-side => 'bottom', -fill => 'x', -pady => 2);
$frame_controles->Label(-text => "Temporalidades: ")->pack(-side => 'left', -padx => 10);

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

# Conectar botones al motor usando los sufijos 'm' para coincidir con MarketData.pm

$frame_controles->Radiobutton(
    -text     => "1 Minuto",
    -value    => '1m',
    -variable => \$active_tf,
    -indicatoron => 0,
    -command  => sub { $chart_engine->set_timeframe('1m') },
)->pack(-side => 'left', -padx => 2);
$frame_controles->Radiobutton(
    -text     => "5 Minutos",
    -value    => '5m',
    -variable => \$active_tf,
    -indicatoron => 0,
    -command  => sub { $chart_engine->set_timeframe('5m') },
)->pack(-side => 'left', -padx => 2);
$frame_controles->Radiobutton(
    -text     => "15 Minutos",
    -value    => '15m',
    -variable => \$active_tf,
    -indicatoron => 0,
    -command  => sub { $chart_engine->set_timeframe('15m') },
)->pack(-side => 'left', -padx => 2);


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
