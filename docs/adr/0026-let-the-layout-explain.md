# 26. Let the layout explain

Date: 2026-10-25

## Status

Accepted.

## Context

Cards, settings rows and list footers carried subtitles, detail lines and helper sentences that restated the title or the value beside them (SHARPIT-WEBAPP ADR-107).

## Decision

We will avoid unnecessary labels and secondary descriptions and let the layout do the explaining. Text stays when it carries data, names an error and its fix, offers the next step of an actionable empty state, confirms a destructive action, or states consent / legal terms. The `subtitle` / `detail` / footer APIs remain for those cases.

## Consequences

Calmer screens and fewer strings in `Localizable.xcstrings`. Titles and values must be self-evident.
