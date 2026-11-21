# 36. The training mode says what it changes and until when

Date: 2026-11-21

## Status

Accepted. Builds on [ADR 0035](0035-the-shared-components-turn-clinique-in-place.md).

## Context

The mode drawer (Actif / En pause / Blessé / Malade) was a list of four rows with a description each, a switch and a date picker for its length. It never said what the mode did to the plan, left « reprendre » to picking « Actif » in the list, and the line under Résumé's verdict was a tinted capsule that warned without opening anything.

## Decision

- The drawer opens on the mode as a glyph in a ring, its word as a `CliniqueStatusPill`, and when it ends (« Reprise dans 9 jours »). The four modes are tiles, the held one ringed in ink.
- « Ce que ça change » gives two lines per mode, for the plan and for the coach, in the web's meaning (`planningImpact`).
- The length is chosen on chips — « Jusqu'à nouvel ordre », 3 jours, 1 semaine, 2 semaines, « Une date » — that write the wire's single `until_date`.
- « Reprendre l'entraînement » is the ink action while a mode is on.
- Résumé's line is the pill and the resumption, and opens the drawer.

The wire, the store and the existing copy (`alertLine`, `planningImpact`, `hint`) are unchanged.
