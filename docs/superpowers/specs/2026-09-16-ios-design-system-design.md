# SHARPIT iOS design system (v1 foundation) — design

**Date:** 2026-09-16  
**Status:** Draft for review  
**Repos:** `SHARPIT-APP`  
**Related:** [2026-09-15-ios-native-v1-design.md](./2026-09-15-ios-native-v1-design.md), SHARPIT `docs/design/DESIGN_LANGUAGE.md`

> **Superseded in part (2026-09-19) — see SHARPIT [ADR-041](../../../../SHARPIT/docs/adr/ADR-041-ios-design-tokens-generated-from-web.md).**
> Sections **4.1 Color**, **4.2 Typography** and **4.3 Spacing & ratio** no longer hold.
> Color tokens are generated from the web design system, the three brand typefaces are
> embedded, and the spacing ladder follows the Apple 4/8 pt grid (φ is retained only as an
> optical ratio inside components). The rest of this spec — approach, components,
> composition rule, screen structure — remains current.

## 1. Goal

Establish a **native-first SwiftUI design system** that sits on Apple chrome (Liquid Glass, system navigation) and adds a **SHARPIT instrument layer** so Résumé feels precise, calm, and distinctive — not a generic fitness dashboard and not a web clone.

Scope for this foundation: **tokens + reusable components + refactor of Résumé (Today) only**. Other tabs stay placeholders until a later pass.

## 2. Design principles (from product language)

1. **Revelation over decoration** — every pixel earns its place.
2. **Earned density** — high information, impeccable structure.
3. **Temporal permanence** — no trend chrome; prefer system materials and typography that age well.
4. **Apple chrome, SHARPIT content** — tab bar / nav / glass are system; verdict, signals, and plates carry brand meaning.
5. **Golden ratio (φ)** — spacing ladder, optical splits (major/minor), and in-component air derive from `SharpitRatio` (`φ ≈ 1.618`). No ad-hoc gaps when a φ step or split applies.

Mental model: precision instrument (chronograph / clinical readout), not gamified tracker.

## 3. Approach

**Native-only for v1 foundation.** No SwiftUIX, CombineCocoa, or third-party chart libs in this pass.

| Layer | Source |
| --- | --- |
| Chrome | SwiftUI TabView / NavigationStack / iOS 26 `glassEffect` / toolbar |
| Structure | Causal stack: verdict → session → signals |
| Identity | Tokens + Sharpit components (`VerdictHero`, plates, strips) |
| Charts | Deferred (Apple `Charts` when Plan/Activité need them) |

SwiftUIX may be reconsidered later **only** for a concrete API gap, not as a default dependency.

## 4. Token architecture

Files under `SHARPIT-APP/DesignSystem/`:

### 4.1 Color (semantic)

| Token | Role |
| --- | --- |
| `postureProtect` | Attention / protect day (maps `V1TodayPosture.protect`) |
| `postureSteady` | Default capacity (`.steady`) — prefer `Color.accentColor` unless brand leaf is defined |
| `posturePush` | Capacity available (`.push`) |
| `postureUncertain` | Low confidence / unknown (`.uncertain`) |
| `canvasTop` | Soft wash from posture accent at low opacity |
| `canvasBase` | `Color(.systemBackground)` |
| `labelSecondary` | Eyebrows, meta — `.secondary` |

No decorative purple gradients. Semantic color is reserved for posture meaning.

### 4.2 Typography

| Style | Size / weight | Use |
| --- | --- | --- |
| `eyebrow` | 11pt semibold, tracking ~1.6, uppercase | Section / verdict eyebrow |
| `verdict` | ~36pt semibold, tight tracking | Today hero headline |
| `body` | Body | Subline, explanation |
| `label` | 10–11pt semibold, uppercase, tracked | Plate / signal labels |
| `data` | Title3+ monospacedDigit semibold | Scores, %, durations |

Use system SF; do not embed Syne/Plex on iOS in this foundation (web may differ). Instrument feel comes from hierarchy and tabular figures, not custom fonts yet.

### 4.3 Spacing & ratio

**Foundation:** `SharpitRatio` (`φ`, `major(of:)`, `minor(of:)`, `step(_:power:)`).

**Ladder** (base `8` × φⁿ, plus one octave at `sm`):

| Token | Value | Derivation |
| --- | --- | --- |
| `xxs` | 8 | base |
| `xs` | 13 | ≈ 8φ |
| `sm` | 16 | 2 × base (octave) |
| `md` / `pageInset` / `section` / `cardPadding` | 21 | ≈ 8φ² |
| `lg` | 34 | ≈ 8φ³ |
| `cardRadius` | 25 | major(40) |

Optical divisions inside components (e.g. overnight gauge score lift) use `SharpitRatio.minor(of:)` / `major(of:)` — never a private copy of φ.

### 4.4 Surfaces

| Surface | Implementation |
| --- | --- |
| Canvas | Vertical gradient `canvasTop` → `canvasBase`, ignores safe area |
| Glass card | iOS 26 `glassEffect(.regular, in: .rect(cornerRadius: 24))`; else ultraThinMaterial continuous rounded rect |
| Glass capsule | Same for chips (weather, future filters) |

## 5. Components

| Component | Responsibility | Not responsible for |
| --- | --- | --- |
| `SharpitTheme` / style helpers | Tokens + text/color accessors | Networking, Clerk |
| `SharpitEyebrow` | Uppercase tracked label | Business copy |
| `VerdictHero` | Eyebrow + headline + subline + optional meta row | Fetching |
| `SessionPlate` | Title, subtitle, kind badge, metrics row, glass | List of all sessions |
| `SignalStrip` | Horizontal equal-width signal cells | Domain scoring |
| `SharpitLoadingInstrument` | Skeleton matching loaded structure | Fake network delay |
| Existing glass helpers | Move/consolidate into DesignSystem | Feature logic |

**Composition rule:** `TodayView` / `TodayInstrumentView` only compose these components + screen state. No one-off typography in feature files once migrated.

## 6. Résumé screen (apply foundation)

Loaded state remains:

1. Canvas tinted by posture  
2. `VerdictHero` (no glass behind verdict — text sits on canvas)  
3. `SessionPlate` list under “Séance”  
4. `SignalStrip` under “Signaux”  
5. Weather chip in toolbar (Apple Weather + location)

Loading state uses `SharpitLoadingInstrument` with the **same** structure (text skeleton for verdict, glass for plates) — never a single opaque white block over the gradient.

Empty / failed / unauthorized stay `ContentUnavailableView` with instrument tone (short copy, one action).

## 7. Testing

- Unit: token/posture color mapping; any pure formatting helpers (e.g. display name already covered).
- No snapshot tests required in this pass (simulator visual check on iOS 27).
- Existing `V1TodayDecodingTests` must remain green; UI refactor must not change DTOs.

## 8. Out of scope

- Plan / Coach / Activité / Moi visual systems  
- SwiftUIX / CombineCocoa / SwiftUICharts  
- Custom brand fonts  
- Motion system beyond system defaults  
- Dark-mode-only art direction (support both via system colors)  
- Associated Domains / device signing (orthogonal)

## 9. Success criteria

- Résumé loading and loaded layouts share the same visual grammar.  
- Feature files no longer hard-code verdict font sizes or ad-hoc glass.  
- App still feels Apple-native (system chrome) while the content layer reads as SHARPIT instrument.  
- Build + unit tests pass on iPhone simulator (prefer iOS 27).

## 10. Implementation order (high level)

1. Add `DesignSystem/` tokens + move glass helpers.  
2. Extract `VerdictHero`, `SessionPlate`, `SignalStrip`, loading instrument.  
3. Refactor `TodayView` to compose them.  
4. Visual pass on iOS 27 simulator; commit.

Detailed steps land in `docs/superpowers/plans/2026-09-16-ios-design-system.md` after this spec is approved.
