# Brand fonts

Empty until `scripts/fetch-brand-fonts.sh` is run once and the result committed.

The three families (Syne, IBM Plex Sans, JetBrains Mono, all SIL OFL 1.1) carry most of
the SHARPIT identity on the web — see ADR-041. Until the files land here,
`SharpitTypography` resolves to the system face: the layout is correct, only the identity
is missing.

`SharpitFonts.register()` registers whatever it finds in the bundle at launch, so adding a
weight needs no project or Info.plist change.
