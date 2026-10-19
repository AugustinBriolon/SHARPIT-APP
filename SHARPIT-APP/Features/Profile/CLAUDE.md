# Training thresholds

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Threshold estimates.** Seuils & repères (`ThresholdsView`) carries the web's
calibration helpers through `ThresholdSuggestionStore` (built when the profile client is also
`ThresholdEstimating`, which `AthleteProfileClient` is). « Proposition depuis tes records »
(`ThresholdSuggestionCard`) shows `GET /api/v1/athlete-profile/apply-estimates`'s `changes` — the
stored value beside the proposed one, both worded by the server, « Hausse / Baisse / Nouveau », each
kept or left out with `SharpitKeepToggle` — and « Appliquer » (« Appliquer (n) » when some are left
out) posts `{ fields: [...] }` (`V1ThresholdField`; the server writes only what it still proposes,
and answers 400 with `reason` — `no_estimates`, `unchanged`, `nothing_selected`, worded by
`V1ThresholdApplyRefusal`). It is a write like the others: the kept estimates show in the profile and
the fields on the tap (`AthleteProfileStore.show`, `V1ThresholdApplyPreview.patch(for:)`), wait for a
value being typed (`settle`), go out through `SharpitRetry`, and `AthleteProfileStore.refresh` reads
the profile and its threshold history back; `revision` then resets the form to the stored values.
Thresholds a watch synced on the web say so in the line above the cards (« Importés de ta montre … »);
the app imports none itself (`docs/adr/0013`). Each discipline is one white card of rows — name and
meaning left, the figure typed in place right — never a coloured tile or a boxed field.
