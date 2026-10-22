#!/usr/bin/env python3
"""Verify complete native records and the immutable historical correction endpoints."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
import zlib

import complete_records_history as history
import complete_record_history_pairs as history_pairs
import compose_complete_record_history as composition
import prepare_complete_record_updates as updates
import verify_classic_records as native

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = ROOT / "src/storage/packages/bundled_campaigns"
MOVEMENT_COLUMNS = (1, 2, 3, 6, 11, 12)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def read(path):
    return json.loads(path.read_bytes())


def pinned(path, digest):
    data = path.read_bytes()
    require(re.fullmatch(r"[0-9a-f]{64}", digest or "") and sha(data) == digest,
            f"pinned file differs: {path.name}")
    return data


def decode_receipt(compressed, source_hash, compressed_hash, length):
    require(sha(compressed) == compressed_hash, "complete-record compressed receipt differs")
    decoder = zlib.decompressobj()
    raw = decoder.decompress(compressed, length + 1)
    require(len(raw) == length and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail,
            "complete-record receipt length or stream differs")
    require(sha(raw) == source_hash, "complete-record decoded receipt differs")
    return raw


def archive(path, identity):
    data = pinned(path, identity["archiveSha256"])
    require(len(data) == identity["bytes"], f"archive length differs: {path.name}")
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        require(len(names) == len(set(names)), f"duplicate archive member: {path.name}")
        files = {name: zf.read(name) for name in names}
    actual = {name: {"bytes": len(value), "sha256": sha(value)} for name, value in files.items()}
    require(actual == identity["files"], f"complete archive inventory differs: {path.name}")
    manifest = json.loads(files["manifest.json"])
    require(manifest["packageHash"] == identity["packageHash"], f"package identity differs: {path.name}")
    return manifest, files


def check_movement(final_bytes, baseline_bytes):
    current = {row["id"]: row for row in json.loads(final_bytes)["maps"]}
    baseline = {row["id"]: row for row in json.loads(baseline_bytes)["maps"]}
    require(set(current) == set(baseline), "reviewed movement map inventory differs")
    for map_id, row in current.items():
        old = baseline[map_id]
        for key in ("width", "height", "levelType", "levelIndex", "classicTileValues", "topologyFormat"):
            require(row[key] == old[key], f"native map changed during movement retention: {map_id}:{key}")
        require(len(row["cells"]) == len(old["cells"]), f"movement cell count differs: {map_id}")
        for index, (cell, prior) in enumerate(zip(row["cells"], old["cells"])):
            require(all(cell[column] == prior[column] for column in MOVEMENT_COLUMNS),
                    f"unreviewed movement change: {map_id}:{index}")
        require(row["boatReplacementProfiles"] == old["boatReplacementProfiles"],
                f"unreviewed boat profile change: {map_id}")


def historical_workspace(temporary, package_root, inventory):
    """Run unchanged historical checks against their exact original v6 endpoints."""
    root = temporary / "historical"
    tool_root = root / "tools"
    tool_root.mkdir(parents=True)
    for path in (ROOT / "tools").iterdir():
        if path.is_file() and path.suffix in (".py", ".ps1", ".rs", ".json", ".bundle"):
            shutil.copyfile(path, tool_root / path.name)
    shutil.copytree(ROOT / "tools/fixtures", tool_root / "fixtures",
                    ignore=shutil.ignore_patterns("*.md", "complete-records-history", "__pycache__"))
    shutil.copytree(ROOT / "contracts/realmz2", root / "contracts/realmz2")
    shutil.copytree(ROOT / "src/storage/saves", root / "src/storage/saves",
                    ignore=shutil.ignore_patterns("*.md", "*.uid"))
    application = root / "src/storage/packages/application"
    application.mkdir(parents=True)
    for path in (ROOT / "src/storage/packages/application").iterdir():
        if path.is_file() and path.suffix != ".md":
            shutil.copyfile(path, application / path.name)
    target = root / "src/storage/packages/bundled_campaigns"
    target.mkdir(parents=True)
    for name, digest in inventory["historicalFiles"].items():
        require(Path(name).name == name, "historical metadata name is not a leaf")
        (target / name).write_bytes(pinned(BUNDLE / name, digest))
    baseline = inventory["baselineCatalog"]
    (target / "castle-bundled-scenarios.provenance.json").write_bytes(
        pinned(BUNDLE / baseline["file"], baseline["sha256"]))
    recipes = ROOT / "tools/fixtures/complete-records-history/recipes"
    pinned(recipes / "manifest.json", inventory["historyRecipes"]["manifestSha256"])
    history.command_reconstruct(argparse.Namespace(
        recipe_dir=recipes, candidate_dir=package_root, output_dir=temporary / "reconstructed"))
    for path in sorted((temporary / "reconstructed").glob("*.realmz2")):
        shutil.copyfile(path, target / path.name)
    # The new receipt is intentionally absent here: the legacy verifier sees
    # only its original archives, catalog and immutable correction receipts.
    shell = shutil.which("pwsh") or shutil.which("powershell")
    require(shell is not None, "PowerShell is required for historical endpoint checks")
    result = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-File",
                             str(tool_root / "verify_bundled_scenarios.ps1")],
                            cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    require(result.returncode == 0, "historical endpoint verification failed:\n" + result.stdout[-10000:])
    return target


def verify_history_maps(package_root, old_root, inventory, rows):
    catalog = read(old_root / "castle-bundled-scenarios.provenance.json")
    expected = history_pairs.expected_pairs(old_root, catalog)
    old_catalog = {row["campaignId"]: row for row in catalog["scenarios"]}
    fixture = ROOT / "tools/fixtures/complete-records-history/historical-state.zip"
    pinned(fixture, inventory["historyStateSha256"])
    with zipfile.ZipFile(fixture) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "duplicate historical state member")
        index = json.loads(archive.read("index.json"))
        require(index.get("kind") == "realmz.complete-records-history-state" and
                index.get("formatVersion") == 1, "historical state format differs")
        state_rows = {row["packageHash"]: row for row in index["packages"]}
        require(len(state_rows) == len(index["packages"]) == 40, "historical state inventory differs")
        owned_names = {"index.json"}
        seen = set()
        for filename, row in rows.items():
            campaign = row["campaignId"]
            baseline = old_catalog[campaign]
            authorities = {value["packageHash"]: value for value in expected[campaign]}
            require({pair["packageHash"] for pair in row["previousRevisions"]} ==
                    {baseline["packageHash"], *authorities}, "unlisted or missing save predecessor")
            after = updates.read_package(package_root / filename, 7)
            for pair in row["previousRevisions"]:
                if pair["packageHash"] == baseline["packageHash"]:
                    require("history" not in pair, "immediate transition has a historical alias")
                    before = updates.read_package(old_root / filename, 6)
                    require(updates.file_inventory(before) == pair["files"], "immediate old file inventory differs")
                else:
                    authority = authorities[pair["packageHash"]]
                    require(all(pair[key] == authority[key] for key in ("archiveSha256", "bytes")),
                            "historical archive pin differs")
                    require(pair.get("history") == {key: value for key, value in authority.items()
                                                    if key not in ("packageHash", "archiveSha256", "bytes")},
                            "historical route authority differs")
                    state_row = state_rows[pair["packageHash"]]
                    require(state_row["campaignId"] == campaign, "historical state campaign differs")
                    owned_names.update(item["file"] for item in state_row["files"].values())
                    before = composition.fixture_package(archive, state_row, pair)
                    manifest_bytes = archive.read(state_row["files"]["manifest.json"]["file"])
                    manifest = json.loads(manifest_bytes)
                    require(pair["files"] == {**manifest["files"], "manifest.json": {
                        "bytes": len(manifest_bytes), "sha256": sha(manifest_bytes)}},
                        "historical complete file inventory differs from the original manifest")
                    seen.add(pair["packageHash"])
                mapped, finding = updates.state_revision(before, after, campaign)
                require(not finding["mappingBlockers"] and not finding["timerPositionBlockers"] and
                        all(pair[field] == mapped[field] for field in composition.STATE_FIELDS),
                        f"semantic save mapping differs: {campaign}:{pair['packageHash']}")
                changed = sorted(name for name in pair["files"].keys() | row["files"].keys()
                                 if pair["files"].get(name) != row["files"].get(name))
                require(pair["changedPaths"] == changed, "declared complete package delta differs")
        require(seen == set(state_rows) and set(names) == owned_names,
                "unreferenced or unavailable historical state document")


def verify(package_root):
    policy = (ROOT / "src/storage/saves/complete_record_package_delta.gd").read_text(encoding="utf-8")
    match = re.search(r'const RECEIPT_SHA256 := "([0-9a-f]{64})"', policy)
    require(match is not None, "complete-record receipt has no final runtime pin")
    compressed_match = re.search(r'const COMPRESSED_SHA256 := "([0-9a-f]{64})"', policy)
    length_match = re.search(r'const RECEIPT_BYTES := (\d+)', policy)
    require(compressed_match is not None and length_match is not None, "receipt encoding pins are missing")
    receipt_bytes = decode_receipt((package_root / "complete-records.json.zlib").read_bytes(),
                                  match.group(1), compressed_match.group(1), int(length_match.group(1)))
    require(receipt_bytes == pinned(BUNDLE / "complete-records.json", match.group(1)),
            "shipped complete-record receipt differs from its maintainer source")
    receipt = json.loads(receipt_bytes)
    require(receipt.get("kind") == "realmz-rebuilt.complete-records" and receipt.get("formatVersion") == 1,
            "complete-record receipt format differs")
    inventory = json.loads(pinned(BUNDLE / "complete-records-inventory.json", receipt["inventorySha256"]))
    require(inventory.get("kind") == "realmz.complete-records-inventory" and inventory.get("formatVersion") == 1,
            "complete-record inventory format differs")
    catalog_bytes = pinned(package_root / "castle-bundled-scenarios.provenance.json", inventory["catalogSha256"])
    catalog = json.loads(catalog_bytes)
    app = inventory["application"]
    app_path = ROOT / "src/storage/packages/application/realmz-classic-application-library.realmz2"
    pinned(app_path, app["archiveSha256"])
    require(receipt["applicationPackageHash"] == app["packageHash"], "receipt application differs")
    with zipfile.ZipFile(app_path) as zf:
        require(json.loads(zf.read("manifest.json"))["packageHash"] == app["packageHash"],
                "application manifest identity differs")
        application_content = json.loads(zf.read("content.json"))
        application_assets = json.loads(zf.read("assets/index.json"))['assets']
    expected_files = history.EXPECTED
    require({p.name for p in package_root.glob("*.realmz2")} == expected_files,
            "complete-record package set differs")
    rows = {row["file"]: row for row in receipt["campaigns"]}
    expected = {row["file"]: row for row in inventory["campaigns"]}
    provenance = {row["file"]: row for row in catalog["scenarios"]}
    require(len(receipt["campaigns"]) == len(inventory["campaigns"]) == len(catalog["scenarios"]) == 13
            and set(rows) == set(expected) == set(provenance) == expected_files,
            "complete-record campaign inventory differs")
    corrections = native.correction_map(inventory["nativeCorrections"])
    contexts = native.source_context_campaigns(inventory["sourceContexts"])
    checks, sources = [], 0
    for index, filename in enumerate(sorted(rows)):
        row, pin, entry = rows[filename], expected[filename], provenance[filename]
        manifest, files = archive(package_root / filename, row)
        require(manifest["schemaVersion"] == 7 and manifest["schemaHash"] == inventory["schemaSha256"]
                and manifest["compiler"] == inventory["compiler"], f"compiler/schema identity differs: {filename}")
        for field in ("campaignId", "packageHash", "archiveSha256", "bytes"):
            require(row[field] == pin[field] == entry[field], f"reviewed identity differs: {filename}:{field}")
        facts = json.loads(files["content.json"])["classicRecords"]
        require(sha(canonical(facts)) == pin["classicRecordsSha256"], f"native fact inventory differs: {filename}")
        source_rows = [{"nativePath": value["nativePath"], "byteLength": value["byteLength"],
                        "sha256": value["sha256"]} for value in facts["sources"]]
        require(sorted(source_rows, key=lambda x: x["nativePath"]) == pin["sources"],
                f"original source inventory differs: {filename}")
        sources += len(source_rows)
        check = native.verify_package(package_root / filename, corrections, index, contexts, application_content, application_assets)
        require(check.get("passed") is True and check["startupSourceContext"]["startupRoleVerified"] is True,
                f"independent source accounting failed: {filename}")
        checks.append(check)
        previous = row["previousRevisions"]
        require(previous and len({p["packageHash"] for p in previous}) == len(previous),
                f"update predecessor inventory differs: {filename}")
    require(sources == 460, "bundled original source file count differs")
    require(sum(check.get("correctionsUsed", 0) for check in checks) == len(corrections),
            "not every declared native correction was verified")
    require(native.run_self_test()["passed"], "native corruption probes failed")
    with tempfile.TemporaryDirectory(prefix="realmz-complete-records-") as scratch:
        old_root = historical_workspace(Path(scratch), package_root, inventory)
        baseline_catalog = read(old_root / "castle-bundled-scenarios.provenance.json")
        old_rows = {row["file"]: row for row in baseline_catalog["scenarios"]}
        for filename, row in rows.items():
            with zipfile.ZipFile(old_root / filename) as old, zipfile.ZipFile(package_root / filename) as current:
                check_movement(current.read("world.json"), old.read("world.json"))
            baseline_pair = [p for p in row["previousRevisions"] if p["packageHash"] == old_rows[filename]["packageHash"]]
            require(len(baseline_pair) == 1 and baseline_pair[0]["archiveSha256"] == old_rows[filename]["archiveSha256"],
                    f"immediate v6 update pair differs: {filename}")
        verify_history_maps(package_root, old_root, inventory, rows)
    return {"kind": "realmz.complete-records-verification", "formatVersion": 1,
            "campaigns": len(rows), "originalSourceFiles": sources,
            "historicalEndpoints": 13, "explicitSaveTransitions": 53, "passed": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", type=Path, default=BUNDLE,
                        help="reviewed bundle or archives/receipts extracted from the actual PCK")
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.package_root.resolve()), sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, native.CheckError, history.RecipeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
