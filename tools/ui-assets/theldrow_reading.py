"""Build and verify the Pen-reviewed Theldrow outlines for preview or production."""

import argparse
import hashlib
import json
import struct
from pathlib import Path
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.svgLib.path import parse_path
from fontTools.ttLib import TTFont


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_glyph(record):
    pen = TTGlyphPen(None)
    parse_path(
        record["path"],
        TransformPen(Cu2QuPen(pen, 0.5, all_quadratic=True), (1, 0, 0, -1, 0, 0)),
    )
    return pen.glyph()


def read_master(path, baseline):
    master = json.loads(Path(path).read_text(encoding="utf-8"))
    if master["schemaVersion"] != 2:
        raise ValueError("Unsupported reviewed-master schema")
    if digest(baseline) != master["baselineSha256"]:
        raise ValueError("Baseline identity mismatch")
    with TTFont(baseline, recalcTimestamp=False) as font:
        if set(map(int, master["glyphs"])) != set(font.getBestCmap()):
            raise ValueError("Coverage changed")
        if font["head"].unitsPerEm != master["rules"]["unitsPerEm"]:
            raise ValueError("Units per em changed")
    return master


def build(master_path, baseline_path, output_path, production=False):
    master = read_master(master_path, baseline_path)
    if Path(output_path).resolve() == Path(baseline_path).resolve():
        raise ValueError("Never overwrite the baseline")
    font = TTFont(baseline_path, recalcTimestamp=False, checkChecksums=2)
    cmap = font.getBestCmap()
    rules = master["rules"]
    if set(map(int, master["glyphs"])) != set(cmap):
        raise ValueError("Coverage changed")
    for cp, record in master["glyphs"].items():
        name = cmap[int(cp)]
        glyph = source_glyph(record)
        font["glyf"][name] = glyph
        glyph.recalcBounds(font["glyf"])
        font["hmtx"][name] = (
            int(record["advance"]),
            glyph.xMin if glyph.numberOfContours else 0,
        )
    for tag in ("kern", "GPOS", "GSUB", "GDEF", "DSIG", "FFTM"):
        if tag in font:
            del font[tag]
    pairs = rules["kerning"]
    feature = [
        "languagesystem DFLT dflt;",
        "languagesystem latn dflt;",
        "feature kern {",
    ]
    for pair, value in sorted(pairs.items()):
        if len(pair) != 2 or not all(ord(c) in cmap for c in pair):
            raise ValueError("Invalid kerning pair")
        feature.append(f"pos {cmap[ord(pair[0])]} {cmap[ord(pair[1])]} {int(value)};")
    feature.append("} kern;")
    addOpenTypeFeaturesFromString(font, "\n".join(feature))
    set_metrics(font, rules)
    set_candidate_names(
        font, "Theldrow Rebuilt" if production else rules["family"], production
    )
    font["head"].created = font["head"].modified = 2082844800
    font["head"].fontRevision = 1.1
    font["maxp"].recalc(font)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = output_path.with_suffix(output_path.suffix + ".tmp")
    try:
        font.save(temporary, reorderTables=True)
        report = verify(master_path, baseline_path, temporary, production)
        temporary.replace(output_path)
        return report
    finally:
        font.close()
        temporary.unlink(missing_ok=True)


def set_metrics(font, rules):
    upper = max(
        g.yMax
        for g in font["glyf"].glyphs.values()
        if getattr(g, "numberOfContours", 0) > 0
    )
    lower = min(
        g.yMin
        for g in font["glyf"].glyphs.values()
        if getattr(g, "numberOfContours", 0) > 0
    )
    ascent = max(rules["ascent"], upper)
    descent = min(rules["descent"], lower)
    font["hhea"].ascent = ascent
    font["hhea"].descent = descent
    font["hhea"].lineGap = rules["lineGap"]
    os2 = font["OS/2"]
    os2.sTypoAscender = ascent
    os2.sTypoDescender = descent
    os2.sTypoLineGap = rules["lineGap"]
    os2.usWinAscent = ascent
    os2.usWinDescent = -descent
    os2.sCapHeight = rules["capHeight"]
    os2.sxHeight = rules["xHeight"]
    os2.version = max(4, os2.version)
    os2.fsSelection |= 1 << 7


def set_candidate_names(font, family, production=False):
    font["name"].names = [
        n
        for n in font["name"].names
        if n.nameID not in (1, 2, 3, 4, 5, 6, 9, 10, 16, 17)
    ]
    values = {
        1: family,
        2: "Regular",
        3: "TheldrowRebuilt-1.100" if production else "TheldrowReadingCandidate-1.100",
        4: family + " Regular",
        5: "Version 1.100",
        6: "TheldrowRebuilt-Regular"
        if production
        else "TheldrowReadingCandidate-Regular",
        9: "Realmz Rebuilt project; contours refined in Pen",
        10: "Pen-reviewed Theldrow with proportional advances, optical spacing, GPOS kerning and revised vertical metrics."
        if production
        else "Reading candidate with proportional advances, optical spacing, GPOS kerning and revised vertical metrics.",
        16: family,
        17: "Regular",
    }
    for nid, value in values.items():
        font["name"].setName(value, nid, 3, 1, 0x0409)
        font["name"].setName(value, nid, 1, 0, 0)


def verify(master_path, baseline_path, font_path, production=False):
    master = read_master(master_path, baseline_path)
    font = TTFont(font_path, recalcTimestamp=False, checkChecksums=2)
    font.ensureDecompiled()
    cmap = font.getBestCmap()
    if set(cmap) != set(map(int, master["glyphs"])):
        raise ValueError("Compiled coverage differs from master")
    errors = verify_metrics(font, master["rules"], production)
    metrics = verify_glyphs(font, master, errors)
    pair_count = verify_pairs(font, master["rules"], errors)
    data = Path(font_path).read_bytes()
    data += b"\0" * ((-len(data)) % 4)
    if (
        sum(struct.unpack(">" + str(len(data) // 4) + "I", data)) & 0xFFFFFFFF
        != 0xB1B0AFBA
    ):
        errors.append("Font checksum invalid")
    if errors:
        raise ValueError("\n".join(errors))
    report = dict(
        fontSha256=digest(font_path),
        masterSha256=digest(master_path),
        baselineSha256=digest(baseline_path),
        glyphCount=len(cmap),
        kerningPairs=pair_count,
        ascent=font["hhea"].ascent,
        descent=font["hhea"].descent,
        lineGap=font["hhea"].lineGap,
        verified=[
            "coverage",
            "exact compiled Pen contours",
            "Pen outline bounds",
            "exact advances",
            "left bearings",
            "vertical containment",
            "coherent vertical metrics",
            "candidate identity",
            "GPOS pairs",
            "table checksums",
            "font checksum",
        ],
        glyphs=metrics,
    )
    font.close()
    return report


def verify_metrics(font, rules, production=False):
    errors = []
    os2 = font["OS/2"]
    hhea = font["hhea"]
    ink = [g for g in font["glyf"].glyphs.values() if g.numberOfContours > 0]
    expected = (
        max(rules["ascent"], max(g.yMax for g in ink)),
        min(rules["descent"], min(g.yMin for g in ink)),
        rules["lineGap"],
    )
    if (hhea.ascent, hhea.descent, hhea.lineGap) != expected:
        errors.append("Vertical metrics differ from master")
    if (os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap) != expected:
        errors.append("OS/2 and hhea metrics disagree")
    if (os2.usWinAscent, -os2.usWinDescent) != expected[:2]:
        errors.append("Windows vertical metrics disagree")
    if (os2.sxHeight, os2.sCapHeight) != (rules["xHeight"], rules["capHeight"]):
        errors.append("Body and capital metrics differ")
    if font["head"].unitsPerEm != rules["unitsPerEm"]:
        errors.append("Units per em differ")
    if font["name"].getDebugName(1) != (
        "Theldrow Rebuilt" if production else rules["family"]
    ):
        errors.append("Candidate family identity differs")
    if os2.version < 4 or not os2.fsSelection & (1 << 7):
        errors.append("Typographic metric selection is invalid")
    return errors


def verify_glyphs(font, master, errors):
    cmap = font.getBestCmap()
    metrics = []
    for cp, record in master["glyphs"].items():
        name = cmap[int(cp)]
        g = font["glyf"][name]
        g.recalcBounds(font["glyf"])
        expected_glyph = source_glyph(record)
        if expected_glyph.compile(font["glyf"]) != g.compile(font["glyf"]):
            errors.append(f"U+{int(cp):04X}: compiled contours differ from Pen source")
        p = BoundsPen(None)
        parse_path(record["path"], TransformPen(p, (1, 0, 0, -1, 0, 0)))
        actual = BoundsPen(font.getGlyphSet())
        font.getGlyphSet()[name].draw(actual)
        if p.bounds:
            if (
                not actual.bounds
                or max(abs(a - b) for a, b in zip(p.bounds, actual.bounds)) > 1.1
            ):
                errors.append(f"U+{int(cp):04X}: outline bounds changed")
            if font["hmtx"][name][1] != g.xMin:
                errors.append(f"U+{int(cp):04X}: left-bearing mismatch")
            if g.yMax > font["hhea"].ascent or g.yMin < font["hhea"].descent:
                errors.append(f"U+{int(cp):04X}: vertical clipping")
        elif g.numberOfContours:
            errors.append(f"U+{int(cp):04X}: blank acquired ink")
        if font["hmtx"][name][0] != record["advance"]:
            errors.append(f"U+{int(cp):04X}: advance changed")
        metrics.append(
            dict(codepoint=int(cp), advance=record["advance"], bounds=actual.bounds)
        )
    return metrics


def verify_pairs(font, rules, errors):
    cmap = font.getBestCmap()
    actual_pairs = {}
    for lookup in font["GPOS"].table.LookupList.Lookup:
        if lookup.LookupType != 2:
            raise ValueError("Unexpected positioning lookup")
        for sub in lookup.SubTable:
            if sub.Format != 1:
                raise ValueError("Unexpected pair positioning format")
            for first, group in zip(sub.Coverage.glyphs, sub.PairSet):
                for rec in group.PairValueRecord:
                    actual_pairs[first, rec.SecondGlyph] = rec.Value1.XAdvance
    expected = {
        (cmap[ord(p[0])], cmap[ord(p[1])]): v for p, v in rules["kerning"].items()
    }
    if actual_pairs != expected:
        errors.append("GPOS pairs differ from reviewed master")
    return len(expected)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--master", required=True, type=Path)
    p.add_argument("--baseline", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    p.add_argument("--verify-only", action="store_true")
    p.add_argument("--production", action="store_true")
    p.add_argument("--receipt", type=Path)
    a = p.parse_args()
    report = (verify if a.verify_only else build)(
        a.master, a.baseline, a.output, a.production
    )
    if a.receipt:
        a.receipt.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "glyphs"}, indent=2))


if __name__ == "__main__":
    main()
