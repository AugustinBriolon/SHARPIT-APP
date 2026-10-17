# 0015. New accounts wait for the gate, and a 403 is not a session expiry

Date: 2026-10-17

## Status

Accepted

## Context

New users reported two failures on their first launch: the onboarding wizard did not open, and
"a token problem" during sign-up.

- `AccountGateModel.resolve` read the consents and the profile once. Any failure — Clerk handing
  out no token in the seconds after sign-up, a 401 on a token the server did not take yet, a
  network drop — sent the athlete to the tabs (`.ready`). The gate is only resolved again when the
  Clerk user changes, so nothing ever reopened the wizard: the new account landed in empty tabs.
- From there, the tabs' reads went through `SharpitClient`, which treated **401 and 403** alike:
  refresh the token once, then `AuthSession.expireSession()` — purge the local data and sign out.
  The server answers 403 for refusals that have nothing to do with the session: consents owed
  (`CONSENT_REQUIRED`, health consent), Pro features, the coach's discuss quota. A new account that
  had not accepted the consents was therefore signed out with « Session expirée ».

## Decision

1. The gate's read runs through `SharpitRetry` with a predicate that also retries
   `SharpitAPIError.unauthorized` (`AccountGateModel.isWorthRetrying`): four tries, 1 s / 2 s / 4 s
   apart, each asking for a fresh token.
2. When the read still fails, an athlete the phone remembers as onboarded is let in (the app works
   offline, as before). A never-onboarded account gets `Status.unreachable(message)`: a
   `SharpitStateMessage.failed` screen with « Réessayer » and « Se déconnecter ».
3. `SharpitClient` treats only **401** as a session gone. A 403 is a refusal: it surfaces the
   server's message (or a generic « pas ouverte à ton compte » line) and never purges or signs out.

## Options considered

### Option A — Retry and hold new accounts at the gate (chosen)

Pros: fixes both symptoms at their source; the onboarded athlete's offline behaviour is unchanged.
Cons: a brand-new account with no network cannot enter the app (it would have nothing to show).

### Option B — Let the athlete in and re-resolve the gate on foreground

Pros: never blocks. Cons: the athlete sees empty tabs first, then is yanked into the wizard; the
403 sign-outs still happen in between.

### Option C — Map 403 to a dedicated `forbidden` error everywhere

Pros: a precise type for callers. Cons: a dozen per-resource clients map 403 themselves without
signing out; only `SharpitClient` had the destructive behaviour, so fixing that path is enough
now. Revisit if a screen needs to tell refusals apart.

## Consequences

### Positive
- A new account always lands in the wizard, or on a screen that says why and retries.
- A consents/Pro/quota refusal no longer erases the local cache and signs the athlete out.

### Negative
- Up to ~7 s of launch mark before the unreachable screen on a dead network for a new account.

### Neutral
- `SharpitRetry.run` gains a `retryingOn:` predicate; writes keep the default (`isTransient`).

## References
- `SHARPIT-APP/App/AccountGate.swift`
- `SHARPIT-APP/Networking/SharpitClient.swift`
- `SHARPIT-APPTests/OnboardingTests.swift`, `SHARPIT-APPTests/SharpitClientRefusalTests.swift`
