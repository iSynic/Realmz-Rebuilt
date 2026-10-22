"""Name only the historical routes already supported at the reviewed v6 endpoint."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import zlib


def require(condition, message):
    if not condition:
        raise ValueError(message)


def expected_pairs(bundle: Path, catalog: dict) -> dict[str, list[dict]]:
    def receipt(name):
        raw = (bundle / name).read_bytes()
        pins[name] = hashlib.sha256(raw).hexdigest()
        return json.loads(zlib.decompress(raw) if name.endswith(".zlib") else raw)

    pins = {}
    compression = receipt("source-compression.json")
    programs = receipt("program-restoration.json.zlib")
    payment = receipt("trouble-payment-restoration.json")
    receipt("native-map-triggers.json")
    by_id = {row["campaignId"]: row for row in catalog["scenarios"]}
    compressed = {row["campaignId"]: row for row in compression["campaigns"]}
    restored = {row["campaignId"]: row for row in programs["campaigns"]}
    require(len(by_id) == len(compressed) == len(restored) == 13 and
            set(by_id) == set(compressed) == set(restored), "historical campaign inventories differ")
    result = {key: [] for key in by_id}

    def append(campaign, route, previous, receipts):
        require(all(name in pins for name in receipts), "historical receipt is missing")
        result[campaign].append({
            "route": route,
            "packageHash": previous["packageHash"],
            "archiveSha256": previous["archiveSha256"],
            "bytes": previous["bytes"],
            "originalEndpointPackageHash": by_id[campaign]["packageHash"],
            "originalEndpointArchiveSha256": by_id[campaign]["archiveSha256"],
            "authorityReceipts": {name: pins[name] for name in receipts},
        })

    for campaign, row in by_id.items():
        encoded, program = compressed[campaign], restored[campaign]
        require(encoded["packageHash"] == row["packageHash"] and
                encoded["archiveSha256"] == row["archiveSha256"] and
                encoded["previousPackage"]["packageHash"] == program["packageHash"] and
                encoded["previousPackage"]["archiveSha256"] == program["archiveSha256"],
                f"historical compression/program endpoints differ: {campaign}")
        append(campaign, "compression", encoded["previousPackage"], ["source-compression.json"])
        append(campaign, "programs", program["previousPackage"],
               ["program-restoration.json.zlib", "source-compression.json"])
        append(campaign, "markers", row["nativeTileRefresh"]["previousPackage"],
               ["native-map-triggers.json", "trouble-payment-restoration.json",
                "program-restoration.json.zlib", "source-compression.json"])
        if campaign == payment["campaignId"]:
            append(campaign, "payment", payment["previousPackage"],
                   ["trouble-payment-restoration.json", "program-restoration.json.zlib",
                    "source-compression.json"])
        identities = [value["packageHash"] for value in result[campaign]]
        require(len(identities) == len(set(identities)) and row["packageHash"] not in identities,
                f"historical predecessor identities collide: {campaign}")
    require(sum(len(rows) for rows in result.values()) == 40, "historical route count differs")
    return result
