#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper; # Librería nativa para imprimir arreglos de forma legible
use Tk;

# Añade el directorio actual a las rutas de búsqueda de librerías
use lib '.';
use Market::MarketData;
use Market::IndicatorManager;
use Market::Indicators::ATR;
use Market::ChartEngine;

print "========== INICIANDO MOTOR DE DATOS ==========\n";

# 1. Instanciar la clase
my $market_data = Market::MarketData->new();

# 2. Cargar el archivo CSV
my $archivo_csv = 'Data/2026_03.csv';
open my $fh, '<', $archivo_csv or die "CRÍTICO: No se pudo abrir $archivo_csv: $!";

my $header = <$fh>; # Leemos y descartamos la primera línea (encabezados)

print "[*] Ingiriendo datos de 1 minuto en streaming simulado...\n";
while (my $linea = <$fh>) {
    chomp $linea;
    # Dividimos la línea por comas y la pasamos como referencia de arreglo
    my @columnas = split /,/, $linea;
    $market_data->add_candle(\@columnas);
}
close $fh;

# 3. Pruebas de la temporalidad Base (1m)
print "\n========== RESULTADOS: TIMEFRAME 1m ==========\n";
print "Total de velas procesadas : " . $market_data->size() . "\n";
print "Índice de la última vela  : " . $market_data->last_index() . "\n";
print "Timestamp índice 10       : " . $market_data->get_timestamp(10) . "\n";

print "\n[*] Inspeccionando la última vela de 1m:\n";
print Dumper($market_data->last_candle());

# 4. Pruebas de Agrupación Matemática (5m y 15m)
print "\n========== CONSTRUYENDO TIMEFRAMES ==========\n";
print "[*] Ejecutando build_timeframes()...\n";
$market_data->build_timeframes();

# Cambiamos el estado global a 5 minutos
$market_data->set_timeframe('5m');
print "\n========== RESULTADOS: TIMEFRAME 5m ==========\n";
print "Total de velas generadas  : " . $market_data->size() . "\n";
print "[*] Inspeccionando la primera vela de 5m (agrupación de las primeras 5 de 1m):\n";
print Dumper($market_data->get_candle(0));

# Cambiamos el estado global a 15 minutos
$market_data->set_timeframe('15m');
print "\n========== RESULTADOS: TIMEFRAME 15m ==========\n";
print "Total de velas generadas  : " . $market_data->size() . "\n";

# 5. Prueba de Slicing (Simulando la vista del ChartEngine)
$market_data->set_timeframe('5m');
print "\n========== PRUEBA DE SLICING (5m) ==========\n";
print "[*] Extrayendo velas visibles (índices del 0 al 2)...\n";
my $slice = $market_data->get_slice(0, 2);
print Dumper($slice);

# 6. Prueba de Time Anchors
$market_data->set_timeframe('1m');
print "\n========== PRUEBA DE TIME ANCHORS ==========\n";
my $anchors = $market_data->compute_time_anchors();
print "[*] Índices donde se detectó un salto de hora (para dibujar el grid vertical):\n";
print join(" | ", @$anchors) . "\n";

print "\n========== PRUEBAS FINALIZADAS ==========\n";