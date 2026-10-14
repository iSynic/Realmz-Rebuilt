"""Verify v6 native map-marker refreshes and reconstruct their prior documents."""
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def _json_document(archive, name):
    try:
        return json.loads(archive.read(name))
    except (KeyError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read {name}: {error}") from error


def _sorted_trigger_refs(values):
    def order(value):
        try:
            return int(value.rsplit(":", 1)[-1])
        except (AttributeError, ValueError):
            return 2**32 - 1
    return sorted(values, key=order)


def reconstruct_previous_documents(archive, receipt):
    """Invert only the native marker projection declared by one receipt row."""
    previous = receipt.get("previousDocuments")
    require(isinstance(previous, dict) and previous, "receipt has no previousDocuments")
    required = {"content.json", "world.json", "scenario.json", "assets/index.json"}
    require(required <= previous.keys(), "receipt omits a required previous document")
    documents = {name: _json_document(archive, name) for name in previous}
    world = documents["world.json"]
    scenario = documents["scenario.json"]
    maps = {item["id"]: item for item in world.get("maps", [])}

    for map_doc in maps.values():
        require("classicTileValues" in map_doc, "v6 map is missing classicTileValues")
        map_doc.pop("classicTileValues")

    seen_marker_cells = set()
    for change in receipt.get("markerChanges", []):
        map_id = change["mapId"]
        cell_index = change["cellIndex"]
        key = (map_id, cell_index)
        require(key not in seen_marker_cells, "duplicate markerChanges cell")
        seen_marker_cells.add(key)
        require(map_id in maps, f"markerChanges names missing map {map_id}")
        cells = maps[map_id].get("cells", [])
        require(isinstance(cell_index, int) and 0 <= cell_index < len(cells),
                "markerChanges cell index is invalid")
        cell = cells[cell_index]
        require(len(cell) > 7 and cell[7] == change["correctedFeatures"],
                f"corrected features differ at {map_id} cell {cell_index}")
        cell[7] = change["previousFeatures"]

    restored_ids = set()
    triggers = world.get("triggers", [])
    programs = scenario.get("programs", [])
    # Reverse producer order because several restored records can share one cell.
    # Each receipt row records the cell refs immediately before its own insertion.
    for row in reversed(receipt.get("restoredEmptyRecords", [])):
        trigger_id = row["id"]
        require(trigger_id not in restored_ids, "duplicate restoredEmptyRecords trigger")
        restored_ids.add(trigger_id)
        matching = [trigger for trigger in triggers if trigger.get("id") == trigger_id]
        require(len(matching) == 1, f"restored trigger {trigger_id} is missing or duplicated")
        trigger = matching[0]
        require(trigger.get("programId") == row["programId"]
                and trigger.get("mapId") == row["mapId"]
                and trigger.get("chancePercent") == row["chancePercent"],
                f"restored trigger identity differs for {trigger_id}")
        coordinate = row["coordinate"]
        require(trigger.get("coordinate") == coordinate,
                f"restored trigger coordinate differs for {trigger_id}")
        map_doc = maps[row["mapId"]]
        index = row["cellIndex"]
        require(index == coordinate["y"] * map_doc["width"] + coordinate["x"],
                f"restored trigger cell differs for {trigger_id}")
        refs = map_doc["cells"][index][4]
        require(refs == _sorted_trigger_refs(row["previousCellRefs"] + [trigger_id]),
                f"restored trigger cell references differ for {trigger_id}")
        map_doc["cells"][index][4] = row["previousCellRefs"]
        triggers.remove(trigger)
        matching_programs = [program for program in programs
                             if program.get("id") == row["programId"]]
        require(len(matching_programs) == 1,
                f"restored program {row['programId']} is missing or duplicated")
        program = matching_programs[0]
        require(program.get("ownerKind") == "trigger"
                and program.get("ownerId") == trigger_id
                and program.get("instructions") == [],
                f"restored program {row['programId']} is not an empty program owned by {trigger_id}")
        programs.remove(program)

    order = receipt.get("previousProgramOrder")
    require(isinstance(order, list) and len(order) == len(set(order)),
            "receipt previousProgramOrder is missing or duplicated")
    by_id = {program.get("id"): program for program in programs}
    require(len(by_id) == len(programs) and set(by_id) == set(order),
            "remaining programs do not match previousProgramOrder")
    scenario["programs"] = [by_id[program_id] for program_id in order]

    reconstructed = {}
    for name, metadata in previous.items():
        require(isinstance(metadata, dict) and isinstance(metadata.get("schemaVersion"), int),
                f"previous schema version is missing for {name}")
        documents[name]["schemaVersion"] = metadata["schemaVersion"]
        encoded = canonical(documents[name])
        require(digest(encoded) == metadata.get("sha256"),
                f"reconstructed previous document hash differs for {name}")
        reconstructed[name] = encoded
    return reconstructed


def _native_marker(level_type, raw):
    if level_type == "land":
        magnitude = abs(raw) if raw < 0 else raw & ~0x6000
        return magnitude > 999
    if level_type == "dungeon":
        return bool((raw & 0xFFFF) & 0x1000)
    raise ValueError(f"unknown map levelType {level_type!r}")


def _verify_map_markers(world, campaign):
    maps = world.get("maps")
    require(isinstance(maps, list) and maps, f"{campaign} has no maps")
    for map_doc in maps:
        width, height = map_doc.get("width"), map_doc.get("height")
        cells, values = map_doc.get("cells"), map_doc.get("classicTileValues")
        require(isinstance(width, int) and isinstance(height, int)
                and width > 0 and height > 0, f"{campaign} map dimensions are invalid")
        require(isinstance(cells, list) and len(cells) == width * height,
                f"{campaign} map cells have the wrong shape")
        require(isinstance(values, list) and len(values) == width * height,
                f"{campaign} map classicTileValues have the wrong shape")
        for index, (cell, raw) in enumerate(zip(cells, values)):
            require(isinstance(raw, int) and not isinstance(raw, bool)
                    and -32768 <= raw <= 32767,
                    f"{campaign} map tile {index} is not signed int16")
            require(isinstance(cell, list) and len(cell) > 7
                    and isinstance(cell[7], list),
                    f"{campaign} map cell {index} has invalid features")
            action_points = [feature for feature in cell[7]
                             if isinstance(feature, list) and len(feature) > 1
                             and feature[1] == "action-point"]
            require(len(action_points) <= 1,
                    f"{campaign} map cell {index} has duplicate Action Point features")
            marked = _native_marker(map_doc["levelType"], raw)
            require(bool(action_points) == marked,
                    f"{campaign} map {map_doc['id']} cell {index} Action Point feature "
                    "does not match its native tile marker")


def _verify_media_receipt(archive, row, campaign):
    expected = row.get("preservation", {}).get("mediaInventory", {})
    require(expected.get("identical") is True,
            f"{campaign} receipt does not prove preserved media")
    media = {name: digest(archive.read(name)) for name in archive.namelist()
             if name.startswith("assets/media/")}
    require(len(media) == expected.get("files") == row.get("preservedMediaFiles"),
            f"{campaign} preserved media inventory count differs")
    require(digest(canonical(media)) == expected.get("sha256"),
            f"{campaign} media inventory hash differs from receipt")


def _match_receipt(entry, rows):
    matches = [row for row in rows
               if row.get("outputFile") == entry["file"]
               or row.get("name") == entry["name"]]
    require(len(matches) == 1, f"no unique native refresh receipt for {entry['file']}")
    row = matches[0]
    require(row.get("outputFile") == entry["file"] and row.get("name") == entry["name"],
            f"receipt output filename/name differs for {entry['file']}")
    return row


def _require_leaf(value, label):
    require(isinstance(value, str) and value and value not in (".", "..")
            and "/" not in value and "\\" not in value
            and Path(value).name == value,
            f"{label} must be a sanitized filename")


def verify(root):
    bundle = root / "src/storage/packages/bundled_campaigns"
    catalog = json.loads((bundle / "castle-bundled-scenarios.provenance.json").read_text(encoding="utf-8"))
    receipt_path = bundle / "native-map-triggers.json"
    require(receipt_path.is_file(), "native-map-triggers.json is missing")
    report = json.loads(receipt_path.read_text(encoding="utf-8"))
    policy = (root / "src/storage/saves/marker_save_update.gd").read_text(encoding="utf-8")
    pinned_receipt = re.search(r'const RECEIPT_SHA256 := "([0-9a-f]{64})"', policy)
    require(pinned_receipt is not None
            and pinned_receipt.group(1) == digest(receipt_path.read_bytes()),
            "save marker-update policy does not pin the verified correction receipt")
    require(report.get("kind") == "providence.classic-map-marker-correction"
            and report.get("schemaVersion") == 6,
            "native marker receipt kind or schema version is unsupported")
    schema_path = root / "contracts/realmz2/realmz2-package-v6.schema.json"
    schema_hash = digest(schema_path.read_bytes())
    require(report.get("schemaSha256") == schema_hash,
            "native marker receipt schema hash differs")
    scenarios = catalog.get("scenarios", [])
    rows = report.get("scenarios", [])
    require(len(scenarios) == len(rows) == 13,
            "native marker refresh must cover exactly 13 scenarios")
    require(len({entry.get("campaignId") for entry in scenarios}) == 13
            and len({entry.get("file") for entry in scenarios}) == 13,
            "bundled scenario catalog has duplicate campaign or archive identities")
    compiler = report.get("compiler", {})
    require(isinstance(compiler.get("commit"), str) and compiler["commit"],
            "native marker receipt compiler identity is missing")
    require(compiler.get("sourceDirty") is False and compiler.get("profile") == "release",
            "native marker refresh requires a clean release compiler build")
    inputs = json.loads((root / "tools/scenario-importer-inputs.json").read_text(encoding="utf-8"))
    source = inputs.get("sourceUpdate", inputs["source"])
    require(compiler["commit"] == source["commit"]
            and compiler.get("sourceTree") == source["tree"]
            and compiler.get("schemaSha256") == source["schemaSha256"] == schema_hash
            and compiler.get("cargoLockSha256") == source["cargoLockSha256"],
            "native marker compiler differs from the pinned importer source")
    require(len({row.get("outputFile") for row in rows}) == len(rows),
            "native marker receipt output filenames are duplicated")
    require(len({row.get("name") for row in rows}) == len(rows),
            "native marker receipt scenario names are duplicated")
    for row in rows:
        _require_leaf(row.get("sourceFile"), "receipt sourceFile")
        _require_leaf(row.get("outputFile"), "receipt outputFile")
        native_inputs = row.get("nativeInputs")
        require(isinstance(native_inputs, list) and native_inputs,
                f"{row.get('outputFile')} receipt has no native inputs")
        require("Data LD" in {native.get("path") for native in native_inputs},
                f"{row.get('outputFile')} receipt omits Data LD")
        require(len({native.get("path") for native in native_inputs}) == len(native_inputs),
                f"{row.get('outputFile')} receipt duplicates a native input")
        for native in native_inputs:
            _require_leaf(native.get("path"), "receipt native input path")
            require(isinstance(native.get("bytes"), int) and native["bytes"] > 0
                    and isinstance(native.get("sha256"), str)
                    and len(native["sha256"]) == 64
                    and all(char in "0123456789abcdef" for char in native["sha256"]),
                    f"{row.get('outputFile')} receipt has an invalid native input identity")
    matched_rows = set()
    prior_packages = set()

    for entry in scenarios:
        refresh = entry.get("nativeTileRefresh")
        require(isinstance(refresh, dict)
                and refresh.get("operation") == "correct-classic-map-markers"
                and refresh.get("compilerRevision") == compiler["commit"]
                and refresh.get("receiptFile") == "native-map-triggers.json",
                f"{entry['file']} has incomplete nativeTileRefresh provenance")
        row = _match_receipt(entry, rows)
        require(id(row) not in matched_rows, f"receipt row was reused for {entry['file']}")
        matched_rows.add(id(row))
        previous = refresh.get("previousPackage", {})
        require(previous.get("compilerRevision")
                and previous.get("packageHash") == row.get("sourcePackageHash")
                and previous.get("archiveSha256") == row.get("sourceSha256")
                and previous.get("contentId") == row.get("sourceContentId")
                and isinstance(previous.get("bytes"), int) and previous["bytes"] > 0,
                f"{entry['file']} previous package identity differs from receipt")
        require(previous["packageHash"] not in prior_packages
                and previous["packageHash"] != entry.get("packageHash")
                and previous["archiveSha256"] != entry.get("archiveSha256")
                and entry["campaignId"] == entry["file"].removesuffix(".realmz2"),
                f"{entry['file']} is not a unique stock save-update transition")
        prior_packages.add(previous["packageHash"])
        require(set(row.get("previousDocuments", {}))
                == {"content.json", "world.json", "scenario.json", "assets/index.json"},
                f"{entry['file']} marker update changed its permitted document set")
        require(entry.get("compilerRevision") == compiler["commit"],
                f"{entry['file']} compiler revision differs from receipt")
        package_path = bundle / entry["file"]
        package_bytes = package_path.read_bytes()
        require(len(package_bytes) == entry.get("bytes")
                and digest(package_bytes) == entry.get("archiveSha256")
                and digest(package_bytes) == row.get("outputSha256"),
                f"{entry['file']} output archive identity differs")
        with zipfile.ZipFile(package_path) as archive:
            manifest = _json_document(archive, "manifest.json")
            require(manifest.get("schemaVersion") == 6
                    and manifest.get("schemaHash") == schema_hash
                    and manifest.get("compiler", {}).get("commit") == compiler["commit"]
                    and manifest.get("packageHash") == entry.get("packageHash")
                    and manifest.get("contentId") == entry.get("contentId")
                    and manifest.get("packageHash") == row.get("outputPackageHash")
                    and manifest.get("contentId") == row.get("outputContentId"),
                    f"{entry['file']} manifest identity differs from receipt")
            world = _json_document(archive, "world.json")
            _verify_map_markers(world, entry["name"])
            reconstruct_previous_documents(archive, row)
            _verify_media_receipt(archive, row, entry["name"])
    require(len(matched_rows) == 13, "not all native marker receipt rows were used")
    print("Verified native map markers, reversible receipts and 13 pinned save-update transitions.")


if __name__ == "__main__":
    try:
        verify(Path(__file__).resolve().parent.parent)
    except (AssertionError, KeyError, TypeError, ValueError, OSError, zipfile.BadZipFile) as error:
        sys.exit(f"Native marker verification failed: {error}")
