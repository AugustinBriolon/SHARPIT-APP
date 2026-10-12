# Consent and privacy

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Consent.** `AccountGate` sits between `AuthGate` and `RootView`. A new account meets the
consents inside the onboarding, as its step just before Sources; the legal wall
(`PrivacyConsentWallView`, the web's `/consent`) stands only in front of an athlete already
onboarded. CGU, Politique de confidentialité and the health consent are required together (the
server refuses one without the other), AI processing and the unofficial-providers notice are
optional; the wizard's « Tout accepter » ticks all five, since the first week needs AI. The wall's
reason and the version in force come from `/api/v1/privacy/consent` (`V1PrivacyConsents.wallReason`
mirrors `needsLegalConsentFromProfile`), so a new version of the documents brings the wall back
without an app release. The documents are the web's published `/terms` and `/privacy`, opened
in-app (`LegalDocumentSheet`) — never a bundled copy. Paramètres → Confidentialité & conditions
changes each consent; withdrawing health reports to the gate through the environment and the wall
stands again. It also deletes the account (`/api/v1/privacy/delete`: data, provider access and
the Clerk identity, then a local sign-out; the server e-mails a confirmation). A subscription that
still renews is named in the confirmation, with the App Store's subscription sheet one tap away:
deleting an account cannot cancel it; Compte ends with an immediate sign-out.

Confidentialité › Tes données › « Exporter mes données » reads `/api/v1/privacy/export` (the web's
GDPR export: profile, consents, activities, plan, measures, never a credential, `PrivacyExportClient`),
writes it to a temporary `sharpit-export-<day>.json` (`PrivacyExport`, named by the day, never by the
athlete) and hands it to the system share sheet (`SharpitShareSheet`, `UIActivityViewController`,
`.sheet(item:)` — `ShareLink` needs its file before the tap). The row turns into its progress while
the server builds the file.
