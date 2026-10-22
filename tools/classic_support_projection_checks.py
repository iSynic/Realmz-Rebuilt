"""Independent operational checks for Classic scenario support sources.

Offsets are zero-based and big-endian, cross-checked against the pinned Castle
source consumers and Providence codecs. Bytes not named by an operational
mapping remain source-retention facts, not inferred package fields.
"""
from __future__ import annotations

import struct


def i16(data: bytes, offset: int) -> int:
    return struct.unpack_from(">h", data, offset)[0]


def i32(data: bytes, offset: int) -> int:
    return struct.unpack_from(">i", data, offset)[0]


def mac_text(raw: bytes) -> str:
    return raw.decode("mac_roman").replace("\0", " ").replace("\r", "\n")


def pascal(raw: bytes) -> str:
    return mac_text(raw[1:1 + min(raw[0], len(raw) - 1)])


def _compare_fields(actual, expected, path, compare):
    for field, value in expected.items():
        compare(actual.get(field), value, path, 0, field)
        yield field


def verify(content, world, scenario, manifest, native, compare, require):
    """Check operational projections; report preserved spans with no projection.

    `manifest` is the compiled package manifest (including its start field);
    `native` maps exact Classic source basenames to effective retained bytes.
    Scenario startup's first twenty bytes and Data RI/CI operational fields are
    represented in `content.campaign`; Global hooks live in `scenario`;
    Data Solids-derived passability is computed for signed special-resource map
    cells against the map's named base terrain profile. Every retained custom
    Map Stats table is projected, because opcode 57 can select a landlook after
    startup even when Data RD does not select it.
    """
    campaign = content.get("campaign")
    require(isinstance(campaign, dict), "support projection: campaign is missing")
    report = []

    # The scenario marker's fixed numeric startup header is consumed at new-game
    # entry. Name/description/security and unused marker bytes remain retained.
    startup_names = [row['nativePath'] for row in content.get('classicRecords', {}).get('sources', [])
                     if any(layout.get('family') == 'scenario-startup' for layout in row.get('layouts', []))]
    require(len(startup_names) <= 1, "scenario startup source identity is ambiguous")
    if startup_names:
        path = startup_names[0]
        raw = native[path]
        require(len(raw) >= 316, f"{path}: startup source is shorter than 316 bytes")
        expected = {"recommendedPartyLevels": i32(raw, 0), "maximumPartyLevels": i32(raw, 4)}
        require(all(value >= 0 for value in expected.values()),
                f"{path}: startup level limits contain a negative signed value")
        fields = list(_compare_fields(campaign, expected, path, compare))
        start = manifest.get("start")
        require(isinstance(start, dict), f"{path}: compiled manifest start projection is missing")
        x, y, land = i32(raw, 12), i32(raw, 16), i32(raw, 8)
        require(land >= 0 and 0 <= x < 90 and 0 <= y < 90,
                f"{path}: startup map or coordinate is outside Classic bounds")
        for field, value in (("mapId", f"land:{land}"), ("x", x), ("y", y)):
            compare(start.get(field), value, path, 0, f"start.{field}")
            fields.append(f"start.{field}")
        report.append({"nativePath": path, "fieldsCompared": fields,
                       "sourceOnlyByteSpans": [[8, 20, "start location not represented in content campaign"],
                                               [20, 60, "Data CS-dependent registration security"],
                                               [60, 316, "author check and unused startup bytes"]]})
        if "Data CS" in native:
            backup = native["Data CS"]
            # Registration bytes have no gameplay projection. Their printability
            # cannot turn exact source retention into a preservation failure.
            segments = {}
            if len(backup) >= 40:
                second = bytes((raw[40 + i] - backup[20 + i]) & 0xff for i in range(20))
                first = bytes((raw[20 + i] - second[i]) & 0xff for i in range(20))
                for name, value in (("segment1", first), ("segment2", second)):
                    visible = value.split(b"\0", 1)[0]
                    segments[name] = "printable-ascii" if all(32 <= byte <= 126 for byte in visible) else "binary-source-only"
            report.append({"nativePath": "Data CS", "recordsCompared": 0, "fieldsCompared": 0,
                           "sourceOnlyByteSpans": [[0, len(backup), "Castle registration backup; no package projection"]],
                           "decodedSegments": segments or "supplied-fragment"})

    if "Data RI" in native:
        raw = native["Data RI"]
        require(len(raw) == 320, "Data RI: expected exactly 320 bytes")
        restrictions = campaign.get("restrictions")
        require(isinstance(restrictions, dict), "Data RI: operational campaign restrictions are missing")
        party = i16(raw, 256)
        expected = {
            "description": pascal(raw[:256]),
            "maxPartySize": 6 if party == 0 else party,
            "maxLevel": max(0, i16(raw, 258)),
            "bannedRaces": [f"classic.race.{i + 1}" for i, v in enumerate(raw[260:290]) if v],
            "bannedCastes": [f"classic.caste.{i + 1}" for i, v in enumerate(raw[290:320]) if v],
        }
        for field, value in expected.items():
            compare(restrictions.get(field), value, "Data RI", 0, field)
        report.append({"nativePath": "Data RI", "fieldsCompared": list(expected),
                       "sourceOnlyByteSpans": []})

    if "Data CI" in native:
        raw = native["Data CI"]
        require(len(raw) == 18 * 256, "Data CI: expected exactly 18 256-byte slots")
        contact = campaign.get("contact")
        require(isinstance(contact, dict), "Data CI: operational contact projection is missing")
        expected = {"version": pascal(raw[256:512]),
                    "date": pascal(raw[512:768]), "author": pascal(raw[768:1024]),
                    "email": pascal(raw[1024:1280]), "web": pascal(raw[1280:1536]),
                    "fee": pascal(raw[1536:1792]), "description": pascal(raw[17 * 256:18 * 256])}
        for field, value in expected.items():
            actual = campaign.get("version", "") if field == "version" else campaign.get("author", "") if field == "author" else campaign.get("description", "") if field == "description" else contact.get(field, "")
            compare(actual, value, "Data CI", 0, field)
        report.append({"nativePath": "Data CI", "fieldsCompared": list(expected),
                       "sourceOnlyContactSlots": [{"slot": slot, "text": pascal(raw[slot * 256:(slot + 1) * 256]),
                           "disposition": "retained native Contact presentation; no current Rebuilt consumer"}
                           for slot in [0, *range(7, 17)]],
                       "sourceOnlyByteSpans": [[0, 256, "native Contact title, distinct from canonical campaign name"],
                           [7 * 256, 17 * 256, "native Contact payment/caption slots; currently unconsumed"]]})

    if "Global" in native:
        raw = native["Global"]
        require(len(raw) >= 60, "Global: missing complete thirty-short hook table")
        hooks = scenario.get("applicationHooks")
        require(isinstance(hooks, dict), "Global: application hook projection is missing")
        for slot, field in ((0, "startGame"), (1, "partyDeath"), (2, "endAdventure"),
                            (4, "shop"), (5, "temple")):
            value = i16(raw, slot * 2)
            expected = f"xap:{value}" if value else None
            compare(hooks.get(field), expected, "Global", slot, field)
        report.append({"nativePath": "Global", "fieldsCompared": ["startGame", "partyDeath", "endAdventure", "shop", "temple"],
                       "sourceOnlyByteSpans": [[6, 8, "unmapped global slot 3"], [12, 60, "unmapped global slots 6-29"], [60, len(raw), "retained trailing bytes"]]})

    if "Data Solids" in native:
        raw = native["Data Solids"]
        require(len(raw) == 1024, "Data Solids: expected exactly 1024 Boolean bytes")
        terrain_sets = {row.get("id"): row for row in world.get("battleTerrainSets", [])
                        if isinstance(row, dict) and isinstance(row.get("id"), str)}
        uses = []
        comparison_keys = []
        for map_row in world.get("maps", []):
            if not isinstance(map_row, dict) or map_row.get("levelType") != "land":
                continue
            identity = map_row.get("identity")
            tile_values = map_row.get("classicTileValues")
            cells = map_row.get("cells")
            require(isinstance(tile_values, list) and isinstance(cells, list) and len(tile_values) == len(cells),
                    f"Data Solids: {identity} must retain one signed native tile and compact cell per map coordinate")
            metadata = map_row.get("metadata")
            require(isinstance(metadata, dict), f"Data Solids: {identity} has no map metadata")
            terrain_id = metadata.get("battleTerrainSetId")
            terrain_set = terrain_sets.get(terrain_id)
            require(isinstance(terrain_set, dict), f"Data Solids: {identity} has no named base terrain set {terrain_id!r}")
            base_tile = terrain_set.get("baseTile")
            profiles = {row.get("tile"): row for row in terrain_set.get("tiles", []) if isinstance(row, dict)}
            require(type(base_tile) is int and base_tile in profiles,
                    f"Data Solids: {identity} base tile {base_tile!r} has no named profile")
            base_profile = profiles[base_tile]
            # Providence topology.rs: passable = (profile.walkable || solid_type == 0)
            # && !special_solid. Classic Map Stats' walkable predicate makes the
            # first clause equivalent to solid_type == 0 || solid_type == 0.
            profile_passable = base_profile.get("solid") == 0
            width = map_row.get("width")
            require(type(width) is int and width > 0, "Data Solids: map width is invalid")
            for offset, value in enumerate(tile_values):
                if isinstance(value, int) and -999 < value < 0:
                    resource_id = -value
                    require(resource_id < len(raw), f"Data Solids: {identity} uses out-of-range resource {resource_id}")
                    cell = cells[offset]
                    require(isinstance(cell, list) and len(cell) == 13 and type(cell[2]) is int,
                            f"Data Solids: {identity} cell {offset} compact row is malformed")
                    expected_passable = profile_passable and raw[resource_id] == 0
                    actual_passable = bool(cell[2] & 1)
                    map_identity = map_row.get("id", identity)
                    compare(actual_passable, expected_passable, "Data Solids",
                            f"{map_identity}:{offset}", "cells.passable")
                    comparison_keys.append(f"Data Solids#{map_identity}:{offset}.cells.passable")
                    uses.append({"map": map_row.get("id", identity), "x": offset % width, "y": offset // width,
                                 "rawTile": value, "resourceId": resource_id, "solid": raw[resource_id] != 0,
                                 "baseTerrainSetId": terrain_id, "baseTile": base_tile,
                                 "profileSolid": base_profile.get("solid"),
                                 "expectedPassable": expected_passable, "actualPassable": actual_passable})
        # Castle buttonchoice.c applies solids[-hit] only to negative field
        # values in (-999, 0). Providence bakes the resulting block into the
        # passability bit consumed by MapTopology; the source-retention verifier
        # independently binds all 1024 source bytes.
        report.append({"nativePath": "Data Solids", "recordsCompared": 0,
                       "fieldsCompared": len(uses), "comparisonKeys": comparison_keys,
                       "referencedSpecialCells": uses,
                       "consumingRule": "Castle buttonchoice.c: solids[-hit] when -999 < hit < 0",
                       "sourceOnlyByteSpans": [[0, 1024, "native passability lookup; map cells retain signed resource IDs"]]})

    custom_names = {6: "Data Custom 1 BD", 7: "Data Custom 2 BD", 8: "Data Custom 3 BD"}
    for landlook, path in custom_names.items():
        if path not in native:
            continue
        raw = native[path]
        require(len(raw) == 8104, f"{path}: expected exactly 8104 bytes")
        sets = [row for row in world.get("battleTerrainSets", [])
                if isinstance(row, dict) and row.get("landlook") == landlook]
        require(len(sets) == 1, f"{path}: custom Map Stats projection is missing or duplicated, including opcode 57 landlook targets")
        by_tile = {row.get("tile"): row for row in sets[0].get("tiles", []) if isinstance(row, dict)}
        require(len(by_tile) == len(sets[0].get("tiles", [])), f"{path}: duplicate or malformed tile identity")
        fields = (("sound", 0), ("time", 2), ("solid", 4), ("shore", 6),
                  ("needBoat", 8), ("isPath", 10), ("los", 12), ("flyFloat", 14), ("forest", 16))
        checked = 0
        for tile in range(201):
            record = by_tile.get(tile)
            require(record is not None, f"{path}: omitted custom Map Stats tile {tile}")
            base = tile * 40
            expected = {}
            for field, offset in fields:
                value = i16(raw, base + offset)
                expected[field] = (value != 0) if field in ("shore", "isPath", "los", "flyFloat") else value
            expected["combatBuild"] = [[i16(raw, base + 20 + (y * 3 + x) * 2) for x in range(3)] for y in range(3)]
            for field, value in expected.items():
                compare(record.get(field), value, path, tile, field)
                checked += 1
        report.append({"nativePath": path, "recordsCompared": 201, "fieldsCompared": checked,
                       "sourceOnlyByteSpans": [[8040, 8104, "base tile/scale and range-slot extension"]]})

    terrain_looks = {row.get('landlook') for row in world.get('battleTerrainSets', [])}
    land_ids = {row.get('levelIndex') for row in world.get('maps', []) if row.get('levelType') == 'land'}
    dependencies = []
    for program in scenario.get('programs', []):
        for action in program.get('instructions', []):
            extra = action.get('extraCode')
            if action.get('opcode') != 57 or not isinstance(extra, list) or len(extra) < 5:
                continue
            look = ((extra[0] + 128) & 255) - 128
            required = extra[2] in land_ids and (look in (0, 3, 4, 5, 9, 10)
                or look in custom_names and len(native.get(custom_names[look], b'')) >= 8044)
            require(not required or look in terrain_looks,
                    f"opcode 57: {program.get('id')} slot {action.get('slot')} lost required landlook {look}")
            dependencies.append({'programId': program.get('id'), 'slot': action.get('slot'),
                                 'nativeLook': extra[0], 'assignedLook': look, 'requiredTable': required,
                                 'tablePresent': look in terrain_looks})
    report.append({'operation': 'opcode-57-landlook-dependencies', 'dependencies': dependencies})

    return report


def self_test():
    """Focused synthetic tests prove each family rejects omission and mutation."""
    checks = []
    def run(data, world=None, scenario=None, campaign=None):
        content = {"campaign": campaign or {"name": "S", "recommendedPartyLevels": 1,
            "maximumPartyLevels": 2, "version": "v", "author": "a", "description": "d",
            "contact": {"title": "t", "email": "e", "web": "w", "date": "date", "fee": "f"},
            "restrictions": {"description": "r", "maxPartySize": 6, "maxLevel": 0,
                             "bannedRaces": [], "bannedCastes": []}}}
        content['classicRecords'] = {'sources': [{'nativePath': 'S', 'layouts': [{'family': 'scenario-startup'}]}] if 'S' in data else []}
        actual_scenario = scenario or {"applicationHooks": {"startGame": None, "partyDeath": None,
            "endAdventure": None, "shop": None, "temple": None}}
        actual_world = world or {"specialLandSolidity": {"solid": []}, "battleTerrainSets": []}
        def compare(actual, expected, path, idx, field):
            if actual != expected: raise AssertionError(f"{path}#{idx}.{field}: {actual!r} != {expected!r}")
        def require(condition, message):
            if not condition: raise AssertionError(message)
        return verify(content, actual_world, actual_scenario, {"start":{"mapId":"land:0","x":0,"y":0}}, data, compare, require)
    startup = bytearray(316); struct.pack_into(">ii", startup, 0, 1, 2)
    run({"S": bytes(startup)}); checks.append("startup-positive")
    bad = bytearray(startup); bad[3] ^= 1
    try: run({"S": bytes(bad)})
    except AssertionError: checks.append("startup-mutation-rejected")
    else: raise AssertionError("startup signed mutation was accepted")
    backup = bytes(316)
    run({"S": bytes(startup), "Data CS": backup}); checks.append("data-cs-source-only-validated")
    binary = bytearray(backup); binary[20] = 128
    binary_report = run({"S": bytes(startup), "Data CS": bytes(binary)})
    assert binary_report[-1]['decodedSegments']['segment1'] == 'binary-source-only'
    checks.append("data-cs-binary-source-only-retained")
    ri = bytearray(320); ri[258:260] = b"\0\x03"; ri[260] = 1
    c = {"name": "S", "recommendedPartyLevels": 1, "maximumPartyLevels": 2, "version": "v", "author": "a", "description": "d",
         "contact": {"title":"t","email":"e","web":"w","date":"date","fee":"f"},
         "restrictions":{"description":"","maxPartySize":6,"maxLevel":3,"bannedRaces":["classic.race.1"],"bannedCastes":[]}}
    run({"Data RI": bytes(ri)}, campaign=c); checks.append("ri-positive")
    try: run({"Data RI": bytes(ri)}, campaign={**c,"restrictions":{**c["restrictions"],"bannedRaces":[]}})
    except AssertionError: checks.append("ri-omission-rejected")
    else: raise AssertionError("RI omission was accepted")
    # Data CI: prove a nonempty author-controlled contact value is checked.
    ci = bytearray(18 * 256); ci[0] = 1; ci[1] = ord("T"); ci[4 * 256] = 1; ci[4 * 256 + 1] = ord("E")
    cc = {**c, "name":"T", "version":"", "author":"", "description":"",
          "contact": {**c["contact"], "email":"E", "web":"", "date":"", "fee":""}}
    run({"Data CI": bytes(ci)}, campaign={**cc,"name":"canonical folder name"}); checks.append("ci-distinct-title-positive")
    try: run({"Data CI": bytes(ci)}, campaign={**cc,"contact":{**cc["contact"],"email":""}})
    except AssertionError: checks.append("ci-mutation-rejected")
    else: raise AssertionError("CI mutation was accepted")
    # Global's signed hook ID must be represented and exact.
    glob = bytearray(60); glob[:2] = (-9).to_bytes(2, "big", signed=True)
    hooks = {"startGame":"xap:-9","partyDeath":None,"endAdventure":None,"shop":None,"temple":None}
    run({"Global": bytes(glob)}, scenario={"applicationHooks":hooks}); checks.append("global-positive")
    try: run({"Global": bytes(glob)}, scenario={"applicationHooks":{**hooks,"startGame":"xap:9"}})
    except AssertionError: checks.append("global-signed-mutation-rejected")
    else: raise AssertionError("Global signed mutation was accepted")
    # Special solidity is combined with the named base terrain profile and
    # compared to the passability bit consumed by the runtime.
    solids = bytearray(1024); solids[41] = 0xff
    def solid_world(passable, profile_solid=0):
        return {"maps":[{"id":"land:0","levelType":"land","width":90,
                         "metadata":{"battleTerrainSetId":"landlook-0"},
                         "classicTileValues":[-41],"cells":[["t",1,1 if passable else 0,None,[],[],[],[],0,"",None,0,0]]}],
                "battleTerrainSets":[{"id":"landlook-0","landlook":0,"baseTile":4,
                                       "tiles":[{"tile":4,"solid":profile_solid}]}]}
    solid_report = run({"Data Solids":bytes(solids)}, world=solid_world(False))
    assert solid_report[0]["referencedSpecialCells"][0]["solid"] is True
    assert solid_report[0]["comparisonKeys"] == ["Data Solids#land:0:0.cells.passable"]
    checks.append("solids-cell-consumer-positive")
    try: run({"Data Solids":bytes(solids)}, world=solid_world(True))
    except AssertionError: checks.append("solids-passability-mismatch-rejected")
    else: raise AssertionError("Data Solids passability mismatch was accepted")
    solid_report = run({"Data Solids":bytes(1024)}, world=solid_world(True))
    assert solid_report[0]["referencedSpecialCells"][0]["solid"] is False
    checks.append("solids-value-mutation-observed")
    try: run({"Data Solids":bytes(1024)}, world=solid_world(True, profile_solid=1))
    except AssertionError: checks.append("solids-profile-combination-rejected")
    else: raise AssertionError("Data Solids ignored the underlying profile")
    # One custom Map Stats row detects a signed source change and projection deletion.
    stats = bytearray(8104); stats[:2] = (-7).to_bytes(2,"big",signed=True)
    tiles = []
    for tile in range(201):
        row = {"tile":tile,"sound": -7 if tile == 0 else 0,"time":0,"solid":0,"shore":False,
               "needBoat":0,"isPath":False,"los":False,"flyFloat":False,"forest":0,
               "combatBuild":[[0,0,0],[0,0,0],[0,0,0]]}
        tiles.append(row)
    world = {"battleTerrainSets":[{"landlook":6,"tiles":tiles}]}
    rd = bytearray(644); rd[520] = 6
    run({"Data Custom 1 BD":bytes(stats)}, world=world); checks.append("mapstats-positive-without-rd-selection")
    try: run({"Data Custom 1 BD":bytes(stats)}, world={"battleTerrainSets":[]})
    except AssertionError: checks.append("mapstats-opcode57-target-omission-rejected")
    else: raise AssertionError("unselected custom Map Stats omission was accepted")
    bad_tiles = [dict(row) for row in tiles]; bad_tiles[0]["sound"] = 7
    try: run({"Data Custom 1 BD":bytes(stats)}, world={"battleTerrainSets":[{"landlook":6,"tiles":bad_tiles}]})
    except AssertionError: checks.append("mapstats-signed-mutation-rejected")
    else: raise AssertionError("Map Stats signed mutation was accepted")
    omitted = [row for row in tiles if row["tile"] != 0]
    try: run({"Data Custom 1 BD":bytes(stats)}, world={"battleTerrainSets":[{"landlook":6,"tiles":omitted}]})
    except AssertionError: checks.append("mapstats-omission-rejected")
    else: raise AssertionError("Map Stats omission was accepted")
    return checks
