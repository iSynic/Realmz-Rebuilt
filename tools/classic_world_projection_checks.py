"""Independent Classic player-map, land-layout, and map-tile projection checks.

Native offsets are zero-based, big-endian, and transcribed from the pinned
Castle `mapstuff.c` consumer (`mapstuff.c:79-106`, `:118-125`) and Providence's
explicit map transpose (`classic_world.rs:83-109`, `:155-172`). The land map's
C `field[x][y]` storage is compared to canonical document `y*90+x` order; the
dungeon map is compared in linear native order. This module checks a compiled
v7 package; it does not decode or authorize source content.
"""
from __future__ import annotations

import struct

PLAYER_MAP_BYTES = 340
PLAYER_MAP_WORDS = 42
PLAYER_MAP_NOTE_OFFSET = 84
PLAYER_MAP_NOTE_BYTES = 256
MAP_CELLS = 90 * 90
MAP_BYTES = MAP_CELLS * 2
LAYOUT_BYTES = 256
LAYOUT_CELLS = 128


def _i16(data, offset):
    return struct.unpack_from(">h", data, offset)[0]


def _words(data, offset, count):
    return list(struct.unpack_from(f">{count}h", data, offset))


def _mac_text(data):
    return data.decode("mac_roman").replace("\0", " ").replace("\r", "\n")


def _note(row):
    size = row[0]
    return _mac_text(row[1:1 + min(size, PLAYER_MAP_NOTE_BYTES - 1)])


def _operational(words):
    show, icon_size, level = words[35], words[34], words[32]
    return show < 0 or (icon_size > 0 and (words[33] != 0 or level >= 0))


def _map_by_id(rows, field, require, label):
    require(isinstance(rows, list), f"{label}: expected array")
    result = {}
    for row in rows:
        require(isinstance(row, dict) and field in row,
                f"{label}: malformed row or missing {field}")
        key = row[field]
        require(key not in result, f"{label}: duplicate identity {key!r}")
        result[key] = row
    return result


def _compare_world_maps(world, native, compare, require, checked):
    maps = world.get("maps")
    require(isinstance(maps, list), "world maps: expected array")
    source_maps = {}
    for row in maps:
        require(isinstance(row, dict), "world maps: malformed row")
        key = (row.get("levelType"), row.get("levelIndex"))
        require(key not in source_maps, f"world maps: duplicate source identity {key!r}")
        source_maps[key] = row
    for level_type, path in (("land", "Data LD"), ("dungeon", "Data DL")):
        if path not in native:
            continue
        raw = native[path]
        complete, tail = divmod(len(raw), MAP_BYTES)
        record_facts = 0
        for index in range(complete):
            row = source_maps.get((level_type, index))
            require(row is not None, f"{path}: omitted complete map {index}")
            actual = row.get("classicTileValues")
            require(isinstance(actual, list), f"{path} {index}: missing classicTileValues")
            native_row = raw[index * MAP_BYTES:(index + 1) * MAP_BYTES]
            if level_type == "land":
                # Castle stores field[x][y] in C row-major memory. Providence
                # documents cells in canonical y*90+x order; transpose explicitly.
                expected = [_i16(native_row, (x * 90 + y) * 2)
                            for y in range(90) for x in range(90)]
            else:
                # Dungeon field storage is consumed as the native linear row.
                expected = _words(native_row, 0, MAP_CELLS)
            compare(actual, expected, path, index, "classicTileValues")
            require(row.get("width") == 90 and row.get("height") == 90,
                    f"{path} {index}: document dimensions differ from native 90x90")
            require(row.get("levelType") == level_type and row.get("levelIndex") == index,
                    f"{path} {index}: map source identity differs")
            record_facts += 1
        checked.append({"nativePath": path, "completeRecordsCompared": record_facts,
                        "partialBytesRetained": tail,
                        "nativeCellOrder": "x-major-transposed-to-y-major" if level_type == "land" else "linear"})


def _target_map_id(world, level_type, level_index):
    for row in world.get("maps", []):
        if row.get("levelType") == level_type and row.get("levelIndex") == level_index:
            return row.get("id")
    return f"{level_type}:{level_index}"


def verify(content, world, native, compare, require, assets=None, application_assets=None):
    """Verify v7 player-map facts and operational world projections.

    `native` maps exact native filenames to effective source bytes. The parent
    verifier independently checks original/effective source retention and edit
    receipts; this function reports the physical partial tails it observed.
    """
    checked = []
    media = {row['id']: row for row in (application_assets or [])}
    media.update({row['id']: row for row in (assets or [])})
    def resource(identity, resource_type, resource_id):
        value = media.get(identity)
        if value is not None:
            require(value.get('resourceType') == resource_type and value.get('resourceId') == resource_id,
                    f'Data MD2: {identity} changed exact {resource_type} {resource_id} identity')
        else:
            require(identity == f'classic.resource.{resource_type}.{resource_id}',
                    f'Data MD2: unresolved media identity does not retain exact {resource_type} {resource_id}')
    raw = native.get("Data MD2")
    if raw is not None:
        complete, tail = divmod(len(raw), PLAYER_MAP_BYTES)
        facts = content.get("classicRecords", {}).get("playerMaps")
        require(isinstance(facts, list), "Data MD2: missing classicRecords.playerMaps")
        require(len(facts) == complete,
                f"Data MD2: facts contain {len(facts)} rows for {complete} complete native records")
        operational_ids = []
        facts_only = []
        world_rows = _map_by_id(world.get("playerMaps"), "classicId", require, "world playerMaps")
        expected_world_ids = set()
        for index in range(complete):
            row = raw[index * PLAYER_MAP_BYTES:(index + 1) * PLAYER_MAP_BYTES]
            fact = facts[index]
            require(isinstance(fact, dict) and fact.get("id") == index,
                    f"Data MD2: player-map facts missing physical id {index}")
            expected_words = _words(row, 0, PLAYER_MAP_WORDS)
            expected_note_bytes = list(row[PLAYER_MAP_NOTE_OFFSET:PLAYER_MAP_NOTE_OFFSET + PLAYER_MAP_NOTE_BYTES])
            compare(fact.get("words"), expected_words, "Data MD2", index, "words")
            compare(fact.get("noteBytes"), expected_note_bytes, "Data MD2", index, "noteBytes")
            if index >= 20:
                facts_only.append({"id": index, "reason": "outside fixed Classic player-map catalog"})
                continue
            if not _operational(expected_words):
                facts_only.append({"id": index, "reason": "nonoperational native row; unsafe crop inputs are not evaluated"})
                continue
            operational_ids.append(index)
            expected_world_ids.add(index)
            actual = world_rows.get(index)
            require(actual is not None, f"Data MD2: operational player-map {index} omitted from world")
            compare(actual.get("id"), f"classic.player-map.{index}", "Data MD2", index, "id")
            compare(actual.get("classicId"), index, "Data MD2", index, "classicId")
            compare(actual.get("start"), {"x": expected_words[30], "y": expected_words[31]},
                    "Data MD2", index, "start")
            compare(actual.get("iconSize"), expected_words[34], "Data MD2", index, "iconSize")
            compare(actual.get("note"), _note(row[84:]), "Data MD2", index, "note")
            compare(actual.get("pictureRect"), {"top": expected_words[38], "left": expected_words[39],
                    "bottom": expected_words[40], "right": expected_words[41]},
                    "Data MD2", index, "pictureRect")
            show, picture_id, level, is_dungeon = expected_words[35], expected_words[33], expected_words[32], expected_words[36] != 0
            if show < 0:
                mode, expected_map = "scrolling-text", None
                resource(actual.get('scrollingTextAssetId'), 'TEXT', show)
            elif picture_id != 0:
                mode, expected_map = "picture", _target_map_id(world, "dungeon" if is_dungeon else "land", level)
            else:
                mode, expected_map = ("dungeon-crop" if is_dungeon else "land-crop"), _target_map_id(world, "dungeon" if is_dungeon else "land", level)
            compare(actual.get("mode"), mode, "Data MD2", index, "mode")
            if expected_map is not None:
                compare(actual.get("mapId"), expected_map, "Data MD2", index, "mapId")
                resource(actual.get('partyMarkerAssetId'), 'cicn', 138)
            if mode in ("land-crop", "dungeon-crop"):
                markers = [{"classicIconId": expected_words[s], "x": expected_words[s + 1], "y": expected_words[s + 2]}
                           for s in range(0, 30, 3) if expected_words[s] != 0]
                actual_markers = actual.get("markers")
                require(isinstance(actual_markers, list), f"Data MD2 {index}: crop markers are missing")
                compare([{key: item.get(key) for key in ("classicIconId", "x", "y")} for item in actual_markers],
                        markers, "Data MD2", index, "markers")
                for marker in actual_markers:
                    resource(marker.get('iconAssetId'), 'cicn', marker['classicIconId'])
            elif mode == "picture":
                resource(actual.get('pictureAssetId'), 'PICT', picture_id)
            else:
                compare(actual.get("mapId"), None, "Data MD2", index, "mapId")
        require(set(world_rows) == expected_world_ids,
                "world playerMaps: operational IDs differ from all operational fixed native rows")
        checked.append({"nativePath": "Data MD2", "completeFacts": complete,
                        "operationalFixedIds": operational_ids, "factsOnly": facts_only,
                        "overflowFacts": max(0, complete - 20), "partialBytesRetained": tail})

    layout = native.get("Layout")
    if layout is not None:
        require(len(layout) >= LAYOUT_BYTES, "Layout: incomplete fixed 256-byte native record")
        tail = len(layout) - LAYOUT_BYTES
        expected = _words(layout[:LAYOUT_BYTES], 0, LAYOUT_CELLS)
        actual = world.get("landLayout")
        require(isinstance(actual, dict), "Layout: missing world.landLayout")
        compare(actual.get("rows"), 8, "Layout", 0, "rows")
        compare(actual.get("cols"), 16, "Layout", 0, "cols")
        compare(actual.get("cells"), expected, "Layout", 0, "cells")
        checked.append({"nativePath": "Layout", "recordsCompared": 1,
                        "suffixBytesPreserved": tail})

    _compare_world_maps(world, native, compare, require, checked)
    return checked







