# Specs

Una spec describe QUÉ se quiere y POR QUÉ, no el cómo técnico detallado. Cada spec se
implementa vía una o más tasks en `tasks/`. Fuente de verdad de los requisitos:
`../docs/material_profesor/Especificacion_Proyeto_2a_Fase.pdf` + transcripciones de clase.

## Índice de specs

| Spec | Tema | Entrega | Prioridad |
|------|------|---------|-----------|
| 0000 | Pulido Fase 1: etiqueta TradingView del crosshair + grid temporal equidistante (parcial: crosshair aceptado; criterio de grid reemplazado por 0000b) | Antes de Fase 2 | Alta |
| 0000b | Eje temporal inferior TradingView por fronteras reales de reloj/calendario | Antes de Fase 2 | Alta |
| 0000c | Pulido post-0000b: ticks 90m en gaps, crosshair con hora y paneo suave | Antes de Fase 2 | Alta |
| 0000d | Regresiones visuales post-0000c: crosshair en eje temporal y control de ticks/grid en gaps | Antes de Fase 2 | Alta |
| 0000e | Coherencia lógica del eje temporal: índices reales y crosshair alineado | Antes de Fase 2 | Alta |
| 0000f | Tickmarks ponderados tipo TradingView/Supercharts: días como anchors, formato intradía y cadencias visuales 1m (implementado, pero visualmente insuficiente) | Antes de Fase 2 | Alta |
| 0000g | Cadencia global uniforme del eje temporal tipo TradingView: Modo A obligatorio con días + horas uniformes; no aceptar modo diario como cierre final | Antes de Fase 2 | Alta |
| 0001 | Temporalidades extendidas (1m..W) | 29/06 | Alta |
| 0002 | Sistema Replay | 29/06 | Alta |
| 0003 | Arquitectura base de Overlays | 29/06 | Alta (habilitador) |
| 0004 | SMC Structures (BOS/CHoCH/FVG/Fibonacci) | 29/06 + 13/07 | Alta |
| 0005 | Módulo de Liquidez (swings, EQH/EQL, sweep/grab/run, FSM) | 29/06 + 13/07 | Alta |
| 0006 | Concurrencia Liquidez → BOS/CHoCH (pesos de probabilidad) | 13/07 | Media |
| 0007 | DIY Custom Strategy Builder | 13/07 | Media |
| 0008 | Perfil de Volumen avanzado | 13/07 | Media |
| 0009 | Anchored VWAP multipivot | 13/07 | Media |
| 0010 | UI: menú de timeframe + toggles de overlays + controles Replay | 29/06 | Alta |
| 0011 | (Fase 3) HMM + Viterbi tensorial (MXNet) | Fin semestre | Futura |
| 0012 | (Fase 3) Selección de features con Pearson/PCC | Fin semestre | Futura |

## Plantilla

```
# Spec: [nombre]

## Objetivo

## Problema

## Usuarios afectados

## Comportamiento esperado

## Fuera de alcance

## Criterios de aceptación

## Casos límite

## Plan de verificación
```

## Convenciones

- Las specs no cambian; si un requisito cambia, se versiona o se añade una nueva.
- Cada spec enlaza el apartado del PDF oficial y la(s) clase(s) relevante(s).
- Los parámetros numéricos llevan su valor inicial del PDF y se marcan como "calibrable".
