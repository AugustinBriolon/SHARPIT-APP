# 36. The training mode is a wheel

Date: 2026-11-21

## Status

Accepted.

## Context

The mode drawer (Actif / En pause / Blessé / Malade) was a list of rows — a glyph in a circle, a name, a description, a check — with a switch and a date picker for its length. The layout was another app's, copied. The athlete keeps the mode day by day and reads no explanation of it. Several richer drawers were drawn (tiles, « Ce que ça change », length chips, a painted stretch of days) and all refused: the first integration did enough.

## Decision

The chip opens a short sheet holding a title and a wheel of the four modes. Turning the wheel sets the mode.

- No description, no length, no confirm button. A mode set from the phone holds until it is changed (`until_modified`); the web can still give one an end.
- The chip names the mode and never shows a date.
- The line under Résumé's verdict is unchanged.
- `ActivityStatusStore` keeps only the newest write's answer, since a wheel can send several in a row, and falls back to the last store the server confirmed.
