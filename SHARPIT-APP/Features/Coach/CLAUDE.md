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
