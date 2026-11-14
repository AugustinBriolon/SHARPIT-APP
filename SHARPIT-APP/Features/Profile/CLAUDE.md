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

**Seuils, Clinique.** `ThresholdsView` follows its mock-up (`docs/adr/0035`): the page's title with
where the figures come from under it, « D'après tes records » in a bordered card (how many to review
as a pill, each proposal a line with its direction and a check, « Appliquer (N) »), then each
discipline as a name over its lines. The mock-up's power-zones bar is not drawn: the profile carries
the thresholds, not the zones.

**Matériel, Clinique.** `EquipmentView` (Paramètres › Matériel) is one page on its mock-up's shape:
« Ajouter » in the bar adds a sport, « Mes sports » lists the sports practiced — glyph in the round
tile, what is owned for it (`SportsReadout.equipmentSummary`), « … » to take it out of the plan,
closed for the last sport a plan can stand on — then the kit by sport (`EquipmentBySport`, the
onboarding's own): a section's name over lines split by hairlines, each what it is, what it changes
for the coach, and « Oui » / « Non », flipped by a tap and saved as it changes (`docs/adr/0014`). The
mock-up's wear — kilometres per shoe, chain and tyres — is not drawn: the app holds a capability
inventory, no mileage per item. `SharpitScreenDemo equipment` shows it.
