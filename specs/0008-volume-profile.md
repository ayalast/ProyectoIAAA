# Spec 0008: Perfil de Volumen avanzado

Fuente: PDF Fase 2 §7 "Perfil de Volumen Avanzado". Clase 06-15 (Fase 2.2).
Package (sugerido, por confirmar ubicación): `Market/Indicators/VolumeProfile.pm` +
`Market/Overlays/VolumeProfile.pm`.

## Objetivo
Calcular y proyectar horizontalmente el perfil de volumen con POC (Point of Control), VAH (Value
Area High) y VAL (Value Area Low), bajo tres modos operativos basados en pivots analíticos.

## Problema
El volumen por nivel de precio revela zonas de aceptación/rechazo institucional; el POC/VAH/VAL
son referencias clave para anclar VWAP (spec 0009) y validar zonas de liquidez (spec 0005).

## Comportamiento esperado
Tres modos:
- **Por Sesión:** se inicializa y segmenta de forma fija con la apertura cronológica de cada
  sesión configurada.
- **Por BOS / CHoCH:** acumula y distribuye el volumen tomando como anclajes de inicio/fin los
  eventos confirmados en temporalidades 1H, 2H, 4H, D y W.
- **Por Velas Históricas del Pasado Lejano (contingencia):** mecanismo activado automáticamente
  cuando no hay datos/velas en el pasado reciente; calcula desde el inicio de sesión lejana o por
  eventos macro confirmados en HTF.
- Salidas: POC (nivel de mayor volumen), VAH y VAL (límites del área de valor), proyectados como
  histograma horizontal. Overlay activable; respeta Replay.

## Fuera de alcance
- Footprint/delta por vela (no exigido).
- Volumen comprador/vendedor (delta) — el profesor lo mencionó como "si avanza bien"; confirmar.

## Criterios de aceptación
- Los tres modos producen un perfil con POC/VAH/VAL coherentes sobre el rango anclado.
- El modo de contingencia se activa solo cuando falta histórico reciente.
- Render horizontal correcto y activable; sin futuro en Replay.

## Casos límite
- Rango sin volumen suficiente; empates en el POC.
- Anclaje en un BOS/CHoCH muy reciente (poca data).

## Plan de verificación
- `perl -I. -c`.
- Comparación visual con el Volume Profile de TradingView (POC/VAH/VAL).
