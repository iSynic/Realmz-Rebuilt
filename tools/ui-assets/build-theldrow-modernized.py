#!/usr/bin/env python3
"""Build the deterministic Theldrow Rebuilt TTF from curated Pencil paths."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.recordingPen import DecomposingRecordingPen, replayRecording
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.svgLib.path import parse_path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


CHAR_RE = re.compile(r"^char\s+id=(?P<id>\d+).*?xadvance=(?P<xadvance>-?\d+)\b")
LETTER_CODEPOINTS = list(range(ord("A"), ord("Z") + 1)) + list(
    range(ord("a"), ord("z") + 1)
)
FIGURE_CODEPOINTS = list(range(ord("0"), ord("9") + 1))
PENCIL_WIDTH_LIMIT = 1.12
CU2QU_MAX_ERROR = 2.048


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_metrics(path: Path) -> dict[int, int]:
    records: dict[int, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = CHAR_RE.match(line)
        if match:
            records[int(match.group("id"))] = int(match.group("xadvance"))
    if len(records) != 185:
        raise RuntimeError(f"Expected 185 Castle metrics, found {len(records)}")
    return records


def read_pencil_glyphs(path: Path) -> dict[int, dict[str, object]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schemaVersion") != 1:
        raise RuntimeError("Unsupported Pencil glyph schema")
    glyphs = {
        int(key.removeprefix("U+"), 16): value
        for key, value in payload.get("glyphs", {}).items()
    }
    if sorted(glyphs) != LETTER_CODEPOINTS:
        raise RuntimeError("Pencil source must contain exactly A-Z and a-z")
    return glyphs


def read_rules(path: Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schemaVersion") != 1:
        raise RuntimeError("Unsupported Theldrow styling-rule schema")
    zones: dict[int, tuple[int, int]] = {}
    for record in payload.get("verticalZones", {}).values():
        y_min = int(record["yMin"])
        y_max = int(record["yMax"])
        if y_max <= y_min:
            raise RuntimeError("Theldrow vertical zone has no height")
        for character in str(record["characters"]):
            codepoint = ord(character)
            if codepoint in zones:
                raise RuntimeError(f"Duplicate vertical zone for {character}")
            zones[codepoint] = (y_min, y_max)
    if sorted(zones) != LETTER_CODEPOINTS:
        raise RuntimeError("Theldrow rules must classify exactly A-Z and a-z")
    utility_zones: dict[int, tuple[int, int]] = {}
    for record in payload.get("utilityVerticalZones", {}).values():
        y_min = int(record["yMin"])
        y_max = int(record["yMax"])
        if y_max <= y_min:
            raise RuntimeError("Theldrow utility vertical zone has no height")
        for character in str(record["characters"]):
            codepoint = ord(character)
            if codepoint in utility_zones:
                raise RuntimeError(f"Duplicate utility vertical zone for {character}")
            utility_zones[codepoint] = (y_min, y_max)
    if sorted(utility_zones) != FIGURE_CODEPOINTS:
        raise RuntimeError("Theldrow utility rules must classify exactly 0-9")
    payload["resolvedVerticalZones"] = zones
    payload["resolvedUtilityVerticalZones"] = utility_zones
    return payload


def build_pencil_glyph(
    codepoint: int,
    record: dict[str, object],
    advance: int,
    target_vertical_bounds: tuple[int, int],
    horizontal_rules: dict[str, object],
) -> object:
    view_x, view_y, view_width, view_height = [float(value) for value in record["viewBox"]]
    target_y_min, target_y_max = target_vertical_bounds
    target_height = target_y_max - target_y_min
    if target_height <= 0:
        raise RuntimeError("Target glyph has no vertical extent")
    character = chr(codepoint)
    weight_rules = horizontal_rules.get("weightExpansionUnits", {})
    expansion_x = (
        float(weight_rules.get("capitalX", 0.0)) if character.isupper() else 0.0
    )
    expansion_y = (
        float(weight_rules.get("capitalY", 0.0)) if character.isupper() else 0.0
    )
    base_target_height = target_height - 2.0 * expansion_y
    if base_target_height <= 0:
        raise RuntimeError(f"Weight expansion consumes {character}'s vertical zone")
    scale_y = base_target_height / view_height
    scale_x = scale_y
    projected_width = view_width * scale_x
    optical_width_ratio = horizontal_rules["widthRatios"].get(character)
    if ord("A") <= codepoint <= ord("Z") and optical_width_ratio is None:
        natural_width_ratio = projected_width / advance
        capital_maximum = float(horizontal_rules["capitalMaxWidthRatio"])
        if natural_width_ratio > capital_maximum:
            optical_width_ratio = capital_maximum
    if optical_width_ratio is not None:
        target_width = advance * optical_width_ratio
        base_target_width = target_width - 2.0 * expansion_x
        if base_target_width <= 0:
            raise RuntimeError(f"Weight expansion consumes {character}'s width")
        scale_x *= base_target_width / projected_width
        projected_width = base_target_width
    maximum_width = advance * PENCIL_WIDTH_LIMIT
    final_projected_width = projected_width + 2.0 * expansion_x
    if final_projected_width > maximum_width:
        allowed_base_width = maximum_width - 2.0 * expansion_x
        scale_x *= allowed_base_width / projected_width
        projected_width = allowed_base_width
        final_projected_width = maximum_width
    optical_offset_x = advance * float(
        horizontal_rules["offsetRatios"].get(character, 0.0)
    )
    offset_x = (
        (advance - final_projected_width) / 2.0
        + optical_offset_x
        + expansion_x
        - view_x * scale_x
    )
    offset_y = target_y_max - expansion_y + view_y * scale_y

    glyph_pen = TTGlyphPen(None)
    quadratic_pen = Cu2QuPen(glyph_pen, CU2QU_MAX_ERROR, all_quadratic=True)
    offsets = [(0.0, 0.0)]
    if expansion_x > 0.0 or expansion_y > 0.0:
        offsets.extend(
            [
                (-expansion_x, 0.0),
                (expansion_x, 0.0),
                (0.0, -expansion_y),
                (0.0, expansion_y),
                (-expansion_x, -expansion_y),
                (-expansion_x, expansion_y),
                (expansion_x, -expansion_y),
                (expansion_x, expansion_y),
            ]
        )
    for delta_x, delta_y in offsets:
        transformed = TransformPen(
            quadratic_pen,
            (
                scale_x,
                0.0,
                0.0,
                -scale_y,
                offset_x + delta_x,
                offset_y + delta_y,
            ),
        )
        parse_path(str(record["path"]), transformed)
    return glyph_pen.glyph()


def build_utility_glyph(
    utility: TTFont,
    codepoint: int,
    advance: int,
    target_upm: int,
    target_vertical_bounds: tuple[int, int] | None,
) -> object:
    utility_cmap = utility.getBestCmap()
    glyph_name = utility_cmap.get(codepoint)
    if glyph_name is None:
        if codepoint in (0x007F, 0x00A0):
            return TTGlyphPen(None).glyph()
        raise RuntimeError(f"Utility font has no U+{codepoint:04X}")
    source_upm = utility["head"].unitsPerEm
    scale_x = target_upm / source_upm
    source_advance = utility["hmtx"].metrics[glyph_name][0]
    if source_advance * scale_x > advance * PENCIL_WIDTH_LIMIT:
        scale_x *= (advance * PENCIL_WIDTH_LIMIT) / (source_advance * scale_x)
    offset_x = (advance - source_advance * scale_x) / 2.0
    glyph_set = utility.getGlyphSet()
    recording = DecomposingRecordingPen(glyph_set)
    glyph_set[glyph_name].draw(recording)
    scale_y = scale_x
    offset_y = 0.0
    if target_vertical_bounds is not None:
        bounds_pen = BoundsPen(glyph_set)
        glyph_set[glyph_name].draw(bounds_pen)
        if bounds_pen.bounds is None:
            raise RuntimeError(f"Utility U+{codepoint:04X} has no measurable bounds")
        _, source_y_min, _, source_y_max = bounds_pen.bounds
        source_height = source_y_max - source_y_min
        target_y_min, target_y_max = target_vertical_bounds
        target_height = target_y_max - target_y_min
        if source_height <= 0 or target_height <= 0:
            raise RuntimeError(f"Utility U+{codepoint:04X} has invalid vertical bounds")
        scale_y = target_height / source_height
        offset_y = target_y_min - source_y_min * scale_y
    glyph_pen = TTGlyphPen(None)
    transformed = TransformPen(
        glyph_pen, (scale_x, 0.0, 0.0, scale_y, offset_x, offset_y)
    )
    replayRecording(recording.value, transformed)
    return glyph_pen.glyph()


def update_names(font: TTFont) -> None:
    family = "Theldrow Rebuilt"
    full = "Theldrow Rebuilt Regular"
    values = {
        0: "Realmz art used under the project owner's non-commercial license; utility glyphs retain their source licenses.",
        1: family,
        2: "Regular",
        3: "TheldrowRebuilt-Regular-1.000",
        4: full,
        5: "Version 1.000",
        6: "TheldrowRebuilt-Regular",
        8: "Realmz Rebuilt project",
        9: "Modernized letter contours curated in Pencil; strict production zones and Castle metrics preserved.",
        10: "Modernized derivative of Realmz Theldrow with strict cap, x-height, ascender, descender, sidebearing, and mixed-case optical-weight rules plus Grenze Gotisch OFL utility outlines.",
        13: "Realmz-Art-NonCommercial, CC0-1.0, and OFL-1.1",
        16: family,
        17: "Regular",
    }
    name = font["name"]
    name.names = []
    for name_id, value in values.items():
        name.setName(value, name_id, 3, 1, 0x0409)
        name.setName(value, name_id, 1, 0, 0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glyphs", required=True, type=Path)
    parser.add_argument("--rules", required=True, type=Path)
    parser.add_argument("--metrics", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--utility", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    metrics = read_metrics(args.metrics)
    pencil = read_pencil_glyphs(args.glyphs)
    rules = read_rules(args.rules)
    font = TTFont(args.baseline, recalcTimestamp=False, checkChecksums=2)
    utility = TTFont(args.utility, recalcTimestamp=False, checkChecksums=2)
    if "fvar" in utility:
        utility = instantiateVariableFont(utility, {"wght": 500.0}, inplace=False)
    cmap = font.getBestCmap()
    target_upm = font["head"].unitsPerEm
    if target_upm != int(rules["unitsPerEm"]):
        raise RuntimeError(
            f"Rule UPM {rules['unitsPerEm']} does not match font UPM {target_upm}"
        )

    for codepoint in LETTER_CODEPOINTS:
        glyph_name = cmap.get(codepoint)
        if glyph_name is None:
            raise RuntimeError(f"Baseline font has no U+{codepoint:04X}")
        advance = font["hmtx"].metrics[glyph_name][0]
        font["glyf"][glyph_name] = build_pencil_glyph(
            codepoint,
            pencil[codepoint],
            advance,
            rules["resolvedVerticalZones"][codepoint],
            rules["horizontal"],
        )

    glyph_order = list(font.getGlyphOrder())
    for codepoint in sorted(set(metrics) - set(LETTER_CODEPOINTS)):
        advance = int(math.floor(metrics[codepoint] * target_upm / 15.0 + 0.5))
        glyph_name = cmap.get(codepoint)
        if glyph_name is None:
            glyph_name = f"uni{codepoint:04X}"
            suffix = 1
            while glyph_name in glyph_order:
                suffix += 1
                glyph_name = f"uni{codepoint:04X}.{suffix}"
            glyph_order.append(glyph_name)
            for subtable in font["cmap"].tables:
                if subtable.isUnicode():
                    subtable.cmap[codepoint] = glyph_name
        font["glyf"][glyph_name] = build_utility_glyph(
            utility,
            codepoint,
            advance,
            target_upm,
            rules["resolvedUtilityVerticalZones"].get(codepoint),
        )
        font["hmtx"].metrics[glyph_name] = (advance, 0)
    font.setGlyphOrder(glyph_order)
    font["glyf"].glyphOrder = glyph_order

    for codepoint, pixel_advance in metrics.items():
        glyph_name = font.getBestCmap()[codepoint]
        advance = int(math.floor(pixel_advance * target_upm / 15.0 + 0.5))
        left_bearing = font["hmtx"].metrics[glyph_name][1]
        font["hmtx"].metrics[glyph_name] = (advance, left_bearing)

    update_names(font)
    font["OS/2"].sCapHeight = int(rules["hierarchy"]["capHeight"])
    font["OS/2"].sxHeight = int(rules["hierarchy"]["xHeight"])
    for table in ("DSIG", "FFTM"):
        if table in font:
            del font[table]
    font["head"].created = 0
    font["head"].modified = 0
    font["head"].fontRevision = 1.0
    glyph_keys = set(font["glyf"].glyphs)
    order_keys = set(font.getGlyphOrder())
    if glyph_keys != order_keys or len(font["glyf"].glyphs) != len(font.getGlyphOrder()):
        raise RuntimeError(
            "Glyph order/table mismatch: "
            f"order={len(font.getGlyphOrder())}, glyf={len(font['glyf'].glyphs)}, "
            f"order-only={sorted(order_keys - glyph_keys)}, "
            f"glyf-only={sorted(glyph_keys - order_keys)}"
        )
    font["glyf"].ensureDecompiled()
    for glyph in font["glyf"].glyphs.values():
        if not hasattr(glyph, "numberOfContours"):
            glyph.numberOfContours = 0
        if glyph.numberOfContours == 0:
            glyph.xMin = glyph.yMin = glyph.xMax = glyph.yMax = 0
        else:
            glyph.recalcBounds(font["glyf"])
    font["maxp"].recalc(font)
    if hasattr(font["OS/2"], "recalcUnicodeRanges"):
        font["OS/2"].recalcUnicodeRanges(font)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    font.save(temporary, reorderTables=True)
    built = TTFont(temporary, recalcTimestamp=False, checkChecksums=2)
    coverage = set(metrics) - set(built.getBestCmap())
    if coverage:
        raise RuntimeError(
            "Built font lacks Castle codepoints: "
            + ", ".join(f"U+{value:04X}" for value in sorted(coverage))
        )
    temporary.replace(args.output)
    print(
        f"Built {args.output} with {len(metrics)} Castle codepoints; "
        f"SHA-256 {sha256(args.output)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
