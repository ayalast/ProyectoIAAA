package Market::ChartEngine;
use strict;
use warnings;

use Time::Moment;
use Market::Panels::Scales;
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;
use Market::ReplayController;
use Market::OverlayManager;
use Market::Indicators::SMC_Structures;
use Market::Overlays::SMC_Structures;
use Market::Indicators::Liquidity;
use Market::Overlays::Liquidity;

# Constantes del módulo (valores fijos del paquete, no estado global mutable).
#   RIGHT_MARGIN     => margen interno derecho del área de ploteo. Los ejes ahora
#                       son canvases separados, así que debe ser 0.
#   MIN_VISIBLE_BARS => mínimo de velas visibles en la ventana (Req. 8, 10)
#   ZOOM_STEP        => barras por paso de rueda en el zoom horizontal
#   TIME_AXIS_DRAG_PX_PER_BAR => sensibilidad del drag horizontal del eje temporal
use constant {
    RIGHT_MARGIN     => 0,
    MIN_VISIBLE_BARS => 2,
    MAX_VISIBLE_BARS => 40000,
    ZOOM_STEP        => 5,
    CTRL_MASK        => 0x0004,
    TIME_AXIS_DRAG_PX_PER_BAR => 8,
};

# Paleta de tema claro por defecto (local al módulo). Se usa solo si el llamador
# no inyecta un hash `theme`. Mantiene EXACTAMENTE las mismas claves del contrato
# de tema definido en el diseño, de modo que los paneles puedan consumirla sin
# recurrir a variables globales.
sub _default_theme {
    return {
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
    };
}

sub new {
    my ($class, %args) = @_;

    my $self = {
        market_data      => $args{market_data},      
        indicator_manager=> $args{indicator_manager},
        price_canvas     => $args{price_canvas},     
        atr_canvas       => $args{atr_canvas},       
        
        visible_bars     => 60,
        offset           => 0,
        is_auto_scale    => 1,
        manual_min_y     => undef,
        manual_max_y     => undef,
        scale_mode_callback => $args{scale_mode_callback},
        ctrl_zoom_x_shift => 0,
        ctrl_zoom_y_lock_min => undef,
        ctrl_zoom_y_lock_max => undef,
        is_atr_auto_scale => 1,
        atr_manual_min_y => undef,
        atr_manual_max_y => undef,
        atr_axis_drag_start_y => undef,
        atr_axis_drag_min_y => undef,
        atr_axis_drag_max_y => undef,
        atr_drag_start_min_y => undef,
        atr_drag_start_max_y => undef,
        render_pending   => 0,
        drag_start_x     => undef,
        drag_start_y     => undef,
        drag_start_panel => undef,
        drag_start_offset=> 0,
        axis_drag_start_y=> undef,
        axis_drag_min_y  => undef,
        axis_drag_max_y  => undef,
        vertical_drag_y  => undef,
        
        %args,
    };
    bless $self, $class;

    # Tema claro: se usa el inyectado por el llamador (market.pl) o un default
    # local con las mismas claves. El tema viaja por la instancia, nunca como global.
    $self->{theme} = $args{theme} || _default_theme();

    $self->{price_panel} = Market::Panels::PricePanel->new(
        canvas => $self->{price_canvas},
        theme  => $self->{theme},
    );
    $self->{atr_panel}   = Market::Panels::ATRPanel->new(
        canvas => $self->{atr_canvas},
        theme  => $self->{theme},
    );

    # spec 0002: ReplayController — índice-tope para Replay.
    $self->{replay_controller} = Market::ReplayController->new(
        market_data => $self->{market_data},
    );

    # spec 0003: OverlayManager — registro de overlays.
    $self->{overlay_manager} = Market::OverlayManager->new();

    # spec 0004 / task 0008: overlay SMC_Structures. Consume el indicador de
    # cálculo (capa Indicators). El indicador se alimenta incrementalmente en
    # render() hasta el tope efectivo (respeta replay_idx). El overlay solo lee.
    $self->{smc_indicator} = Market::Indicators::SMC_Structures->new(k => 3);
    $self->{smc_overlay} = Market::Overlays::SMC_Structures->new(
        indicator => $self->{smc_indicator},
        theme     => $self->{theme},
        visible   => 0,   # task 0018 (F4): capas OFF por defecto (arranque limpio)
    );
    $self->{overlay_manager}->register('smc', $self->{smc_overlay});
    # Alimentado incremental: último índice global ya procesado por el indicador.
    $self->{_smc_fed_up_to} = -1;

    # spec 0005 / task 0012: overlay Liquidity. Consume el indicador de cálculo
    # (capa Indicators). Mismo patrón que SMC: alimentación incremental en render
    # hasta el tope efectivo (respeta replay_idx); el overlay solo lee.
    $self->{liq_indicator} = Market::Indicators::Liquidity->new(k => 1);
    $self->{liq_overlay} = Market::Overlays::Liquidity->new(
        indicator => $self->{liq_indicator},
        theme     => $self->{theme},
        visible   => 0,   # task 0018 (F4): capas OFF por defecto (arranque limpio)
    );
    $self->{overlay_manager}->register('liq', $self->{liq_overlay});
    $self->{_liq_fed_up_to} = -1;

    $self->bind_events();
    
    return $self;
}


sub compute_window {
    my ($self) = @_;
    
    my $total_candles = $self->{market_data}->size();
    return (0, -1) if !$total_candles || $total_candles <= 0;

    if ($total_candles >= MIN_VISIBLE_BARS) {
        $self->{visible_bars} = MIN_VISIBLE_BARS if $self->{visible_bars} < MIN_VISIBLE_BARS;
    } else {
        $self->{visible_bars} = $total_candles;
    }

    $self->{visible_bars} = $total_candles if $self->{visible_bars} > $total_candles;
    $self->{visible_bars} = MAX_VISIBLE_BARS if $self->{visible_bars} > MAX_VISIBLE_BARS;

    $self->{offset} = $self->_clamp_offset($self->{offset});

    # spec 0002: si Replay está activo, el límite superior efectivo es replay_idx.
    # Ninguna capa debe leer/dibujar velas con índice > replay_idx.
    my $replay = $self->{replay_controller};
    my $effective_total = $total_candles;
    if ($replay && $replay->is_active()) {
        my $eff_end = $replay->effective_end($total_candles - 1);
        $effective_total = $eff_end + 1;
    }

    my $end_idx = $effective_total - 1 - $self->{offset};
    my $start_idx = $end_idx - $self->{visible_bars} + 1;

    # spec 0018d: en modo NORMAL, start_idx puede ser NEGATIVO: eso crea el
    # espacio vacío a la izquierda de la primera vela (igual que el espacio a la
    # derecha de la última), comportamiento de Fase 1. NO se clampa a 0 aquí
    # porque eso encogería x_bars (= end-start+1) y haría "zoom" de las velas.
    # Solo bajo Replay se clampa para no pintar índices fuera del tope.
    if ($replay && $replay->is_active()) {
        $start_idx = 0 if $start_idx < 0;
    }

    return ($start_idx, $end_idx);
}

# sync_overlay_indicators — task 0015.
# Lleva los indicadores SMC y Liquidity exactamente al tope de alimentación
# efectivo según el estado de Replay. Los indicadores son máquinas
# incrementales con estado; alimentarlos hasta el fin del dataset filtra
# futuro (FVG mitigado por velas futuras, pivotes confirmados con velas
# futuras) aunque el overlay filtre el dibujo por index <= end. Corrección:
#   * Replay ACTIVO   → feed_to = replay_controller->current_index (replay_idx).
#   * Replay INACTIVO → feed_to = size()-1 (vista normal intacta).
# El avance/retroceso de cada indicador lo resuelve _feed_indicator_to.
# Es público para que t/16 pueda verificar el cableado sin invocar render()
# (que requiere UI completa) pero NO se invoca desde fuera de ChartEngine en
# producción.
sub sync_overlay_indicators {
    my ($self) = @_;
    return unless $self->{overlay_manager};

    my $replay   = $self->{replay_controller};
    my $last_idx = $self->{market_data}->size() - 1;
    my $feed_to;
    if ($replay && $replay->is_active() && defined $replay->current_index()) {
        $feed_to = $replay->current_index();
        $feed_to = $last_idx if defined $last_idx && $feed_to > $last_idx;
    } else {
        $feed_to = $last_idx;
    }

    # task 0018 (F3/F4): alimentación BAJO DEMANDA. Un indicador pesado
    # (SMC/Liquidity) solo se alimenta si su overlay está visible. Con las capas
    # apagadas por defecto, el arranque es instantáneo (no calcula nada pesado);
    # el costo se paga al activar la capa, una sola vez (cursor cacheado).
    # Si no hay overlay registrado (p.ej. tests t/16), se alimenta igual para
    # preservar el comportamiento verificado.
    $self->_feed_indicator_to($self->{smc_indicator}, '_smc_fed_up_to', $feed_to)
        if $self->_overlay_wants_feed('smc');
    $self->_feed_indicator_to($self->{liq_indicator}, '_liq_fed_up_to', $feed_to)
        if $self->_overlay_wants_feed('liq');
    return $feed_to;
}

# _overlay_wants_feed($name) — true si el indicador asociado debe alimentarse:
# cuando su overlay está visible, o cuando no hay overlay registrado (tests).
sub _overlay_wants_feed {
    my ($self, $name) = @_;
    my $mgr = $self->{overlay_manager};
    my $ov  = $mgr ? $mgr->get($name) : undef;
    return 1 unless $ov;                 # sin overlay (tests t/16) → alimentar
    return $ov->is_visible() ? 1 : 0;    # con overlay → solo si visible
}


# _feed_indicator_to($indicator, $cursor_key, $feed_to)
# task 0015: lleva un indicador incremental exactamente al índice $feed_to,
# respetando el cursor $self->{$cursor_key} (último índice ya alimentado).
#   * Avance (feed_to > cursor): update_last de cursor+1 .. feed_to.
#   * Retroceso (feed_to < cursor): reset() + realimentar 0 .. feed_to.
# El indicador refleja entonces el estado que tendría si el dataset terminara
# en feed_to (cero fuga de futuro en Replay). Mismo patrón para SMC y Liquidity.
sub _feed_indicator_to {
    my ($self, $indicator, $cursor_key, $feed_to) = @_;
    return unless $indicator && defined $feed_to;
    return if $feed_to < 0;

    my $fed_up_to = $self->{$cursor_key};
    $fed_up_to = -1 unless defined $fed_up_to;

    if ($feed_to > $fed_up_to) {
        for my $i ($fed_up_to + 1 .. $feed_to) {
            $indicator->update_last($self->{market_data}, $i);
        }
        $self->{$cursor_key} = $feed_to;
    } elsif ($feed_to < $fed_up_to) {
        $indicator->reset();
        for my $i (0 .. $feed_to) {
            $indicator->update_last($self->{market_data}, $i);
        }
        $self->{$cursor_key} = $feed_to;
    }
    return;
}

sub round {
    my ($self, $value) = @_;

    return 0 if !defined $value;

    return int($value + ($value >= 0 ? 0.5 : -0.5));
}

sub _max_offset_for_visible {
    my ($self) = @_;

    my $total = $self->{market_data}->size() || 0;
    return 0 if $total < MIN_VISIBLE_BARS;

    return ($total - MIN_VISIBLE_BARS) > 0 ? ($total - MIN_VISIBLE_BARS) : 0;
}

sub _min_offset_for_visible {
    my ($self) = @_;

    my $total = $self->{market_data}->size() || 0;
    return 0 if $total < MIN_VISIBLE_BARS;


    my $visible = $self->{visible_bars} || MIN_VISIBLE_BARS;
    $visible = $total if $visible > $total;

    return -(($visible > MIN_VISIBLE_BARS) ? ($visible - MIN_VISIBLE_BARS) : 0);
}

sub _clamp_offset {
    my ($self, $offset) = @_;

    $offset = 0 if !defined $offset;
    my $min_offset = $self->_min_offset_for_visible();
    my $max_offset = $self->_max_offset_for_visible();
    $offset = $min_offset if $offset < $min_offset;
    $offset = $max_offset if $offset > $max_offset;
    return $offset;
}

sub _pad_visible_slice {
    my ($self, $slice, $start, $end) = @_;

    return unless $slice;
    my $target = defined $start && defined $end && $end >= $start ? $end - $start + 1 : 0;
    push @$slice, (undef) x ($target - @$slice) if $target > @$slice;
}

sub _canvas_width {
    my ($self, $canvas) = @_;
    return 1 unless $canvas;

    my $w = 0;
    my $geom = eval { $canvas->geometry() };
    if (defined $geom && $geom =~ /^(\d+)x\d+/) {
        $w = $1;
    }
    $w ||= eval { $canvas->Width() } || eval { $canvas->width() } || 1;
    return $w > 1 ? $w : 1;
}

sub _canvas_size {
    my ($self, $canvas) = @_;
    return (1, 1) unless $canvas;
    my ($w, $h) = (0, 0);
    my $geom = eval { $canvas->geometry() };
    if (defined $geom && $geom =~ /^(\d+)x(\d+)/) {
        ($w, $h) = ($1, $2);
    }
    $w ||= eval { $canvas->Width() }  || eval { $canvas->width() }  || 1;
    $h ||= eval { $canvas->Height() } || eval { $canvas->height() } || 1;
    $w = 1 if $w < 1;
    $h = 1 if $h < 1;
    return ($w, $h);
}

sub _reset_canvas_view {
    my ($self, $canvas) = @_;
    return unless $canvas;

    my ($w, $h) = $self->_canvas_size($canvas);
    eval { $canvas->xviewMoveto(0) };
    eval { $canvas->yviewMoveto(0) };
    eval { $canvas->configure(-scrollregion => [0, 0, $w, $h]) };
}

sub request_render {
    my ($self) = @_;

    return if $self->{render_pending};
    $self->{render_pending} = 1;

    my $canvas = $self->{price_canvas} || $self->{atr_canvas};
    if ($canvas) {
        $canvas->after(20, sub {
            $self->{render_pending} = 0;
            $self->render();
        });
    } else {
        $self->{render_pending} = 0;
        $self->render();
    }
}

sub render {
    my ($self) = @_;
    
    # 1. Obtener la porción temporal de la ventana visible
    my ($start, $end) = $self->compute_window();
    
    # 2. Extraer subconjuntos de datos reales
    my $visible_candles = $self->{market_data}->get_slice($start, $end);
    my $visible_atr     = $self->{indicator_manager}->slice_array('ATR', $start, $end);
    $self->_pad_visible_slice($visible_candles, $start, $end);
    $self->_pad_visible_slice($visible_atr, $start, $end);

    # spec 0000i: overscan de render horizontal. El slice de dibujo incluye
    # una vela extra a cada lado (start-1, end+1) para que las velas parcialmente
    # visibles durante paneo suave (ctrl_zoom_x_shift) se rendericen desde antes.
    # La escala X sigue usando x_bars de la ventana visible; draw_start_offset
    # permite al panel calcular el índice local correcto (incluyendo -1 y
    # visible_bars) para posicionar las velas overscan.
    my $total = $self->{market_data}->size();
    my $draw_start = $start > 0 ? $start - 1 : $start;
    my $draw_end   = ($end < $total - 1) ? $end + 1 : $end;
    my $draw_candles = $self->{market_data}->get_slice($draw_start, $draw_end);
    my $draw_atr     = $self->{indicator_manager}->slice_array('ATR', $draw_start, $draw_end);
    $self->_pad_visible_slice($draw_candles, $draw_start, $draw_end);
    $self->_pad_visible_slice($draw_atr, $draw_start, $draw_end);
    my $draw_start_offset = $draw_start - $start;
    my $visible_count = $end - $start + 1;
    
    # 3. Calcular rangos de precios e indicadores para construir escalas dinámicas
    my ($min_p, $max_p) = $self->{price_panel}->get_y_range($visible_candles);
    my ($min_a, $max_a) = $self->{atr_panel}->get_y_range($visible_atr);
    
    if (defined $self->{ctrl_zoom_y_lock_min} && defined $self->{ctrl_zoom_y_lock_max}) {
        ($min_p, $max_p) = ($self->{ctrl_zoom_y_lock_min}, $self->{ctrl_zoom_y_lock_max});
    } elsif (!$self->{is_auto_scale} && defined $self->{manual_min_y} && defined $self->{manual_max_y}) {
        ($min_p, $max_p) = ($self->{manual_min_y}, $self->{manual_max_y});
    } else {
        ($self->{manual_min_y}, $self->{manual_max_y}) = ($min_p, $max_p);
    }

    if (!defined $min_p || !defined $max_p || $min_p == $max_p) {
        $min_p = 20000;
        $max_p = 30000;
    }
    if (!$self->{is_atr_auto_scale} && defined $self->{atr_manual_min_y} && defined $self->{atr_manual_max_y}) {
        ($min_a, $max_a) = ($self->{atr_manual_min_y}, $self->{atr_manual_max_y});
    } else {
        ($self->{atr_manual_min_y}, $self->{atr_manual_max_y}) = ($min_a, $max_a);
    }
    if (!defined $min_a || !defined $max_a || $min_a == $max_a) {
        $min_a = 0;
        $max_a = 100;
    }
    
    # 4. Instanciar los sistemas de coordenadas. La escala X usa un ancho compartido
    # para que PricePanel y ATRPanel queden sincronizados barra por barra.
    my ($price_w, $price_h) = $self->_canvas_size($self->{price_canvas});
    my ($atr_w, $atr_h)     = $self->_canvas_size($self->{atr_canvas});
    my $shared_w = $price_w;

    $self->_reset_canvas_view($self->{price_canvas});
    $self->_reset_canvas_view($self->{atr_canvas});
    $self->_reset_canvas_view($self->{price_axis_canvas});
    $self->_reset_canvas_view($self->{atr_axis_canvas});
    $self->_reset_canvas_view($self->{time_axis_canvas});

    if (!$self->{_printed_render_diag}) {
        print "[*] Render geometry: price=${price_w}x${price_h} atr=${atr_w}x${atr_h} window=$start-$end bars=" . scalar(@$visible_candles) . "\n";
        $self->{_printed_render_diag} = 1;
    }

    my $x_bars = $end - $start + 1;
    $x_bars = scalar(@$visible_candles) if $x_bars < 1;
    $x_bars = 1 if $x_bars < 1;

    my $price_scale = Market::Panels::Scales->new(min_y => $min_p, max_y => $max_p, bars => $x_bars, right_margin => RIGHT_MARGIN);
    my $atr_scale   = Market::Panels::Scales->new(min_y => $min_a, max_y => $max_a, bars => $x_bars, right_margin => RIGHT_MARGIN);
    $price_scale->{width}  = $shared_w;
    $price_scale->{height} = $price_h;
    $price_scale->{draw_labels} = $self->{price_axis_canvas} ? 0 : 1;
    $price_scale->{draw_last_label} = $self->{price_axis_canvas} ? 0 : 1;
    $price_scale->{draw_crosshair_label} = $self->{price_axis_canvas} ? 0 : 1;
    $price_scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    $price_scale->{tick_size} = 0.25;
    $price_scale->{draw_start_offset} = $draw_start_offset;
    $price_scale->{visible_count} = $visible_count;
    $atr_scale->{width}    = $shared_w;
    $atr_scale->{height}   = $atr_h;
    $atr_scale->{draw_labels} = $self->{atr_axis_canvas} ? 0 : 1;
    $atr_scale->{draw_last_label} = $self->{atr_axis_canvas} ? 0 : 1;
    $atr_scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    $atr_scale->{draw_start_offset} = $draw_start_offset;
    $atr_scale->{visible_count} = $visible_count;

    
    $self->{price_panel}->set_scale($price_scale);

    $self->{atr_panel}->set_scale($atr_scale);
    
    # 5. Ejecutar render en cada sub-canvas
    # spec 0000i: pasar draw_candles (con overscan) al panel para que las velas
    # parcialmente visibles durante paneo se rendericen desde antes.
    $self->{price_panel}->render($self->{price_canvas}, $draw_candles, $price_scale);
    $self->{atr_panel}->render($self->{atr_canvas}, $draw_atr, $atr_scale);
    my $time_labels = $self->compute_intraday_labels();
    $self->{price_panel}->draw_time_axis($self->{price_canvas}, $time_labels, { draw_grid => 1, draw_labels => 0 });
    $self->_render_price_axis($price_scale, $visible_candles);
    $self->_render_atr_axis($atr_scale, $visible_atr);
    $self->_render_time_axis($price_scale, $time_labels);

    # spec 0003 / task 0015: overlays — compute + draw respetando replay_idx
    # (start/end ya vienen truncados por compute_window si Replay está activo).
    if ($self->{overlay_manager}) {
        # task 0015: el cableado de alimentación de los indicadores SMC/Liquidity
        # se sincroniza con el tope de Replay (ver sync_overlay_indicators).
        $self->sync_overlay_indicators();

        # compute_all y el filtro del overlay (index <= end) actúan como segunda
        # barrera (defensa en profundidad); la corrección real es alimentar hasta
        # feed_to en sync_overlay_indicators.
        $self->{overlay_manager}->compute_all($self->{market_data}, $start, $end);
        $self->{overlay_manager}->draw_all($self->{price_canvas}, $price_scale);
    }

    $self->_draw_crosshair_all() if defined $self->{last_mouse_x};
    $self->_redraw_pointer_symbol();
}

sub _render_price_axis {
    my ($self, $source_scale, $visible_candles) = @_;

    my $canvas = $self->{price_axis_canvas};
    return unless $canvas && $source_scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    $canvas->delete('y_scale');
    $canvas->delete('axis_last_price');

    my $axis_scale = Market::Panels::Scales->new(
        min_y        => $source_scale->{min_y},
        max_y        => $source_scale->{max_y},
        bars         => 1,
        right_margin => 0,
    );
    $axis_scale->{width}           = $w;
    $axis_scale->{height}          = $source_scale->{height} || $h;
    $axis_scale->{draw_grid}       = 0;
    $axis_scale->{draw_labels}     = 1;
    $axis_scale->{label_x}         = 4;
    $axis_scale->{label_anchor}    = 'w';
    $axis_scale->{grid_color}      = $self->{theme}{grid}      // '#e6e6e6';
    $axis_scale->{axis_text_color} = $self->{theme}{axis_text} // '#363a45';
    $axis_scale->{tick_size}       = $source_scale->{tick_size};
    $axis_scale->_draw_y_scale($canvas);

    return unless $visible_candles && @$visible_candles;
    my $last_candle;
    for my $candle (@$visible_candles) {
        $last_candle = $candle if defined $candle;
    }
    return unless defined $last_candle;
    my ($open, $close) = @{$last_candle}[1, 4];
    return unless defined $close;

    my $y = $axis_scale->value_to_y($close);

    my $label = sprintf('%.2f', $close);
    my $bg = (defined $open && $close >= $open)
        ? ($self->{theme}{bull} // '#26a69a')
        : ($self->{theme}{bear} // '#ef5350');
    my $fg = $self->{theme}{last_price_fg} // '#ffffff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $bg, -outline => $bg, -tags => 'axis_last_price');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'axis_last_price');
}

sub _draw_price_axis_crosshair {
    my ($self, $y) = @_;

    my $canvas = $self->{price_axis_canvas};
    return unless $canvas;

    $canvas->delete('axis_crosshair');
    return unless defined $y;

    my $scale = $self->{price_panel} ? $self->{price_panel}->{scale} : undef;
    return unless $scale;

    my ($w, undef) = $self->_canvas_size($canvas);
    my $value = $scale->y_to_value($y);
    my $tick = $scale->{tick_size} || 0.25;
    $value = int($value / $tick + ($value >= 0 ? 0.5 : -0.5)) * $tick;
    my $label = sprintf('%.2f', $value);
    my $bg = $self->{theme}{label_bg} // '#363a45';
    my $fg = $self->{theme}{label_fg} // '#ffffff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $bg, -outline => $bg, -tags => 'axis_crosshair');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'axis_crosshair');
}

sub _draw_atr_axis_crosshair {
    my ($self, $y) = @_;

    my $canvas = $self->{atr_axis_canvas};
    return unless $canvas;

    $canvas->delete('atr_axis_crosshair');
    return unless defined $y;

    my $scale = $self->{atr_panel} ? $self->{atr_panel}->{scale} : undef;
    return unless $scale;

    my ($w, undef) = $self->_canvas_size($canvas);
    my $value = $scale->y_to_value($y);
    my $label = sprintf('%.4f', $value);
    my $bg = $self->{theme}{label_bg} // '#363a45';
    my $fg = $self->{theme}{label_fg} // '#ffffff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $bg, -outline => $bg, -tags => 'atr_axis_crosshair');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'atr_axis_crosshair');
}

sub _render_time_axis {
    my ($self, $source_scale, $labels) = @_;

    my $canvas = $self->{time_axis_canvas};
    return unless $canvas && $source_scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    my $old_scale = $self->{price_panel}->{scale};
    my $axis_scale = Market::Panels::Scales->new(
        bars         => $source_scale->{bars},
        right_margin => RIGHT_MARGIN,
    );
    $axis_scale->{width}  = $source_scale->{width} || $w;
    $axis_scale->{height} = $h;
    $axis_scale->{x_shift} = $source_scale->{x_shift} || 0;

    $self->{price_panel}->{scale} = $axis_scale;
    $self->{price_panel}->draw_time_axis($canvas, $labels, { draw_grid => 0, draw_labels => 1 });
    $self->{price_panel}->{scale} = $old_scale;
}

sub _render_atr_axis {
    my ($self, $source_scale, $visible_atr) = @_;

    my $canvas = $self->{atr_axis_canvas};
    return unless $canvas && $source_scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    $canvas->delete('y_scale');
    $canvas->delete('atr_axis_last');

    my $axis_scale = Market::Panels::Scales->new(
        min_y        => $source_scale->{min_y},
        max_y        => $source_scale->{max_y},
        bars         => 1,
        right_margin => 0,
    );
    $axis_scale->{width}           = $w;
    $axis_scale->{height}          = $source_scale->{height} || $h;
    $axis_scale->{draw_grid}       = 0;
    $axis_scale->{draw_labels}     = 1;
    $axis_scale->{label_x}         = 4;
    $axis_scale->{label_anchor}    = 'w';
    $axis_scale->{grid_color}      = $self->{theme}{grid}      // '#e6e6e6';
    $axis_scale->{axis_text_color} = $self->{theme}{axis_text} // '#363a45';
    $axis_scale->_draw_y_scale($canvas);

    my $last;
    for my $v (@$visible_atr) {
        $last = $v if defined $v;
    }
    return unless defined $last;

    my $y = $axis_scale->value_to_y($last);
    my $label = sprintf('%.4f', $last);
    my $fg = $self->{theme}{last_price_fg} // '#ffffff';
    my $line = $self->{theme}{atr_line} // '#2962ff';

    $canvas->createRectangle(0, $y - 8, $w, $y + 8, -fill => $line, -outline => $line, -tags => 'atr_axis_last');
    $canvas->createText(4, $y, -text => $label, -anchor => 'w', -font => 'Helvetica 9 bold', -fill => $fg, -tags => 'atr_axis_last');
}


sub _set_cursor {
    my ($self, $widget, $cursor) = @_;

    return unless defined $widget && defined $cursor;
    eval { $widget->configure(-cursor => $cursor) };
}

sub _draw_pointer_symbol {
    my ($self, $widget, $x, $y, $kind) = @_;

    return unless defined $widget;
    eval { $widget->delete('pointer_symbol') };
}

sub _clear_pointer_symbol {
    my ($self, $widget) = @_;

    eval { $widget->delete('pointer_symbol') } if defined $widget;
    $self->{pointer_widget} = undef;
}

sub _redraw_pointer_symbol {
    my ($self) = @_;

    return;
}

sub _bind_all_canvas {
    my ($self) = @_;
    
    # Aseguramos capturar las referencias exactas de los objetos de Tk
    my $p_canvas = $self->{price_canvas};
    my $a_canvas = $self->{atr_canvas};
    my $axis_canvas = $self->{price_axis_canvas};
    my $atr_axis_canvas = $self->{atr_axis_canvas};
    my $time_canvas = $self->{time_axis_canvas};
    
    # 1. Binding nativo para el panel de Precios usando la sintaxis clásica 'bind'
    if (defined $p_canvas) {
        $p_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_mouse_move($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $p_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_start_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $p_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $p_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_drag(); });
        $p_canvas->Tk::bind('<MouseWheel>', [sub {
            my ($widget, $delta, $x, $y, $state) = @_;
            my $step = $delta > 0 ? -ZOOM_STEP : ZOOM_STEP;
            $self->_wheel_zoom($widget, $step, $x, $y, $state);
            return 'break';
        }, Tk::Ev('D'), Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $p_canvas->Tk::bind('<Button-4>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, -ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $p_canvas->Tk::bind('<Button-5>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $p_canvas->Tk::bind('<Double-Button-1>', sub { $self->reset_view(); });
        $p_canvas->Tk::bind('<Configure>', sub { $self->_on_resize($p_canvas); });
        $p_canvas->Tk::bind('<Key-a>', sub { $self->set_scale_mode('auto'); });
        $p_canvas->Tk::bind('<Key-m>', sub { $self->set_scale_mode('manual'); });
        $p_canvas->Tk::bind('<Key-plus>', sub { $self->set_scale_mode('manual'); $self->_vertical_zoom(0.9); });
        $p_canvas->Tk::bind('<Key-minus>', sub { $self->set_scale_mode('manual'); $self->_vertical_zoom(1.1); });
        $p_canvas->Tk::bind('<Up>', sub { $self->set_scale_mode('manual'); $self->_vertical_drag(-10); });
        $p_canvas->Tk::bind('<Down>', sub { $self->set_scale_mode('manual'); $self->_vertical_drag(10); });
        $p_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($p_canvas, 'crosshair'); $p_canvas->focus; });
        $p_canvas->Tk::bind('<Leave>', sub {
            $self->_set_cursor($p_canvas, 'crosshair');
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
            $self->_clear_pointer_symbol($p_canvas);
        });
    }
    
    # 2. Binding nativo idéntico para el panel del ATR
    if (defined $a_canvas) {
        $a_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_mouse_move($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $a_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_start_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $a_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_horizontal_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $a_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_drag(); });
        $a_canvas->Tk::bind('<MouseWheel>', [sub {
            my ($widget, $delta, $x, $y, $state) = @_;
            my $step = $delta > 0 ? -ZOOM_STEP : ZOOM_STEP;
            $self->_wheel_zoom($widget, $step, $x, $y, $state);
            return 'break';
        }, Tk::Ev('D'), Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $a_canvas->Tk::bind('<Button-4>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, -ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $a_canvas->Tk::bind('<Button-5>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $a_canvas->Tk::bind('<Configure>', sub { $self->_on_resize($a_canvas); });
        $a_canvas->Tk::bind('<Key-a>', sub { $self->set_atr_scale_mode('auto'); });
        $a_canvas->Tk::bind('<Key-m>', sub { $self->set_atr_scale_mode('manual'); });
        $a_canvas->Tk::bind('<Key-plus>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_zoom(0.9); });
        $a_canvas->Tk::bind('<Key-minus>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_zoom(1.1); });
        $a_canvas->Tk::bind('<Up>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_drag(-10); });
        $a_canvas->Tk::bind('<Down>', sub { $self->set_atr_scale_mode('manual'); $self->_atr_vertical_drag(10); });
        $a_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($a_canvas, 'crosshair'); $a_canvas->focus; });
        $a_canvas->Tk::bind('<Leave>', sub {
            $self->_set_cursor($a_canvas, 'crosshair');
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
            $self->_clear_pointer_symbol($a_canvas);
        });
    }

    if (defined $axis_canvas) {
        $axis_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_draw_pointer_symbol($widget, $x, $y, 'v');
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $axis_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $y) = @_;
            $self->_start_price_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $axis_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $y) = @_;
            $self->_on_price_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $axis_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_price_axis_drag(); });
        $axis_canvas->Tk::bind('<Double-Button-1>', sub { $self->set_scale_mode('auto'); });
        $axis_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($axis_canvas, 'sb_v_double_arrow') });
        $axis_canvas->Tk::bind('<Leave>', sub { $self->_set_cursor($axis_canvas, 'sb_v_double_arrow'); $self->_clear_pointer_symbol($axis_canvas); });
    }

    if (defined $atr_axis_canvas) {
        $atr_axis_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_draw_pointer_symbol($widget, $x, $y, 'v');
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $atr_axis_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $y) = @_;
            $self->_start_atr_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $atr_axis_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $y) = @_;
            $self->_on_atr_axis_drag($widget, $y);
        }, Tk::Ev('y')]);
        $atr_axis_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_atr_axis_drag(); });
        $atr_axis_canvas->Tk::bind('<Double-Button-1>', sub { $self->_reset_atr_scale(); });
        $atr_axis_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($atr_axis_canvas, 'sb_v_double_arrow') });
        $atr_axis_canvas->Tk::bind('<Leave>', sub { $self->_set_cursor($atr_axis_canvas, 'sb_v_double_arrow'); $self->_clear_pointer_symbol($atr_axis_canvas); });
    }

    if (defined $time_canvas) {
        $time_canvas->Tk::bind('<Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_time_axis_motion($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $time_canvas->Tk::bind('<ButtonPress-1>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_start_time_axis_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $time_canvas->Tk::bind('<B1-Motion>', [sub {
            my ($widget, $x, $y) = @_;
            $self->_on_time_axis_drag($widget, $x, $y);
        }, Tk::Ev('x'), Tk::Ev('y')]);
        $time_canvas->Tk::bind('<ButtonRelease-1>', sub { $self->_end_time_axis_drag(); });
        $time_canvas->Tk::bind('<MouseWheel>', [sub {
            my ($widget, $delta, $x, $y, $state) = @_;
            my $step = $delta > 0 ? -ZOOM_STEP : ZOOM_STEP;
            $self->_wheel_zoom($widget, $step, $x, $y, $state);
            return 'break';
        }, Tk::Ev('D'), Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $time_canvas->Tk::bind('<Button-4>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, -ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $time_canvas->Tk::bind('<Button-5>', [sub {
            my ($widget, $x, $y, $state) = @_;
            $self->_wheel_zoom($widget, ZOOM_STEP, $x, $y, $state);
            return 'break';
        }, Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')]);
        $time_canvas->Tk::bind('<Enter>', sub { $self->_set_cursor($time_canvas, 'sb_h_double_arrow') });
        $time_canvas->Tk::bind('<Leave>', sub {
            $self->_set_cursor($time_canvas, 'sb_h_double_arrow');
            $self->{last_mouse_x} = undef;
            $self->{last_mouse_y} = undef;
            $self->{active_canvas} = undef;
            $self->_draw_crosshair_all();
            $self->_clear_pointer_symbol($time_canvas);
        });
    }
}

sub bind_events {
    my ($self) = @_;
    $self->_bind_all_canvas();
}

# _anchor_index_and_x($anchor_x) — calcula el punto de anclaje del zoom (Req. 9.1, 9.2,
# 9.4) ANTES de cambiar el nivel de zoom.
#
# Dado un X de pantalla (o undef), devuelve la pareja:
#       ($anchor_index, $anchor_screen_x)
# donde $anchor_index es el índice GLOBAL del dato que debe quedar fijo y
# $anchor_screen_x es la coordenada X de pantalla en la que debe permanecer.
#
# Toda conversión X<->índice vive EXCLUSIVAMENTE en Scales (regla de oro de
# coordenadas): se instancia un Market::Panels::Scales con los mismos parámetros que
# usa render() —bars = nº de velas visibles (end - start + 1 de compute_window),
# right_margin => RIGHT_MARGIN y el ancho real del canvas de precios—.
#
#   * $anchor_x DEFINIDO (cursor sobre una barra del área de ploteo):
#       local  = Scales->x_to_index($anchor_x)   # índice LOCAL acotado a [0, bars-1]
#       global = start + local                    # índice GLOBAL del dato
#       => devuelve (global, $anchor_x)
#
#   * $anchor_x UNDEF (sin cursor): el ancla es la última vela visible, cuyo índice
#     GLOBAL es 'end' (de compute_window). Su X de pantalla es el centro de su barra:
#       local_de_end = end - start
#       screen_x     = Scales->index_to_center_x(local_de_end)
#       => devuelve (end, screen_x)
sub _anchor_index_and_x {
    my ($self, $anchor_x) = @_;

    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    $bars = 1 if $bars < 1;

    # Escala SOLO para convertir X <-> índice; mismos parámetros que render().
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});

    if (defined $anchor_x) {
        # Cursor sobre una barra: índice LOCAL -> GLOBAL; la X se conserva tal cual.
        my $local  = $scale->x_to_index($anchor_x);
        my $global = $start + $local;
        return ($global, $anchor_x);
    }

    # Sin cursor: ancla = última vela real visible. Si la ventana incluye espacio
    # vacío a cualquier lado, el ancla se acota al rango real de datos.
    my $last_real = ($self->{market_data}->size() || 1) - 1;
    my $anchor_index = $end > $last_real ? $last_real : $end;
    $anchor_index = 0 if $anchor_index < 0;
    my $local_of_anchor = $anchor_index - $start;

    my $screen_x = $scale->index_to_center_x($local_of_anchor);
    return ($anchor_index, $screen_x);
}

# _zoom_anchor_x — decide el X de anclaje para los eventos de rueda/Button-4/5.
#
# Devuelve $self->{last_mouse_x} (ya actualizado por <Motion>) SOLO si el cursor está
# sobre una barra del área de ploteo, es decir, dentro de [0, plot_width]. En cualquier
# otro caso (sin cursor, o el cursor cae sobre el margen derecho de precios) devuelve
# undef, de modo que el ancla pase a ser la última vela visible (Req. 9.1).
#
# plot_width vive en Scales (regla de oro): se obtiene de una instancia con el ancho
# real del canvas y RIGHT_MARGIN, sin calcular el margen por nuestra cuenta.
sub _zoom_anchor_x {
    my ($self) = @_;

    my $x = $self->{last_mouse_x};
    return undef unless defined $x;                  # sin cursor => última vela

    my $canvas = $self->{price_canvas};
    return undef unless $canvas;
    my $w = $self->_canvas_width($canvas);
    return undef unless defined $w && $w > 0;

    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    $bars = 1 if $bars < 1;

    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $w;
    my $plot_w = $scale->plot_width();

    return ($x >= 0 && $x <= $plot_w) ? $x : undef;
}

sub _clear_ctrl_zoom_state {
    my ($self) = @_;

    $self->{ctrl_zoom_x_shift} = 0;
    $self->{ctrl_zoom_y_lock_min} = undef;
    $self->{ctrl_zoom_y_lock_max} = undef;
}

sub _wheel_zoom_delta {
    my ($self, $step) = @_;

    my $total = $self->{market_data}->size() || 0;
    return 0 unless $total > 0;

    my $old_visible = $self->{visible_bars} || MIN_VISIBLE_BARS;
    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    $max_visible = MIN_VISIBLE_BARS if $max_visible < MIN_VISIBLE_BARS;

    my $zoom_scale = -$step / ZOOM_STEP;
    my $factor = 1 + ($zoom_scale / 10);
    $factor = 0.1 if $factor < 0.1;

    my $new_visible = $self->round($old_visible / $factor);
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible if $new_visible > $max_visible;

    if ($new_visible == $old_visible) {
        if ($zoom_scale < 0 && $old_visible < $max_visible) {
            $new_visible = $old_visible + 1;
        } elsif ($zoom_scale > 0 && $old_visible > MIN_VISIBLE_BARS) {
            $new_visible = $old_visible - 1;
        }
    }

    return $new_visible - $old_visible;
}

sub _wheel_zoom {
    my ($self, $widget, $step, $x, $y, $state) = @_;

    if (defined $x) {
        $self->{last_mouse_x} = $self->_snap_crosshair_x($x);
        $self->{last_mouse_y} = $self->round($y) if defined $y;
        $self->{active_canvas} = $widget if defined $widget;
    }

    my $delta = $self->_wheel_zoom_delta($step);
    return if $delta == 0;

    my $ctrl_pressed = defined $state && ($state & CTRL_MASK);
    if ($ctrl_pressed) {
        my $anchor_x = $self->_zoom_anchor_x();
        if (defined $anchor_x) {
            $self->_ctrl_horizontal_zoom($delta, $anchor_x);
            return;
        }
    }

    $self->_clear_ctrl_zoom_state();
    $self->_horizontal_zoom($delta, undef);
}

sub _ctrl_horizontal_zoom {
    my ($self, $delta, $anchor_x) = @_;

    my $total = $self->{market_data}->size();
    return if !$total;

    my ($start, $end) = $self->compute_window();
    my $old_visible = $self->{visible_bars} || ($end - $start + 1) || 1;
    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    $max_visible = MIN_VISIBLE_BARS if $max_visible < MIN_VISIBLE_BARS;
    my $new_visible = $old_visible + $delta;
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible     if $new_visible > $max_visible;
    return if $new_visible == $old_visible;

    my $canvas_w = $self->_canvas_width($self->{price_canvas});
    return if !$canvas_w || $canvas_w <= 0;

    my $old_scale = Market::Panels::Scales->new(bars => $old_visible, right_margin => RIGHT_MARGIN);
    $old_scale->{width} = $canvas_w;
    $old_scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    my $anchor_global = $start + $old_scale->x_to_index_float($anchor_x) - 0.5;

    my $new_scale = Market::Panels::Scales->new(bars => $new_visible, right_margin => RIGHT_MARGIN);
    $new_scale->{width} = $canvas_w;
    my $new_bar_w = $new_scale->plot_width() / $new_visible;
    return if $new_bar_w <= 0;

    my $target_start = $anchor_global - (($anchor_x - ($new_bar_w / 2)) / $new_bar_w);
    my $new_start = $self->round($target_start);
    my $new_end = $new_start + $new_visible - 1;
    my $new_offset = ($total - 1) - $new_end;

    $self->{visible_bars} = $new_visible;
    $self->{offset} = $self->_clamp_offset($new_offset);
    ($new_start, $new_end) = $self->compute_window();

    $self->{ctrl_zoom_x_shift} = $anchor_x - (($anchor_global - $new_start + 0.5) * $new_bar_w);
    $self->{last_mouse_x} = $self->round($anchor_x);

    if ($self->{is_auto_scale}) {
        $self->{ctrl_zoom_y_lock_min} = undef;
        $self->{ctrl_zoom_y_lock_max} = undef;
    } elsif (!defined $self->{ctrl_zoom_y_lock_min} || !defined $self->{ctrl_zoom_y_lock_max}) {
        if (defined $self->{manual_min_y} && defined $self->{manual_max_y}) {
            $self->{ctrl_zoom_y_lock_min} = $self->{manual_min_y};
            $self->{ctrl_zoom_y_lock_max} = $self->{manual_max_y};
        }
    }

    $self->request_render();
}

# _horizontal_zoom($delta, $anchor_x) — zoom horizontal con ANCLAJE (Req. 8.1, 8.2,
# 9.1, 9.2, 9.3, 9.4).
#
# $delta      cambio en visible_bars (negativo = zoom-in, positivo = zoom-out).
# $anchor_x   X de pantalla del ancla, o undef. Si se llama con un solo argumento
#             ($anchor_x undef), el ancla es la última vela visible (compatibilidad
#             con los llamadores antiguos de un argumento).
#
# Algoritmo (design.md, "Algoritmo de zoom con anclaje"):
#   1. (anchor_index, anchor_screen_x) = _anchor_index_and_x($anchor_x)  [ANTES del zoom]
#   2. new_visible = clamp(visible_bars + delta, MIN_VISIBLE_BARS, total)
#   3. visible_bars = new_visible
#   4. bar_w' = plot_width / new_visible  (derivado dentro de Scales)
#   5. reposicionar el ancla en anchor_screen_x:
#        local'   = anchor_screen_x / bar_w' - 0.5   (vía Scales->x_to_index_float)
#        end_idx' = anchor_index + (new_visible - 1 - local')
#        offset   = (total - 1) - end_idx'
#   6. offset entero y acotado para conservar como mínimo dos velas reales en cada extremo.

#   7. request_render()
#
# Toda conversión X<->índice se hace SOLO con Scales (Req. 9.4). El ancla se conserva
# dentro de la tolerancia de una barra (Req. 9.3) porque offset es entero (el redondeo
# introduce a lo sumo ±0.5 barra de desviación).
sub _horizontal_zoom {
    my ($self, $delta, $anchor_x) = @_;

    my $total = $self->{market_data}->size();
    return unless $total && $total > 0;
    my $old_offset = $self->{offset};
    my $use_cursor_anchor = defined $anchor_x;

    # 1. Punto de anclaje (índice GLOBAL + X de pantalla) ANTES de cambiar el zoom.
    #    Solo Ctrl+rueda usa ancla de cursor; rueda normal conserva el borde derecho.
    my ($anchor_index, $anchor_screen_x) = $use_cursor_anchor ? $self->_anchor_index_and_x($anchor_x) : $self->_anchor_index_and_x(undef);

    # 2. Nuevo nº de velas visibles, acotado a [MIN_VISIBLE_BARS, total].
    #    (Esto sustituye el antiguo mínimo de 10 por MIN_VISIBLE_BARS = 2.)
    my $new_visible = $self->{visible_bars} + $delta;

    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible     if $new_visible > $max_visible;

    # 3. Aplicar el nuevo zoom.
    $self->{visible_bars} = $new_visible;

    if (!$use_cursor_anchor) {
        if ($old_offset <= 0) {
            $self->{offset} = $self->_clamp_offset($old_offset);
            $self->request_render();
            return;
        }
    }

    # 4. Nueva escala con el nuevo nº de barras. bar_w' = plot_width / new_visible se
    #    deriva dentro de Scales; la inversión X->índice continuo vive en x_to_index_float.
    my $scale = Market::Panels::Scales->new(
        bars         => $new_visible,

        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});

    # 5. Reposicionar el ancla en su X de pantalla previa.
    #    index_to_center_x(local) = (local + 0.5) * bar_w  =>  local = X/bar_w - 0.5.
    #    X/bar_w lo da Scales->x_to_index_float (la división vive en Scales).
    my $local_target = $scale->x_to_index_float($anchor_screen_x) - 0.5;
    my $end_idx      = $anchor_index + ($new_visible - 1 - $local_target);
    my $offset       = ($total - 1) - $end_idx;

    # 6. Offset entero y acotado. compute_window define:
    #      end = total - 1 - offset ; start = end - visible_bars + 1.
    #    El clamp conserva como mínimo MIN_VISIBLE_BARS velas reales en ambos extremos.

    $offset = $self->round($offset);
    $self->{offset} = $self->_clamp_offset($offset);

    if ($use_cursor_anchor) {
        my ($new_start, undef) = $self->compute_window();
        my $new_local = $anchor_index - $new_start;
        $new_local = 0 if $new_local < 0;
        $new_local = $new_visible - 1 if $new_local >= $new_visible;
        $scale->{x_shift} = 0;
        $self->{last_mouse_x} = $self->round($scale->index_to_center_x($new_local));
    }

    # 7. Render diferido (coalescing).
    $self->request_render();
}

sub _start_horizontal_drag {
    my ($self, $widget, $x, $y) = @_;

    # spec 0000c: preservar x_shift para paneo fraccional suave. NO limpiar
    # ctrl_zoom_state aquí; reset_view/set_timeframe sí lo resetean cuando corresponde.
    my $root_x = eval { $widget->pointerx() };
    my $root_y = eval { $widget->pointery() };
    $self->{drag_start_x} = defined $root_x ? $root_x : $x;
    $self->{drag_start_y} = defined $root_y ? $root_y : $y;
    $self->{drag_start_panel} = defined $widget && defined $self->{atr_canvas} && $widget == $self->{atr_canvas} ? 'atr' : 'price';
    $self->{drag_start_offset} = $self->{offset};
    $self->{drag_start_x_shift} = $self->{ctrl_zoom_x_shift} || 0;

    if (defined $widget) {
        $self->_set_cursor($widget, 'fleur');
        $self->{drag_cursor_canvas} = $widget;
    }

    my $price_scale = $self->{price_panel} ? $self->{price_panel}->{scale} : undef;
    $self->{drag_start_min_y} = defined $self->{manual_min_y} ? $self->{manual_min_y} : (defined $price_scale ? $price_scale->{min_y} : undef);
    $self->{drag_start_max_y} = defined $self->{manual_max_y} ? $self->{manual_max_y} : (defined $price_scale ? $price_scale->{max_y} : undef);

    my $atr_scale = $self->{atr_panel} ? $self->{atr_panel}->{scale} : undef;
    $self->{atr_drag_start_min_y} = defined $self->{atr_manual_min_y} ? $self->{atr_manual_min_y} : (defined $atr_scale ? $atr_scale->{min_y} : undef);
    $self->{atr_drag_start_max_y} = defined $self->{atr_manual_max_y} ? $self->{atr_manual_max_y} : (defined $atr_scale ? $atr_scale->{max_y} : undef);
}

sub _on_horizontal_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_on_mouse_move($widget, $x, $y);
    return unless defined $self->{drag_start_x};
    my $canvas = $self->{price_canvas};
    return unless $canvas;

    my $root_x = eval { $widget->pointerx() };
    my $root_y = eval { $widget->pointery() };
    my $current_x = defined $root_x ? $root_x : $x;
    my $current_y = defined $root_y ? $root_y : $y;
    my $width = $self->_canvas_width($canvas);
    my $scale = Market::Panels::Scales->new(
        bars         => $self->{visible_bars} || 1,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $width;
    my $bar_w = $scale->plot_width() / ($self->{visible_bars} || 1);
    return if $bar_w <= 0;

    # spec 0000c: paneo horizontal suave/fraccional. Se separa el desplazamiento
    # en píxeles en parte entera (offset) y resto fraccional (x_shift), de modo
    # que arrastres menores a una vela desplacen visualmente sin saltar offset.
    my $dx = $current_x - $self->{drag_start_x};
    my $delta_float = $dx / $bar_w;
    my $delta_whole = int($delta_float);
    my $remainder_px = $dx - ($delta_whole * $bar_w);

    my $new_offset = $self->{drag_start_offset} + $delta_whole;
    my $new_shift  = ($self->{drag_start_x_shift} || 0) + $remainder_px;

    # Normalizar: mantener x_shift en [-bar_w, bar_w] ajustando offset.
    while ($new_shift >= $bar_w) {
        $new_shift -= $bar_w;
        $new_offset += 1;
    }
    while ($new_shift <= -$bar_w) {
        $new_shift += $bar_w;
        $new_offset -= 1;
    }

    $self->{offset} = $self->_clamp_offset($new_offset);
    # spec 0018c: si el offset tocó su límite (2 velas en el borde), NO permitir
    # desplazamiento sub-vela adicional: x_shift se anula para que las velas no
    # tiemblen ni se asomen más allá del límite al seguir arrastrando.
    if ($self->{offset} != $new_offset) {
        $new_shift = 0;
    }
    $self->{ctrl_zoom_x_shift} = $new_shift;

    if (($self->{drag_start_panel} || 'price') eq 'atr') {
        $self->_apply_atr_vertical_drag_from_start($current_y);
    } else {
        $self->_apply_vertical_drag_from_start($current_y);
    }
    $self->request_render();
}

sub _on_time_axis_motion {
    my ($self, $widget, $x, $y) = @_;

    return unless defined $x;
    $self->{last_mouse_x} = $self->_snap_crosshair_x($x);
    $self->{last_mouse_y} = undef;
    $self->{active_canvas} = $widget if defined $widget;
    $self->_draw_crosshair_all();
    $self->_draw_pointer_symbol($widget, $x, $y, 'h') if defined $widget && defined $y;
}

sub _start_time_axis_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_clear_ctrl_zoom_state();
    $self->_set_cursor($widget, 'sb_h_double_arrow');
    my $root_x = eval { $widget->pointerx() };
    $self->{time_axis_drag_start_x} = defined $root_x ? $root_x : $x;
    $self->{time_axis_drag_visible} = $self->{visible_bars};
}

sub _on_time_axis_drag {
    my ($self, $widget, $x, $y) = @_;

    $self->_on_time_axis_motion($widget, $x, $y);
    return unless defined $self->{time_axis_drag_start_x};

    my $root_x = eval { $widget->pointerx() };
    my $current_x = defined $root_x ? $root_x : $x;
    return unless defined $current_x;

    my $total = $self->{market_data}->size();
    return unless $total && $total > 0;

    my $max_visible = $total < MAX_VISIBLE_BARS ? $total : MAX_VISIBLE_BARS;
    my $delta = int(($current_x - $self->{time_axis_drag_start_x}) / TIME_AXIS_DRAG_PX_PER_BAR);
    my $new_visible = ($self->{time_axis_drag_visible} || $self->{visible_bars}) + $delta;
    $new_visible = MIN_VISIBLE_BARS if $new_visible < MIN_VISIBLE_BARS;
    $new_visible = $max_visible     if $new_visible > $max_visible;
    return if $new_visible == $self->{visible_bars};

    $self->_horizontal_zoom($new_visible - $self->{visible_bars}, undef);
}

sub _end_time_axis_drag {
    my ($self) = @_;
    $self->_set_cursor($self->{time_axis_canvas}, 'sb_h_double_arrow');
    $self->{time_axis_drag_start_x} = undef;
    $self->{time_axis_drag_visible} = undef;
}

sub _apply_vertical_drag_from_start {
    my ($self, $current_y) = @_;

    return if $self->{is_auto_scale};
    return unless defined $current_y;
    return unless defined $self->{drag_start_y};
    return unless defined $self->{drag_start_min_y} && defined $self->{drag_start_max_y};

    my $range = $self->{drag_start_max_y} - $self->{drag_start_min_y};
    return if $range <= 0;

    my (undef, $height) = $self->_canvas_size($self->{price_canvas});
    return if $height <= 0;

    my $dy = $current_y - $self->{drag_start_y};
    return if $dy == 0;

    my $delta_value = $dy * ($range / $height);
    $self->{manual_min_y} = $self->{drag_start_min_y} + $delta_value;
    $self->{manual_max_y} = $self->{drag_start_max_y} + $delta_value;
}

sub _apply_atr_vertical_drag_from_start {
    my ($self, $current_y) = @_;

    return if $self->{is_atr_auto_scale};
    return unless defined $current_y;
    return unless defined $self->{drag_start_y};
    return unless defined $self->{atr_drag_start_min_y} && defined $self->{atr_drag_start_max_y};

    my $range = $self->{atr_drag_start_max_y} - $self->{atr_drag_start_min_y};
    return if $range <= 0;

    my (undef, $height) = $self->_canvas_size($self->{atr_canvas});
    return if $height <= 0;

    my $dy = $current_y - $self->{drag_start_y};
    return if $dy == 0;

    my $delta_value = $dy * ($range / $height);
    $self->{atr_manual_min_y} = $self->{atr_drag_start_min_y} + $delta_value;
    $self->{atr_manual_max_y} = $self->{atr_drag_start_max_y} + $delta_value;
}

sub _start_price_axis_drag {
    my ($self, $widget, $y) = @_;

    $self->_clear_ctrl_zoom_state();
    $self->_set_cursor($widget, 'sb_v_double_arrow');
    my $root_y = eval { $widget->pointery() };
    $self->{axis_drag_start_y} = defined $root_y ? $root_y : $y;

    my $scale = $self->{price_panel} ? $self->{price_panel}->{scale} : undef;
    my $min = defined $self->{manual_min_y} ? $self->{manual_min_y} : (defined $scale ? $scale->{min_y} : undef);
    my $max = defined $self->{manual_max_y} ? $self->{manual_max_y} : (defined $scale ? $scale->{max_y} : undef);
    return unless defined $min && defined $max && $max > $min;

    $self->{axis_drag_min_y} = $min;
    $self->{axis_drag_max_y} = $max;
}

sub _on_price_axis_drag {
    my ($self, $widget, $y) = @_;

    return unless defined $self->{axis_drag_start_y};
    return unless defined $self->{axis_drag_min_y} && defined $self->{axis_drag_max_y};

    my $root_y = eval { $widget->pointery() };
    my $current_y = defined $root_y ? $root_y : $y;
    return unless defined $current_y;

    my $dy = $current_y - $self->{axis_drag_start_y};
    my $min = $self->{axis_drag_min_y};
    my $max = $self->{axis_drag_max_y};
    my $center = ($min + $max) / 2;
    my $half = ($max - $min) / 2;

    my $factor = exp($dy / 220);
    $factor = 0.000001 if $factor < 0.000001;
    $half *= $factor;

    $self->{manual_min_y} = $center - $half;
    $self->{manual_max_y} = $center + $half;
    if ($self->{is_auto_scale}) {
        $self->set_scale_mode('manual');
    } else {
        $self->request_render();
    }
}

sub _end_price_axis_drag {
    my ($self) = @_;

    $self->_set_cursor($self->{price_axis_canvas}, 'sb_v_double_arrow');
    $self->{axis_drag_start_y} = undef;
    $self->{axis_drag_min_y} = undef;
    $self->{axis_drag_max_y} = undef;
}

sub _start_atr_axis_drag {
    my ($self, $widget, $y) = @_;

    $self->_clear_ctrl_zoom_state();
    $self->_set_cursor($widget, 'sb_v_double_arrow');
    my $root_y = eval { $widget->pointery() };
    $self->{atr_axis_drag_start_y} = defined $root_y ? $root_y : $y;

    my $scale = $self->{atr_panel} ? $self->{atr_panel}->{scale} : undef;
    my $min = defined $self->{atr_manual_min_y} ? $self->{atr_manual_min_y} : (defined $scale ? $scale->{min_y} : undef);
    my $max = defined $self->{atr_manual_max_y} ? $self->{atr_manual_max_y} : (defined $scale ? $scale->{max_y} : undef);
    return unless defined $min && defined $max && $max > $min;

    $self->{atr_axis_drag_min_y} = $min;
    $self->{atr_axis_drag_max_y} = $max;
}

sub _on_atr_axis_drag {
    my ($self, $widget, $y) = @_;

    return unless defined $self->{atr_axis_drag_start_y};
    return unless defined $self->{atr_axis_drag_min_y} && defined $self->{atr_axis_drag_max_y};

    my $root_y = eval { $widget->pointery() };
    my $current_y = defined $root_y ? $root_y : $y;
    return unless defined $current_y;

    my $dy = $current_y - $self->{atr_axis_drag_start_y};
    my $min = $self->{atr_axis_drag_min_y};
    my $max = $self->{atr_axis_drag_max_y};
    my $center = ($min + $max) / 2;
    my $half = ($max - $min) / 2;

    my $factor = exp($dy / 220);
    $factor = 0.000001 if $factor < 0.000001;
    $half *= $factor;

    $self->{atr_manual_min_y} = $center - $half;
    $self->{atr_manual_max_y} = $center + $half;
    if ($self->{is_atr_auto_scale}) {
        $self->set_atr_scale_mode('manual');
    } else {
        $self->request_render();
    }
}

sub _end_atr_axis_drag {
    my ($self) = @_;

    $self->_set_cursor($self->{atr_axis_canvas}, 'sb_v_double_arrow');
    $self->{atr_axis_drag_start_y} = undef;
    $self->{atr_axis_drag_min_y} = undef;
    $self->{atr_axis_drag_max_y} = undef;
}

sub _reset_atr_scale {
    my ($self) = @_;

    $self->set_atr_scale_mode('auto');
}

sub set_atr_scale_mode {
    my ($self, $mode) = @_;

    return unless defined $mode && ($mode eq 'auto' || $mode eq 'manual');
    if ($mode eq 'auto') {
        $self->{is_atr_auto_scale} = 1;
        $self->{atr_manual_min_y} = undef;
        $self->{atr_manual_max_y} = undef;
    } else {
        $self->{is_atr_auto_scale} = 0;
    }

    if (ref($self->{atr_scale_mode_callback}) eq 'CODE') {
        $self->{atr_scale_mode_callback}->($mode);
    }

    $self->request_render();
}

sub set_scale_mode {
    my ($self, $mode) = @_;

    return unless defined $mode && ($mode eq 'auto' || $mode eq 'manual');

    if ($mode eq 'auto') {
        $self->{is_auto_scale} = 1;
        $self->{manual_min_y} = undef;
        $self->{manual_max_y} = undef;
    } else {
        $self->{is_auto_scale} = 0;
    }

    if (ref($self->{scale_mode_callback}) eq 'CODE') {
        $self->{scale_mode_callback}->($mode);
    }

    $self->request_render();
}

sub _on_resize {
    my ($self, $widget) = @_;

    return if $self->{_resize_pending};
    $self->{_resize_pending} = 1;
    my $canvas = $self->{price_canvas} || $widget;
    if ($canvas) {
        $canvas->after(60, sub {
            $self->{_resize_pending} = 0;
            $self->request_render();
        });
        return;
    }
    $self->{_resize_pending} = 0;
    $self->request_render();
}

sub _end_drag {
    my ($self) = @_;

    if (defined $self->{drag_cursor_canvas}) {
        $self->_set_cursor($self->{drag_cursor_canvas}, 'crosshair');
    }
    $self->{drag_start_x} = undef;
    $self->{drag_start_y} = undef;
    $self->{drag_start_panel} = undef;
    $self->{drag_start_min_y} = undef;
    $self->{drag_start_max_y} = undef;
    $self->{atr_drag_start_min_y} = undef;
    $self->{atr_drag_start_max_y} = undef;
    $self->{drag_start_offset} = undef;
    $self->{drag_start_x_shift} = undef;
    $self->{drag_cursor_canvas} = undef;
}

sub _vertical_drag {
    my ($self, $dy) = @_;

    return if $self->{is_auto_scale};
    return if !$dy || $dy == 0;

    my $price_scale = $self->{price_panel}->{scale};
    return if !defined $price_scale;

    my $val_at_zero = $price_scale->y_to_value(0);
    my $val_at_one  = $price_scale->y_to_value(1);
    my $units_per_pixel = $val_at_zero - $val_at_one;

    my $value_delta = $dy * $units_per_pixel;

    $self->{manual_min_y} += $value_delta;
    $self->{manual_max_y} += $value_delta;

    $self->request_render();
}

sub _vertical_zoom {
    my ($self, $factor) = @_;

    return if $self->{is_auto_scale};
    return if !$factor || $factor <= 0;

    my $min = $self->{manual_min_y};
    my $max = $self->{manual_max_y};
    return if !defined $min || !defined $max;

    my $center = ($min + $max) / 2;
    my $half_range = ($max - $min) / 2;

    $half_range *= $factor;

    $self->{manual_min_y} = $center - $half_range;
    $self->{manual_max_y} = $center + $half_range;

    $self->request_render();
}

sub _atr_vertical_drag {
    my ($self, $dy) = @_;

    return if $self->{is_atr_auto_scale};
    return if !$dy || $dy == 0;

    my $atr_scale = $self->{atr_panel}->{scale};
    return if !defined $atr_scale;

    my $val_at_zero = $atr_scale->y_to_value(0);
    my $val_at_one  = $atr_scale->y_to_value(1);
    my $units_per_pixel = $val_at_zero - $val_at_one;

    my $value_delta = $dy * $units_per_pixel;

    $self->{atr_manual_min_y} += $value_delta;
    $self->{atr_manual_max_y} += $value_delta;

    $self->request_render();
}

sub _atr_vertical_zoom {
    my ($self, $factor) = @_;

    return if $self->{is_atr_auto_scale};
    return if !$factor || $factor <= 0;

    my $min = $self->{atr_manual_min_y};
    my $max = $self->{atr_manual_max_y};
    return if !defined $min || !defined $max;

    my $center = ($min + $max) / 2;
    my $half_range = ($max - $min) / 2;

    $half_range *= $factor;

    $self->{atr_manual_min_y} = $center - $half_range;
    $self->{atr_manual_max_y} = $center + $half_range;

    $self->request_render();
}

sub _snap_crosshair_x {
    my ($self, $raw_x) = @_;

    return undef unless defined $raw_x;
    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    return $self->round($raw_x) if $bars < 1;

    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});
    $scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;
    my $local = $scale->x_to_index($raw_x);
    return $self->round($scale->index_to_center_x($local));
}

sub _on_mouse_move {
    my ($self, $widget, $raw_x, $raw_y) = @_;
    
    return if !defined $raw_x || !defined $raw_y;
    
    my $pixel_x = $self->_snap_crosshair_x($raw_x);
    my $pixel_y = $self->round($raw_y);
    
    $self->{last_mouse_x} = $pixel_x;
    $self->{last_mouse_y} = $pixel_y;
    $self->{active_canvas} = $widget;
    
    $self->_draw_crosshair_all();
    $self->_draw_pointer_symbol($widget, $pixel_x, $pixel_y, 'cross');
}

# _crosshair_time_label — etiqueta de fecha estilo TradingView (Dow DD Mon 'YY) de la vela bajo el cursor (Req. 7.4, spec 0000).
#
# Calcula el índice de dato bajo el cursor a partir de la posición horizontal
# almacenada en $self->{last_mouse_x}. Toda conversión X->índice vive en Scales
# (regla de oro de coordenadas): se instancia un Market::Panels::Scales con los
# mismos parámetros que usan render()/compute_intraday_labels —bars = nº de velas
# visibles (end - start + 1 de compute_window), right_margin => RIGHT_MARGIN y el
# ancho real del canvas de precios— y se usa x_to_index para obtener el índice
# LOCAL dentro de la ventana visible.
#
# El índice LOCAL se convierte a GLOBAL sumando 'start' (inicio de la ventana):
#   global = start + local
# Con ese índice global se obtiene el timestamp de MarketData (get_timestamp), se
# parsea con Time::Moment y se formatea como fecha+hora TradingView
# 'Dow DD Mon 'YY HH:MM' (p.ej. "Thu 23 Apr '26 09:31") reutilizando el helper
# _crosshair_date_label($tm) como prefijo de fecha y añadiendo HH:MM (spec 0000c).
#
# Devuelve la cadena 'Dow DD Mon 'YY HH:MM', o undef si:
#   * no hay cursor (last_mouse_x indefinido),
#   * la ventana visible no tiene barras,
#   * el índice global queda fuera del rango real de datos, o
#   * el timestamp no existe / no es parseable por Time::Moment.
sub _crosshair_time_label {
    my ($self) = @_;

    my $last_x = $self->{last_mouse_x};
    return undef unless defined $last_x;          # sin cursor => sin etiqueta

    # Ventana visible en índices GLOBALES; 'start' mapea local -> global.
    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    return undef if $bars < 1;                    # ventana vacía => sin etiqueta

    # Escala SOLO para convertir X -> índice (regla de oro: conversión en Scales).
    # Mismos parámetros que render()/compute_intraday_labels: right_margin reservado
    # y el ancho real del canvas de precios (bar_w = plot_width / bars).
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});
    $scale->{x_shift} = $self->{ctrl_zoom_x_shift} || 0;

    # X -> índice LOCAL (acotado por Scales a [0, bars-1]) -> índice GLOBAL.
    my $local  = $scale->x_to_index($last_x);
    my $global = $start + $local;

    # Defensa adicional: el índice global debe caer en el rango real de datos.
    my $size = $self->{market_data}->size();
    return undef if $global < 0 || $global >= $size;

    # Timestamp de MarketData -> Time::Moment -> 'Dow DD Mon 'YY HH:MM' (spec 0000c).
    my $ts = $self->{market_data}->get_timestamp($global);
    return undef unless defined $ts;
    my $tm = eval { Time::Moment->from_string($ts) };
    return undef unless $tm;

    my $date = $self->_crosshair_date_label($tm);
    return undef unless defined $date;
    return sprintf("%s %02d:%02d", $date, $tm->hour, $tm->minute);
}

sub _draw_crosshair_all {
    my ($self) = @_;

    my $last_x = $self->{last_mouse_x};
    my $last_y = $self->{last_mouse_y};

    if (!defined $last_x) {
        # Cursor fuera: limpiar el crosshair y la etiqueta de tiempo en ambos
        # paneles. Contrato acordado con la tarea 6.2 para PricePanel:
        # draw_crosshair($x, $y, $time_text) -> con todo undef se borra también la
        # etiqueta de tiempo. El ATRPanel conserva su firma de 2 argumentos.
        $self->{price_panel}->draw_crosshair(undef, undef, undef);
        $self->{atr_panel}->draw_crosshair(undef, undef);
        $self->_draw_price_axis_crosshair(undef);
        $self->_draw_atr_axis_crosshair(undef);
        # spec 0000d: limpiar la etiqueta del crosshair temporal del canvas del eje.
        if (defined $self->{time_axis_canvas}) {
            $self->{time_axis_canvas}->delete('time_axis_crosshair');
        }
        return;
    }

    my $price_y = undef;
    my $atr_y = undef;

    if (defined $self->{active_canvas} && defined $self->{time_axis_canvas} && $self->{active_canvas} == $self->{time_axis_canvas}) {
        $price_y = undef;
        $atr_y = undef;
    } elsif (defined $self->{active_canvas} && $self->{active_canvas} == $self->{atr_canvas}) {
        $atr_y = $last_y;
    } else {
        $price_y = $last_y;
    }

    # Etiqueta de tiempo (HH:MM) de la vela bajo el cursor; undef si no aplica.
    my $time_text = $self->_crosshair_time_label();

    # PricePanel recibe la etiqueta de tiempo como TERCER argumento (Req. 7.4):
    # draw_crosshair($x, $y, $time_text). El ATRPanel mantiene su firma de 2
    # argumentos (NO recibe etiqueta de tiempo); la X sigue sincronizada entre
    # ambos paneles porque comparten $last_x.
    # spec 0000d: si existe time_axis_canvas, la caja de tiempo se dibuja ahí
    # (draw_time_crosshair_label), no en el price_canvas.
    if (defined $self->{time_axis_canvas}) {
        $self->{price_panel}->draw_crosshair($last_x, $price_y, undef);
        $self->{price_panel}->draw_time_crosshair_label($self->{time_axis_canvas}, $last_x, $time_text);
    } else {
        $self->{price_panel}->draw_crosshair($last_x, $price_y, $time_text);
    }
    $self->{atr_panel}->draw_crosshair($last_x, $atr_y);
    $self->_draw_price_axis_crosshair($price_y);
    $self->_draw_atr_axis_crosshair($atr_y);
}

sub set_timeframe {
    my ($self, $tf) = @_;

    # spec 0001: 8 temporalidades soportadas.
    my %valid_tf = map { $_ => 1 } qw(1m 5m 15m 1h 2h 4h D W);
    if (!$valid_tf{$tf}) {
            warn "Temporalidad '$tf' no soportada por el sistema.";
            return;
    }

    $self->{market_data}->build_tf_candles($tf) if $tf ne '1m';
    $self->{market_data}->set_timeframe($tf);
    $self->{indicator_manager}->reset_all();
    for (my $i = 0; $i < $self->{market_data}->size(); $i++) {
        $self->{indicator_manager}->update_last($self->{market_data}, $i);
    }
    # spec 0004 / task 0008: reset del indicador SMC al cambiar timeframe para
    # que el overlay se recalcule sobre la nueva serie.
    if ($self->{smc_indicator}) {
        $self->{smc_indicator}->reset();
        $self->{_smc_fed_up_to} = -1;
    }
    # spec 0005 / task 0012: reset del indicador de liquidez (mismo criterio).
    if ($self->{liq_indicator}) {
        $self->{liq_indicator}->reset();
        $self->{_liq_fed_up_to} = -1;
    }
    $self->{is_auto_scale} = 1;
    $self->{manual_min_y} = undef;
    $self->{manual_max_y} = undef;
    $self->{is_atr_auto_scale} = 1;
    $self->{atr_manual_min_y} = undef;
    $self->{atr_manual_max_y} = undef;
    if (ref($self->{atr_scale_mode_callback}) eq 'CODE') {
        $self->{atr_scale_mode_callback}->('auto');
    }
    $self->_clear_ctrl_zoom_state();
    $self->reset_view();
}

sub reset_view {
    my ($self) = @_;

    $self->{visible_bars} = 60;
    $self->{offset} = 0;
    $self->{is_auto_scale} = 1;
    $self->{manual_min_y} = undef;
    $self->{manual_max_y} = undef;
    $self->{is_atr_auto_scale} = 1;
    $self->{atr_manual_min_y} = undef;
    $self->{atr_manual_max_y} = undef;
    if (ref($self->{atr_scale_mode_callback}) eq 'CODE') {
        $self->{atr_scale_mode_callback}->('auto');
    }
    $self->_clear_ctrl_zoom_state();
    $self->request_render();
}

# compute_intraday_labels — etiquetas del eje de tiempo inferior (Req. 5.2, 5.6, 5.7,
# 5.8, 6.1, 6.2, 6.4).
#
# Produce un arrayref de etiquetas enriquecidas con la forma:
#       { index => <índice LOCAL en la ventana visible>,
#         text  => <'HH:MM' o 'DD Mon'>,
#         is_date => 0|1,
#         grid => 0|1,
#         label => 0|1 }
#
# Convención de índice (CRÍTICA): el `index` de salida es LOCAL (0-based dentro de la
# ventana visible), porque las velas se dibujan con índices locales 0..N-1 y
# PricePanel::draw_time_axis centra cada etiqueta vía Scales->index_to_center_x(index).
# El índice local se obtiene como `global - start`, robusto frente a timestamps
# omitidos (no es la posición del bucle).
#
# Espaciado temporal (Req. 5.6, spec 0000b): el eje inferior prioriza fronteras
# REALES de reloj/calendario tipo TradingView, no equidistancia por stride. Se
# escanea cada timestamp visible; un tick se selecciona si cae en una frontera
# real del intervalo elegido (HH:MM con (hour*60+minute) % interval == 0). Los
# gaps de sesión/noche/fin de semana no crean huecos visuales (las velas siguen
# por índice), pero tampoco fuerzan marcas equidistantes que pierdan coherencia
# de reloj.
#
# Cambios de día (Req. 6.1, 6.4): la fecha ("DD Mon", is_date => 1) aparece SOLO
# cuando hay cambio real de día respecto al timestamp global anterior, o cuando la
# vela cae en medianoche real (00:00) sin vela anterior. La primera vela visible a
# mitad de día NO se convierte en fecha: muestra "HH:MM".
#
# Casos límite:
#   * Ventana sin barras => lista vacía sin error (Req. 5.7).
#   * Timestamp no parseable => esa etiqueta se omite y continúan las demás (Req. 5.8;
#     get_all_timestamps ya descarta los no parseables).
sub compute_intraday_labels {
    my ($self) = @_;

    my @labels;

    # Elementos visibles: arrayref de { index => <GLOBAL>, ts => <Time::Moment> }.
    # get_all_timestamps ya descarta los timestamps no parseables (Req. 5.8).
    my $visible_elements = $self->get_all_timestamps();
    my $total = scalar(@$visible_elements);
    return \@labels if $total == 0;   # Req. 5.7: ventana sin barras => sin etiquetas.

    # Ventana visible en índices GLOBALES. 'start' permite convertir los índices
    # globales (velas y anclas de tiempo) a LOCALES (los que consume draw_time_axis).
    my ($start, $end) = $self->compute_window();
    my $bars = $end - $start + 1;
    $bars = 1 if $bars < 1;

    # Escala temporal SOLO para medir la separación en píxeles entre etiquetas.
    # Regla de oro: la conversión de coordenadas vive en Scales, así que se
    # instancia Market::Panels::Scales con el mismo right_margin que usa render()
    # y se le inyecta el ancho real del canvas de precios (bar_w = plot_width/bars).
    my $scale = Market::Panels::Scales->new(
        bars         => $bars,
        right_margin => RIGHT_MARGIN,
    );
    $scale->{width} = $self->_canvas_width($self->{price_canvas});

    # Mapa índice LOCAL => Time::Moment de cada vela visible con timestamp parseable.
    my %tm_by_local;
    for my $el (@$visible_elements) {
        $tm_by_local{ $el->{index} - $start } = $el->{ts};
    }

    my $bar_w = $bars > 0 ? $scale->plot_width() / $bars : 1;
    $bar_w = 1 if $bar_w <= 0;
    my $tf_minutes = $self->_timeframe_minutes();
    my $interval_minutes = $self->_time_axis_interval_minutes($tf_minutes, $bar_w);

    # spec 0000g: plan global de cadencia uniforme tipo TradingView.
    # Se elige UNA cadencia dominante para toda la ventana visible, no se
    # aceptan candidatos localmente por peso. Los días son anchors obligatorios
    # y las horas siguen una única cadencia. Esto evita secuencias irregulares
    # tipo DAY|HOUR|DAY|DAY|HOUR.
    # Modo A = días + horas uniformes. El modo diario es fallback incompleto.

    # Peek al timestamp pre-ventana para detectar cambio de día en el primer visible.
    my $prev_tm;
    if ($start > 0) {
        my $pre_ts = $self->{market_data}->get_timestamp($start - 1);
        $prev_tm = eval { Time::Moment->from_string($pre_ts) } if defined $pre_ts;
    }

    # Construir candidatos desde velas reales (spec 0000e/0000f: índices enteros).
    my @candidates;
    for my $el (@$visible_elements) {
        my $global = $el->{index};
        my $tm     = $el->{ts};
        next unless defined $tm;

        my $local  = $global - $start;
        my $weight = $self->_time_axis_weight_for_point($tm, $prev_tm);
        next if $weight < 21;  # skip MIN1: TradingView closest cadence is 5m
        my $text   = $self->_time_axis_label_for_weight($tm, $weight);
        next unless defined $text;

        push @candidates, {
            index         => $local,
            text          => $text,
            weight        => $weight,
            is_date       => ($weight >= 50) ? 1 : 0,
            intraday_mins => $tm->hour * 60 + $tm->minute,
            year          => $tm->year,
            month         => $tm->month,
            day           => $tm->day_of_month,
            date_ordinal  => $tm->year * 366 + $tm->day_of_year,
            grid          => 1,
            label         => 0,
            x             => $scale->index_to_center_x($local),
        };
        $prev_tm = $tm;
    }

    # Elegir el mejor plan global de cadencia (spec 0000g).
    my $plan = $self->_choose_time_axis_plan(\@candidates, $bar_w, $tf_minutes);

    # Marcar aceptados del plan con label=1; el resto queda con label=0 pero
    # grid=1 para compatibilidad con tests que inspeccionan candidatos por grid.
    # El plan puede sobrescribir texto/tipo (p.ej. día 1 -> Apr en zoom calendario).
    my %accepted = map { $_->{index} => $_ } @$plan;
    for my $cand (@candidates) {
        my $planned = $accepted{ $cand->{index} };
        if ($planned) {
            $cand->{label} = 1;
            $cand->{text} = $planned->{text} if defined $planned->{text};
            $cand->{is_date} = $planned->{is_date} if exists $planned->{is_date};
        }
        else {
            $cand->{label} = 0;
        }
    }

    for my $item (sort { $a->{index} <=> $b->{index} } @candidates) {
        push @labels, {
            index   => $item->{index},
            text    => $item->{text},
            is_date => $item->{is_date},
            grid    => $item->{grid},
            label   => $item->{label},
        };
    }

    return \@labels;
}

# _choose_time_axis_plan($candidates, $bar_w, $tf_minutes) — spec 0000g
# Elije un plan global de cadencia uniforme. Prueba cadencias de densa a
# dispersa; la primera que produce min_gap_px >= 65 y consistencia entre
# segmentos día-a-día es el plan Modo A aceptado.
# Si ninguna cadencia intradía funciona, retorna solo días (fallback incompleto).
sub _choose_time_axis_plan {
    my ($self, $candidates, $bar_w, $tf_minutes) = @_;

    # Zoom calendario: cuando el ancho por barra es mínimo y la ventana cubre
    # muchas fechas, TradingView deja de mostrar horas y usa mes + días.
    # No activar en rangos cortos 1m/5m: aunque bar_w sea bajo, allí 0000g debe
    # seguir mostrando Modo A (días + horas) si caben horas.
    my @date_candidates = grep { $_->{is_date} } @$candidates;
    if ($bar_w <= 1.15 && @date_candidates >= 20) {
        my @calendar = $self->_build_calendar_time_axis_plan($candidates, $bar_w);
        return \@calendar if @calendar >= 2;
    }

    my @cadences = (5, 15, 30, 60, 90, 180, 360, 720, 1440);
    @cadences = grep { $_ >= $tf_minutes } @cadences;

    # Similar a LWC: separar por ancho de label. 65px evita saturar 1m/5m
    # y permite 90m en NQ1!/15m cuando el canvas visible tiene ancho comparable
    # al de la app/screenshot de TradingView.
    my $min_label_px = 65;
    my $min_indices  = int(($min_label_px / $bar_w) + 0.999);
    $min_indices = 1 if $min_indices < 1;

    for my $cad (@cadences) {
        # spec 0000g: solo probar cadencias cuyo espaciado natural en píxeles
        # es >= min_label_px. Thinning de una cadencia densa crea cadencias
        # efectivas sucias (e.g. thinning 1h a cada 8h produce 08:00, no limpio).
        my $cadence_px = ($cad / $tf_minutes) * $bar_w;
        next if $cadence_px < $min_label_px;

        my @plan = $self->_build_time_axis_plan($candidates, $cad, $min_indices);
        @plan = $self->_adjust_sparse_time_axis_plan($candidates, \@plan, $cad, $tf_minutes, $min_indices);
        @plan = $self->_densify_sparse_gaps_in_time_axis_plan($candidates, \@plan, $cad, $tf_minutes, $min_indices);
        next unless @plan >= 2;

        my $min_gap = $self->_plan_min_gap_px(\@plan, $cad, $tf_minutes);
        next if !defined($min_gap) || $min_gap < $min_label_px;

        if ($self->_plan_is_consistent(\@plan, $cad, $tf_minutes)) {
            return \@plan;
        }
    }

    # Fallback: solo días (incompleto, no aceptación final de spec 0000g).
    my @daily = $self->_build_time_axis_plan($candidates, 1440, $min_indices);
    return \@daily;
}

# _build_calendar_time_axis_plan($candidates, $bar_w) — zoom calendario.
# Usa solo anchors de fecha reales: mes + días seleccionados. No muestra horas.
# Generalista: separación por ancho estimado de label (box-based), no umbral fijo.
# Los anchors de mes (Apr, May) siempre ganan frente a días cercanos.
# spec 0000i: densidad tipo TradingView — permite días consecutivos si caben.
# spec 0000j: filtra días de sesión parcial nocturna (primera vela >= 17:00)
# que TradingView no muestra como labels principales en modo calendario mensual.
sub _build_calendar_time_axis_plan {
    my ($self, $candidates, $bar_w) = @_;

    my @dates = grep { $_->{is_date} } @$candidates;
    return () unless @dates;

    my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    # spec 0000j: umbral de sesión parcial nocturna. Un día cuya primera vela
    # sea >= 17:00 (1020 min) y no tenga velas antes del mediodía es un anchor
    # débil: TradingView no lo usa como label principal en calendario mensual.
    my $NOCTURNAL_THRESHOLD_MINS = 1020;

    # Ancho estimado de cada tipo de label en píxeles.
    my $day_label_px = 20;
    my $month_label_px = 40;
    my $min_gap_px = 6;

    # spec 0000j: separación mínima entre días basada en calendario, no solo
    # en ancho de texto. Cuando se omiten días parciales (domingos nocturnos),
    # los días vecinos pueden quedar comprimidos por el gap de sesión. Exigir
    # que la separación x entre días sea >= 80% de un día calendario normal.
    # Esto evita que aparezcan días como 6 pegados a 3 tras omitir el domingo 5.
    my $normal_day_indices = 96; # ~96 barras de 15m por día con sesión completa
    my $min_day_gap_px = int($normal_day_indices * $bar_w * 0.80 + 0.5);
    $min_day_gap_px = $min_gap_px if $min_day_gap_px < $min_gap_px;

    my @calendar;
    for my $d (@dates) {
        my %cand = %$d;
        if (($cand{day} || 0) == 1 || ($cand{weight} || 0) >= 60) {
            $cand{text} = $months[($cand{month} || 1) - 1] || $cand{text};
            $cand{calendar_month_anchor} = 1;
            $cand{label_half_width} = $month_label_px / 2;
            $cand{weak_partial_session} = 0;
        }
        else {
            $cand{label_half_width} = $day_label_px / 2;
            # spec 0000j: detectar sesión parcial nocturna.
            my $first_mins = $cand{intraday_mins} // 0;
            $cand{weak_partial_session} = ($first_mins >= $NOCTURNAL_THRESHOLD_MINS) ? 1 : 0;
        }
        push @calendar, \%cand;
    }

    my @accepted;
    for my $cand (@calendar) {
        if ($cand->{calendar_month_anchor}) {
            # Mes siempre entra. Si colisiona con último día aceptado, el día se elimina.
            if (@accepted && !$accepted[-1]{calendar_month_anchor}) {
                my $half_sum = $accepted[-1]{label_half_width} + $cand->{label_half_width} + $min_gap_px;
                if ($cand->{x} - $accepted[-1]{x} < $half_sum) {
                    pop @accepted;
                }
            }
            push @accepted, $cand;
            next;
        }

        # spec 0000j: omitir días de sesión parcial nocturna en modo calendario.
        next if $cand->{weak_partial_session};

        # Día normal: aceptar si no colisiona con el último aceptado.
        if (@accepted) {
            my $last = $accepted[-1];
            if (!$last->{calendar_month_anchor}) {
                # Día-día: exigir separación calendario mínima.
                next if $cand->{x} - $last->{x} < $min_day_gap_px;
            }
            else {
                # Mes-día: separación por ancho de label.
                my $half_sum = $last->{label_half_width} + $cand->{label_half_width} + $min_gap_px;
                next if $cand->{x} - $last->{x} < $half_sum;
            }
        }
        push @accepted, $cand;
    }

    return @accepted;
}

# _build_time_axis_plan($candidates, $cadence, $min_indices) — spec 0000g
# Construye un plan con una sola cadencia: todos los anchors de día/mes/año
# + horas que satisfagan minutes % cadence == 0.
#
# Importante: dentro de UNA cadencia, las horas se aceptan cronológicamente.
# No se ordenan por peso porque eso degrada 90m a una cadencia visual de 3h
# (18:00/21:00 desplazan 19:30/22:30), distinto a TradingView en NQ1! 15m.
# Los anchors de día/mes/año siguen reemplazando el timestamp de su propia vela.
sub _build_time_axis_plan {
    my ($self, $candidates, $cadence, $min_indices) = @_;

    my @filtered;
    for my $cand (@$candidates) {
        if ($cand->{weight} >= 50) {
            push @filtered, { %$cand };
        }
        elsif ($cadence < 1440 && defined $cand->{intraday_mins}
               && $cand->{intraday_mins} % $cadence == 0) {
            push @filtered, { %$cand };
        }
    }

    my @accepted;
    for my $cand (sort { $a->{index} <=> $b->{index} } @filtered) {
        if (@accepted && $cand->{index} - $accepted[-1]{index} < $min_indices) {
            # Si el candidato actual representa una frontera temporal más importante
            # (p.ej. 01:00 sobre 00:15, o DAY/MONTH sobre hora cercana), reemplaza
            # la marca previa. Esto mantiene fronteras reales de reloj/calendario sin
            # volver al thinning global por peso que destruía la cadencia 90m.
            if (($cand->{weight} || 0) > ($accepted[-1]{weight} || 0)) {
                pop @accepted;
            }
            else {
                next;
            }
        }
        $cand->{label} = 1;
        push @accepted, $cand;
    }

    return @accepted;
}

# _adjust_sparse_time_axis_plan() — ajustes tipo TradingView en zooms lejanos.
# Generalista: parte del plan de cadencia global y, solo para cadencias intradía
# lejanas (>=12h, <1D), enriquece huecos amplios con candidatos reales de alta
# jerarquía (HOUR12/HOUR6/HOUR3) si respetan separación. No hardcodea fechas ni
# horas específicas: la hora elegida sale de pesos temporales + espacio disponible.
sub _adjust_sparse_time_axis_plan {
    my ($self, $candidates, $plan, $cadence, $tf_minutes, $min_indices) = @_;
    return @$plan if !defined($cadence) || $cadence < 720 || $cadence >= 1440 || !$plan || !@$plan;

    my @out = map { { %$_ } } @$plan;
    my $natural_indices = (defined $tf_minutes && $tf_minutes > 0)
        ? int(($cadence / $tf_minutes) + 0.999)
        : 0;
    my $compressed_gap_limit = $natural_indices + int($natural_indices / 2 + 0.999);

    # Si hay DAY|DAY comprimido por sesión/weekend, el segundo DAY puede ocultarse
    # para dejar que el intervalo respire con horas intradía reales. Esto replica la
    # compresión lógica de TradingView sin inventar puntos.
    my %drop_index;
    my @dropped_dates;
    for (my $i = 1; $i < @out; $i++) {
        my $left  = $out[$i - 1];
        my $right = $out[$i];
        next unless $left->{is_date} && $right->{is_date};
        next unless $natural_indices > 0 && ($right->{index} - $left->{index}) <= $compressed_gap_limit;

        my $next = $out[$i + 1];
        next unless $next;
        my @inside = grep {
            !$_->{is_date}
            && ($_->{weight} || 0) >= 31
            && $_->{index} > $right->{index}
            && $_->{index} < $next->{index}
            && $_->{index} - $left->{index} >= $min_indices
            && $next->{index} - $_->{index} >= $min_indices
        } @$candidates;
        if (@inside) {
            $drop_index{ $right->{index} } = 1;
            push @dropped_dates, { %$right };
        }
    }
    @out = grep { !$drop_index{ $_->{index} } } @out;

    my %selected = map { $_->{index} => 1 } @out;
    my @extra;

    my $try_add_between = sub {
        my ($left, $right) = @_;
        my $left_idx  = defined $left  ? $left->{index}  : -1;
        my $right_idx = defined $right ? $right->{index} : undef;
        return unless defined $right_idx;

        my @pool = grep {
            !$_->{is_date}
            && !$selected{ $_->{index} }
            && ($_->{weight} || 0) >= 31
            && $_->{index} > $left_idx
            && $_->{index} < $right_idx
        } @$candidates;

        # Igual que LWC: pesos mayores primero; luego orden cronológico. La separación
        # final evita saturar y determina si queda HOUR12, HOUR6 o HOUR3.
        for my $cand (sort { ($b->{weight} || 0) <=> ($a->{weight} || 0) || $a->{index} <=> $b->{index} } @pool) {
            my $ok = 1;
            for my $s (@out, @extra) {
                if (abs($cand->{index} - $s->{index}) < $min_indices) {
                    $ok = 0;
                    last;
                }
            }
            next unless $ok;
            push @extra, { %$cand };
            $selected{ $cand->{index} } = 1;
        }
    };

    # Borde izquierdo. Esto añade labels como 03:00 solo cuando realmente caben
    # antes del primer hito fuerte.
    $try_add_between->(undef, $out[0]) if @out;

    # Huecos internos: solo rellenar el intervalo que contiene un DAY comprimido
    # ocultado. No llenar cualquier DAY|DAY, porque TradingView mantiene huecos
    # como 24|26 sin insertar una hora artificial.
    for my $dropped (@dropped_dates) {
        my ($left, $right);
        for my $item (@out) {
            $left = $item if $item->{index} < $dropped->{index};
            if ($item->{index} > $dropped->{index}) {
                $right = $item;
                last;
            }
        }
        $try_add_between->($left, $right) if $left && $right;
    }

    return sort { $a->{index} <=> $b->{index} } (@out, @extra);
}

# _densify_sparse_gaps_in_time_axis_plan() — spec 0000h.
# Después de construir un plan intradía válido, mide los huecos visuales entre
# labels consecutivos. Si un hueco es demasiado grande (> 1.5x la cadencia
# natural), intenta insertar un candidato real existente que reduzca el hueco
# sin colisionar. El caso 14:30 entre 12:00 y 18:00 sale de esta regla general,
# no de hardcodear la fecha/hora.
sub _densify_sparse_gaps_in_time_axis_plan {
    my ($self, $candidates, $plan, $cadence, $tf_minutes, $min_indices) = @_;
    return @$plan if !defined($cadence) || $cadence >= 1440 || !$plan || @$plan < 2;

    my @out = map { { %$_ } } @$plan;
    my $natural_indices = int(($cadence / $tf_minutes) + 0.999);
    my $gap_threshold = int($natural_indices * 1.5 + 0.999);

    my %selected = map { $_->{index} => 1 } @out;
    my @extra;

    for (my $i = 0; $i < $#out; $i++) {
        my $left  = $out[$i];
        my $right = $out[$i + 1];
        my $gap = $right->{index} - $left->{index};
        next if $gap <= $gap_threshold;

        # No densificar gaps entre dos anchors de día (session/weekend gaps).
        next if $left->{is_date} && $right->{is_date};

        my @pool = grep {
            !$selected{$_->{index}}
            && !$_->{is_date}
            && ($_->{weight} || 0) >= 22
            && $_->{index} > $left->{index}
            && $_->{index} < $right->{index}
            && $_->{index} - $left->{index} >= $min_indices
            && $right->{index} - $_->{index} >= $min_indices
        } @$candidates;

        next unless @pool;

        my $midpoint = ($left->{index} + $right->{index}) / 2;
        my $best;
        my $best_score;
        for my $cand (@pool) {
            my $dist_from_mid = abs($cand->{index} - $midpoint);
            my $score = -$dist_from_mid * 10 + ($cand->{weight} || 0);
            if (!defined $best_score || $score > $best_score) {
                $best = { %$cand };
                $best_score = $score;
            }
        }

        if ($best) {
            $best->{label} = 1;
            $selected{$best->{index}} = 1;
            push @extra, $best;
        }
    }

    return sort { $a->{index} <=> $b->{index} } (@out, @extra);
}

# _plan_min_gap_px($plan) — spec 0000g
# Retorna el menor gap en píxeles entre labels consecutivos del plan.
sub _plan_min_gap_px {
    my ($self, $plan, $cadence, $tf_minutes) = @_;
    return undef if @$plan < 2;
    my $min;
    my $natural_indices = (defined $cadence && defined $tf_minutes && $tf_minutes > 0)
        ? int(($cadence / $tf_minutes) + 0.999)
        : 0;
    for my $i (1 .. $#$plan) {
        my $left  = $plan->[$i - 1];
        my $right = $plan->[$i];
        # Igual que TradingView, no invalidar el plan por anchors de día pegados
        # cuando el gap de mercado está comprimido por índice lógico (ej. 26|27).
        my $compressed_gap_limit = $natural_indices + int($natural_indices / 2 + 0.999);
        next if $natural_indices > 0
             && $left->{is_date} && $right->{is_date}
             && ($right->{index} - $left->{index}) <= $compressed_gap_limit;
        my $gap = $right->{x} - $left->{x};
        $min = $gap if !defined($min) || $gap < $min;
    }
    return $min;
}

# _plan_is_consistent($plan) — spec 0000g
# Verifica que no haya patrón DAY|HOUR|DAY|DAY|HOUR en segmentos internos.
# Los gaps de sesión (días consecutivos sin horas entre ellos) son excepciones
# aceptables solo en bordes. La inconsistencia se detecta cuando un segmento
# interno tiene 0 horas mientras otros tienen >0.
# También rechaza planes con 1 sola hora perdida entre muchos días (no es Modo A).
sub _plan_is_consistent {
    my ($self, $plan, $cadence, $tf_minutes) = @_;

    my @day_pos;
    for my $i (0 .. $#$plan) {
        push @day_pos, $i if $plan->[$i]{is_date};
    }

    return 1 if @day_pos < 2;

    my @hour_counts;
    for my $i (1 .. $#day_pos) {
        push @hour_counts, $day_pos[$i] - $day_pos[$i - 1] - 1;
    }

    my $has_hours = grep { $_ > 0 } @hour_counts;
    my $has_zero  = grep { $_ == 0 } @hour_counts;

    # spec 0000g: si hay horas pero son muy pocas frente a muchos días, no es Modo A.
    # En zooms más alejados TradingView sí acepta ~1 hora por día (p.ej. 12:00),
    # así que solo rechazamos planes realmente pobres: menos de media hora visible
    # por anchor de día.
    my $total_hours = grep { !$_->{is_date} } @$plan;
    if (@day_pos >= 3 && $total_hours > 0 && $total_hours < int(@day_pos / 2)) {
        return 0;
    }

    return 1 if !$has_hours || !$has_zero;

    # Hay mezcla: algunos segmentos con horas, otros sin.
    # Segmentos internos (no borde) con 0 horas son inconsistentes salvo
    # que los días estén tan cerca que no quepa ninguna hora (gap de sesión).
    for my $i (0 .. $#hour_counts) {
        next if $i == 0 && $hour_counts[0] == 0;  # borde izquierdo
        next if $i == $#hour_counts && $hour_counts[-1] == 0;  # borde derecho
        if ($hour_counts[$i] == 0 && $has_hours) {
            my $left  = $plan->[ $day_pos[$i] ];
            my $right = $plan->[ $day_pos[$i + 1] ];
            my $natural_indices = (defined $cadence && defined $tf_minutes && $tf_minutes > 0)
                ? int(($cadence / $tf_minutes) + 0.999)
                : 0;
            # TradingView comprime gaps de sesión/weekend por índice lógico: dos días
            # pueden quedar muy juntos (p.ej. 26|27) y no por eso debe caerse a
            # modo diario. Si entre ambos anchors no cabría ni una marca de la
            # cadencia elegida, se permite como gap comprimido interno.
            my $compressed_gap_limit = $natural_indices + int($natural_indices / 2 + 0.999);
            next if $natural_indices > 0 && ($right->{index} - $left->{index}) <= $compressed_gap_limit;
            return 0;
        }
    }

    return 1;
}

# debug_time_axis_snapshot() — wrapper mínimo hacia módulo removible de debug.
# La lógica profesional vive en Market/Debug/TimeAxisSnapshot.pm para poder
# eliminar/omitir el sistema de diagnóstico sin mezclarlo con el motor principal.
sub debug_time_axis_snapshot {
    my ($self, %opts) = @_;
    require Market::Debug::TimeAxisSnapshot;
    if (exists $opts{timeframe} || exists $opts{start_ts} || exists $opts{end_ts}
        || exists $opts{start_index} || exists $opts{end_index} || exists $opts{visible_bars}) {
        return Market::Debug::TimeAxisSnapshot->capture_range($self, %opts);
    }
    return Market::Debug::TimeAxisSnapshot->capture($self, %opts);
}

# _time_axis_weight_for_point($tm, $prev_tm) — spec 0000f
# Asigna un peso temporal comparando el timestamp actual con el anterior real.
# Inspirado en lightweight-charts/time-scale-point-weight-generator.ts.
# Pesos: YEAR=70, MONTH=60, DAY=50, HOUR12=33, HOUR6=32, HOUR3=31,
# HOUR1=30, MIN90=29, MIN30=22, MIN15=21.5, MIN5=21, MIN1=20.
sub _time_axis_weight_for_point {
    my ($self, $tm, $prev_tm) = @_;

    if (defined $prev_tm) {
        return 70 if $tm->year != $prev_tm->year;
        return 60 if $tm->month != $prev_tm->month;
        return 50 if $tm->day_of_month != $prev_tm->day_of_month;
    }
    elsif ($tm->hour == 0 && $tm->minute == 0) {
        return 50;
    }

    my $m = $tm->hour * 60 + $tm->minute;
    return 33   if $m % 720 == 0;
    return 32   if $m % 360 == 0;
    return 31   if $m % 180 == 0;
    return 30   if $m % 60  == 0;
    return 29   if $m % 90  == 0;
    return 22   if $m % 30  == 0;
    return 21.5 if $m % 15  == 0;
    return 21   if $m % 5   == 0;
    return 20;
}

# _time_axis_label_for_weight($tm, $weight) — spec 0000f
# Formatea el texto del label del eje inferior según el peso temporal.
# YEAR => "2026", MONTH => "Apr", DAY => "15", intradía => "HH:MM".
sub _time_axis_label_for_weight {
    my ($self, $tm, $weight) = @_;

    return undef unless defined $tm && ref($tm) eq 'Time::Moment';

    if ($weight >= 70) {
        return sprintf("%04d", $tm->year);
    }
    elsif ($weight >= 60) {
        my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
        return $months[$tm->month - 1];
    }
    elsif ($weight >= 50) {
        return sprintf("%d", $tm->day_of_month);
    }
    return sprintf("%02d:%02d", $tm->hour, $tm->minute);
}

# _time_label_for_index($tm, $is_date) — formatea el texto de UNA etiqueta del eje
# de tiempo (Req. 5.2, 5.8, 6.4).
#
# Firma elegida: recibe el objeto Time::Moment YA PARSEADO ($tm) y el flag $is_date.
# Se opta por el objeto (en vez del string ISO o el índice) porque
# compute_intraday_labels ya dispone de los Time::Moment construidos por
# get_all_timestamps; así se evita re-parsear y se centraliza la validación.
#
# Formato de salida:
#   * $is_date verdadero => fecha corta "DD Mon": día con dos dígitos (cero a la
#     izquierda) y abreviatura de mes en inglés de 3 letras, p.ej. "18 May".
#   * $is_date falso     => hora "HH:MM" en 24h con cero a la izquierda, rango
#     "00:00".."23:59", p.ej. "09:05".
#
# Devuelve undef si $tm no es un Time::Moment utilizable (timestamp no parseable),
# para que el llamador omita esa etiqueta y continúe con las demás (Req. 5.8).
sub _is_time_axis_boundary {
    my ($self, $tm, $interval_minutes) = @_;

    return 0 unless defined $tm && ref($tm) eq 'Time::Moment';
    return 0 unless defined $interval_minutes && $interval_minutes > 0;

    if ($interval_minutes < 1440) {
        my $minutes = $tm->hour * 60 + $tm->minute;
        return ($minutes % $interval_minutes) == 0 ? 1 : 0;
    }

    return $tm->hour == 0 && $tm->minute == 0 ? 1 : 0;
}

sub _time_axis_interval_minutes {
    my ($self, $tf_minutes, $bar_w) = @_;

    # Escaleras por fronteras reales tipo TradingView (spec 0000b). Cada candidato
    # es >= tf_minutes y divisible por tf_minutes (salvo 90m que es multiple de
    # 1/5/15). 5m omite 720/12h: el usuario observó que de 6h pasa a dias. 15m
    # añade 2880/4320 (2D/3D) en zoom muy lejano. Las ramas 1h/2h/4h/D/W quedan
    # preparadas para Fase 2 (no se invocan hoy porque _timeframe_minutes solo
    # devuelve 1/5/15).
    my @ladder;
    if    ($tf_minutes == 1)     { @ladder = (1, 5, 15, 30, 60, 90, 180, 360, 720, 1440, 10080, 43200, 525600); }
    elsif ($tf_minutes == 5)     { @ladder = (5, 15, 30, 60, 90, 180, 360, 1440, 10080, 43200, 525600); }
    elsif ($tf_minutes == 15)    { @ladder = (15, 30, 60, 90, 180, 360, 1440, 2880, 4320, 10080, 43200, 525600); }
    elsif ($tf_minutes == 60)    { @ladder = (60, 180, 360, 720, 1440, 10080, 43200, 525600); }
    elsif ($tf_minutes == 120)   { @ladder = (120, 240, 360, 720, 1440, 10080, 43200, 525600); }
    elsif ($tf_minutes == 240)   { @ladder = (240, 720, 1440, 10080, 43200, 525600); }
    elsif ($tf_minutes == 1440)  { @ladder = (1440, 10080, 43200, 129600, 259200, 525600); }
    elsif ($tf_minutes == 10080) { @ladder = (10080, 43200, 129600, 259200, 525600); }
    else                         { @ladder = (1, 5, 15, 30, 60, 90, 180, 360, 720, 1440, 10080, 43200, 525600); }

    my $target_px = 100;
    for my $interval (@ladder) {
        next if $interval < $tf_minutes;
        my $px = ($interval / $tf_minutes) * $bar_w;
        return $interval if $px >= $target_px;
    }
    return $ladder[-1];
}

sub _time_label_for_index {
    my ($self, $tm, $is_date) = @_;

    return undef unless defined $tm && ref($tm) eq 'Time::Moment';

    if ($is_date) {
        my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
        my $mon = $months[ $tm->month - 1 ];
        return undef unless defined $mon;          # mes fuera de rango (defensivo)
        return sprintf("%02d %s", $tm->day_of_month, $mon);
    }

    return sprintf("%02d:%02d", $tm->hour, $tm->minute);
}

# _local_abs_minutes($tm) — minutos absolutos en zona horaria local del timestamp.
# Usado por compute_intraday_labels para detectar fronteras de reloj entre dos
# timestamps cuando hay un gap de datos (spec 0000c). Es monótono en tiempo local
# y alineado a medianoche local: como 1440 es divisible por todos los intervalos
# intradía usados, los múltiplos de interval_minutes caen en fronteras de reloj.
sub _local_abs_minutes {
    my ($self, $tm) = @_;
    return (($tm->year * 366 + $tm->day_of_year) * 1440 + $tm->hour * 60 + $tm->minute);
}

# _crosshair_date_label($tm) — etiqueta inferior del crosshair estilo TradingView
# (spec 0000): 'Dow DD Mon 'YY', p.ej. "Thu 23 Apr '26".
# Time::Moment->day_of_week es ISO 8601 (1=Lun .. 7=Dom), verificado con prueba
# mínima sobre 2026-04-23 (dow=4 => Thu).
sub _crosshair_date_label {
    my ($self, $tm) = @_;

    return undef unless defined $tm && ref($tm) eq 'Time::Moment';

    my @dow = qw(Mon Tue Wed Thu Fri Sat Sun);
    my @mon = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my $dow = $dow[ $tm->day_of_week - 1 ];
    my $mon = $mon[ $tm->month - 1 ];
    return undef unless defined $dow && defined $mon;

    return sprintf("%s %02d %s '%02d", $dow, $tm->day_of_month, $mon, $tm->year % 100);
}

sub get_all_timestamps {
    my ($self) = @_;

    my ($start, $end) = $self->compute_window();
    my @timestamps;
    my $last_index = eval { $self->{market_data}->last_index() };
    $last_index = ($self->{market_data}->size() || 0) - 1 if !defined $last_index;
    my $last_ts = $last_index >= 0 ? $self->{market_data}->get_timestamp($last_index) : undef;
    my $last_tm = defined $last_ts ? eval { Time::Moment->from_string($last_ts) } : undef;
    my $tf_minutes = $self->_timeframe_minutes();

    for (my $i = $start; $i <= $end; $i++) {
        my $ts = ($i >= 0 && $i <= $last_index) ? $self->{market_data}->get_timestamp($i) : undef;
        if (defined $ts) {
            my $parsed = eval { Time::Moment->from_string($ts) };
            push @timestamps, { index => $i, ts => $parsed } if $parsed;
        }
        elsif (defined $last_tm && $i > $last_index) {
            my $future = eval { $last_tm->plus_minutes(($i - $last_index) * $tf_minutes) };
            push @timestamps, { index => $i, ts => $future } if $future;
        }
    }

    return \@timestamps;

}

sub _timeframe_minutes {
    my ($self) = @_;

    my $tf = eval { $self->{market_data}->{active_tf} } || '1m';
    return 5    if $tf eq '5m';
    return 15   if $tf eq '15m';
    return 60   if $tf eq '1h';
    return 120  if $tf eq '2h';
    return 240  if $tf eq '4h';
    return 1440 if $tf eq 'D';
    return 10080 if $tf eq 'W';
    return 1;
}
1;
