"""Distinguish preserved unavailable TEXT references from lost native resources."""
import json
from pathlib import Path
import struct
import zipfile
from audit_native_programs import sha


def resource_keys(data):
    if data[:4] == bytes.fromhex("00051607"):
        entries = [struct.unpack_from(">III", data, 26 + i * 12)
                   for i in range(struct.unpack_from(">H", data, 24)[0])]
        forks = [(offset, length) for identity, offset, length in entries if identity == 2]
        assert len(forks) == 1, "native resource fork is ambiguous"
        offset, length = forks[0]
        data = data[offset:offset + length]
    _, map_offset, _, map_length = struct.unpack_from(">IIII", data)
    assert map_offset + map_length <= len(data) and map_length >= 28
    type_list = map_offset + struct.unpack_from(">H", data, map_offset + 24)[0]
    result = set()
    for index in range(struct.unpack_from(">H", data, type_list)[0] + 1):
        entry = type_list + 2 + index * 8
        kind = data[entry:entry + 4].decode("mac_roman")
        count, offset = struct.unpack_from(">HH", data, entry + 4)
        for reference in range(count + 1):
            position = type_list + offset + reference * 12
            assert position + 12 <= map_offset + map_length
            result.add((kind, struct.unpack_from(">h", data, position)[0]))
    return result


def unavailable_text(root):
    bundle = root / "src/storage/packages/bundled_campaigns"
    catalog = json.loads((bundle / "castle-bundled-scenarios.provenance.json").read_bytes())
    with zipfile.ZipFile(root / "src/storage/packages/application/realmz-classic-application-library.realmz2") as archive:
        application = {(row["resourceType"], row["resourceId"])
                       for row in json.loads(archive.read("assets/index.json"))["assets"]}
    result = []
    for entry in catalog["scenarios"]:
        with zipfile.ZipFile(bundle / entry["file"]) as archive:
            assets = json.loads(archive.read("assets/index.json"))["assets"]
            source = next(row for row in assets if row["kind"] == "classic-source-index")
            receipt = json.loads(archive.read(source["path"]))
            native = next(row for row in receipt["sources"] if row["nativePath"] == "Scenario.rsrc")
            data = archive.read(native["assetPath"])
            assert sha(data) == native["sha256"], "native resource source differs"
            native_keys = resource_keys(data)
            compiled = {(row["resourceType"], row["resourceId"]) for row in assets}
            for program in json.loads(archive.read("scenario.json"))["programs"]:
                for action in program["instructions"]:
                    if action.get("opcode") != 62 or ("TEXT", action["id"]) in compiled:
                        continue
                    key = ("TEXT", action["id"])
                    assert key not in native_keys and key not in application, "available native TEXT was omitted"
                    result.append(dict(campaignId=entry["campaignId"], programId=program["id"],
                                       slot=action["slot"], resourceId=action["id"],
                                       disposition="preserved-authored-unavailable-resource"))
    return result


if __name__ == "__main__":
    print(json.dumps(unavailable_text(Path(__file__).resolve().parent.parent)))
