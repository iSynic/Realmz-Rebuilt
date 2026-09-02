#!/usr/bin/env python3
"""Build deterministic Theldrow glyph and specimen sheets.

The source character set and native glyph strike come from the committed Castle
FONT 1601 export.  The scalable sheet uses the committed Samuel-outline TTF with
those same Castle advances.  Outputs are design references, not runtime assets.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


EXPECTED = {
    "Theldrow-Classic.fnt": "58d26ee47c046a97ca3332dc65819f9eb3c0c9ea54128ba785b66a83309c8dcb",
    "Theldrow-Classic.png": "7dbba1d6638e5a27049098acf41f648ea390b3a482610f8065f809b5c753f394",
    "Theldrow-Classic-Vector.ttf": "999aafa27022234d06e26b2385f3dda46cb0e1ea7e440b9e7e51a170e8586eea",
}

CHAR_RE = re.compile(
    r"^char\s+id=(?P<id>\d+)\s+x=(?P<x>\d+)\s+y=(?P<y>\d+)\s+"
    r"width=(?P<width>\d+)\s+height=(?P<height>\d+)\s+"
    r"xoffset=(?P<xoffset>-?\d+)\s+yoffset=(?P<yoffset>-?\d+)\s+"
    r"xadvance=(?P<xadvance>-?\d+)"
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_sources(font_dir: Path) -> None:
    for name, expected in EXPECTED.items():
        path = font_dir / name
        actual = sha256(path)
        if actual != expected:
            raise RuntimeError(f"{name} SHA-256 mismatch: expected {expected}, got {actual}")


def read_characters(fnt_path: Path) -> list[dict[str, int]]:
    characters: list[dict[str, int]] = []
    for line in fnt_path.read_text(encoding="utf-8").splitlines():
        match = CHAR_RE.match(line)
        if not match:
            continue
        characters.append({key: int(value) for key, value in match.groupdict().items()})
    if len(characters) != 185:
        raise RuntimeError(f"Expected 185 Theldrow characters, found {len(characters)}")
    return characters


def read_ttf_cmap(ttf_path: Path) -> set[int]:
    """Return mapped Unicode codepoints from format 4/12 cmap subtables."""
    data = ttf_path.read_bytes()
    num_tables = struct.unpack_from(">H", data, 4)[0]
    cmap_offset = None
    for index in range(num_tables):
        offset = 12 + index * 16
        tag, _checksum, table_offset, _length = struct.unpack_from(">4sIII", data, offset)
        if tag == b"cmap":
            cmap_offset = table_offset
            break
    if cmap_offset is None:
        raise RuntimeError("Theldrow vector TTF has no cmap table")

    _version, subtable_count = struct.unpack_from(">HH", data, cmap_offset)
    codepoints: set[int] = set()
    subtable_offsets: set[int] = set()
    for index in range(subtable_count):
        _platform, _encoding, relative_offset = struct.unpack_from(
            ">HHI", data, cmap_offset + 4 + index * 8
        )
        subtable_offsets.add(cmap_offset + relative_offset)

    for offset in sorted(subtable_offsets):
        format_number = struct.unpack_from(">H", data, offset)[0]
        if format_number == 4:
            seg_count = struct.unpack_from(">H", data, offset + 6)[0] // 2
            end_codes_offset = offset + 14
            start_codes_offset = end_codes_offset + seg_count * 2 + 2
            deltas_offset = start_codes_offset + seg_count * 2
            range_offsets_offset = deltas_offset + seg_count * 2
            for segment in range(seg_count):
                end_code = struct.unpack_from(">H", data, end_codes_offset + segment * 2)[0]
                start_code = struct.unpack_from(">H", data, start_codes_offset + segment * 2)[0]
                delta = struct.unpack_from(">h", data, deltas_offset + segment * 2)[0]
                range_offset = struct.unpack_from(">H", data, range_offsets_offset + segment * 2)[0]
                if start_code == 0xFFFF and end_code == 0xFFFF:
                    continue
                for codepoint in range(start_code, end_code + 1):
                    if range_offset == 0:
                        glyph_id = (codepoint + delta) & 0xFFFF
                    else:
                        glyph_address = (
                            range_offsets_offset
                            + segment * 2
                            + range_offset
                            + (codepoint - start_code) * 2
                        )
                        glyph_id = struct.unpack_from(">H", data, glyph_address)[0]
                        if glyph_id:
                            glyph_id = (glyph_id + delta) & 0xFFFF
                    if glyph_id:
                        codepoints.add(codepoint)
        elif format_number == 12:
            group_count = struct.unpack_from(">I", data, offset + 12)[0]
            for group in range(group_count):
                start, end, first_glyph = struct.unpack_from(">III", data, offset + 16 + group * 12)
                if first_glyph:
                    codepoints.update(range(start, end + 1))
    return codepoints


def tile_background(size: tuple[int, int], tile_path: Path) -> Image.Image:
    tile = Image.open(tile_path).convert("RGB")
    canvas = Image.new("RGB", size, (18, 21, 22))
    for y in range(0, size[1], tile.height):
        for x in range(0, size[0], tile.width):
            canvas.paste(tile, (x, y))
    return canvas


def native_glyph(atlas: Image.Image, record: dict[str, int], scale: int) -> Image.Image:
    width = record["width"]
    if width == 0:
        return Image.new("RGBA", (1, record["height"] * scale), (255, 255, 255, 0))
    crop = atlas.crop(
        (
            record["x"],
            record["y"],
            record["x"] + width,
            record["y"] + record["height"],
        )
    )
    return crop.resize((crop.width * scale, crop.height * scale), Image.Resampling.NEAREST)


def draw_vector_glyph(
    canvas: Image.Image,
    font: ImageFont.FreeTypeFont,
    character: str,
    cell_box: tuple[int, int, int, int],
) -> None:
    if character.isspace():
        return
    draw = ImageDraw.Draw(canvas)
    bbox = draw.textbbox((0, 0), character, font=font, anchor="lt")
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    x0, y0, x1, y1 = cell_box
    x = x0 + (x1 - x0 - width) // 2 - bbox[0]
    y = y0 + (y1 - y0 - height) // 2 - bbox[1]
    draw.text((x, y), character, font=font, fill=(255, 255, 255, 255), anchor="lt")


def build_glyph_sheets(
    output_dir: Path,
    font_dir: Path,
    characters: list[dict[str, int]],
) -> dict[str, object]:
    columns = 16
    rows = math.ceil(len(characters) / columns)
    cell_width = 128
    cell_height = 128
    size = (columns * cell_width, rows * cell_height)
    vector_sheet = Image.new("RGBA", size, (255, 255, 255, 0))
    native_sheet = Image.new("RGBA", size, (255, 255, 255, 0))
    vector_path_source = font_dir / "Theldrow-Classic-Vector.ttf"
    vector_font = ImageFont.truetype(str(vector_path_source), 88)
    vector_codepoints = read_ttf_cmap(vector_path_source)
    native_atlas = Image.open(font_dir / "Theldrow-Classic.png").convert("RGBA")
    cells: list[dict[str, object]] = []

    for index, record in enumerate(characters):
        row, column = divmod(index, columns)
        x = column * cell_width
        y = row * cell_height
        codepoint = record["id"]
        character = chr(codepoint)
        box = (x, y, x + cell_width, y + cell_height)
        if codepoint in vector_codepoints:
            draw_vector_glyph(vector_sheet, vector_font, character, box)

        native = native_glyph(native_atlas, record, 6)
        native_x = x + (cell_width - native.width) // 2
        native_y = y + (cell_height - native.height) // 2
        native_sheet.alpha_composite(native, (native_x, native_y))

        cells.append(
            {
                "index": index,
                "codepoint": codepoint,
                "unicode": f"U+{codepoint:04X}",
                "character": character,
                "row": row,
                "column": column,
                "x": x,
                "y": y,
                "width": cell_width,
                "height": cell_height,
                "nativeAdvance": record["xadvance"],
                "vectorAvailable": codepoint in vector_codepoints,
            }
        )

    vector_path = output_dir / "theldrow-vector-glyph-sheet.png"
    native_path = output_dir / "theldrow-native-glyph-sheet.png"
    vector_sheet.save(vector_path, format="PNG", optimize=False, compress_level=9)
    native_sheet.save(native_path, format="PNG", optimize=False, compress_level=9)

    mapping = {
        "schemaVersion": 1,
        "font": "Theldrow Classic",
        "purpose": "Design reference; transparent cells are suitable for tracing and recoloring.",
        "columns": columns,
        "rows": rows,
        "cellWidth": cell_width,
        "cellHeight": cell_height,
        "vectorGlyphCount": sum(record["id"] in vector_codepoints for record in characters),
        "nativeGlyphCount": len(characters),
        "sourceHashes": EXPECTED,
        "cells": cells,
    }
    map_path = output_dir / "theldrow-glyph-sheet.json"
    map_path.write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return mapping


def build_reference_sheet(
    output_dir: Path,
    font_dir: Path,
    characters: list[dict[str, int]],
) -> None:
    columns = 16
    rows = math.ceil(len(characters) / columns)
    cell_width = 150
    cell_height = 146
    header_height = 104
    size = (columns * cell_width, header_height + rows * cell_height)
    canvas = Image.new("RGBA", size, (18, 21, 22, 255))
    draw = ImageDraw.Draw(canvas)
    vector_path_source = font_dir / "Theldrow-Classic-Vector.ttf"
    glyph_font = ImageFont.truetype(str(vector_path_source), 78)
    vector_codepoints = read_ttf_cmap(vector_path_source)
    native_atlas = Image.open(font_dir / "Theldrow-Classic.png").convert("RGBA")
    title_font = ImageFont.truetype(str(font_dir / "Theldrow-Classic-Vector.ttf"), 44)
    label_font = ImageFont.truetype(str(font_dir / "AlegreyaSans-Regular.ttf"), 17)
    gold = (224, 184, 76)
    ivory = (238, 232, 210)
    muted = (154, 162, 164)
    border = (70, 77, 79)

    draw.text((24, 18), "Theldrow Classic glyph reference", font=title_font, fill=gold)
    draw.text(
        (26, 68),
        "185 Castle FONT 1601 characters rendered from the remetricked vector font",
        font=label_font,
        fill=muted,
    )
    for index, record in enumerate(characters):
        row, column = divmod(index, columns)
        x = column * cell_width
        y = header_height + row * cell_height
        fill = (25, 29, 30) if (row + column) % 2 == 0 else (21, 25, 26)
        draw.rectangle((x, y, x + cell_width - 1, y + cell_height - 1), fill=fill, outline=border)
        character = chr(record["id"])
        if not character.isspace() and record["id"] in vector_codepoints:
            bbox = draw.textbbox((0, 0), character, font=glyph_font, anchor="lt")
            glyph_width = bbox[2] - bbox[0]
            glyph_height = bbox[3] - bbox[1]
            glyph_x = x + (cell_width - glyph_width) // 2 - bbox[0]
            glyph_y = y + 10 + (92 - glyph_height) // 2 - bbox[1]
            draw.text((glyph_x, glyph_y), character, font=glyph_font, fill=ivory, anchor="lt")
        elif not character.isspace():
            native = native_glyph(native_atlas, record, 5)
            native_x = x + (cell_width - native.width) // 2
            native_y = y + 10 + (92 - native.height) // 2
            canvas.alpha_composite(native, (native_x, native_y))
        suffix = "" if record["id"] in vector_codepoints else " native"
        label = f"U+{record['id']:04X}  adv {record['xadvance']}{suffix}"
        label_bbox = draw.textbbox((0, 0), label, font=label_font)
        label_x = x + (cell_width - (label_bbox[2] - label_bbox[0])) // 2
        draw.text((label_x, y + 116), label, font=label_font, fill=muted)

    canvas.save(output_dir / "theldrow-glyph-reference.png", format="PNG", optimize=False, compress_level=9)


def draw_text(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int],
) -> None:
    draw.text(xy, text, font=font, fill=fill)


def build_specimen(output_dir: Path, repo_root: Path, font_dir: Path) -> None:
    width, height = 1920, 1200
    canvas = tile_background(
        (width, height), repo_root / "src/presentation/assets/ui/classic-charcoal-slate-tile.png"
    )
    draw = ImageDraw.Draw(canvas, "RGBA")
    gold = (224, 184, 76)
    ivory = (238, 232, 210)
    muted = (162, 170, 172)
    border = (97, 105, 108)
    panel = (12, 15, 16, 188)

    draw.rounded_rectangle((44, 38, width - 44, height - 38), radius=12, fill=panel, outline=border, width=2)
    title_font = ImageFont.truetype(str(font_dir / "Theldrow-Classic-Vector.ttf"), 78)
    section_font = ImageFont.truetype(str(font_dir / "Theldrow-Classic-Vector.ttf"), 44)
    sample_font = ImageFont.truetype(str(font_dir / "Theldrow-Classic-Vector.ttf"), 64)
    body_font = ImageFont.truetype(str(font_dir / "Theldrow-Classic-Vector.ttf"), 42)
    small_font = ImageFont.truetype(str(font_dir / "Theldrow-Classic-Vector.ttf"), 28)
    utility_font = ImageFont.truetype(str(font_dir / "AlegreyaSans-Regular.ttf"), 24)

    draw_text(draw, (84, 62), "Theldrow Classic", title_font, gold)
    draw_text(
        draw,
        (88, 148),
        "Samuel outlines remetricked to the exact Castle FONT 1601 horizontal advances",
        utility_font,
        muted,
    )
    draw.line((84, 192, width - 84, 192), fill=border, width=2)

    draw_text(draw, (84, 222), "Uppercase", section_font, gold)
    draw_text(draw, (84, 274), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", sample_font, ivory)
    draw_text(draw, (84, 366), "Lowercase", section_font, gold)
    draw_text(draw, (84, 418), "abcdefghijklmnopqrstuvwxyz", sample_font, ivory)
    draw_text(draw, (84, 510), "Numerals and punctuation", section_font, gold)
    draw_text(draw, (84, 562), "0123456789  ! ? & @ # $ % ( ) [ ] { } + - = / \\", sample_font, ivory)

    draw.line((84, 654, width - 84, 654), fill=border, width=2)
    draw_text(draw, (84, 684), "Display", section_font, gold)
    draw_text(draw, (84, 736), "Realmz Rebuilt", title_font, gold)
    draw_text(draw, (84, 832), "Classic Adventures Reconstructed", sample_font, ivory)
    draw_text(draw, (84, 924), "The quick brown fox jumps over the lazy dog.", body_font, ivory)
    draw_text(draw, (84, 994), "Small UI sample: Search  Area Search  Items  Spells  Trade", small_font, muted)
    draw_text(
        draw,
        (84, 1100),
        "Transparent atlas pages and a Unicode cell map are generated beside this specimen.",
        utility_font,
        muted,
    )
    canvas.save(output_dir / "theldrow-specimen.png", format="PNG", optimize=False, compress_level=9)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Output directory (default: artifacts/font-sheets/theldrow-classic)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    font_dir = repo_root / "src/presentation/assets/fonts"
    output_dir = args.output_dir or repo_root / "artifacts/font-sheets/theldrow-classic"
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    verify_sources(font_dir)
    characters = read_characters(font_dir / "Theldrow-Classic.fnt")
    build_glyph_sheets(output_dir, font_dir, characters)
    build_reference_sheet(output_dir, font_dir, characters)
    build_specimen(output_dir, repo_root, font_dir)

    print(f"Built Theldrow font sheets in {output_dir}")
    for path in sorted(output_dir.iterdir()):
        if path.is_file():
            print(f"{path.name}: {sha256(path)}")


if __name__ == "__main__":
    main()
