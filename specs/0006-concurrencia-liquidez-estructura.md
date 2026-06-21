# Spec 0006: Concurrencia Liquidez → BOS / CHoCH (pesos de probabilidad)

Fuente: PDF Fase 2 §5 "Relación Estructural y de Concurrencia". Clase 06-16.
Toca: `Market/Indicators/Liquidity.pm` ↔ `Market/Indicators/SMC_Structures.pm`.

## Objetivo
Una vez la máquina de estados de liquidez (spec 0005) resuelve y clasifica un evento, modificar
internamente los pesos de probabilidad para la confirmación de quiebres estructurales en
SMC_Structures (spec 0004).

## Problema
Estructura y liquidez no son independientes: un barrido de liquidez precede a giros; una ruptura
con aceptación confirma tendencia. El sistema debe reflejar esa relación para producir señales de
alta probabilidad (y, en Fase 3, observaciones más informativas para el HMM).

## Comportamiento esperado
Tras `Resolved` con su clasificación final:
- **Sweep:** incrementa drásticamente el peso de probabilidad de un **CHoCH** inminente en la
  dirección **contraria** al barrido (giros de alta precisión).
- **Liquidity Run:** valida la fuerza de la tendencia; mayor probabilidad de confirmar un **BOS**
  tras romper el siguiente pivote estructural.
- **Liquidity Grab:** absorción institucional inmediata ⇒ emitir **alerta visual de Reversal** de
  corto/mediano plazo.
- Los **FVG** formados en la vela del barrido o inmediatamente posterior a un Sweep/Grab adquieren
  la etiqueta **"Zona de Alta Reacción"** (punto optimizado de gatillo para el Strategy Builder,
  spec 0007).

## Fuera de alcance
- La generación efectiva de órdenes (no hay trading real).
- El consumo de estos pesos por el HMM (Fase 3).

## Criterios de aceptación
- Un Sweep resuelto eleva el peso de CHoCH contrario; un Run eleva el de BOS; un Grab dispara
  alerta de reversal.
- Los FVG post-sweep/grab quedan marcados como "Zona de Alta Reacción".
- La comunicación liquidez→estructura no rompe el desacople (se hace por datos/contratos, no
  metiendo render en el cálculo).

## Casos límite
- Eventos solapados (sweep y run cercanos): definir prioridad/última clasificación.
- Pesos que se acumulan o decaen en el tiempo (definir si caducan).

## Plan de verificación
- `perl -I. -c`.
- Test manual: provocar un sweep en Replay y verificar el sesgo hacia CHoCH contrario y el marcado
  de FVG de alta reacción.
