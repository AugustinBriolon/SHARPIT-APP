# External beta — TestFlight copy and protocol

The copy to paste into App Store Connect (TestFlight › External testing) and the message that
invites the beta's triathletes. Store copy is French, as the app is.

The beta tests the product's bet (positioning 2026-10-02): a plan that repairs itself, measured by
the share of athletes doing at least 70 % of their planned sessions over their first four weeks.
What they write through « Donner un avis » lands in `AthleteFeedback` and in `FEEDBACK_EMAIL`.
Every Monday at 07:00 UTC the web's `/api/cron/beta-report` mails `FEEDBACK_EMAIL` both: the
outcome athlete by athlete and the week's notes (`scripts/reports/beta-report.ts` prints the same
report on demand).

## Beta App Description

> SharpIt est un coach d'endurance qui prépare ta course avec toi. Il lit ta nuit, ta récupération
> et tes séances (Apple Santé, Garmin) et ajuste ton plan au fil des jours : il te propose d'alléger
> quand ta nuit a été courte, te dit quand une séance est dans la boîte et t'aide à réorganiser ta
> semaine quand tu en rates une.
>
> Cette bêta est réservée à quelques triathlètes qui préparent une course. Ton avis façonne la
> suite : tout passe par « Donner un avis », dans Paramètres.

## What to Test

> Merci de tester SharpIt ! Pendant 4 semaines, utilise-le pour préparer ta course :
>
> 1. À l'arrivée : renseigne ta course (format, date) et laisse le coach préparer ta première
>    semaine. Branche Apple Santé (et Garmin si tu en as un).
> 2. Le matin : regarde la proposition du jour. Si ta nuit a été courte, SharpIt peut te proposer
>    d'alléger — accepte ou garde ton plan.
> 3. Après une séance : tu dois recevoir « Séance dans la boîte » dans l'heure qui suit la
>    synchro. Dis-nous si elle n'arrive pas.
> 4. Une séance ratée : le lendemain, « Dommage pour hier » te propose de réorganiser ta semaine.
>    Essaie, et dis-nous si la proposition tient la route.
>
> Un bug, une idée, un truc qui agace ? Paramètres › Donner un avis. On lit tout.

## Beta App Review notes

> Connexion : « Se connecter avec Apple » ou Google, aucun compte de démonstration nécessaire.
> L'onboarding demande le prénom, les sports, une course objectif et les consentements, puis
> génère une première semaine d'entraînement.
>
> Apple Santé est en lecture seule et optionnel : il sert à lire le sommeil, la variabilité
> cardiaque et les séances. Les données de santé restent sur nos serveurs en Europe et ne sont
> jamais synchronisées sur iCloud.
>
> Les notifications (verdict du matin, séance faite, séance manquée, rappels) se règlent dans
> Paramètres › Notifications.

Risk to weigh before submitting: the in-app Garmin connection is on in TestFlight builds
(`ProviderAvailability.garminInApp`) and relies on an unofficial access. Beta App Review applies
the App Review Guidelines (5.2.2): if it is flagged, ship the external beta with Garmin off and keep
Apple Health — Garmin Connect writes its sessions and nights into Apple Health anyway.

## Invitation message

> Salut ! Je lance la bêta de SharpIt, une app qui prépare ta course avec toi et ajuste ton plan
> selon ta forme. Je cherche 3-4 triathlètes pour l'utiliser pendant 4 semaines, à partir de
> maintenant.
>
> Concrètement : tu installes l'app via TestFlight (lien ci-dessous), tu renseignes ta course, et
> tu suis le plan comme d'habitude. SharpIt te fait signe le matin, après tes séances et quand tu
> en rates une. De mon côté, je te demande juste de me dire ce qui marche et ce qui coince —
> directement dans l'app (Paramètres › Donner un avis) ou par message.
>
> Un appel de 15 minutes à la fin des 4 semaines pour faire le point, et c'est tout. Partant ?
>
> [lien TestFlight]

## Running the four weeks

- Week 0: install, onboarding, first week generated — check each tester reached Plan with
  sessions (the adherence report lists them once a session is planned).
- Weekly: read Monday's report mail; answer every note within a day.
- Week 4: the 15-minute call — « la dernière fois que tu as lâché un plan, qu'est-ce qui s'est
  passé ? », then what SharpIt changed. Success: ≥ 70 % of planned sessions done for most testers.
