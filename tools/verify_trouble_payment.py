"""Validate the exact additive native XAP restoration and its historical boundary."""
import hashlib
import json
from pathlib import Path
import re
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")


def restoration(root):
    path = root / "src/storage/packages/bundled_campaigns/trouble-payment-restoration.json"
    policy = (root / "src/storage/saves/payment_save_update.gd").read_text(encoding="utf-8")
    pin = re.search(r'const RECEIPT_SHA256 := "([0-9a-f]{64})"', policy)
    assert pin and digest(path.read_bytes()) == pin[1], "payment receipt pin differs"
    record = json.loads(path.read_bytes())
    assert record["kind"] == "realmz-rebuilt.trouble-payment-restoration"
    assert record["formatVersion"] == 1
    assert record["campaignId"] == "scenario-trouble-in-the-sword-lands"
    assert record["compilerToolSha256"] == digest((root / "tools/restore_trouble_payment.rs").read_bytes())
    assert record["nativeSha256"] == "9a10703a149d804258fc0950ceb50e036dd2f4aeb7919cfb39b4e5c3ab1ca5e5"
    assert record["nativeRecordSha256"] == "e84563b9246ee4b8a8406d3fb19a77bfc153140dff752a914d2ab533a05cf776"
    expected = {"id": "xap:330", "ownerId": "Data ED3:macro:330", "ownerKind": "extra-action-point",
                "instructions": [{"kind": "classicAction", "slot": slot, "rawOpcode": opcode,
                                  "opcode": opcode, "id": operand, "gosub": False, "extraCode": None}
                                 for slot, opcode, operand in [(0, 1, 569), (7, 24, 0)]]}
    assert record["addedPrograms"] == [expected], "restoration differs from native record 330"
    return record


def remove_addition(scenario, record):
    for addition in record["addedPrograms"]:
        matches = [p for p in scenario["programs"] if p["id"] == addition["id"]]
        assert matches == [addition], "missing, duplicate or altered payment program"
        scenario["programs"].remove(matches[0])
    assert digest(canonical(scenario)) == record["previousScenarioSha256"], "existing scenario programs changed"
    return scenario


def verify(root):
    from verify_program_restoration import correction_for, reverse_current_documents
    record = restoration(root)
    bundle = root / "src/storage/packages/bundled_campaigns"
    catalog = json.loads((bundle / "castle-bundled-scenarios.provenance.json").read_bytes())
    entry = next(e for e in catalog["scenarios"] if e["campaignId"] == record["campaignId"])
    program = correction_for(root, entry["campaignId"], entry["packageHash"])
    endpoint = program["previousPackage"] if program else entry
    assert entry["programRestoration"] == {"operation": "restore-native-payment-program",
                                           "receiptFile": "trouble-payment-restoration.json",
                                           "previousPackage": record["previousPackage"]}
    for key in ["file", "packageHash", "contentId", "archiveSha256", "bytes", "compilerRevision"]:
        assert (entry[key] if key == "file" else endpoint[key]) == record[key], f"payment provenance differs: {key}"
    package = bundle / entry["file"]
    assert digest(package.read_bytes()) == entry["archiveSha256"]
    with zipfile.ZipFile(package) as archive:
        documents = {name: json.loads(archive.read(name)) for name in ["scenario.json", "content.json", "world.json"]}
        reverse_current_documents(archive, documents, root)
        scenario = documents["scenario.json"]
        remove_addition(scenario, record)
        manifest = json.loads(archive.read("manifest.json"))
        assert manifest["packageHash"] == entry["packageHash"]
        assert manifest["contentId"] == entry["contentId"]
        messages = json.loads(archive.read("content.json"))["messages"]
        assert any(m["id"] == 569 and m["text"] for m in messages), "refusal message missing"
    print("Verified native Trouble XAP 330, exact additive scenario delta and pinned save-update receipt.")


if __name__ == "__main__":
    verify(Path(__file__).resolve().parent.parent)
