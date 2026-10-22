"""Inventory native land icons independently of compiled overlay aliases."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

from verify_classic_records import source_edit_bytes


def icon_resource(raw):
    if raw < 0:
        return raw + (2000 if raw < -1999 else 1000 if raw < -999 else 0)
    value = raw & ~0x6000
    for _ in range(3):
        if value > 999:
            value -= 1000
    return value if value > 200 else None


def player_map_resource(raw):
    if raw >= 0:
        return None
    for _ in range(3):
        if raw < -999:
            raw += 1000
    return raw


def inventory(path):
    with zipfile.ZipFile(path) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        content = json.loads(archive.read("content.json"))
        world = json.loads(archive.read("world.json"))
        assets = json.loads(archive.read("assets/index.json"))["assets"]
        descriptor = next(asset for asset in assets if asset["kind"] == "classic-source-index")
        source_index = json.loads(archive.read(descriptor["path"]))["sources"]
        source = next(row for row in source_index if row["nativePath"] == "Data LD")
        original = archive.read(source["assetPath"])
        assert hashlib.sha256(original).hexdigest() == source["sha256"]
        facts = next(row for row in content["classicRecords"]["sources"] if row["nativePath"] == "Data LD")
        effective = source_edit_bytes(original, facts["edits"], facts["effectiveByteLength"])
        assert hashlib.sha256(effective).hexdigest() == facts["effectiveSha256"]
        cases = []
        absent_aliases = 0
        for map_row in world["maps"]:
            if map_row["levelType"] != "land":
                continue
            assert map_row["width"] == map_row["height"] == 90
            level = map_row["levelIndex"]
            for offset, compiled_raw in enumerate(map_row["classicTileValues"]):
                x, y = offset % 90, offset // 90
                raw = struct.unpack_from(">h", effective, level * 16200 + (x * 90 + y) * 2)[0]
                assert compiled_raw == raw, (path, map_row["id"], x, y)
                resource = icon_resource(raw)
                if resource is None:
                    continue
                alias = map_row["cells"][offset][10]
                absent_aliases += alias is None
                cases.append({"mapId": map_row["id"], "x": x, "y": y,
                              "raw": raw, "resourceId": resource, "compiledAlias": alias,
                              "playerMapResourceId": player_map_resource(raw)})
    return {"path": str(path.resolve()), "archiveSha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "packageHash": manifest["packageHash"], "campaignId": manifest["campaignId"],
            "nativeSourceSha256": source["sha256"], "effectiveSourceSha256": facts["effectiveSha256"],
            "missingCompiledAliases": absent_aliases, "cases": cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("output must be fresh")
    report = {"format": "realmz.map-icon-inventory/1",
              "castleRevision": "491816ad60037394f92c428e99c004494d3c28b3",
              "proofMode": "Independent retained Data LD bytes and centerpict source semantics; no gameplay claim",
              "packages": [inventory(path) for path in args.package]}
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("NATIVE MAP ICONS:", sum(len(row["cases"]) for row in report["packages"]),
          "packages", len(report["packages"]))


if __name__ == "__main__":
    main()
