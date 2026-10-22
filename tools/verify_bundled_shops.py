"""Verify signed shop references and the exact additive package repair boundary."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

from verify_bundled_native_tiles import reconstruct_previous_documents
from verify_trouble_payment import restoration, remove_addition
from verify_program_restoration import correction_for, reverse_current_documents


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()


def verify(root):
    bundle = root / "src/storage/packages/bundled_campaigns"
    catalog = json.loads((bundle / "castle-bundled-scenarios.provenance.json").read_text(encoding="utf-8"))
    repairs = json.loads((bundle / "shop-restoration.json").read_text(encoding="utf-8"))
    assert repairs["compilerToolSha256"] == digest((root / "tools/restore_bundled_shops.rs").read_bytes()), "repair compiler helper drift"
    transitions = {r["campaignId"]: r for r in repairs["transitions"]}
    assert len(transitions) == 3 and sum(len(r["shopIds"]) for r in transitions.values()) == 31
    site_count = 0
    for entry in catalog["scenarios"]:
        path = bundle / entry["file"]
        with zipfile.ZipFile(path) as archive:
            content = json.loads(archive.read("content.json"))
            scenario = json.loads(archive.read("scenario.json"))
            correction = correction_for(root, entry["campaignId"], entry["packageHash"])
            source_paths = {row["path"] for row in correction["recipe"]["payloadAdditions"]} if correction else set()
            assets = json.loads(archive.read("assets/index.json"))["assets"]
            source_index = next(row for row in assets if row["kind"] == "classic-source-index")
            native_sources = json.loads(archive.read(source_index["path"]))["sources"]
            native_shop_rows = next(row["byteLength"] for row in native_sources if row["nativePath"] == "Data SD") // 3002
            manifest = json.loads(archive.read("manifest.json"))
            shops = {s["classicId"] for s in content["shops"]}
            for program in scenario["programs"]:
                for action in program["instructions"]:
                    op = action.get("opcode")
                    if op == 6:
                        target = abs(action["id"])
                    elif op in (51, 73) and action.get("extraCode"):
                        target = abs(action["extraCode"][0])
                    else:
                        continue
                    if target not in shops and target >= native_shop_rows and "realmz.scenario.deferred-references-v1" in manifest["capabilities"]:
                        print(f"{entry['name']} preserves {program['id']} slot {action['slot']} with native unavailable shop {target} (source rows {native_shop_rows}).")
                        continue
                    assert target in shops, f"{entry['name']} {program['id']} slot {action['slot']}: missing shop {target}"
                    site_count += 1
            if entry["campaignId"] not in transitions:
                continue
            repair = transitions[entry["campaignId"]]
            refresh = entry.get("nativeTileRefresh")
            if refresh is not None:
                previous = refresh["previousPackage"]
                assert previous["packageHash"] == repair["newPackageHash"]
                assert previous["compilerRevision"] == repair["compilerRevision"] == repairs["compilerRevision"]
                assert previous["archiveSha256"] == repair["newArchiveSha256"]
                assert previous["contentId"] == repair["newContentId"]
                assert previous["bytes"] == repair["bytes"]
                receipt_row = _receipt_row(root, refresh, entry)
                old_documents = reconstruct_previous_documents(archive, receipt_row)
                old_content = json.loads(old_documents["content.json"])
                old_scenario = json.loads(old_documents["scenario.json"])
                current_documents = {name: json.loads(archive.read(name)) for name in
                                     ("content.json", "scenario.json", "world.json", "assets/index.json")}
                reverse_current_documents(archive, current_documents, root)
                if "programRestoration" in entry:
                    remove_addition(current_documents["scenario.json"], restoration(root))
                old_content_comparable = dict(old_content)
                current_content_comparable = dict(current_documents["content.json"])
                old_content_comparable.pop("schemaVersion", None)
                current_content_comparable.pop("schemaVersion", None)
                assert digest(canonical(old_content_comparable)) == digest(canonical(current_content_comparable)), "native refresh changed gameplay content"
                added_program_ids = {row["programId"] for row in receipt_row["restoredEmptyRecords"]}
                current_programs = [program for program in current_documents["scenario.json"]["programs"]
                                    if program["id"] not in added_program_ids]
                assert sorted(old_scenario["programs"], key=lambda p: p["id"]) == sorted(
                    current_programs, key=lambda p: p["id"]
                ), "native refresh changed existing scenario programs"
                content = old_content
                scenario = old_scenario
                payloads = {name: old_documents[name] for name in old_documents
                            if name not in ("content.json", "manifest.json")}
                payloads.update({name: archive.read(name) for name in archive.namelist()
                                 if name.startswith("assets/media/") and name not in source_paths})
                identities = "".join(name + "\0" + digest(payloads[name]) + "\n"
                                     for name in sorted(payloads))
                assert digest(identities.encode()) == repair["unchangedPayloadsSha256"], "unrelated package payload changed"
            else:
                assert entry["packageHash"] == repair["newPackageHash"]
                assert entry["compilerRevision"] == repair["compilerRevision"] == repairs["compilerRevision"]
                assert entry["archiveSha256"] == repair["newArchiveSha256"] == digest(path.read_bytes())
                identities = "".join(name + "\0" + digest(archive.read(name)) + "\n"
                                     for name in sorted(archive.namelist()) if name not in ("manifest.json", "content.json"))
                assert digest(identities.encode()) == repair["unchangedPayloadsSha256"], "unrelated package payload changed"
            additions = [s for s in content["shops"] if s["classicId"] in repair["shopIds"]]
            assert [s["classicId"] for s in additions] == repair["shopIds"]
            assert digest(canonical(additions)) == repair["addedShopsSha256"]
            content["shops"] = [s for s in content["shops"] if s["classicId"] not in repair["shopIds"]]
            assert digest(canonical(content)) == repair["oldContentSha256"], "existing gameplay content changed"
    print(f"Verified {site_count} shop instruction sites across 13 campaigns; 31 source-compiled additions and unchanged existing content.")


def _receipt_row(root, refresh, entry):
    assert refresh.get("receiptFile") == "native-map-triggers.json", "unsupported native refresh receipt file"
    path = root / "src/storage/packages/bundled_campaigns" / refresh["receiptFile"]
    report = json.loads(path.read_text(encoding="utf-8"))
    matches = [row for row in report["scenarios"]
               if row.get("outputFile") == entry["file"]
               and row.get("name") == entry["name"]]
    assert len(matches) == 1, f"{entry['file']} has no unique native refresh receipt row"
    return matches[0]


if __name__ == "__main__":
    try:
        verify(Path(__file__).resolve().parent.parent)
    except (AssertionError, KeyError, ValueError, OSError) as error:
        sys.exit(f"Shop preservation check failed: {error}")
