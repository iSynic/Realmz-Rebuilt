#!/usr/bin/env python3
"""Verify the owner-designated Trouble in the Sword Lands program correction.

The bundle must equal its exact predecessor except for XAP 1794 slot 7 (Keep
Codes becomes opcode 23 with Extra Code row 16020), the appended native row, and
the source and package identities that follow from them. The predecessor then
passes the unchanged terrain-correction check against its own era's catalog.
"""
from __future__ import annotations

import json
from pathlib import Path
import tempfile

import complete_records_history as history
import verify_trouble_terrain as terrain
from verify_trouble_terrain import ROOT, pinned, read_archive, require, sha, snapshot_sha

ED3_RECORD_BYTES = 40
EDCD_ROW_BYTES = 10
PROGRAM_FILES = ("Data ED3", "Data EDCD")


def word(data, offset):
    return int.from_bytes(data[offset:offset + 2], "big", signed=True)


def verify_native(before, after, receipt):
    """Data ED3 changes only the declared slot words; Data EDCD only appends the declared row."""
    program = receipt["program"]
    record = int(program["id"].split(":")[1])
    slot = program["slot"]
    base = record * ED3_RECORD_BYTES + 8
    code_at, id_at = base + slot * 2, base + 16 + slot * 2
    ed3_before, ed3_after = before["Data ED3"], after["Data ED3"]
    require(len(ed3_before) == len(ed3_after) and len(ed3_before) % ED3_RECORD_BYTES == 0, "Data ED3 length differs")
    require(word(ed3_before, code_at) == program["before"]["opcode"] and word(ed3_before, id_at) == program["before"]["id"]
            and word(ed3_after, code_at) == program["after"]["opcode"] and word(ed3_after, id_at) == program["after"]["id"],
            "Data ED3 program words differ from the receipt")
    patched = bytearray(ed3_before)
    patched[code_at:code_at + 2] = ed3_after[code_at:code_at + 2]
    patched[id_at:id_at + 2] = ed3_after[id_at:id_at + 2]
    require(bytes(patched) == ed3_after, "Data ED3 differs outside the declared program words")
    edcd_before, edcd_after = before["Data EDCD"], after["Data EDCD"]
    row = program["after"]["id"]
    require(len(edcd_before) == row * EDCD_ROW_BYTES and edcd_after[:len(edcd_before)] == edcd_before
            and len(edcd_after) == len(edcd_before) + EDCD_ROW_BYTES, "Data EDCD differs outside its appended row")
    require([word(edcd_after, len(edcd_before) + 2 * i) for i in range(5)] == program["after"]["extraCode"]
            and [word(edcd_before, program["before"]["id"] * EDCD_ROW_BYTES + 2 * i) for i in range(5)]
            == program["before"]["extraCode"], "Data EDCD rows differ from the receipt")


def leaf_differences(old, new, path=""):
    if type(old) is not type(new):
        return [(path, old, new)]
    if isinstance(old, dict):
        found = []
        for key in sorted(old.keys() | new.keys()):
            if key not in old or key not in new:
                found.append((f"{path}.{key}", old.get(key), new.get(key)))
            else:
                found += leaf_differences(old[key], new[key], f"{path}.{key}")
        return found
    if isinstance(old, list):
        if len(old) != len(new):
            return [(f"{path}#length", len(old), len(new))]
        return [d for i, (a, b) in enumerate(zip(old, new)) for d in leaf_differences(a, b, f"{path}[{i}]")]
    return [] if old == new else [(path, old, new)]


def neutral(data, hashes):
    """Replace each changed native file hash with its file name so only real value changes remain."""
    text = data.decode("utf-8")
    for digest, name in hashes.items():
        text = text.replace(digest, name)
    return json.loads(text)


def verify_documents(old_files, new_files, receipt):
    files = {row["file"]: row for row in receipt["nativeFiles"]}
    old_hashes = {files[name]["before"]["sha256"]: name for name in PROGRAM_FILES}
    new_hashes = {files[name]["after"]["sha256"]: name for name in PROGRAM_FILES}
    edcd = files["Data EDCD"]
    sizes = (edcd["before"]["bytes"], edcd["after"]["bytes"])
    rows = tuple(size // EDCD_ROW_BYTES for size in sizes)
    program = receipt["program"]

    scenario_old = neutral(old_files["scenario.json"], old_hashes)
    scenario_new = neutral(new_files["scenario.json"], new_hashes)
    index = next(i for i, p in enumerate(scenario_new["programs"]) if p["id"] == program["id"])
    step = next(i for i, s in enumerate(scenario_new["programs"][index]["instructions"]) if s["slot"] == program["slot"])
    at = f".programs[{index}].instructions[{step}]"
    before, after = program["before"], program["after"]
    expected = {(f"{at}.extraCode[{i}]", a, b) for i, (a, b) in enumerate(zip(before["extraCode"], after["extraCode"])) if a != b}
    expected |= {(f"{at}.opcode", before["opcode"], after["opcode"]), (f"{at}.rawOpcode", before["opcode"], after["opcode"]),
                 (f"{at}.id", before["id"], after["id"])}
    require(set(leaf_differences(scenario_old, scenario_new)) == expected, "scenario program delta differs")

    content_old = neutral(old_files["content.json"], old_hashes)
    content_new = neutral(new_files["content.json"], new_hashes)
    records_old, records_new = content_old["classicRecords"], content_new["classicRecords"]
    require(records_new["extraCodes"][:-1] == records_old["extraCodes"] and records_new["extraCodes"][-1]
            == {"id": after["id"], "values": after["extraCode"]}, "compiled Extra Code delta differs")
    records_old["extraCodes"] = records_new["extraCodes"]
    number = int(program["id"].split(":")[1])
    native = next(i for i, p in enumerate(records_new["programs"]) if p["id"] == number and p["nativePath"] == "Data ED3")
    edcd_source = next(i for i, s in enumerate(records_new["sources"]) if s["nativePath"] == "Data EDCD")
    records = f".classicRecords"
    expected = {(f"{records}.programs[{native}].codes[{program['slot']}]", before["opcode"], after["opcode"]),
                (f"{records}.programs[{native}].operands[{program['slot']}]", before["id"], after["id"]),
                (f"{records}.sources[{edcd_source}].byteLength", *sizes),
                (f"{records}.sources[{edcd_source}].effectiveByteLength", *sizes),
                (f"{records}.sources[{edcd_source}].layouts[0].completeRecords", *rows),
                (f"{records}.ruleSelection.capturedSourceSetSha256", records_old["ruleSelection"]["capturedSourceSetSha256"],
                 records_new["ruleSelection"]["capturedSourceSetSha256"])}
    require(set(leaf_differences(content_old, content_new)) == expected, "compiled content delta differs")

    retention = [name for name in new_files if name.startswith("assets/media/") and name.endswith(".json")
                 and name not in old_files]
    previous = [name for name in old_files if name.startswith("assets/media/") and name.endswith(".json")
                and name not in new_files]
    require(len(retention) == len(previous) == 1, "source-retention document delta differs")
    old_hashes[Path(previous[0]).stem] = new_hashes[Path(retention[0]).stem] = "source-index"
    # Assets are ordered by content hash, so compare them by their neutral identity.
    old_index, new_index = neutral(old_files["assets/index.json"], old_hashes), neutral(new_files["assets/index.json"], new_hashes)
    for document in (old_index, new_index):
        document["assets"] = {asset["id"]: asset for asset in document["assets"]}
    differences = leaf_differences(old_index, new_index)
    require(differences and all(path.endswith(".bytes") and (a, b) == sizes for path, a, b in differences)
            and len(differences) == 1, "asset index delta differs")
    differences = leaf_differences(neutral(old_files[previous[0]], old_hashes), neutral(new_files[retention[0]], new_hashes))
    require(len(differences) == 3 and all((a, b) in (sizes, rows) for _, a, b in differences),
            "source-retention document delta differs")
    old_manifest = neutral(old_files["manifest.json"], old_hashes)
    new_manifest = neutral(new_files["manifest.json"], new_hashes)
    for manifest in (old_manifest, new_manifest):
        manifest.pop("contentId"), manifest.pop("packageHash")
        manifest["files"] = {name: None for name in manifest["files"]}
    require(set(old_manifest["files"]) == set(new_manifest["files"]), "manifest file set differs")
    old_manifest["files"] = new_manifest["files"] = None
    require(old_manifest == new_manifest, "manifest changed outside its identities")


def verify_source_catalog(catalog, terrain_catalog, receipt, sources):
    fix = catalog["programCorrection"]
    require(catalog.get("authority") == terrain_catalog.get("authority") == "project-owner-designated"
            and catalog["campaignId"] == receipt["campaignId"] and fix["nativeFiles"] == receipt["nativeFiles"]
            and fix["changes"] == receipt["nativeChanges"], "program source catalog differs from the receipt")
    for key in ("baseSource", "terrainCorrection"):
        require(catalog[key] == terrain_catalog[key], f"program source catalog changed its {key}")
    before = {row["file"]: (row["bytes"], row["sha256"]) for row in terrain_catalog["files"]}
    after = {row["file"]: (row["bytes"], row["sha256"]) for row in catalog["files"]}
    for row in receipt["nativeFiles"]:
        require(before[row["file"]] == (row["before"]["bytes"], row["before"]["sha256"])
                and after[row["file"]] == (row["after"]["bytes"], row["after"]["sha256"]), "program source file differs")
        before[row["file"]] = after[row["file"]]
    require(before == after, "program source snapshot differs outside its native files")
    snapshot = catalog["snapshot"]
    require(snapshot["sha256"] == receipt["sourceCatalog"]["snapshotSha256"] == snapshot_sha(catalog["files"])
            and snapshot["fileCount"] == len(catalog["files"]) and snapshot["bytes"] == sum(f["bytes"] for f in catalog["files"]),
            "program source snapshot differs")
    packaged = {row["nativePath"]: (row["byteLength"], row["sha256"]) for row in sources}
    require(after == packaged, "program source snapshot differs from the packaged original sources")


def terrain_era_entry(entry, receipt, terrain_catalog):
    """The provenance entry as it stood for the predecessor, before the program correction."""
    previous = receipt["previousPackage"]
    era = {key: value for key, value in entry.items() if key != "programCorrection"}
    era.update(compilerRevision=previous["compilerRevision"], contentId=previous["contentId"])
    era["sourceOverride"] = dict(entry["sourceOverride"], snapshotSha256=terrain_catalog["snapshot"]["sha256"])
    return era


def verify(package_root, inventory, current_row, catalog_entry):
    fix = inventory["programCorrection"]
    receipt = json.loads(pinned(fix["receipt"]))
    require(receipt.get("kind") == "realmz-rebuilt.trouble-program-correction" and receipt.get("formatVersion") == 1
            and receipt["campaignId"] == fix["campaignId"] == current_row["campaignId"], "program receipt format differs")
    for key in ("packageHash", "archiveSha256", "bytes"):
        require(receipt[key] == current_row[key], f"program receipt identity differs: {key}")
    require(catalog_entry.get("sourceOverride") == {
        "kind": "project-owner-designated-snapshot", "catalog": Path(fix["sourceCatalog"]["file"]).name,
        "snapshotSha256": receipt["sourceCatalog"]["snapshotSha256"]}, "program source override differs")
    require(catalog_entry.get("programCorrection") == {
        "operation": "retain-owner-program-correction", "receiptFile": Path(fix["receipt"]["file"]).name,
        "previousPackage": receipt["previousPackage"]}, "program provenance differs")
    require(catalog_entry["compilerRevision"] == receipt["compilerRevision"] and catalog_entry["contentId"] == receipt["contentId"],
            "program provenance identity differs")
    owner_terrain = inventory["terrainCorrection"]
    writer = receipt["toolchain"]["writer"]
    require(receipt["compilerRevision"] == writer["commit"] == fix["compiler"]["commit"]
            and writer["sourceBundle"]["sha256"] == owner_terrain["sourceBundle"]["sha256"]
            and receipt["toolchain"]["projectionReceiptSha256"] == fix["projectionReceipt"]["sha256"]
            and receipt["toolchain"]["previousPackageRecipe"] == fix["previousPackageRecipe"]
            and receipt["sourceCatalog"]["sha256"] == fix["sourceCatalog"]["sha256"], "program toolchain pins differ")
    pinned(owner_terrain["sourceBundle"])
    projection = json.loads(pinned(fix["projectionReceipt"]))
    rows = [row for row in projection["campaigns"] if row.get("campaignId") == receipt["campaignId"]]
    hashes = rows[0]["sourceHashes"] if len(rows) == 1 else {}
    require(all(hashes.get(row["file"]) == row["after"]["sha256"] for row in receipt["nativeFiles"]),
            "program projection receipt differs")
    new_path = package_root / receipt["file"]
    new_files = read_archive(new_path)
    sources = json.loads(new_files["content.json"])["classicRecords"]["sources"]
    terrain_catalog = json.loads(pinned(owner_terrain["sourceCatalog"]))
    verify_source_catalog(json.loads(pinned(fix["sourceCatalog"])), terrain_catalog, receipt, sources)
    pinned(fix["previousPackageRecipe"])
    with tempfile.TemporaryDirectory(prefix="realmz-trouble-program-") as scratch:
        old_path = Path(scratch) / receipt["file"]
        history.reconstruct_one(history.load_recipe(ROOT / fix["previousPackageRecipe"]["file"]), new_path, old_path)
        old_archive = old_path.read_bytes()
        previous = receipt["previousPackage"]
        require(sha(old_archive) == previous["archiveSha256"] and len(old_archive) == previous["bytes"],
                "program predecessor archive differs")
        old_files = read_archive(old_path)
        require(json.loads(old_files["manifest.json"])["packageHash"] == previous["packageHash"],
                "program predecessor identity differs")
        changed = receipt["changedFiles"]
        identity = lambda data: None if data is None else {"bytes": len(data), "sha256": sha(data)}
        for name in sorted(old_files.keys() | new_files.keys()):
            before, after = old_files.get(name), new_files.get(name)
            if name in changed:
                require(before != after and changed[name] == {"before": identity(before), "after": identity(after)},
                        f"declared program package delta differs: {name}")
            else:
                require(before == after, f"undeclared program package delta: {name}")
        media = "assets/media/{}.bin"
        native_before = {row["file"]: old_files[media.format(row["before"]["sha256"])] for row in receipt["nativeFiles"]}
        native_after = {row["file"]: new_files[media.format(row["after"]["sha256"])] for row in receipt["nativeFiles"]}
        verify_native(native_before, native_after, receipt)
        verify_documents(old_files, new_files, receipt)
        terrain_row = {"campaignId": receipt["campaignId"], **{k: previous[k] for k in ("packageHash", "archiveSha256", "bytes")}}
        terrain_check = terrain.verify(old_path, owner_terrain, terrain_row,
                                       terrain_era_entry(catalog_entry, receipt, terrain_catalog))
    return {"campaignId": receipt["campaignId"], "programCorrections": 1,
            "terrainCorrections": terrain_check["terrainCorrections"],
            "previousPackageHash": receipt["previousPackage"]["packageHash"]}
