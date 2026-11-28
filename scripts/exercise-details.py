#!/usr/bin/env python3
"""Copies each exercise's body part, equipment and target muscle from the web's catalog into the
app's bundled index (`details`: id -> [bodyPart, equipment, target]), for the exercise sheet's
« À propos ». Run from the repository with the web app checked out beside it:

    python3 scripts/exercise-details.py ../SHARPIT-WEBAPP/packages/app/src/data/exercises-catalog.json
"""
import json
import sys

INDEX = "SHARPIT-APP/Resources/exercises-media-index.json"

catalog = json.load(open(sys.argv[1]))
index = json.load(open(INDEX))
index["details"] = {
    entry["id"]: [entry["bodyPart"], entry["equipment"], entry["target"]]
    for entry in catalog
    if entry["id"] in index["media"]
}
with open(INDEX, "w") as out:
    json.dump(index, out, separators=(",", ":"), ensure_ascii=False)
print(f"{len(index['details'])} exercises described")
