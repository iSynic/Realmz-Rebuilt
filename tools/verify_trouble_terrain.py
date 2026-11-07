#!/usr/bin/env python3
"""Verify the owner-designated Trouble in the Sword Lands terrain correction.

The corrected bundle must equal its exact predecessor except for the declared
native Data LD tile words, the movement compiled for those cells, and the
source and package identities that follow from them.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import zipfile

import complete_records_history as history

ROOT = Path(__file__).resolve().parent.parent
MOVEMENT_COLUMNS = (1, 2, 3, 6, 11, 12)
CORRECTED_COLUMNS = {0, 8, *MOVEMENT_COLUMNS}
LEVEL_BYTES = 16200


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def pinned(pin):
    path = ROOT / pin["file"]
    data = path.read_bytes()
    require(sha(data) == pin["sha256"], f"pinned terrain evidence differs: {path.name}")
    return data


def correction_cells(rows):
    cells = {}
    for row in rows:
        key = (row["mapId"], row["x"], row["y"])
        require(key not in cells and row["before"] != row["after"], f"invalid terrain correction: {key}")
        cells[key] = (row["before"], row["after"])
    return cells


def snapshot_sha(files):
    lines = "".join(f"{row['file']}\0{row['bytes']}\0{row['sha256']}\n" for row in files)
    return sha(lines.encode("utf-8"))


def verify_source_catalog(catalog, receipt, cells, sources):
    require(catalog.get("campaignId") == receipt["campaignId"]
            and catalog.get("authority") == "project-owner-designated", "terrain source catalog identity differs")
    base, fix, snapshot = catalog["baseSource"], catalog["terrainCorrection"], catalog["snapshot"]
    require(base["nativeFile"] == fix["nativeFile"] == receipt["nativeFile"]
            and base["sha256"] == receipt["nativeBeforeSha256"], "terrain source preimage differs")
    require({(c["mapId"], c["x"], c["y"]): (c["before"], c["after"]) for c in fix["cells"]} == cells
            and len(fix["cells"]) == len(cells), "terrain source corrections differ from the receipt")
    require(all(c["mapId"] == f"land:{c['level']}" for c in fix["cells"]), "terrain correction level differs")
    files = catalog["files"]
    require(snapshot["sha256"] == receipt["sourceCatalog"]["snapshotSha256"] == snapshot_sha(files)
            and snapshot["fileCount"] == len(files) and snapshot["bytes"] == sum(f["bytes"] for f in files),
            "terrain source snapshot differs")
    packaged = {row["nativePath"]: (row["byteLength"], row["sha256"]) for row in sources}
    require({f["file"]: (f["bytes"], f["sha256"]) for f in files} == packaged,
            "terrain source snapshot differs from the packaged original sources")
    require(packaged[receipt["nativeFile"]][1] == receipt["nativeAfterSha256"], "corrected native source differs")
    return fix["cells"]


def verify_native_words(before, after, rows):
    require(len(before) == len(after) == 20 * LEVEL_BYTES, "Data LD length differs")
    patched = bytearray(before)
    for row in rows:
        offset = row["level"] * LEVEL_BYTES + (row["x"] * 90 + row["y"]) * 2
        require(int.from_bytes(before[offset:offset + 2], "big", signed=True) == row["before"],
                f"Data LD preimage differs: {row['mapId']} {row['x']},{row['y']}")
        patched[offset:offset + 2] = row["after"].to_bytes(2, "big", signed=True)
    require(bytes(patched) == after, "Data LD differs outside the declared terrain corrections")


def dominant_tuple(cells, tile, landlook, corrected):
    counts = {}
    for index, cell in enumerate(cells):
        if index not in corrected and cell[8] == tile and cell[9] == landlook:
            key = json.dumps([cell[column] for column in MOVEMENT_COLUMNS])
            counts[key] = counts.get(key, 0) + 1
    require(counts, f"corrected terrain {tile} has no uncorrected movement reference")
    return json.loads(max(counts, key=counts.get))


def verify_world(old_bytes, new_bytes, cells):
    old, new = json.loads(old_bytes), json.loads(new_bytes)
    old_maps, new_maps = {m["id"]: m for m in old.pop("maps")}, {m["id"]: m for m in new.pop("maps")}
    require(old == new and old_maps.keys() == new_maps.keys(), "world changed outside its maps")
    require({key[0] for key in cells} <= new_maps.keys(), "terrain correction names an absent map")
    for map_id, map_row in new_maps.items():
        prior = dict(old_maps[map_id])
        width = map_row["width"]
        corrected = {y * width + x: value for (mid, x, y), value in cells.items() if mid == map_id}
        current_cells, prior_cells = map_row.pop("cells"), prior.pop("cells")
        tiles, prior_tiles = map_row.pop("classicTileValues"), prior.pop("classicTileValues")
        require(map_row == prior and len(current_cells) == len(prior_cells) == len(tiles) == len(prior_tiles),
                f"terrain map metadata differs: {map_id}")
        for index, (cell, old_cell) in enumerate(zip(current_cells, prior_cells)):
            if index not in corrected:
                require(cell == old_cell and tiles[index] == prior_tiles[index], f"uncorrected cell differs: {map_id}:{index}")
                continue
            before, after = corrected[index]
            require(prior_tiles[index] == old_cell[8] == before and tiles[index] == cell[8] == after
                    and cell[0] == f"classic.terrain.{after}", f"corrected tile differs: {map_id}:{index}")
            require(all(cell[c] == old_cell[c] for c in range(13) if c not in CORRECTED_COLUMNS),
                    f"corrected cell changed outside terrain and movement: {map_id}:{index}")
            require([cell[c] for c in MOVEMENT_COLUMNS] == dominant_tuple(current_cells, after, cell[9], corrected),
                    f"corrected cell movement differs from its compiled terrain: {map_id}:{index}")


def strip_content_delta(content):
    content = json.loads(content)
    records = content["classicRecords"]
    records["ruleSelection"].pop("capturedSourceSetSha256")
    for row in records["sources"]:
        if row["nativePath"] == "Data LD":
            row.pop("sha256"), row.pop("effectiveSha256")
    return content


def read_archive(path):
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        require(len(names) == len(set(names)), f"duplicate archive member: {path.name}")
        return {name: zf.read(name) for name in names}


def verify_projection(projection, receipt, cells, old_archive, world_bytes):
    rows = [row for row in projection["campaigns"] if row.get("campaignId") == receipt["campaignId"]]
    require(projection.get("kind") and len(rows) == 1, "terrain projection receipt differs")
    world = rows[0]["worldProjection"]
    require(world["baselineArchiveSha256"] == sha(old_archive) and world["afterSha256"] == sha(world_bytes)
            and correction_cells(world["terrainCorrections"]) == cells, "terrain projection identity differs")


def verify_catalog_entry(entry, terrain, receipt):
    require(entry.get("sourceOverride") == {
        "kind": "project-owner-designated-snapshot", "catalog": Path(terrain["sourceCatalog"]["file"]).name,
        "snapshotSha256": receipt["sourceCatalog"]["snapshotSha256"]}, "terrain source override differs")
    require(entry.get("terrainCorrection") == {
        "operation": "retain-owner-terrain-correction", "receiptFile": Path(terrain["receipt"]["file"]).name,
        "previousPackage": receipt["previousPackage"]}, "terrain provenance differs")
    require(entry["compilerRevision"] == receipt["compilerRevision"] and entry["contentId"] == receipt["contentId"],
            "terrain provenance identity differs")


def verify(new_path, terrain, current_row, catalog_entry):
    """Check the terrain correction at `new_path`, the archive identified by `current_row`."""
    receipt = json.loads(pinned(terrain["receipt"]))
    verify_catalog_entry(catalog_entry, terrain, receipt)
    require(receipt.get("kind") == "realmz-rebuilt.trouble-terrain-correction" and receipt.get("formatVersion") == 1
            and receipt["campaignId"] == terrain["campaignId"] == current_row["campaignId"],
            "terrain receipt format differs")
    for key in ("packageHash", "archiveSha256", "bytes"):
        require(receipt[key] == current_row[key], f"terrain receipt identity differs: {key}")
    writer = receipt["toolchain"]["writer"]
    require(receipt["compilerRevision"] == writer["commit"] == terrain["compiler"]["commit"]
            and writer["sourceBundle"]["sha256"] == terrain["sourceBundle"]["sha256"]
            and receipt["toolchain"]["projectionReceiptSha256"] == terrain["projectionReceipt"]["sha256"]
            and receipt["toolchain"]["previousPackageRecipe"] == terrain["previousPackageRecipe"]
            and receipt["sourceCatalog"]["sha256"] == terrain["sourceCatalog"]["sha256"],
            "terrain toolchain pins differ")
    pinned(terrain["sourceBundle"])
    cells = correction_cells(receipt["terrainCorrections"])
    new_files = read_archive(new_path)
    sources = json.loads(new_files["content.json"])["classicRecords"]["sources"]
    rows = verify_source_catalog(json.loads(pinned(terrain["sourceCatalog"])), receipt, cells, sources)
    recipe_path = ROOT / terrain["previousPackageRecipe"]["file"]
    pinned(terrain["previousPackageRecipe"])
    with tempfile.TemporaryDirectory(prefix="realmz-trouble-terrain-") as scratch:
        old_path = Path(scratch) / receipt["file"]
        history.reconstruct_one(history.load_recipe(recipe_path), new_path, old_path)
        old_archive = old_path.read_bytes()
        require(sha(old_archive) == receipt["previousPackage"]["archiveSha256"]
                and len(old_archive) == receipt["previousPackage"]["bytes"], "terrain predecessor archive differs")
        old_files = read_archive(old_path)
    require(json.loads(old_files["manifest.json"])["packageHash"] == receipt["previousPackage"]["packageHash"],
            "terrain predecessor identity differs")
    changed = receipt["changedFiles"]
    identity = lambda data: None if data is None else {"bytes": len(data), "sha256": sha(data)}
    for name in sorted(old_files.keys() | new_files.keys()):
        before, after = old_files.get(name), new_files.get(name)
        if name in changed:
            require(before != after and changed[name] == {"before": identity(before), "after": identity(after)},
                    f"declared terrain package delta differs: {name}")
        else:
            require(before == after, f"undeclared terrain package delta: {name}")
    media = "assets/media/{}.bin"
    verify_native_words(old_files[media.format(receipt["nativeBeforeSha256"])],
                        new_files[media.format(receipt["nativeAfterSha256"])], rows)
    verify_world(old_files["world.json"], new_files["world.json"], cells)
    require(strip_content_delta(old_files["content.json"]) == strip_content_delta(new_files["content.json"]),
            "content changed outside the corrected native source identity")
    verify_projection(json.loads(pinned(terrain["projectionReceipt"])), receipt, cells, old_archive, new_files["world.json"])
    return {"campaignId": receipt["campaignId"], "terrainCorrections": len(cells),
            "previousPackageHash": receipt["previousPackage"]["packageHash"]}
