# 39. The paywall lists everything Pro adds, in a loop

Date: 2026-11-24

## Status

Accepted

## Context

The paywall (`SharpitProPaywallSheet`, `docs/adr/0020`, `docs/adr/0035`) said what Pro is in four
hard-coded lines, each a title and a detail, under a sub-paragraph stating that the athlete's data
stays free. Réglages › Pro lists eleven perks, read from the server (`pro-perks.ts`). The paywall
therefore undersold Pro, and its four lines matched no list.

The athlete asked (2026-11-24) for the whole list on the paywall, each perk a glyph, a hue and a
sentence, scrolling by itself without end, movable with a finger, and for the sub-paragraph to go.

Eleven lines of two rows each do not fit above the plans, and the paywall is itself a scroll view.

## Decision

We will show the eleven perks as one column that rises by itself in a loop, in a window of four
and a half lines (`ProPerkConveyor`).

- The lines are `ProPerkLine.all`: the server's eleven ids, each with a glyph, a pillar's hue and
  one sentence written for the paywall. They are local, so the paywall draws them without waiting
  for `/api/v1/pro`.
- The motion is a function of the clock (`ConveyorLoop`): a steady 22 pt a second, eased in
  from rest. A finger laid on the list holds it and can take it either way; on release the flick
  dies down, the list rests two seconds, then the rise eases back in over 1.6 s (its speed
  follows a smoothstep, so it never starts with a step). The offset is wrapped to one length of the list, and two copies are drawn so the window
  is always full.
- Under Reduce Motion or at the accessibility text sizes the column is the plain list, and
  VoiceOver always reads the plain list.
- No haptic: nothing here is a notch under the finger.
- The sub-paragraph is removed. The paywall no longer says that the athlete's data stays free;
  the last line of the list says SharpIt runs without ads or data resale.

## Options considered

- **A nested scroll view repositioned when it passes one length.** Native momentum, but a jump
  in the scroll position mid-fling shows, and a vertical scroll view inside the paywall's own
  fights it for the drag. Rejected.
- **A horizontal marquee of chips.** Leaves the vertical drag to the page, but a chip holds a
  word, not the sentence asked for. Rejected.
- **Read the lines from the server.** One source, but an empty paywall until it answers, and the
  server's descriptions are paragraphs. Rejected; the ids tie the two lists.

## Consequences

- The paywall says everything Pro adds, and moves while it is read.
- A drag that starts on the column moves the column, not the page: on a small iPhone the page is
  scrolled from its title or its plans.
- A perk added on the server must be added to `ProPerkLine.all`; a test pins the eleven ids.
- The four titled lines of the mock-up (`docs/adr/0035`) are gone from the paywall.
