#!/usr/bin/env python3
"""Verify the strict Theldrow production-sheet rules against a built TTF."""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont


CHAR_RE = re.compile(r"^char\s+id=(?P<id>\d+).*?xadvance=(?P<xadvance>-?\d+)\b")
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
FIGURES = "0123456789"
BOUNDS_TOLERANCE = 16
RATIO_TOLERANCE = 0.008
CURVE_STEPS = 16
DENSITY_SCANLINES = 256


class FlattenedContourPen(BasePen):
    def __init__(self, glyph_set: object) -> None:
        super().__init__(glyph_set)
        self.contours: list[list[tuple[float, float]]] = []
        self._current: list[tuple[float, float]] = []

    def _moveTo(self, point: tuple[float, float]) -> None:
        self._current = [point]

    def _lineTo(self, point: tuple[float, float]) -> None:
        self._current.append(point)

    def _curveToOne(
        self,
        control_one: tuple[float, float],
        control_two: tuple[float, float],
        point: tuple[float, float],
    ) -> None:
        start = self._getCurrentPoint()
        for step in range(1, CURVE_STEPS + 1):
            t = step / CURVE_STEPS
            inverse = 1.0 - t
            self._current.append(
                (
                    inverse**3 * start[0]
                    + 3.0 * inverse**2 * t * control_one[0]
                    + 3.0 * inverse * t**2 * control_two[0]
                    + t**3 * point[0],
                    inverse**3 * start[1]
                    + 3.0 * inverse**2 * t * control_one[1]
                    + 3.0 * inverse * t**2 * control_two[1]
                    + t**3 * point[1],
                )
            )

    def _qCurveToOne(
        self, control: tuple[float, float], point: tuple[float, float]
    ) -> None:
        start = self._getCurrentPoint()
        for step in range(1, CURVE_STEPS + 1):
            t = step / CURVE_STEPS
            inverse = 1.0 - t
            self._current.append(
                (
                    inverse**2 * start[0]
                    + 2.0 * inverse * t * control[0]
                    + t**2 * point[0],
                    inverse**2 * start[1]
                    + 2.0 * inverse * t * control[1]
                    + t**2 * point[1],
                )
            )

    def _closePath(self) -> None:
        if self._current and self._current[-1] != self._current[0]:
            self._current.append(self._current[0])
        if len(self._current) >= 4:
            self.contours.append(self._current)
        self._current = []

    def _endPath(self) -> None:
        self._closePath()


def filled_density(
    glyph_set: object,
    glyph_name: str,
    measured_bounds: tuple[int, int, int, int],
) -> float:
    x_min, y_min, x_max, y_max = measured_bounds
    width = x_max - x_min
    height = y_max - y_min
    pen = FlattenedContourPen(glyph_set)
    glyph_set[glyph_name].draw(pen)
    filled_area = 0.0
    for scanline in range(DENSITY_SCANLINES):
        y = y_min + (scanline + 0.5) * height / DENSITY_SCANLINES
        crossings: list[tuple[float, int]] = []
        for contour in pen.contours:
            for start, end in zip(contour, contour[1:]):
                if start[1] <= y < end[1]:
                    fraction = (y - start[1]) / (end[1] - start[1])
                    crossings.append((start[0] + fraction * (end[0] - start[0]), 1))
                elif end[1] <= y < start[1]:
                    fraction = (y - end[1]) / (start[1] - end[1])
                    crossings.append((end[0] + fraction * (start[0] - end[0]), -1))
        crossings.sort(key=lambda value: value[0])
        winding = 0
        interval_start = 0.0
        row_width = 0.0
        for x, delta in crossings:
            previous_winding = winding
            winding += delta
            if previous_winding == 0 and winding != 0:
                interval_start = x
            elif previous_winding != 0 and winding == 0:
                row_width += x - interval_start
        filled_area += row_width * height / DENSITY_SCANLINES
    return filled_area / (width * height)


def read_metrics(path: Path, units_per_em: int) -> dict[int, int]:
    records: dict[int, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = CHAR_RE.match(line)
        if match:
            records[int(match.group("id"))] = int(
                math.floor(int(match.group("xadvance")) * units_per_em / 15.0 + 0.5)
            )
    if len(records) != 185:
        raise RuntimeError(f"Expected 185 Castle metrics, found {len(records)}")
    return records


def resolve_zones(rules: dict[str, object]) -> dict[str, tuple[int, int]]:
    zones: dict[str, tuple[int, int]] = {}
    for record in rules["verticalZones"].values():
        for character in record["characters"]:
            if character in zones:
                raise RuntimeError(f"Duplicate vertical zone for {character}")
            zones[character] = (int(record["yMin"]), int(record["yMax"]))
    if sorted(zones) != sorted(LETTERS):
        raise RuntimeError("Rules do not classify exactly A-Z and a-z")
    return zones


def resolve_utility_zones(rules: dict[str, object]) -> dict[str, tuple[int, int]]:
    zones: dict[str, tuple[int, int]] = {}
    for record in rules["utilityVerticalZones"].values():
        for character in record["characters"]:
            if character in zones:
                raise RuntimeError(f"Duplicate utility vertical zone for {character}")
            zones[character] = (int(record["yMin"]), int(record["yMax"]))
    if sorted(zones) != sorted(FIGURES):
        raise RuntimeError("Utility rules do not classify exactly 0-9")
    return zones


def bounds(font: TTFont, glyph_name: str) -> tuple[int, int, int, int]:
    glyph = font["glyf"][glyph_name]
    glyph.recalcBounds(font["glyf"])
    return glyph.xMin, glyph.yMin, glyph.xMax, glyph.yMax


def assert_close(actual: int, expected: int, label: str) -> None:
    if abs(actual - expected) > BOUNDS_TOLERANCE:
        raise RuntimeError(f"{label}: expected {expected}, found {actual}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", required=True, type=Path)
    parser.add_argument("--metrics", required=True, type=Path)
    parser.add_argument("--rules", required=True, type=Path)
    args = parser.parse_args()

    rules = json.loads(args.rules.read_text(encoding="utf-8"))
    if rules.get("schemaVersion") != 1:
        raise RuntimeError("Unsupported Theldrow styling-rule schema")
    zones = resolve_zones(rules)
    utility_zones = resolve_utility_zones(rules)
    font = TTFont(args.font, recalcTimestamp=False, checkChecksums=2)
    units_per_em = font["head"].unitsPerEm
    if units_per_em != int(rules["unitsPerEm"]):
        raise RuntimeError("Built font UPM does not match the production sheet")
    metrics = read_metrics(args.metrics, units_per_em)
    cmap = font.getBestCmap()
    glyph_set = font.getGlyphSet()
    horizontal = rules["horizontal"]

    for codepoint, expected_advance in metrics.items():
        glyph_name = cmap.get(codepoint)
        if glyph_name is None:
            raise RuntimeError(f"Missing Castle glyph U+{codepoint:04X}")
        actual_advance = font["hmtx"].metrics[glyph_name][0]
        if actual_advance != expected_advance:
            raise RuntimeError(
                f"U+{codepoint:04X} advance: expected {expected_advance}, "
                f"found {actual_advance}"
            )

    for character in FIGURES:
        glyph_name = cmap[ord(character)]
        _, y_min, _, y_max = bounds(font, glyph_name)
        expected_y_min, expected_y_max = utility_zones[character]
        assert_close(y_min, expected_y_min, f"{character} yMin")
        assert_close(y_max, expected_y_max, f"{character} yMax")

    densities: dict[str, float] = {}
    measured: dict[str, tuple[int, int, int, int, int]] = {}
    for character in LETTERS:
        glyph_name = cmap[ord(character)]
        x_min, y_min, x_max, y_max = bounds(font, glyph_name)
        advance = font["hmtx"].metrics[glyph_name][0]
        measured[character] = (x_min, y_min, x_max, y_max, advance)
        expected_y_min, expected_y_max = zones[character]
        assert_close(y_min, expected_y_min, f"{character} yMin")
        assert_close(y_max, expected_y_max, f"{character} yMax")

        target_ratio = horizontal["widthRatios"].get(character)
        if target_ratio is not None:
            actual_ratio = (x_max - x_min) / advance
            if abs(actual_ratio - float(target_ratio)) > RATIO_TOLERANCE:
                raise RuntimeError(
                    f"{character} width ratio: expected {target_ratio}, "
                    f"found {actual_ratio:.4f}"
                )

        if character.isupper():
            left_ratio = x_min / advance
            right_ratio = (advance - x_max) / advance
            if left_ratio < float(horizontal["minimumCapitalLeftRatio"]):
                raise RuntimeError(f"{character} left sidebearing is too small")
            if right_ratio < float(horizontal["minimumCapitalRightRatio"]):
                raise RuntimeError(f"{character} right sidebearing is too small")
            special = horizontal["specialMinimumRightRatios"].get(character)
            if special is not None and right_ratio < float(special):
                raise RuntimeError(f"{character} special right sidebearing is too small")

        width = x_max - x_min
        height = y_max - y_min
        densities[character] = filled_density(
            glyph_set, glyph_name, (x_min, y_min, x_max, y_max)
        )

    hierarchy = rules["hierarchy"]
    cap_height = int(hierarchy["capHeight"])
    x_height = int(hierarchy["xHeight"])
    if font["OS/2"].sCapHeight != cap_height:
        raise RuntimeError("OS/2 cap height does not match the production sheet")
    if font["OS/2"].sxHeight != x_height:
        raise RuntimeError("OS/2 x-height does not match the production sheet")
    if x_height / cap_height > float(hierarchy["maximumXHeightToCapHeightRatio"]):
        raise RuntimeError("Lowercase x-height is too close to the capital height")
    h_bounds = measured["h"]
    if h_bounds[3] - cap_height < int(hierarchy["minimumHAboveCap"]):
        raise RuntimeError("Lowercase h does not rise far enough above the cap line")
    if -h_bounds[1] < int(hierarchy["minimumHBelowBaseline"]):
        raise RuntimeError("Lowercase h does not extend far enough below the baseline")

    for pair, minimum_gap in rules["pairMinimumGapUnits"].items():
        first, second = pair
        first_bounds = measured[first]
        second_bounds = measured[second]
        gap = first_bounds[4] - first_bounds[2] + second_bounds[0]
        if gap < int(minimum_gap):
            raise RuntimeError(
                f"{pair} pair gap: expected at least {minimum_gap}, found {gap}"
            )

    capital_density = rules["inkDensity"]["capitalRange"]
    lowercase_density = rules["inkDensity"]["lowercaseRange"]
    for character, density in densities.items():
        lower, upper = capital_density if character.isupper() else lowercase_density
        if not float(lower) <= density <= float(upper):
            raise RuntimeError(
                f"{character} ink density {density:.4f} is outside "
                f"[{lower}, {upper}]"
            )

    ink_density = rules["inkDensity"]
    capital_reference = [densities[value] for value in ink_density["capitalReferenceCharacters"]]
    lowercase_reference = [densities[value] for value in ink_density["lowercaseReferenceCharacters"]]
    reference_ratio = statistics.median(capital_reference) / statistics.median(
        lowercase_reference
    )
    minimum_reference_ratio = float(ink_density["minimumReferenceMedianRatio"])
    if reference_ratio < minimum_reference_ratio:
        raise RuntimeError(
            "Capital reference weight remains too light: "
            f"expected ratio {minimum_reference_ratio}, found {reference_ratio:.4f}"
        )
    for pair, minimum_ratio in ink_density["minimumMixedCasePairRatios"].items():
        capital, lowercase = pair
        actual_ratio = densities[capital] / densities[lowercase]
        if actual_ratio < float(minimum_ratio):
            raise RuntimeError(
                f"{pair} mixed-case weight ratio: expected at least {minimum_ratio}, "
                f"found {actual_ratio:.4f}"
            )

    if "kern" in font or "GPOS" in font:
        raise RuntimeError("Theldrow Rebuilt must retain its zero-kerning contract")

    print(
        "Verified strict Theldrow rules: exact Castle advances, "
        "52 letter zones, cap-height figures, cap/x-height hierarchy, A/H sidebearings, "
        "pair gaps, mixed-case optical weight, ink-density envelopes, and zero kerning."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
