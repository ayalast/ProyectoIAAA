use strict;
use warnings;
use Test::More;

use lib '.';
use Market::Debug::IndicatorSnapshot;

my $D = 'Market::Debug::IndicatorSnapshot';

# --- Fixture determinista: salida típica de un indicador SMC ---
my @smc = (
    { index => 5,  type => 'HL', price => 100.25 },
    { index => 2,  type => 'HH', price => 101.50 },
    { index => 9,  type => 'BOS', dir => 'up', price => 101.5 },
    { index => 9,  type => 'LH', price => 100.75 },
);

# 1. type_sequence ordena por (index,type): index 9 desempata BOS<LH alfabéticamente.
is($D->type_sequence(\@smc), 'HH HL BOS LH', 'type_sequence ordena por index y luego type');

# 2. summary_line cuenta por tipo, determinista.
is(Market::Debug::IndicatorSnapshot::summary_line(\@smc),
   'BOS=1 HH=1 HL=1 LH=1', 'summary_line cuenta por tipo ordenado');

# 3. render_items: salida estable y números formateados.
my $txt = $D->render_items(\@smc, title => 'smc_demo');
like($txt, qr/^INDICATOR_DEBUG v1 smc_demo/, 'header con título');
like($txt, qr/index=2 type=HH price=101\.50/, 'item HH formateado a 2 decimales');
like($txt, qr/summary: BOS=1 HH=1 HL=1 LH=1/, 'summary incluida');

# 4. Determinismo: misma entrada -> misma salida byte a byte.
is($D->render_items(\@smc, title => 'smc_demo'), $txt, 'render_items es determinista');

# --- Replay guard: criterio duro del PDF (sin fuga de futuro) ---
my @bad = $D->replay_violations(\@smc, 5);
is(scalar(@bad), 2, 'replay_violations detecta items con index > replay_idx');
is_deeply([ sort { $a <=> $b } map { $_->{index} } @bad ], [9, 9], 'viola en index 9');

is(scalar($D->replay_violations(\@smc, 100)), 0, 'sin violaciones si replay_idx >= max');

my $rtxt = $D->render_items(\@smc, replay_idx => 5);
like($rtxt, qr/replay_guard: replay_idx=5 violations=2 indices=9,9/, 'replay_guard en texto');

# --- Zonas con límites (FVG) y estado FSM ---
my @liq = (
    { index => 12, type => 'FVG_up', hi => 102.0, lo => 101.0, mitig => 0.5 },
    { index => 20, type => 'SWEEP_UP', state => 'Resolved', price => 105.25,
      meta => { v1m => 1000, v5m => 5000, v15m => 15000 } },
);
my $ltxt = $D->render_items(\@liq, fields => [qw(index type hi lo state mitig price)]);
like($ltxt, qr/index=12 type=FVG_up hi=102\.00 lo=101\.00 mitig=0\.50/, 'FVG con límites y mitig');
like($ltxt, qr/index=20 type=SWEEP_UP state=Resolved price=105\.25/, 'evento con estado FSM');

# --- Edge: lista vacía no falla ---
is(Market::Debug::IndicatorSnapshot::summary_line([]), '(empty)', 'lista vacía -> (empty)');
is($D->type_sequence([]), '', 'type_sequence vacío -> cadena vacía');

done_testing();
