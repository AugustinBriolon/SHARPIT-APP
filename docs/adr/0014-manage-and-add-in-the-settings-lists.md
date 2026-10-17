# 0014. Manage and add apart in the settings lists

Date: 2026-10-17

## Status

Accepted

## Context

Paramètres › Sources de données listed every source flat: the iPhone's two switches (Apple Health,
Apple Calendar) and three buttons (Strava, Withings, Google) that connected or disconnected
depending on a state the row did not say. Nothing told what was linked from what was not, and a
disconnection was a second tap on a connect button.

Sports & équipement was one long scroll: seven large tiles, all selectable, then one card per sport
with every piece of kit as a checkbox. The athlete could not read at a glance what they practiced
or owned.

## Decision

Both pages separate what the athlete has from what they can add.

- **Sources** lists the connected sources only. A row opens a sheet with what the source brings and
  « Déconnecter » (confirmation kept). A « + » in the bar opens the sources not yet connected, each
  one tap from linked. « Priorités par catégorie » appears from two connected sources, since a
  choice between sources needs two.
- **Sports & équipement** lists the practiced sports, each row saying what is owned for it. A row
  opens the sport's page with its kit (strength asks where the athlete trains first) and « Retirer ».
  A « + » offers the sports not yet added. The last endurance sport cannot be removed.

The rules live in `ConnectionsReadout.split` and `SportsReadout`, tested without a view. The
onboarding keeps its tiles: it is a first choice, not a list to maintain.

## Options considered

### Option A — Keep the flat lists and clarify the labels
Pros: no new screens. Cons: the connected/not-connected split stays implicit and the sports page
stays long.

### Option B — Manage and add apart (chosen)
Pros: the page answers « what do I have »; the way to add is one known gesture; each sport's kit
is read on its own page. Cons: one more tap to reach a sport's kit.

## Consequences

### Positive
- A connected source and a practiced sport are visible at a glance, with the way out next to them.

### Negative
- Changing the kit of a sport takes a tap more than before.

### Neutral
- `docs/adr/0008` still holds: system lists and sheets, the brand in palette and words.

## References
- `docs/adr/0008`, `docs/adr/0013`
