# Coach

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Coach turns and proposals.** A coach turn is kept as the AI SDK's UI-message parts
(`CoachMessage.parts`), rebuilt from the route's stream by `CoachUIMessageAssembler` — a port of
the SDK's `processUIMessageStream` — and sent back whole: on the next question, on an approval,
and in the saved thread. Nothing in them is trimmed, because the server replays them: provider
metadata carries the model's thought signatures, and an approval carries the server's
`signature`. A calendar tool (`CoachUIParts.calendarToolTypes`) that stops at
`approval-requested` is a `CoachProposalCard` (Valider / Refuser, a second « Confirmer » for a
deletion); once every proposal of the step has an answer, `CoachStore.respond` sends the turn
back and the server carries out the approved ones and goes on writing in the same message, as
`useChat`'s `sendAutomaticallyWhen` does. A new question refuses the proposals left open
(`dismissingUnresolved`), and an applied change bumps `ShellRouter.calendarRevision` so Plan and
Résumé reload. The wording follows the web's `coach-tool-approval-helpers.tsx`.

**Coach thread.** The thread reads like ChatGPT's: a question sent rises to the top
(`CoachThreadLayout` splits the turn under way, which fills at least the screen) and the answer
unrolls below without moving the view; once it runs past the composer, a small glass arrow takes
the athlete to its end. Plain glass on that arrow: interactive glass on a floating button kept
its taps. A thumb on the thread puts the keyboard away, even on an empty conversation. An empty
field turns the send button into the microphone (`CoachDictation`, French, on-device when
possible); the frameworks' callbacks are built in nonisolated functions, since main-actor
closures trap when called on their queues. `-SharpitCoachDemo` scripts two questions on a
streamed answer in Debug builds.

**The wait and the words (the athlete's call, 2026-11-22).** While no words come, one slate line
under the question says what the coach is doing, a band of ink passing over it
(`CoachActivityLine`): « Lecture de tes données » before the server's first chunk, « Réflexion »
once a step is open, the tool being called by its name (« Lecture de ton plan », « Construction de
la séance »), « Analyse » once tools answered, « Application du changement » after an approval.
`CoachActivity.current(parts:)` reads it from the turn's parts — what the stream says, never a
script on a timer — and a line stays 0.65 s at least so quick steps do not flicker. It is gone
once words arrive and leaves no trace in the thread: no « a réfléchi 12 s », no list of steps.
The answer is not typed: `SharpitMarkdownText(isStreaming:)` reveals prose line by line
(`SharpitFadeFrontRenderer`, a `TextRenderer`): a line fades in whole as the stream reaches it and
the words that then join it are simply there — glyph by glyph read as slow (the athlete's call,
2026-11-24); a table, a code block or a list's marker fades in once. Text already there (history)
never fades. Nothing in the composer animates as the page opens (`hasOpened`,
`composerIsSettled`): the budget card and a subject brought from another screen are simply
there; the card fades when an answer takes the budget past half, and nothing slides or scales.

**Coach quota.** The coach is SharpIt Pro (SHARPIT ADR-097); the coach routes share a token budget
per rolling 24 h (ADR-077: about 62 questions Pro). `CoachStore` reads `/api/v1/coach/quota`
(`CoachQuotaClient`, `V1CoachQuota`) on open and after each answer; once half is spent, a thin gauge
above the composer counts the questions left or says when the budget frees up
(`CoachQuotaReadout`). A Free quota (or a `pro_required` refusal on send) sets `needsPro`, and
`SharpitProTeaser` takes the composer's place. The counts are the web's.

**Coach history.** The server keeps the conversations and the client saves the whole thread
after each answer, as the web does. A turn opened from history keeps its stored JSON
(`CoachMessage.stored`) and goes back as it came, its parts brought up to date. The chat route
reports model and gateway failures *inside* a 200 stream (an `error` event); `CoachChatClient`
turns it into `CoachChatError` and logs the chunk kinds of every answer under the `coach`
category, so a silent answer names its cause.

**Clinique.** The thread is swept (`docs/adr/0035`): one sheet under the coach's wash, secondary
text in slate, a failure or a spent budget in the watch status ink, a destructive answer in the
alert one. The cards a turn carries (proposal, workout, food log, data cards) are the shared
bordered cards. The history, the usage sheet and the memory are not swept.

**Chrome.** « Coach » sits in the bar's row; the clock opens a menu (Conversations, Mémoire,
Consommation) and the pencil starts a new conversation. Neither the athlete's bubble nor the
coach's answer carries a name over it: the side and the bubble say who speaks. The composer is one glass box (see « Composer, second pass »).

**Mémoire du coach, Clinique.** `CoachMemoryView` follows its mock-up (`docs/adr/0035`): how many
things are kept under the title (`CoachMemoryReadout.lead`), kinds as chips with their count, each
entry a line — the athlete's sentence, its kind and when it was kept, « Pèse sur le plan » when it
constrains training — that opens to be corrected, with a cross that erases it; « Dire quelque chose au
coach » floats at the bottom; the athlete's own profile text closes the page.

**Cartes de données, Clinique.** A data card in the conversation (`CoachDataCardView`) keeps its
border and opens on a quiet line — what it reads and for which day (`CoachCardCaption`), a pill at
the trailing edge — never a section title or an icon tile. `SharpitScreenDemo coachcards` shows the
three cards from the web's own fixtures. The mock-up's sparkline in a card is not built: the tool
returns the day's figures, not a series.

**Cards, audit (2026-11-15).** A data card is drawn only when the coach calls one of the three
read tools; the server's prompt left that optional, so answers came without cards. The web's prompt
now asks for the tool first (SHARPIT `coach-system-prompt.ts`, « Cartes de données ») — effective
once the web is deployed. « Consommation » and « Historique » are titled sheets with their cross
(`CliniqueSheetTitle`, `cliniqueSheetCross`): the budget read big over a thin bar and two lines;
conversations as hairline rows, the open one tagged « Ouverte ».

**Data cards, light (2026-11-15).** `CoachDataCardView` is a white card inside a hairline that rises
and fades in as it arrives (a fade alone under Reduce Motion). Scores: a thin bar per score in its
hue, filling on arrival. Effort target: the window read big over its place on the 0–21 effort
track, the form on its own line (another scale). Sleep and form: a column a day — sleep as a bar,
form as a dot — and a tap on a day reads its two figures (`CoachDataCardLayout`).

The bar reads « nouvelle conversation » then « ⋯ » (Conversations, Mémoire, Consommation), the list of actions on the right.

« Consommation » gives a time only once the budget is spent (« De nouveau disponible »): a rolling
window has no reset date to show.

**Proposal card, Clinique (the athlete's call, 2026-11-15).** A calendar change the coach proposes
(`CoachProposalCard`) is a bordered card: what it does as a status pill beside the day, the session
as the title, its figures on one slate line, the steps as numbered lines between hairlines, then
one ink button that says what it does (« Ajouter au plan », « Appliquer la modification »,
« Maintenir pour supprimer » — `CoachProposalReadout.approve`) over
« Modifier » and « Ignorer ». Settled, it is one bordered line: the session, its day (or why it
failed), and what became of it as a pill (`CoachProposalReadout.outcome`), a spinner while it is
applied. No tinted chips, numbered discs or coloured wash. `SharpitScreenDemo proposal` shows every state.

**Cards you can act on (the athlete's call, 2026-11-22).** A deletion is confirmed by holding
its button, not by a second tap: `CliniqueHoldButton` fills with ink from its leading edge for
1.2 s, its title turning over as the ink passes, and runs back out if the finger lifts early;
the consequence is said over it from the start. VoiceOver's double tap confirms. No haptic: a
confirmation is not a notch under the finger. A change carried out is a line with a chevron
that opens Plan on its day (`CoachProposal.day`, `ShellRouter.openPlan(on:)`); a deletion, a
refusal or a failure opens nothing. A session the coach drew (`CoachWorkoutCard`) carries
« Ajouter au plan » while it is the thread's last answer: it sends the request as the athlete's
own question, and the coach answers with a proposal — the card never writes the plan. Every
card fades in once as it arrives in an answer being written (`sharpitStreamArrival`).

**Composer, second pass (the athlete's call, 2026-11-24).** One glass box on two floors
(`composerBox`, `composerIsExpanded`): at rest a single line — « + », the question, the trailing
control; written in, carrying a subject, listening or past a short line, the words take the whole
width and the controls drop to a row under them. The `TextField` is one view on both floors — only
its insets move — so the box opening never drops the keyboard. One trailing control
(`composerButton`): the microphone as a plain glyph while the field is empty, then the ink button —
send once there are words, stop while listening or while the coach answers — the ink growing under
the glyph as the symbol morphs. « + » opens the starting points as one bordered card growing from
its corner (`quickActionsPanel`, `CoachQuickActionList`: lines split by hairlines), no longer five
floating pills. A subject brought from another screen sits inside the box, over the words
(`CoachContextTag(isInline:)`). Dictation keeps the box: the wave and « Écoute… » take the « + »'s
corner and the words land in the field. The budget is one quiet line under the box (`quotaLine`: a
short gauge, the count, « Passer Pro » for a Free athlete), in the watch ink once spent; the card
and its cross are gone. Every control in the box is pressable (`.sharpitPressable`) and the box in
hand shows a hairline edge. An empty thread stays bare (the athlete's call, same day): its title and
one sentence at the top, and three starting points (`CoachQuickAction.suggested`) as plain lines
just over the box — no rule, no card — gone as soon as something is typed, joined or the « + » is
open; no arrow down there. The subject's tag is Clinique: a slate clip, the label, its cross — the
ink disc with a lime clip was the earlier brand's. Unchanged rules: nothing animates as the page opens, no bounce, no haptic,
`SharpitMotion` only.
