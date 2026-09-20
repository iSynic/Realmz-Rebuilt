"""Extract the accepted scenario CICN owner inventory from native resource forks.

Usage: python tools/extract_scenario_cicn_ownership.py --castle-scenarios
       "<Castle checkout>/base/Realmz/Scenarios" --output <reviewed lock path>
"""

import argparse
import hashlib
import json
import struct
from pathlib import Path


def _resource_fork(path: Path) -> bytes:
    data = path.read_bytes()
    if data[:4] == bytes.fromhex("00051607"):
        entries = struct.unpack_from(">H", data, 24)[0]
        forks = []
        for index in range(entries):
            entry_id, offset, length = struct.unpack_from(">III", data, 26 + index * 12)
            if entry_id == 2:
                forks.append(data[offset : offset + length])
        if len(forks) != 1:
            raise ValueError(f"{path}: expected one AppleDouble resource fork")
        return forks[0]
    return data


def _cicn_ids(path: Path) -> list[int]:
    data = _resource_fork(path)
    _, map_offset, _, map_length = struct.unpack_from(">IIII", data)
    resource_map = data[map_offset : map_offset + map_length]
    if len(resource_map) < 28:
        raise ValueError(f"{path}: truncated resource map")
    type_list = map_offset + struct.unpack_from(">H", resource_map, 24)[0]
    type_count = struct.unpack_from(">H", data, type_list)[0] + 1
    ids = set()
    for index in range(type_count):
        entry = type_list + 2 + index * 8
        if data[entry : entry + 4] != b"cicn":
            continue
        count, reference_offset = struct.unpack_from(">HH", data, entry + 4)
        for reference in range(count + 1):
            record = type_list + reference_offset + reference * 12
            resource_id = struct.unpack_from(">h", data, record)[0]
            ids.add(resource_id)
    return sorted(ids)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--castle-scenarios", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    catalog_path = root / "src/storage/packages/bundled_campaigns/castle-bundled-scenarios.provenance.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    entries = []
    for scenario in catalog["scenarios"]:
        resource_path = arguments.castle_scenarios / scenario["name"] / "Scenario.rsrc"
        entries.append(
            {
                "campaignId": scenario["campaignId"],
                "classicScenarioResourcesSha256": scenario["classicScenarioResourcesSha256"],
                "scenarioResourceForkSha256": hashlib.sha256(resource_path.read_bytes()).hexdigest(),
                "nativeScenarioCicnIds": _cicn_ids(resource_path),
            }
        )
    document = {"formatVersion": 1, "source": "Castle Realmz Scenario.rsrc resource maps", "entries": entries}
    arguments.output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
