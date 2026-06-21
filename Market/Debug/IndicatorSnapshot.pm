package Market::Debug::IndicatorSnapshot;
use strict;
use warnings;

# Módulo de diagnóstico removible y GENÉRICO para indicadores/overlays de Fase 2.
#
# Igual que Market::Debug::TimeAxisSnapshot hace con el eje temporal, este módulo
# convierte la salida estructurada de un indicador (SMC_Structures, Liquidity, ...)
# en texto determinista que un agente SIN visión puede comparar contra un valor
# esperado en un test .t.
#
# NO conoce los nombres de los accesores de cada indicador. El test toma la lista
# de items del indicador (p.ej. $smc->get_pivots()) y se la pasa aquí. Así el
# módulo permanece estable aunque cambien los indicadores.
#
# Contrato de un "item" (hashref). Campos esperados (todos opcionales salvo index):
#   index  => int    índice GLOBAL de vela donde el elemento queda anclado/confirmado
#   type   => str    p.ej. HH/HL/LL/LH, BOS, CHoCH_true, CHoCH_false, FVG_up,
#                    BSL, SSL, EQH, EQL, SWEEP_UP, GRAB, RUN, ...
#   dir    => str    'up'/'down' cuando aplique
#   price  => num    precio asociado (nivel, extremo)
#   hi,lo  => num     límites de una zona (FVG, order block) cuando aplique
#   state  => str    estado de FSM (Detected/Swept/Acceptance/Reclaimed/Resolved)
#   mitig  => num     % mitigado de un FVG (0..1) cuando aplique
#   meta   => hashref campos extra arbitrarios (volúmenes 1m/5m/15m, etc.)
#
# Reglas de salida:
#   - items se ordenan por (index, type) de forma determinista.
#   - los números se formatean con precisión fija para evitar ruido de coma flotante.

my @DEFAULT_FIELDS = qw(index type dir price hi lo state mitig);

# Campos que SIEMPRE se imprimen como entero (índices de vela). El resto de
# valores numéricos se formatean con precisión fija para evitar que 102.0 se
# imprima como "102" y rompa comparaciones de tests.
my %INT_FIELD = map { $_ => 1 } qw(index global from_index to_index left_global right_global);

# render_items(\@items, %opts) -> string determinista (una línea por item + summary).
# opts:
#   fields    => \@names   campos y orden a imprimir (default @DEFAULT_FIELDS)
#   precision => int       decimales para números (default 2)
#   replay_idx=> int       si se define, añade línea replay_guard
#   title     => str       encabezado opcional
sub render_items {
    my ($class, $items, %opts) = @_;
    $items ||= [];
    my @fields = $opts{fields} ? @{ $opts{fields} } : @DEFAULT_FIELDS;
    my $prec   = defined $opts{precision} ? $opts{precision} : 2;

    my @sorted = sort {
        ($a->{index} // 0) <=> ($b->{index} // 0)
            || (($a->{type} // '') cmp ($b->{type} // ''))
    } @$items;

    my @lines;
    push @lines, "INDICATOR_DEBUG v1" . (defined $opts{title} ? " $opts{title}" : "");
    for my $it (@sorted) {
        my @parts;
        for my $f (@fields) {
            next unless exists $it->{$f} && defined $it->{$f};
            push @parts, "$f=" . _fmt($it->{$f}, $prec, $INT_FIELD{$f});
        }
        push @lines, join(' ', @parts);
    }
    push @lines, "summary: " . summary_line($items);

    if (defined $opts{replay_idx}) {
        my @bad = $class->replay_violations($items, $opts{replay_idx});
        push @lines, sprintf("replay_guard: replay_idx=%d violations=%d%s",
            $opts{replay_idx}, scalar(@bad),
            @bad ? (" indices=" . join(',', map { $_->{index} } @bad)) : "");
    }
    return join("\n", @lines);
}

# Línea compacta de la secuencia de tipos en orden de índice. Útil para asserts
# tipo "HH HL LH LL" sin depender de precios.
sub type_sequence {
    my ($class, $items) = @_;
    $items ||= [];
    my @sorted = sort {
        ($a->{index} // 0) <=> ($b->{index} // 0)
            || (($a->{type} // '') cmp ($b->{type} // ''))
    } @$items;
    return join(' ', map { defined $_->{type} ? $_->{type} : '?' } @sorted);
}

# Conteo por type, determinista.
sub summary_line {
    my ($items) = @_;
    $items ||= [];
    my %count;
    $count{ $_->{type} // '?' }++ for @$items;
    return join(' ', map { "$_=$count{$_}" } sort keys %count) || '(empty)';
}

# Criterio duro del PDF de Replay: ninguna capa puede dibujar índices > replay_idx.
# Devuelve la lista de items que lo violan.
sub replay_violations {
    my ($class, $items, $replay_idx) = @_;
    $items ||= [];
    return () unless defined $replay_idx;
    return grep { defined $_->{index} && $_->{index} > $replay_idx } @$items;
}

sub _fmt {
    my ($v, $prec, $as_int) = @_;
    if (ref $v eq 'HASH')  { return '{' . join(',', map { "$_:" . _fmt($v->{$_}, $prec) } sort keys %$v) . '}'; }
    if (ref $v eq 'ARRAY') { return '[' . join(',', map { _fmt($_, $prec) } @$v) . ']'; }
    # Campos no numéricos (type, dir, state) se devuelven tal cual.
    my $is_num = ($v =~ /^-?\d+\z/) || ($v =~ /^-?\d*\.\d+(?:[eE][-+]?\d+)?\z/) || ($v =~ /^-?\d+\.\d*\z/);
    return $v unless $is_num;
    return int($v) if $as_int;
    return sprintf("%.${prec}f", $v);
}

1;
