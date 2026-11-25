# 40. A hidden gesture may be said once, as a tip

Date: 2026-11-25

## Status

Accepted. Amends `docs/adr/0026`.

## Context

ADR 0026 lets the layout explain: no helper sentence that restates what the screen shows. A few
actions, though, are gestures nothing on screen shows — a long press on a meal copies the day
before's, a swipe turns the day, a finger slid on the exercise picker's alphabet runs through the
catalog, a long press on a goal marks it reached. They are found by chance or not at all. The
athlete asked for TipKit (2026-11-25).

## Decision

We will say a hidden gesture once, as a TipKit tip laid in the page, and nothing else.

- Only a gesture the screen does not show. A visible button, a field or a value never gets a tip:
  the layout explains it (ADR 0026 holds).
- In place (`TipView` in the page's flow, on the tile colour, ink tint), never a bubble over content.
- Once each (`MaxDisplayCount(1)`), dismissable, and at most one tip a day across the app
  (`Tips.configure([.displayFrequency(.daily)])`).
- Shown when the gesture would help: the meal tip after two foods logged, the day tip after three
  journal days opened, the goal tip after Objectifs was opened twice, the alphabet tip the first
  time the picker lists the catalog.
- Tips are kept per iPhone, not per account: they teach a gesture of the app, not anything about
  the athlete, so a change of account does not show them again.
- `-SharpitShowAllTips YES` shows them all in a Debug build.

## Consequences

- Four strings more, each a gesture and its effect. A fifth tip needs a gesture nothing shows.
- A tip dismissed is never shown again, even if the gesture is still unknown: the athlete chose.
