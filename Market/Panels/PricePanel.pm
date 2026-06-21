package Market::Panels::PricePanel;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        %args,
    };
    # El tema (paleta clara) se inyecta vía `theme => \%theme` desde ChartEngine.
    # Garantizar robustez: si no llega, dejar un hashref vacío para que las lecturas
    # posteriores (con defaults //) sean seguras.
    $self->{theme} = {} unless defined $self->{theme};
    bless $self, $class;
    return $self;
}

# Inicializa los IDs de los objetos Tk del crosshair en undef.
sub _init_crosshair_objects {
    my ($self) = @_;
    $self->{_ch_vline}    = undef;
    $self->{_ch_hline}    = undef;
    $self->{_ch_label}    = undef;
    $self->{_ch_label_bg} = undef;
}

# Redondeo auxiliar al entero más cercano.
sub round {
    my ($self, $value) = @_;
    return 0 unless defined $value;
    return int($value + ($value >= 0 ? 0.5 : -0.5));
}

sub _canvas_size {
    my ($self, $canvas) = @_;
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

# Calcula el rango de precios (min, max) de las velas visibles para escalar el eje Y.
# Recibe arrayref de velas [ts, open, high, low, close, vol].
# Devuelve (min_price, max_price) con un padding del 5%.
sub get_y_range {
    my ($self, $data) = @_;
    return (20000, 30000) if !$data || !@$data;

    my @defined = grep { defined $_ } @$data;
    return (20000, 30000) unless @defined;

    my $min = $defined[0]->[3];
    my $max = $defined[0]->[2];

    for my $candle (@defined) {
        $min = $candle->[3] if $candle->[3] < $min;
        $max = $candle->[2] if $candle->[2] > $max;
    }

    my $padding = ($max - $min) * 0.05 || 1;
    return ($min - $padding, $max + $padding);
}

# Asigna el objeto Scales a este panel.
sub set_scale {
    my ($self, $scale) = @_;
    $self->{scale} = $scale;
}

# Dibuja todas las velas japonesas visibles sobre el canvas Tk.
# Inyecta width/height del canvas en el objeto scale antes de usarlo.
# Guarda la última vela en $self->{_last_candle} para render_last_visible_price.
sub render {
    my ($self, $canvas, $data, $scale) = @_;

    my ($canvas_w, $canvas_h) = $self->_canvas_size($canvas);
    $canvas->delete('all');

    return if !$data || !@$data;

    # ChartEngine puede inyectar un ancho compartido para sincronizar X con ATR.
    $scale->{width}  ||= $canvas_w;
    $scale->{height} = $canvas_h;

    # spec 0000i: overscan. draw_start_offset permite que el slice de dibujo
    # incluya velas extra (start-1, end+1). Los índices locales negativos o
    # >= visible_count posicionan las velas overscan correctamente.
    my $draw_offset = $scale->{draw_start_offset} || 0;
    my $visible_count = $scale->{visible_count} || scalar(@$data);

    # Guardar la última vela VISIBLE (no overscan) para render_last_visible_price.
    # El último elemento visible en el slice está en índice -draw_offset + visible_count - 1.
    $self->{_last_candle} = undef;
    my $last_vis_idx = -$draw_offset + $visible_count - 1;
    $last_vis_idx = $#$data if $last_vis_idx > $#$data;
    $last_vis_idx = $#$data if $last_vis_idx < 0;
    for (my $i = $last_vis_idx; $i >= 0; $i--) {
        if (defined $data->[$i]) {
            $self->{_last_candle} = $data->[$i];
            last;
        }
    }

    my $total  = scalar(@$data);
    my $x_bars = $scale->{bars} || $total || 1;
    my $bar_w  = ($x_bars > 0) ? ($scale->plot_width() / $x_bars) : 1;

    if ($bar_w < 2) {
        my $plot_w = int($scale->plot_width());
        $plot_w = 1 if $plot_w < 1;
        for my $px (0 .. $plot_w - 1) {
            # spec 0000i: mapear píxel a índice local visible, luego a índice del slice.
            my $from_local = int($px * $x_bars / $plot_w);
            my $to_local = int((($px + 1) * $x_bars / $plot_w) - 1);
            $to_local = $from_local if $to_local < $from_local;
            my $from = $from_local - $draw_offset;
            my $to = $to_local - $draw_offset;
            $to = $from if $to < $from;
            $to = $total - 1 if $to >= $total;
            $from = 0 if $from < 0;

            my ($open, $high, $low, $close);
            for my $i ($from .. $to) {
                my $candle = $data->[$i];
                next unless defined $candle;
                $open = $candle->[1] if !defined $open;
                $high = $candle->[2] if !defined $high || $candle->[2] > $high;
                $low = $candle->[3] if !defined $low || $candle->[3] < $low;
                $close = $candle->[4];
            }
            next unless defined $open && defined $close;

            my $y_h = $scale->value_to_y($high);
            my $y_l = $scale->value_to_y($low);
            my $color = ($close >= $open)
                ? ($self->{theme}{bull} // '#26a69a')
                : ($self->{theme}{bear} // '#ef5350');
            $canvas->createLine($px + 0.5, $y_h, $px + 0.5, $y_l, -fill => $color, -width => 1, -tags => 'candle');
        }
    } else {
        my $body_w = $bar_w * 0.6;
        $body_w = 1 if $body_w < 1;
        $body_w = $bar_w if $body_w > $bar_w;
        my $half   = $body_w / 2;

        for (my $i = 0; $i < $total; $i++) {
            my $candle = $data->[$i];
            next unless defined $candle;

            my ($ts, $open, $high, $low, $close, $vol) = @$candle;

            my $cx  = $scale->index_to_center_x($i + $draw_offset);
            my $y_o = $scale->value_to_y($open);
            my $y_h = $scale->value_to_y($high);
            my $y_l = $scale->value_to_y($low);
            my $y_c = $scale->value_to_y($close);

            my $color = ($close >= $open)
                ? ($self->{theme}{bull} // '#26a69a')
                : ($self->{theme}{bear} // '#ef5350');

            $canvas->createLine(
                $cx, $y_h, $cx, $y_l,
                -fill  => $color,
                -width => 1,
                -tags  => 'candle',
            );

            my $top    = ($y_o < $y_c) ? $y_o : $y_c;
            my $bottom = ($y_o > $y_c) ? $y_o : $y_c;
            $bottom = $top + 1 if ($bottom - $top) < 1;

            $canvas->createRectangle(
                $cx - $half, $top,
                $cx + $half, $bottom,
                -fill    => $color,
                -outline => $color,
                -tags    => 'candle',
            );
        }
    }

    # Inyectar colores de eje del tema en la escala antes de dibujar el eje Y.
    # La conversión datos↔píxeles sigue viviendo en Scales; aquí solo se le pasan
    # los colores claros (con defaults seguros si el tema no está disponible).
    $scale->{grid_color}      = $self->{theme}{grid}      // '#e6e6e6';
    $scale->{axis_text_color} = $self->{theme}{axis_text} // '#363a45';

    $scale->_draw_y_scale($canvas);
    $canvas->lower('y_grid');
    $canvas->raise('candle');
    $self->render_last_visible_price($canvas);
}

# Dibuja la etiqueta con el precio de cierre de la última vela visible
# en el margen derecho del canvas a la altura del precio.
sub render_last_visible_price {
    my ($self, $canvas) = @_;

    $canvas->delete('price_label');
    my $scale = $self->{scale};
    return unless defined $scale && defined $self->{_last_candle};

    my ($open, $close) = @{$self->{_last_candle}}[1, 4];
    return unless defined $close;

    my $y     = $scale->value_to_y($close);
    my $w     = $scale->{width};
    my $label = sprintf("%.2f", $close);
    my $line_color = (defined $open && $close >= $open)
        ? ($self->{theme}{bull} // '#26a69a')
        : ($self->{theme}{bear} // '#ef5350');
    my $label_bg   = $line_color;
    my $label_fg   = $self->{theme}{last_price_fg} // '#ffffff';

    $canvas->createLine(
        0, $y, $w, $y,
        -fill  => $line_color,
        -dash  => [2, 3],
        -width => 1,
        -tags  => 'price_label',
    );

    return if exists $scale->{draw_last_label} && !$scale->{draw_last_label};

    $canvas->createRectangle(
        $w - 68, $y - 7, $w, $y + 7,
        -fill    => $label_bg,
        -outline => $line_color,
        -tags    => 'price_label',
    );
    $canvas->createText(
        $w - 66, $y,
        -text   => $label,
        -anchor => 'w',
        -font   => 'Helvetica 9 bold',
        -fill   => $label_fg,
        -tags   => 'price_label',
    );
}

# Dibuja el crosshair en este panel y sus etiquetas (valor + tiempo).
#
# Firma (contrato acordado con ChartEngine::_draw_crosshair_all, tarea 6.1):
#     draw_crosshair($x, $y, $time_text)
#   * $x         : coordenada X de pantalla del cursor. Si es undef, se borra TODO el
#                  crosshair (líneas + etiquetas, incluida la de tiempo) y se retorna.
#   * $y         : coordenada Y de pantalla. Si es undef, el cursor no está sobre este
#                  panel: se dibuja solo la línea vertical (sin línea/etiqueta de valor).
#   * $time_text : cadena ya formateada con el tiempo bajo el cursor (p.ej. "09:15" o
#                  "18 May"), o undef si no hay etiqueta de tiempo que mostrar.
#
# La coordenada X es compartida con el ATRPanel para sincronización temporal (Req. 7.1).
# Comportamiento (Req. 7.1, 7.2, 7.4, 7.5):
#   * Línea vertical punteada en $x a lo alto del canvas.
#   * Si $y definido: línea horizontal punteada + cajita de valor en el eje derecho con
#     el precio obtenido vía scale->y_to_value($y).
#   * Si $time_text definido: cajita oscura con el texto de tiempo centrada en $x dentro
#     de la banda inferior (alineada al borde inferior), bajo la línea vertical.
#
# Colores tomados del tema claro en $self->{theme}, con defaults seguros vía // por si la
# clave no está definida (no se hardcodean colores del tema oscuro):
#   * crosshair_line (líneas)            -> '#9598a1'
#   * label_bg / label_fg (cajitas)      -> '#363a45' / '#ffffff'
# Todo se etiqueta con el tag 'price_crosshair' para borrarse junto al resto.
sub draw_crosshair {
    my ($self, $x, $y, $time_text) = @_;

    my $canvas = $self->{canvas};
    return unless defined $canvas;

    $canvas->delete('price_crosshair');
    return unless defined $x;

    my ($w, $h) = $self->_canvas_size($canvas);
    my $scale = $self->{scale};

    # Colores del tema con defaults seguros (tema claro).
    my $line_color  = $self->{theme}{crosshair_line} // '#9598a1';
    my $label_bg    = $self->{theme}{label_bg}        // '#363a45';
    my $label_fg    = $self->{theme}{label_fg}        // '#ffffff';

    # Línea vertical (sincronizada con ATRPanel)
    $canvas->createLine(
        $x, 0, $x, $h,
        -fill  => $line_color,
        -dash  => [4, 4],
        -width => 1,
        -tags  => 'price_crosshair',
    );

    # Línea horizontal y etiqueta de precio bajo el cursor
    if (defined $y) {
        $canvas->createLine(
            0, $y, $w, $y,
            -fill  => $line_color,
            -dash  => [4, 4],
            -width => 1,
            -tags  => 'price_crosshair',
        );

        if (defined $scale && (!exists $scale->{draw_crosshair_label} || $scale->{draw_crosshair_label})) {
            my $value = $scale->y_to_value($y);
            my $label = sprintf("%.2f", $value);

            $canvas->createRectangle(
                $w - 68, $y - 7, $w, $y + 7,
                -fill    => $label_bg,
                -outline => $line_color,
                -tags    => 'price_crosshair',
            );
            $canvas->createText(
                $w - 66, $y,
                -text   => $label,
                -anchor => 'w',
                -font   => 'Helvetica 9 bold',
                -fill   => $label_fg,
                -tags   => 'price_crosshair',
            );
        }
    }

    # Etiqueta de tiempo en la banda inferior, centrada en $x (Req. 7.4).
    # Se dibuja una cajita oscura con el texto de tiempo alineada al borde inferior,
    # bajo la línea vertical del crosshair.
    if (defined $time_text && length $time_text) {
        my $box_h     = 16;                 # alto de la cajita de tiempo
        my $char_w    = 7;                  # ancho aproximado por carácter (Helvetica 9 bold)
        my $pad_x     = 6;                  # padding horizontal a cada lado del texto
        my $half_w    = (length($time_text) * $char_w) / 2 + $pad_x;

        # Centro horizontal de la cajita: $x, ajustado para no salirse de los bordes.
        my $cx = $x;
        $cx = $half_w        if $cx - $half_w < 0;
        $cx = $w - $half_w   if $cx + $half_w > $w;

        my $top    = $h - $box_h;
        my $bottom = $h;

        $canvas->createRectangle(
            $cx - $half_w, $top, $cx + $half_w, $bottom,
            -fill    => $label_bg,
            -outline => $line_color,
            -tags    => 'price_crosshair',
        );
        $canvas->createText(
            $cx, $top + $box_h / 2,
            -text   => $time_text,
            -anchor => 'center',
            -font   => 'Helvetica 9 bold',
            -fill   => $label_fg,
            -tags   => 'price_crosshair',
        );
    }
}

# draw_time_crosshair_label($canvas, $x, $time_text) — spec 0000d:
# Dibuja la caja negra con la etiqueta de tiempo del crosshair sobre el
# canvas del eje temporal (time_axis_canvas), centrada verticalmente en
# ese canvas y con clamp horizontal para no salirse por izquierda/derecha.
# Reemplaza la caja que antes se dibujaba al fondo del price_canvas.
sub draw_time_crosshair_label {
    my ($self, $canvas, $x, $time_text) = @_;

    return unless defined $canvas;
    $canvas->delete('time_axis_crosshair');
    return unless defined $x && defined $time_text && length $time_text;

    my ($w, $h) = $self->_canvas_size($canvas);

    my $line_color = $self->{theme}{crosshair_line} // '#9598a1';
    my $label_bg   = $self->{theme}{label_bg}        // '#363a45';
    my $label_fg   = $self->{theme}{label_fg}        // '#ffffff';

    my $char_w = 7;
    my $pad_x  = 6;
    my $half_w = (length($time_text) * $char_w) / 2 + $pad_x;

    my $cx = $x;
    $cx = $half_w      if $cx - $half_w < 0;
    $cx = $w - $half_w if $cx + $half_w > $w;

    $canvas->createRectangle(
        $cx - $half_w, 0, $cx + $half_w, $h,
        -fill    => $label_bg,
        -outline => $line_color,
        -tags    => 'time_axis_crosshair',
    );
    $canvas->createText(
        $cx, $h / 2,
        -text   => $time_text,
        -anchor => 'center',
        -font   => 'Helvetica 9 bold',
        -fill   => $label_fg,
        -tags   => 'time_axis_crosshair',
    );
}

# Dibuja las etiquetas del eje de tiempo en la banda inferior del panel de precios.
#
# Entrada: arrayref de etiquetas enriquecidas producidas por
# ChartEngine::compute_intraday_labels, cada una con la forma:
#     { index   => <índice LOCAL 0-based en la ventana visible>,
#       text    => <'HH:MM' o 'DD Mon', ya formateado por ChartEngine>,
#       is_date => 0|1 }
#
# Reglas (Req. 5.1, 5.3, 5.4, 6.1, 6.2):
#   * La banda inferior ocupa el ANCHO COMPLETO del canvas y las etiquetas quedan
#     centradas verticalmente dentro del eje temporal compacto.
#   * Cada etiqueta se centra en scale->index_to_center_x(index) (tolerancia 1 px). El
#     index es LOCAL; la X NO se calcula a mano (regla de oro: coordenadas solo en
#     Scales), de modo que las etiquetas siguen a su barra ante scroll/zoom.
#   * El texto ya viene resuelto desde ChartEngine; aquí solo se dibuja $item->{text}
#     (no se reformatea). El texto de fecha "DD Mon" es más ancho y se centra con el
#     anchor 's' para que quede legible sobre su barra.
#   * Etiquetas de hora (is_date=0): estilo TENUE — línea de referencia con color `grid`
#     (trazo fino) y texto en fuente normal con color `axis_text`.
#   * Etiquetas de fecha (is_date=1): énfasis suave — línea de referencia más visible
#     que el grid normal, pero sin tapar velas cercanas al cambio de día.
#
# Colores tomados del tema claro almacenado en $self->{theme}, con defaults seguros
# vía // por si el tema no define la clave (no se hardcodean colores del tema oscuro).
sub draw_time_axis {
    my ($self, $canvas, $labels, $opts) = @_;

    $canvas->delete('time_axis');
    return unless $labels && @$labels;

    $opts ||= {};
    my $draw_grid   = exists $opts->{draw_grid}   ? $opts->{draw_grid}   : 1;
    my $draw_labels = exists $opts->{draw_labels} ? $opts->{draw_labels} : 1;

    my $scale = $self->{scale};
    return unless defined $scale;

    my ($w, $h) = $self->_canvas_size($canvas);
    my $label_y = int($h / 2 + 0.5);

    # Paleta clara: líneas tenues con `grid`; texto y énfasis de fecha con `axis_text`.
    my $grid_color      = $self->{theme}{grid}      // '#e6e6e6';
    my $date_grid_color = $self->{theme}{date_grid} // '#d0d4da';
    my $text_color      = $self->{theme}{axis_text} // '#363a45';

    for my $item (@$labels) {
        my $idx     = $item->{index};
        my $text    = $item->{text};
        my $is_date = $item->{is_date} ? 1 : 0;
        my $item_grid = exists $item->{grid} ? $item->{grid} : 1;
        my $item_label = exists $item->{label} ? $item->{label} : 1;
        next unless defined $idx && defined $text;

        # Centro de la barra anclada: única fuente de coordenadas (Scales).
        my $x = $scale->index_to_center_x($idx);

        if ($is_date) {
            # Cambio de fecha: visible, pero suficientemente suave para no tapar velas.
            # spec 0000d: no dibujar grid si el label quedó oculto por thinning.
            if ($draw_grid && $item_grid && $item_label) {
                $canvas->createLine(
                    $x, 0, $x, $h,
                    -fill  => $date_grid_color,
                    -width => 1,
                    -tags  => ['time_axis', 'time_grid'],
                );
            }
            next unless $draw_labels && $item_label;
            # Texto de fecha "DD Mon" en negrita y centrado verticalmente.
            $canvas->createText(
                $x, $label_y,
                -text   => $text,
                -anchor => 'center',
                -font   => 'Helvetica 8 bold',
                -fill   => $text_color,
                -tags   => 'time_axis',
            );
        }
        else {
            # Etiqueta horaria normal: línea de referencia vertical tenue.
            # spec 0000d: no dibujar grid si el label quedó oculto por thinning.
            if ($draw_grid && $item_grid && $item_label) {
                $canvas->createLine(
                    $x, 0, $x, $h,
                    -fill  => $grid_color,
                    -width => 1,
                    -tags  => ['time_axis', 'time_grid'],
                );
            }
            next unless $draw_labels && $item_label;
            # Texto HH:MM centrado verticalmente.
            $canvas->createText(
                $x, $label_y,
                -text   => $text,
                -anchor => 'center',
                -font   => 'Helvetica 8',
                -fill   => $text_color,
                -tags   => 'time_axis',
            );
        }
    }

    $canvas->lower('time_grid') if $draw_grid;
}

1;
