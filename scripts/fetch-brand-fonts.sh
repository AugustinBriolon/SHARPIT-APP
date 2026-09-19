#!/usr/bin/env bash
#
# Downloads the three SHARPIT brand typefaces into the app bundle (ADR-041).
#
# All three are SIL Open Font License 1.1, which permits embedding in an application.
# The weights match `src/app/layout.tsx` in the web repository, so the native ramp and
# the web ramp resolve to the same faces.
#
# Static per-weight TTFs are requested on purpose: a variable font registers under a
# single PostScript name, and `SharpitTypography` asks for `Syne-SemiBold` by name.
#
# Run this once, then commit the files. `SharpitFonts.register()` picks up anything in
# `SHARPIT-APP/Resources/Fonts` at launch — no Info.plist or project changes needed.

set -euo pipefail

DESTINATION="$(cd "$(dirname "$0")/.." && pwd)/SHARPIT-APP/Resources/Fonts"

# An old User-Agent makes Google Fonts serve static TTF rather than woff2.
LEGACY_USER_AGENT="Mozilla/4.0"

# family:weights, as declared in the web layout.
FAMILIES=(
  "Syne:500;600;700"
  "IBM+Plex+Sans:400;500;600"
  "JetBrains+Mono:400;500"
)

mkdir -p "$DESTINATION"

for entry in "${FAMILIES[@]}"; do
  family="${entry%%:*}"
  weights="${entry##*:}"
  css_url="https://fonts.googleapis.com/css2?family=${family}:wght@${weights}"

  echo "Resolving ${family//+/ } (${weights})"
  css="$(curl -fsSL -A "$LEGACY_USER_AGENT" "$css_url")"

  urls="$(grep -oE "https://[^)]+\.ttf" <<<"$css" | sort -u)"
  if [[ -z "$urls" ]]; then
    echo "  no static TTF returned for ${family//+/ } — check the family name" >&2
    exit 1
  fi

  while IFS= read -r url; do
    name="$(basename "$url")"
    echo "  ${name}"
    curl -fsSL -o "${DESTINATION}/${name}" "$url"
  done <<<"$urls"
done

echo
echo "Fonts written to ${DESTINATION}."
echo "Verify the PostScript names the app asks for:"
echo "  fc-scan --format '%{postscriptname}\\n' ${DESTINATION}/*.ttf"
echo "They must include Syne-Medium, Syne-SemiBold, Syne-Bold, IBMPlexSans-Regular,"
echo "IBMPlexSans-Medium, IBMPlexSans-SemiBold, JetBrainsMono-Regular, JetBrainsMono-Medium."
