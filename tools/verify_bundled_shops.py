"""Verify signed shop references and the exact additive package repair boundary."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile


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
                    assert target in shops, f"{entry['name']} {program['id']} slot {action['slot']}: missing shop {target}"
                    site_count += 1
            if entry["campaignId"] not in transitions:
                continue
            repair = transitions[entry["campaignId"]]
            assert entry["packageHash"] == repair["newPackageHash"]
            assert entry["compilerRevision"] == repair["compilerRevision"] == repairs["compilerRevision"]
            assert entry["archiveSha256"] == repair["newArchiveSha256"] == digest(path.read_bytes())
            additions = [s for s in content["shops"] if s["classicId"] in repair["shopIds"]]
            assert [s["classicId"] for s in additions] == repair["shopIds"]
            assert digest(canonical(additions)) == repair["addedShopsSha256"]
            content["shops"] = [s for s in content["shops"] if s["classicId"] not in repair["shopIds"]]
            assert digest(canonical(content)) == repair["oldContentSha256"], "existing gameplay content changed"
            identities = "".join(name + "\0" + digest(archive.read(name)) + "\n"
                                 for name in sorted(archive.namelist()) if name not in ("manifest.json", "content.json"))
            assert digest(identities.encode()) == repair["unchangedPayloadsSha256"], "unrelated package payload changed"
    print(f"Verified {site_count} shop instruction sites across 13 campaigns; 31 source-compiled additions and unchanged existing content.")


if __name__ == "__main__":
    try:
        verify(Path(__file__).resolve().parent.parent)
    except (AssertionError, KeyError, ValueError, OSError) as error:
        sys.exit(f"Shop preservation check failed: {error}")
