# Nutrition and food log

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Nutrition.** The food log is the athlete's own data and open to everyone; only the coach's
reading is SharpIt Pro (the server sends `{ state: 'pro_required' }` below it and never generates
it), and `NutritionView` shows a `SharpitProTeaser` in its place. `NutritionTodayStore` maps the
answer to the card's states (empty, loaded, failed — an empty day invites to log a meal, a failed read says so and opens
the day, which can retry). `NutritionView` is native, not the web's page: the energy on the app's
tick dial (`SharpitTickGauge`) with goal, exercise and remaining under it, the coach's reading on
the ink plate, the three macros as tiles and the energy split by macro, the meals as a list whose
rows push `NutritionMealView` (entries heaviest first, with the coach's flags), and 14 days of regularity against the calorie goal
(each day's adherence is the server's; the strip reads, it does not navigate). A header carries the
diet in force (from the journal) and the coach pill — the coach pill and the reading's button attach
`CoachDiscussTarget.nutrition` (« Ta nutrition du jour »), never the day state; the « … » menu adds or scans a food, opens
the nutrition targets (`NutritionTargetsSheet`: macros in grams or as % of the energy, the split's
arithmetic in `NutritionTargetSplit`), opens the weight target (`WeightTargetSheet`) or creates one
and, last, « Importer depuis MyFitnessPal ». The Résumé card follows the gauge cells: tinted badge, energy against
the goal, the macros as columns, a context capsule. Goals, percentages and the reading are the
web's; `NutritionReadout` formats them and derives only the energy split (Atwater). Meals and the
add sheet's ways in are ink, told by glyph and name (`SharpitNutritionTone`, ADR-085); the macros
alone keep three tones — protein ink, carbohydrates lime, fat grey — on their columns and on every
food's thin energy-split bar (`NutritionMacroSplitBar`). The goal bar fills lime and turns caution
only past 110 % of the goal.

**Food log.** The log lives in SHARPIT (SHARPIT ADR-061, `/api/v1/food-log`, `FoodLogClient`): the
page is never a « connect a provider » wall (`connected` is always true). `FoodLogStore`, owned by
`NutritionView`, holds the day's entries by meal (Petit-déjeuner, Déjeuner, Dîner, Collations), the
targets and the recent foods. Each meal row has its « + », which opens `FoodAddSheet` — the search
(`FoodSearchStore`, debounced: « Déjà mangés » — the athlete's foods of the last 90 days, with how often and the last portion — then own foods, Ciqual's generic foods and Open Food Facts; a verified food, Ciqual or manufacturer-given, carries `checkmark.seal.fill` after its name, SHARPIT ADR-069), the barcode scanner
(`BarcodeScannerView`, VisionKit's `DataScannerViewController`, offered only where it is supported
and available), « Mes aliments » (`OwnFoodsStore`, `/api/v1/food-log/foods/mine`: tap to pick, swipe
to edit through the custom-food form or delete after asking — logged entries keep their snapshot;
also Paramètres › Nutrition, `OwnFoodsSettingsView`),
a quick add, a custom food per 100 g, then the portion (`FoodPortionPage`: grams
with presets and a live preview, `FoodPortion` mirroring the web's `portionNutrients`). A meal's
page (`FoodLogMealPage`) shows the meal's score (`MealHealthSection`: the energy-weighted mean of its foods' scores and why, SHARPIT ADR-070 — the server's, shown only while the meal's entries are the ones it scored, `FoodLogStore.mealHealth`; the day's sits beside « Repas ») and edits an entry on tap (`FoodEntryEditSheet`) and deletes it on swipe. What MyFitnessPal athletes
log with every day is one tap away (SHARPIT ADR-071): the page's « … » (and a long press on a meal's
row) copies the same meal of the day before (`FoodLogStore.copyFromPreviousDay`, `/api/v1/food-log/copy`;
the empty day's plate offers « Copier la veille » for the whole day); the same menu on an empty meal marks it skipped on purpose (« J'ai sauté ce repas », `FoodLogStore.setSkipped`, `/api/v1/food-log/skipped`, SHARPIT ADR-113), so the coach's reading does not take it for a gap — the row then reads « Repas sauté », and food logged in it clears the mark (`isSkipped` trusts it only while the meal is empty) and keeps the meal under a name
(`saveMeal`, `/api/v1/food-log/meals`); the add sheet's « Mes repas » (`SavedMealsStore`,
`SavedMealsPage`) logs one whole into the meal, shown at once (`logSavedMeal`), and « Créer une
recette » (`FoodRecipePage`, `FoodRecipeBuilder`) builds an own food from other foods — ingredients
weighed raw, the cooked weight and servings optional, the label per 100 g live (`FoodRecipeLabel`,
the web's `recipeLabel`) — then goes on to its portion; a recipe opened from « Mes aliments » edits
its ingredients (`/api/v1/food-log/recipes`). Every
write shows at once and goes out through `SharpitRetry`, put back and toasted if it fails for good;
the server rebuilds the day, so the page reads `/api/v1/nutrition` again for the totals. A described meal (`FoodDescribePage`) validated whole shows all its foods at once and goes out in one request (`FoodLogStore.add(_ drafts:)`, `POST /api/v1/food-log/entries/batch`, all stored or none), its rows swapped for the server's in one change. Open Food
Facts is asked by the server only, and « Données Open Food Facts (ODbL) » stands wherever its
products are listed or picked. The iPhone app never links or syncs MyFitnessPal — its access is
unofficial, App Review 5.2.2 (`docs/adr/0010`, a test guards the routes): the athlete imports their
own MFP export instead (`MyFitnessPalImportSheet`, a ZIP or CSV picked in Fichiers, posted as
multipart to `/api/v1/food-log/import/myfitnesspal`, `MultipartFormData`). A day imported (or synced
on the web) keeps its meals read-only (`NutritionMealView`); the day's own log wins once it holds an
entry. A day without a log draws its own empty plate (never the scaffold's generic empty screen),
which invites to scan or search a first food.

**Ajouter un aliment, Clinique.** The add sheet's search follows its mock-up (`docs/adr/0035`): the
meal as the title with a cross, a capsule search field beside the scanner, chips (« Tous », « Récents »,
« Mes repas », « Mes aliments », « Autre… » for describe, quick add, create a food or a recipe), then
the foods as lines split by hairlines — name, « 100 g · 124 kcal » and what it is, the score at the
trailing edge (`FoodProductRow`, everywhere it is listed). A food still pushes its portion page: the
mock-up's portion stepper docked on the search is not built.

**Repas et portion, Clinique.** A meal's page (`FoodLogMealPage`) follows its mock-up: the meal as
the large title under the nutrition wash, its energy read big with « 31 % de ta journée »
(`FoodLogMealReadout.share`, only against a target), the macros' split on one bar and their grams
(`FoodPortionPreview`, shared by the portion, the edit sheet and a recipe), « Qualité du repas » as a
bordered card, each food a line — name, grams, energy, its own split — and « Ajouter un aliment »
docked (« Copier hier » beside it while the meal is empty). The portion (`FoodPortionPage`) reads the
grams big between − and + (10 g a tap, typed in place too, `FoodGramsRows`), the presets as chips,
then « Pour 200 g » a line per nutrient marked in its hue (`FoodNutrientLines`) and « Ajouter au
dîner » (`FoodLogMeal.addTitle`). Macros keep one hue everywhere — carbs blue, protein purple, fat
green (`NutritionReadout.Macro.tone`) — and one order. `SharpitScreenDemo meal` / `portion` show them.
The mock-ups' recipe, saved meals, own food, food quality, targets and import pages take the shared
list's shape; their own heroes are not built yet.

**Qualité, mes repas, Clinique.** A food's quality (`FoodHealthScoreHeader`) is its score in a ring
in the grade's status hue, the grade as a pill (`FoodHealthPresentation.status`), the verdict and its
sources; each reason is a line marked by a bar in its status hue (`FoodHighlightRow`), never
coloured words or a tick dial. A saved meal is a line — its name, its first foods and their count,
its energy. `SharpitScreenDemo quality` / `savedmeals` / `ownfood` / `recipe` show them.

**Objectifs, Clinique.** `NutritionTargetsSheet` reads the day's energy big between − and + (50 kcal
a tap), then « Répartition »: the macros' split on one bar, grams or shares typed in hairline fields.
The mock-up's per-macro steppers are not built: the fields accept an empty value, which removes a
target. `SharpitScreenDemo targets` shows it.

**Energy ring (2026-11-15).** The ring holds what was eaten; beside it the goal, exercise, and
« Restant » (« Au-delà » once passed) — the athlete's call, reversing the mock-up's remaining-in-ring.

**One « Objectifs » (2026-11-16).** The « … » menu has one line for the targets: `NutritionTargetsSheet`
ends on « Poids cible » (`WeightTargetPlate`, shared with Santé's `WeightTargetSheet`) and one
« Enregistrer » saves the nutrition targets and the profile's `targetWeightKg`; the weight is never
written before the profile is read. « Objectif tenu » is a status pill on its own line under the
figures: laid over the plate it covered the ring.

**A described meal reads as one (2026-11-16).** `FoodDescribePage`'s review opens on the meal — the
athlete's words, the energy big, the macros' split (`DescribedMealTotal`) — over « N aliments », folded
while every food is a known one and open with « À vérifier » when one is the model's guess. A food is a
line (« 200 g · 620 kcal »); a tap opens its grams. The log still stores each food
(`entries/batch`): scores, coach flags and « Déjà mangés » are per food. `SharpitScreenDemo describe`.

**A meal logged whole (SHARPIT ADR-134, 2026-11-16).** A described meal is logged under a name — the
review's « Nom du repas », opened on the athlete's words (`DescribedMealTotal.name`) — sent with the
batch (`group: { label }`). Its foods stay entries carrying `groupId` / `groupLabel`; a meal's page
folds them into one line (`FoodLogMealItem`, `FoodLogGroupRow`: name, « N aliments », energy) that
opens onto the foods, each still edited or deleted on its own. A swipe on the line deletes the meal
and its foods after asking (`FoodLogStore.deleteGroup`, `DELETE /food-log/groups/[id]`). A group down
to one food is shown as that food. A server older than ADR-134 ignores the name: the foods log ungrouped.

**Meal glyphs, a named meal kept, the pinned filter (the athlete's remarks, 2026-11-17).** A meal's
line starts with its glyph (`NutritionMealGlyph`, `NutritionReadout.mealSymbol`: sunrise, sun, moon,
leaf), on the day's log and on an imported day. A long press on a named meal's line offers
« Enregistrer dans Mes repas » — `saveMeal(_:name:groupId:)` sends `groupId`, so only that meal's foods
are kept, under its name by default — and « Supprimer ». A meal's page ends on « Ajouter un aliment »
alone, full width, no dock; « Copier la veille » is in « … ». In the add sheet « Autre… » is pinned at
the trailing edge, opaque; the chips' row is clipped inside it, so a chip slides under it and never
shows beyond. `SharpitScreenDemo meals` draws the day's four meals. Seen on the simulator: the glyphs,
the long press and its naming alert, the button, a chip under « Autre… ». The context menu's preview
cuts the line's text flush at its leading edge. « Supprimer » carries its bin in red itself
(`withTintColor`, always original): on the athlete's iPhone the menu drew it in the app's ink tint.

**The food typed, to create (the athlete's remark, 2026-11-17).** A search of all foods ends on one
more line, `FoodCreateRow`: the words typed as the name, « Créer cet aliment », a « + » where a
result carries its score. The whole line opens the custom-food form with that name
(`.custom(name: query)`), found or not — Open Food Facts lists a brand's other products for one it
lacks (SHARPIT ADR-136). Not shown under « Récents ». Written without Xcode: not built or seen yet.

**When a food was eaten (SHARPIT ADR-137, the athlete's request, 2026-11-19).** The portion, the
quick add, a described meal's review and the edit sheet carry « Heure » under the meal
(`FoodEatenTimePicker`, the system's compact time picker), sent as `eatenMinute` — minutes after the
day's local midnight. `FoodEatenTime` decides what goes out: logging the meal of the hour today opens
on now and sends it; any other meal or day opens on the meal's usual hour (08:00, 12:30, 16:00, 19:30,
the server's) and sends nothing until the athlete sets it — the athlete often logs the day in the
evening, and a guess never reaches the server as a fact. An untouched time follows a change of meal.
A meal's page shows the time before the grams (« 12:40 · 150 g »). The server places each meal of
« Fil de la journée » at its foods' time and gives the times to the coach's reading of the day. Written
without Xcode: not built or seen yet.
