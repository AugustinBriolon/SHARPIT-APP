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
the empty day's plate offers « Copier la veille » for the whole day) and keeps the meal under a name
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
