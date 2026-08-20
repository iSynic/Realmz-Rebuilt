#!/usr/bin/env python3
"""Normalize Pencil's HTML/CSS export into deterministic Theldrow glyph data."""

from __future__ import annotations

import argparse
import json
import re
from html.parser import HTMLParser
from pathlib import Path


GLYPH_NAME_RE = re.compile(r"^Glyph (.) U\+([0-9A-F]{4,6})$")
EXPECTED_CODEPOINTS = set(range(ord("A"), ord("Z") + 1)) | set(
    range(ord("a"), ord("z") + 1)
)


class PencilGlyphParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._active: dict[str, object] | None = None
        self.glyphs: dict[int, dict[str, object]] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value for key, value in attrs if value is not None}
        if tag == "svg":
            name = values.get("data-pencil-name", "")
            match = GLYPH_NAME_RE.match(name)
            if match is None:
                self._active = None
                return
            codepoint = int(match.group(2), 16)
            character = match.group(1)
            if ord(character) != codepoint:
                raise RuntimeError(f"Glyph label mismatch: {name}")
            view_box = [float(value) for value in values["viewbox"].split()]
            if len(view_box) != 4 or view_box[2] <= 0 or view_box[3] <= 0:
                raise RuntimeError(f"Invalid viewBox for {name}: {view_box}")
            self._active = {
                "character": character,
                "codepoint": codepoint,
                "pencilNodeId": values.get("data-pencil-id", ""),
                "viewBox": view_box,
            }
        elif tag == "path" and self._active is not None:
            geometry = values.get("d", "")
            if not geometry or not geometry.rstrip().lower().endswith("z"):
                raise RuntimeError(
                    f"Glyph U+{int(self._active['codepoint']):04X} has an open or empty path"
                )
            record = dict(self._active)
            record["path"] = geometry
            codepoint = int(record["codepoint"])
            if codepoint in self.glyphs:
                raise RuntimeError(f"Duplicate glyph U+{codepoint:04X}")
            self.glyphs[codepoint] = record

    def handle_endtag(self, tag: str) -> None:
        if tag == "svg":
            self._active = None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    reader = PencilGlyphParser()
    reader.feed(args.input.read_text(encoding="utf-8"))
    actual = set(reader.glyphs)
    if actual != EXPECTED_CODEPOINTS:
        missing = ", ".join(f"U+{value:04X}" for value in sorted(EXPECTED_CODEPOINTS - actual))
        extra = ", ".join(f"U+{value:04X}" for value in sorted(actual - EXPECTED_CODEPOINTS))
        raise RuntimeError(f"Expected 52 Basic Latin letters; missing [{missing}], extra [{extra}]")

    payload = {
        "schemaVersion": 1,
        "source": {
            "designTool": "Pencil",
            "documentFrame": "Medieval Classic - Vector Character Study",
            "license": "Realmz-Art-NonCommercial",
            "note": "Project-owner-approved modernized derivative of licensed Realmz Theldrow art.",
        },
        "glyphs": {
            f"U+{codepoint:04X}": {
                "character": record["character"],
                "pencilNodeId": record["pencilNodeId"],
                "viewBox": record["viewBox"],
                "path": record["path"],
            }
            for codepoint, record in sorted(reader.glyphs.items())
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"Extracted {len(reader.glyphs)} Pencil glyphs to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
