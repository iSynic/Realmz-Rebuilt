#!/usr/bin/env python3
"""Compose only the forty existing save routes with a reviewed v6-to-v7 delta."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import complete_record_history_pairs as routes
import prepare_complete_record_updates as updates

STATE_FIELDS = ("simpleSlots", "shopIndexes", "timerIds", "timerPositions",
                "randomRegionIds", "randomPendingCompatibleByMap")
STATE_DOCUMENTS = ("content.json", "world.json", "manifest.json")


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8", newline="\n")


def write_fixture(path, packages):
    """Retain exact historical typed documents, deduplicated independently of ZIP framing."""
    blobs, rows = {}, []
    for package in sorted(packages, key=lambda value: value["packageHash"]):
        files = {}
        for name in STATE_DOCUMENTS:
            raw = package["manifestBytes"] if name == "manifest.json" else package["files"][name]
            digest = updates.sha(raw)
            leaf = f"documents/{digest}.json"
            blobs[leaf] = raw
            files[name] = {"file": leaf, "bytes": len(raw), "sha256": digest}
        rows.append({"campaignId": package["campaignId"],
                     "packageHash": package["packageHash"], "files": files})
    index = {"kind": "realmz.complete-records-history-state", "formatVersion": 1,
             "packages": rows}
    blobs["index.json"] = updates.canonical(index)
    with zipfile.ZipFile(path, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, raw in sorted(blobs.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            info.create_system = 3
            archive.writestr(info, raw, compresslevel=9)


def fixture_package(archive, package_row, pair):
    """Read only hash-bound typed state facts; unavailable native bytes stay unavailable."""
    updates.require(package_row["packageHash"] == pair["packageHash"], "historical state identity differs")
    files = {}
    for name in STATE_DOCUMENTS:
        item = package_row["files"][name]
        raw = archive.read(item["file"])
        expected = pair["files"][name]
        updates.require(len(raw) == item["bytes"] == expected["bytes"] and
                        updates.sha(raw) == item["sha256"] == expected["sha256"],
                        f"historical state document differs: {name}")
        files[name] = raw
    manifest = json.loads(files.pop("manifest.json"))
    updates.require(updates.validate_identity(manifest, Path(pair["packageHash"])) == pair["packageHash"],
                    "historical manifest is not the original endpoint identity")
    updates.require(all(manifest["files"][name] == pair["files"][name]
                        for name in ("content.json", "world.json")),
                    "historical typed facts disagree with their original manifest")
    return {"path": Path(pair["packageHash"]), "packageHash": pair["packageHash"],
            "archiveSha256": pair["archiveSha256"], "archiveBytes": pair["bytes"],
            "campaignId": package_row["campaignId"], "manifestBytes": b"", "files": files,
            "documents": {"content.json": json.loads(files["content.json"])}}


def compose(baseline_dir, candidate_dir, review_dir, historical_index, output):
    updates.require(not output.exists(), "output must be fresh")
    catalog = json.loads((baseline_dir / "castle-bundled-scenarios.provenance.json").read_bytes())
    expected = routes.expected_pairs(baseline_dir, catalog)
    candidates = updates.directory_package_paths(candidate_dir)
    index = json.loads(historical_index.read_bytes())
    indexed = {(row["packageHash"], row["archiveSha256"]): row for row in index}
    receipt = json.loads((review_dir / "receipt.json").read_bytes())
    review = json.loads((review_dir / "generation-report.json").read_bytes())
    updates.require(not review["blockers"] and len(receipt["campaigns"]) == 13,
                    "immediate transitions have unresolved blockers")
    baseline_rows = {row["campaignId"]: row for row in catalog["scenarios"]}
    reports, packages = [], []
    for campaign in receipt["campaigns"]:
        campaign_id = campaign["campaignId"]
        after = updates.read_package(candidates[campaign_id], 7)
        updates.require(after["packageHash"] == campaign["packageHash"] and
                        after["archiveSha256"] == campaign["archiveSha256"] and
                        updates.file_inventory(after) == campaign["files"],
                        "candidate differs from the reviewed immediate transition")
        updates.require(len(campaign["previousRevisions"]) == 1 and
                        campaign["previousRevisions"][0]["packageHash"] == baseline_rows[campaign_id]["packageHash"],
                        "review is not the exact immediate baseline transition")
        for authority in expected[campaign_id]:
            pin = indexed.get((authority["packageHash"], authority["archiveSha256"]))
            updates.require(pin is not None, f"original historical archive unavailable: {authority['packageHash']}")
            before = updates.read_package(Path(pin["path"]))
            updates.require(before["campaignId"] == campaign_id and before["archiveBytes"] == authority["bytes"] and
                            before["archiveSha256"] == authority["archiveSha256"] and
                            before["packageHash"] == authority["packageHash"], "historical archive differs from authority")
            pair, mapping = updates.state_revision(before, after, campaign_id)
            updates.require(not mapping["mappingBlockers"] and not mapping["timerPositionBlockers"],
                            f"historical typed positions are ambiguous: {campaign_id}:{authority['route']}")
            pair["history"] = {key: value for key, value in authority.items()
                               if key not in ("packageHash", "archiveSha256", "bytes")}
            campaign["previousRevisions"].append(pair)
            reports.append({"campaignId": campaign_id, "beforePackageHash": pair["packageHash"],
                            "history": pair["history"], **mapping})
            packages.append(before)
        del after
    updates.require(len(reports) == 40, "historical route count differs")
    output.mkdir(parents=True)
    write_fixture(output / "historical-state.zip", packages)
    write_json(output / "receipt.json", receipt)
    write_json(output / "history-report.json", {
        "kind": "realmz.complete-records-history-composition", "formatVersion": 1,
        "basis": "Original historical policies validate their original v6 endpoints; explicit typed-position maps then reach v7. Missing old native annexes are not inferred.",
        "historicalIndexSha256": hashlib.sha256(historical_index.read_bytes()).hexdigest(),
        "historicalStateSha256": updates.sha((output / "historical-state.zip").read_bytes()),
        "immediateReviewSha256": updates.sha((review_dir / "generation-report.json").read_bytes()),
        "historicalRoutes": reports, "transitions": 53})
    return {"campaigns": 13, "historicalRoutes": 40, "transitions": 53, "output": str(output)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline-dir", "candidate-dir", "review-dir", "historical-index", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(compose(args.baseline_dir, args.candidate_dir, args.review_dir,
                                 args.historical_index, args.output), sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as exc:
        print(f"ERROR: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
