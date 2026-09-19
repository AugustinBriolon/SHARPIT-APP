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

# Reads name ID 6 (PostScript name) out of a TrueType `name` table.
postscript_name() {
  python3 - "$1" <<'PYTHON'
import struct, sys

data = open(sys.argv[1], 'rb').read()
table_count = struct.unpack('>H', data[4:6])[0]
offset, name_offset = 12, None
for _ in range(table_count):
    tag = data[offset:offset + 4]
    table_offset, _length = struct.unpack('>II', data[offset + 8:offset + 16])
    if tag == b'name':
        name_offset = table_offset
    offset += 16

if name_offset is None:
    raise SystemExit(1)

table = data[name_offset:]
record_count, strings_offset = struct.unpack('>HH', table[2:6])
for index in range(record_count):
    platform, _encoding, _language, name_id, length, string_offset = struct.unpack(
        '>HHHHHH', table[6 + index * 12:18 + index * 12]
    )
    if name_id != 6:
        continue
    raw = table[strings_offset + string_offset:strings_offset + string_offset + length]
    print(raw.decode('utf-16-be') if platform == 3 else raw.decode('latin-1'))
    break
PYTHON
}


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
    temporary="${DESTINATION}/.download.ttf"
    curl -fsSL -o "$temporary" "$url"

    # Google serves opaque hashed filenames. Name each file after the PostScript
    # name it actually carries — that is the name `SharpitTypography` asks for, so a
    # mismatch becomes visible in a directory listing instead of at runtime.
    name="$(postscript_name "$temporary")"
    if [[ -z "$name" ]]; then
      echo "  could not read a PostScript name from ${url}" >&2
      rm -f "$temporary"
      exit 1
    fi
    echo "  ${name}"
    mv "$temporary" "${DESTINATION}/${name}.ttf"
  done <<<"$urls"
done

echo
echo "Fonts written to ${DESTINATION}:"
ls -1 "${DESTINATION}"/*.ttf | xargs -n1 basename
