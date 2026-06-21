# Spec 0009: Anchored VWAP multipivot

Fuente: PDF Fase 2 §8 "Anchored VWAP". Clase 06-15 (Fase 2.2).
Package (sugerido, por confirmar ubicación): `Market/Indicators/AnchoredVWAP.pm` +
`Market/Overlays/AnchoredVWAP.pm`.

## Objetivo
Calcular el Precio Promedio Ponderado por Volumen Anclado, reiniciando sus sumas acumuladas de
volumen y precio ponderado al detectar ciertos eventos/pivots de anclaje.

## Problema
El VWAP anclado a eventos relevantes (no solo al inicio de sesión) da una referencia dinámica de
valor justo desde el momento institucionalmente importante. Es parte de la Fase 2.2.

## Comportamiento esperado
El cálculo reinicia sus acumuladores estrictamente al detectar cualquiera de estos 5 anclajes:
1. **Inicio de Sesión:** anclaje al primer tick/vela de la sesión activa.
2. **Apertura de Mercado:** anclaje a la apertura oficial del mercado del activo.
3. **BOS Confirmado:** inicialización en la vela exacta donde se valida un Break of Structure.
4. **CHoCH Confirmado:** inicialización en la vela exacta donde se confirma el Change of Character.
5. **Por Volume Profile:** anclaje dinámico coordinado con el nodo de mayor concentración de
   volumen (POC) determinado por el perfil (spec 0008).
- Fórmula VWAP: `Σ(precio_típico_i · volumen_i) / Σ(volumen_i)` desde el anclaje hasta la vela
  actual (precio típico = (H+L+C)/3, o el que defina la guía).
- "Multipivot": pueden coexistir varios VWAP anclados a distintos eventos a la vez. Overlay
  activable; respeta Replay.

## Fuera de alcance
- Bandas de desviación del VWAP (no exigidas explícitamente; añadir solo si el profesor lo pide).

## Criterios de aceptación
- El VWAP reinicia exactamente en la vela del evento de anclaje (sin arrastrar acumulado previo).
- Soporta varios anclajes simultáneos (multipivot).
- Coordinación correcta con BOS/CHoCH (spec 0004) y con el POC (spec 0008).
- Sin futuro en Replay.

## Casos límite
- Dos anclajes en la misma vela; anclaje muy reciente (un solo punto).
- Volumen cero en el tramo inicial.

## Plan de verificación
- `perl -I. -c`.
- Comparación visual con Anchored VWAP de TradingView desde un pivote conocido.
