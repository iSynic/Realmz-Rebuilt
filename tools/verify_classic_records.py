#!/usr/bin/env python3
"""Independently verify schema-v7 Classic record facts in .realmz2 archives."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import sys
import zipfile
from pathlib import Path

import classic_projection_checks
import classic_world_projection_checks
import classic_support_projection_checks

MAX_ENTRIES = 100_000
MAX_ENTRY_BYTES = 512 * 1024 * 1024
MAX_ARCHIVE_BYTES = 2 * 1024 * 1024 * 1024
SHA_RE = re.compile(r"^[0-9a-f]{64}$")

# Independently transcribed from the source-backed descriptor table in
# providence/crates/providence-core/src/codecs.rs and its named constants in
# providence/crates/providence-core/src/codecs/*.rs. These are framing facts,
# not evaluation-bundle output. Unlisted paths stay opaque.
CODEC_LAYOUTS = {
    "Data LD": ("land-maps", 16200), "Data DL": ("dungeon-maps", 16200),
    "Layout": ("land-layout", 256), "Data RD": ("land-random-levels", 644),
    "Data RDD": ("dungeon-random-levels", 644), "Data DD": ("land-action-points", 40),
    "Data DDD": ("dungeon-action-points", 40),
    "Data EDCD": ("extra-codes", 10), "Data ED": ("simple-encounters", 426),
    "Data ED2": ("complex-encounters", 520), "Data ED3": ("extra-action-points", 40),
    "Data TD2": ("rogue-encounters", 118),
    "Data TD3": ("timed-encounters", 40), "Data BD": ("battle-records", 346),
    "Data MD": ("scenario-monsters", 210), "Data MD-1": ("mega-monster-variant-records", 210),
    "Data MD1": ("monster-variant-records", 210), "Data NI": ("scenario-item-definitions", 100),
    "Data Race": ("race-rules", 408), "Data Caste": ("caste-rules", 576),
    "Data SD": ("shop-records", 3002), "Data TD": ("treasure-records", 48),
    "Data SD2": ("scenario-messages", 256),
    "Data OD": ("option-labels", 25), "Data MD2": ("player-maps", 340),
    "Data S": ("standard-spell-definitions", 30),
    "Data Spell": ("scenario-spell-definitions", 30),
    "Global": ("global-macro-hooks", 60), "Data CI": ("scenario-contact-info", 4608),
    "Data CS": ("scenario-security-backup", 316), "Data RI": ("scenario-restrictions", 320),
    "Scenario": ("scenario-support", 600), "Data Solids": ("special-land-solidity", 1024),
    "Data ID": ("item-definitions", 100), "Data DES": ("monster-descriptions", 256),
}
# These additional exact paths use the same CODEC_REGISTRY descriptors. Scenario
# markers/startup names are recognized separately because their path is content-defined.
CODEC_LAYOUTS.update({
    "Data Custom 1 BD": ("custom-landlook-metadata", 40),
    "Data Custom 2 BD": ("custom-landlook-metadata", 40),
    "Data Custom 3 BD": ("custom-landlook-metadata", 40),
})
THREE = {
    "Data ED": ("simple", "simple-encounters"),
    "Data TD3": ("timed", "timed-encounters"),
    "Data SD": ("shops", "shop-records"),
}
NAMESPACE = {
    "Data BD": ("battles", None), "Data MD": ("monsters", 0),
    "Data MD-1": ("monsterSets", -1), "Data MD1": ("monsterSets", 1),
}
RESOURCE_MAGICS = {0x00051600, 0x00051607}
STARTUP_CONTEXT_LAYOUTS = {
    "startup": ("scenario-startup", 316, [{"start": 0, "end": 20}, {"start": 60, "end": 316}], 320, 4),
    "security": ("scenario-security-startup", 316, [{"start": 0, "end": 316}], 320, 4),
}
STARTUP_LAYOUT_FAMILIES = {value[0]: value for value in STARTUP_CONTEXT_LAYOUTS.values()}


def fixed_layout(path: str, layouts: list) -> tuple[str, int] | None:
    """Return the independent framing for an exact or registry-pattern path."""
    return CODEC_LAYOUTS.get(path)


def checked_slice(data: bytes, offset: int, length: int) -> bytes:
    require(isinstance(offset, int) and isinstance(length, int) and offset >= 0 and length >= 0 and
            offset + length <= len(data), "malformed resource fork")
    return data[offset:offset + length]


def resource_payload(data: bytes) -> bytes:
    if len(data) < 4 or struct.unpack_from(">I", data)[0] not in RESOURCE_MAGICS:
        return data
    require(len(data) >= 26, "malformed AppleSingle/AppleDouble resource container")
    count = struct.unpack_from(">H", data, 24)[0]
    require(26 + count * 12 <= len(data), "malformed AppleSingle/AppleDouble descriptor table")
    for index in range(count):
        entry_id, offset, length = struct.unpack_from(">III", data, 26 + index * 12)
        if entry_id == 2:
            return checked_slice(data, offset, length)
    raise CheckError("AppleSingle/AppleDouble resource fork is missing")


def is_resource_fork_path(path: str) -> bool:
    return path.endswith((".rsrc", ".rsf")) or any(
        part == ".rsrc" or part.startswith("._") for part in path.split("/"))


def parse_resource_inventory(data: bytes) -> list[dict]:
    """Read resource identities and payload digests without relying on compiler output."""
    fork = resource_payload(data)
    require(len(fork) >= 32, "malformed resource fork")
    data_offset, map_offset, data_length, map_length = struct.unpack_from(">IIII", fork)
    checked_slice(fork, data_offset, data_length)
    checked_slice(fork, map_offset, map_length)
    map_header = checked_slice(fork, map_offset, 28)
    type_list = map_offset + struct.unpack_from(">H", map_header, 24)[0]
    name_list = map_offset + struct.unpack_from(">H", map_header, 26)[0]
    raw_type_count = struct.unpack_from(">H", fork, type_list)[0]
    if raw_type_count == 0xFFFF:
        return []
    occurrences: dict[tuple[bytes, int], int] = {}
    result = []
    for type_index in range(raw_type_count + 1):
        type_offset = type_list + 2 + type_index * 8
        type_bytes = checked_slice(fork, type_offset, 8)
        resource_type_bytes = type_bytes[:4]
        raw_count, refs_rel = struct.unpack_from(">HH", type_bytes, 4)
        ref_list = type_list + refs_rel
        for ref_index in range(raw_count + 1):
            ref = checked_slice(fork, ref_list + ref_index * 12, 12)
            resource_id = struct.unpack_from(">h", ref)[0]
            relative = int.from_bytes(ref[5:8], "big")
            length_offset = data_offset + relative
            length = struct.unpack_from(">I", checked_slice(fork, length_offset, 4))[0]
            payload = checked_slice(fork, length_offset + 4, length)
            key = (resource_type_bytes, resource_id)
            occurrence = occurrences.get(key, 0)
            occurrences[key] = occurrence + 1
            require(len(result) < MAX_ENTRIES, "resource fork entry count exceeds checker limit")
            result.append({"resourceTypeBytes": list(resource_type_bytes), "resourceId": resource_id,
                           "occurrence": occurrence, "sha256": sha(payload), "byteLength": len(payload)})
    return result


class CheckError(Exception):
    pass


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CheckError(message)


def read_json(data: bytes, label: str) -> dict:
    try:
        value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CheckError(f"invalid {label} JSON") from exc
    require(isinstance(value, dict), f"{label} must be an object")
    return value


def safe_name(name: str) -> bool:
    return bool(name) and not name.startswith(("/", "\\")) and "\\" not in name and all(
        part not in ("", ".", "..") for part in name.split("/")
    )


def verify_manifest_identities(blobs: dict[str, bytes], manifest: dict) -> None:
    hasher = hashlib.sha256()
    for name in ("content.json", "world.json", "scenario.json", "assets/index.json"):
        require(name in blobs, "content identity document is missing")
        data = blobs[name]
        hasher.update(len(name).to_bytes(8, "big"))
        hasher.update(name.encode())
        hasher.update(len(data).to_bytes(8, "big"))
        hasher.update(data)
    require(manifest.get("contentId") == hasher.hexdigest(), "manifest content identity differs from documents")
    unsigned = {key: value for key, value in manifest.items() if key != "packageHash"}
    canonical = json.dumps(unsigned, ensure_ascii=False, sort_keys=True,
                           separators=(",", ":"), allow_nan=False).encode("utf-8")
    require(manifest.get("packageHash") == sha(canonical), "manifest package identity differs")


def read_archive(path: Path) -> tuple[dict[str, bytes], dict]:
    try:
        archive = zipfile.ZipFile(path)
    except (OSError, zipfile.BadZipFile) as exc:
        raise CheckError("archive is not a readable ZIP") from exc
    with archive:
        infos = archive.infolist()
        require(len(infos) <= MAX_ENTRIES, "archive entry count exceeds checker limit")
        total = 0
        names: set[str] = set()
        for info in infos:
            require(safe_name(info.filename), "archive contains an unsafe entry path")
            require(info.filename not in names, "archive contains duplicate entry names")
            names.add(info.filename)
            require(not info.is_dir(), "archive contains directory entries")
            require(info.file_size <= MAX_ENTRY_BYTES, "archive entry exceeds checker limit")
            total += info.file_size
            require(total <= MAX_ARCHIVE_BYTES, "archive expanded size exceeds checker limit")
            require(not (info.flag_bits & 1), "encrypted archive entries are unsupported")
        require("manifest.json" in names, "archive has no manifest.json")
        blobs = {}
        for info in infos:
            chunks, size = [], 0
            with archive.open(info) as stream:
                while True:
                    chunk = stream.read(1024 * 1024)
                    if not chunk:
                        break
                    size += len(chunk)
                    require(size <= info.file_size and size <= MAX_ENTRY_BYTES,
                            "archive entry expands beyond its declared size")
                    chunks.append(chunk)
            require(size == info.file_size, "archive entry size differs from its directory")
            blobs[info.filename] = b"".join(chunks)
    manifest = read_json(blobs["manifest.json"], "manifest")
    files = manifest.get("files")
    require(isinstance(files, dict), "manifest file inventory is missing")
    require(set(files) == set(blobs) - {"manifest.json"}, "archive entries differ from manifest inventory")
    for name, expected in files.items():
        require(safe_name(name) and isinstance(expected, dict), "manifest has invalid file entry")
        data = blobs[name]
        require(expected.get("bytes") == len(data) and expected.get("sha256") == sha(data),
                "manifest file integrity check failed")
    require(manifest.get("schemaVersion") == 7, "archive is not schema v7")
    verify_manifest_identities(blobs, manifest)
    return blobs, manifest


def unpack_signed(data: bytes, count: int, width: int) -> list[int]:
    return list(struct.unpack(">" + str(count) + ("b" if width == 1 else "h"), data))


def native_fact(path: str, row: bytes) -> dict:
    if path == "Data ED":
        return {
            "codes": unpack_signed(row[:32], 32, 1),
            "operands": unpack_signed(row[32:96], 32, 2),
            "choiceResults": unpack_signed(row[96:100], 4, 1),
            "canBackOutByte": row[100], "maxTimes": unpack_signed(row[101:102], 1, 1)[0],
            "casteSuccess": unpack_signed(row[102:103], 1, 1)[0], "reservedByte": row[103],
            "promptMessageId": struct.unpack(">h", row[104:106])[0],
            "textSlots": [list(row[106 + i * 80:186 + i * 80]) for i in range(4)],
        }
    if path == "Data TD3":
        return {"words": list(struct.unpack(">20h", row))}
    return {
        "itemIds": list(struct.unpack(">1000h", row[:2000])),
        "quantities": list(row[2000:3000]), "inflation": struct.unpack(">h", row[3000:3002])[0],
    }


def correction_map(receipt: dict | None) -> dict:
    if receipt is None:
        return {}
    require(receipt.get("kind") == "realmz.classic-record-corrections" and receipt.get("version") == 1,
            "correction receipt has an unsupported kind or version")
    rows = receipt.get("corrections")
    require(isinstance(rows, list), "correction receipt has no corrections array")
    result = {}
    for row in rows:
        require(isinstance(row, dict) and all(k in row for k in
                ("campaignId", "packageHash", "family", "nativePath", "recordId", "field",
                 "sourceValue", "packageValue", "reason")),
                "correction entry is incomplete")
        require(isinstance(row["packageHash"], str) and SHA_RE.fullmatch(row["packageHash"]),
                "correction entry package hash is invalid")
        key = (row["campaignId"], row["packageHash"], row["family"], row["nativePath"],
               row["recordId"], row["field"])
        require(key not in result and isinstance(row["reason"], str) and row["reason"].strip(),
                "correction entries must be unique and justified")
        result[key] = row
    return result


def compare_or_correct(actual, expected, key, corrections, used, label):
    if actual == expected:
        return
    correction = corrections.get(key)
    if correction and correction["sourceValue"] == expected and correction["packageValue"] == actual:
        used.add(key)
        return
    raise CheckError(f"{label} differs from retained native bytes")


def verify_facts(native_path: str, facts: list, raw: bytes, corrections=None, used=None) -> None:
    family, layout_family = THREE[native_path]
    stride = CODEC_LAYOUTS[native_path][1]
    corrections = corrections or {}
    used = used if used is not None else set()
    complete = len(raw) // stride
    require(len(facts) == complete, f"{family} facts omit or add complete source records")
    for record_id, (fact, start) in enumerate(zip(facts, range(0, complete * stride, stride))):
        require(isinstance(fact, dict) and fact.get("id") == record_id, f"{family} fact indices are not contiguous")
        expected = native_fact(native_path, raw[start:start + stride])
        for field, value in expected.items():
            compare_or_correct(fact.get(field), value,
                               (family, native_path, record_id, field), corrections, used,
                               f"{family} field comparison")


def source_edit_bytes(original: bytes, edits: list, expected_length: int) -> bytes:
    require(len(edits) <= 100_000 and expected_length <= MAX_ENTRY_BYTES,
            "source edit count or effective payload exceeds checker limits")
    output = bytearray()
    cursor = 0
    previous_offset = -1
    previous_end = 0
    calculated_length = len(original)
    for edit in edits:
        require(isinstance(edit, dict) and set(edit) == {"offset", "before", "after"},
                "source edit has invalid fields")
        offset, before, after = edit["offset"], edit["before"], edit["after"]
        require(type(offset) is int and 0 <= offset <= len(original), "source edit offset is invalid")
        require(isinstance(before, list) and isinstance(after, list) and
                all(type(value) is int and 0 <= value <= 255 for value in before + after),
                "source edit byte arrays are invalid")
        require(before != after, "source edit does not change its declared span")
        require(offset >= previous_offset and offset >= previous_end and offset + len(before) <= len(original),
                "source edits are not sorted, disjoint, or within the original payload")
        require(original[offset:offset + len(before)] == bytes(before), "source edit preimage differs from retained bytes")
        output.extend(original[cursor:offset])
        output.extend(after)
        require(len(output) <= MAX_ENTRY_BYTES, "effective source exceeds checker limit")
        cursor = offset + len(before)
        previous_offset = offset
        previous_end = cursor
        calculated_length += len(after) - len(before)
    output.extend(original[cursor:])
    require(len(output) <= MAX_ENTRY_BYTES, "effective source exceeds checker limit")
    require(calculated_length == expected_length and len(output) == expected_length,
            "source edits do not produce the declared effective byte length")
    return bytes(output)


def source_context_campaigns(value: dict | None) -> dict[str, dict]:
    if value is None:
        return {}
    require(value.get("kind") == "realmz.classic-startup-source-contexts" and value.get("version") == 1,
            "source contexts have an unsupported kind or version")
    rows = value.get("campaigns")
    require(isinstance(rows, list), "source contexts have no campaigns array")
    result = {}
    for row in rows:
        require(isinstance(row, dict) and isinstance(row.get("campaignId"), str) and
                row["campaignId"] and row["campaignId"] not in result,
                "source context campaign identities are missing or duplicated")
        result[row["campaignId"]] = row
    return result


def _startup_layout_fact(layout: dict, role: str, raw: bytes, effective: bytes) -> None:
    family, stride, owned, _, _ = STARTUP_CONTEXT_LAYOUTS[role]
    # The first structure is 316 bytes. Sources may omit or retain extra
    # alignment/trailer bytes; their exact lengths are input identities, not
    # an independent reason to discard an otherwise supplied source.
    require(len(raw) >= stride, f"{family} lacks its complete essential structure")
    complete, tail = divmod(len(raw), stride)
    require(layout.get("family") == family and layout.get("recordBytes") == stride and
            layout.get("completeRecords") == complete and layout.get("trailingBytes") == tail and
            layout.get("ownedByteRanges") == owned,
            f"{family} descriptor differs from its exact independent framing")
    require(len(effective) == len(raw) and effective[stride:] == raw[stride:],
            f"{family} trailing bytes were changed or dropped")


def _startup_layout_pair(facts: dict, raw: bytes, effective: bytes) -> None:
    layouts = facts.get("layouts", [])
    require(isinstance(layouts, list) and len(layouts) == 2 and
            {row.get("family") for row in layouts if isinstance(row, dict)} == set(STARTUP_LAYOUT_FAMILIES),
            "startup source must claim the exact startup/security layout pair")
    by_family = {row["family"]: row for row in layouts}
    for role, (family, _, _, _, _) in STARTUP_CONTEXT_LAYOUTS.items():
        _startup_layout_fact(by_family[family], role, raw, effective)


def verify_startup_source_contexts(campaign_id: str, facts_by_path: dict, raw_by_path: dict[str, bytes],
                                  effective_by_path: dict[str, bytes], contexts: dict[str, dict],
                                  strict_mode: bool) -> dict:
    context = contexts.get(campaign_id)
    claimed_paths = []
    for path, fact in facts_by_path.items():
        if any(isinstance(layout, dict) and layout.get("family") in STARTUP_LAYOUT_FAMILIES
               for layout in fact.get("layouts", [])):
            claimed_paths.append(path)

    if strict_mode:
        require(context is not None, "strict source contexts omit this campaign")
    if context is None:
        if claimed_paths:
            require(len(claimed_paths) == 1, "startup layout pair is claimed by multiple native sources")
            path = claimed_paths[0]
            _startup_layout_pair(facts_by_path[path], raw_by_path[path], effective_by_path[path])
            disposition = "compiler-declared-exact-framing; startup role not independently established"
        else:
            disposition = "startup role and framing unavailable; source bytes retained and accounted as opaque"
        return {"startupRoleVerified": False,
                "roleEvidence": "compiler-declared; independent native filename role unavailable",
                "framingEvidence": "compiler-declared" if claimed_paths else "opaque-byte-accounting",
                "startupSourcePath": claimed_paths[0] if claimed_paths else None,
                "disposition": disposition}

    require(context.get("evidenceBasis") and isinstance(context["evidenceBasis"], str),
            "source context evidenceBasis is required")
    source = context.get("source")
    require(isinstance(source, dict) and set(source) == {"nativePath", "sha256", "byteLength"},
            "strict source context must declare one exact startup source identity")
    path = source["nativePath"]
    require(isinstance(path, str) and path in raw_by_path and
            source["sha256"] == sha(raw_by_path[path]) and
            source["byteLength"] == len(raw_by_path[path]),
            "strict startup context does not match exact retained native bytes")
    require(path in facts_by_path and claimed_paths == [path],
            "strict startup context path differs from the package layout claim")
    _startup_layout_pair(facts_by_path[path], raw_by_path[path], effective_by_path[path])
    return {"startupRoleVerified": True, "roleEvidence": context["evidenceBasis"],
            "framingEvidence": "independently-contextualized-and-byte-matched",
            "startupSourcePath": path,
            "disposition": "startup and security roles independently matched to retained source identity"}


def verify_source_retention(content: dict, assets: dict, blobs: dict, campaign_id: str = "",
                            source_contexts: dict[str, dict] | None = None) -> tuple[dict[str, bytes], dict[str, bytes], list[dict], dict, dict]:
    records = content.get("classicRecords")
    require(isinstance(records, dict), "content.classicRecords is missing")
    source_facts = records.get("sources")
    require(isinstance(source_facts, list), "classicRecords.sources is missing")
    assets_list = assets.get("assets")
    require(isinstance(assets_list, list), "assets index is invalid")
    indices = [a for a in assets_list if isinstance(a, dict) and a.get("kind") == "classic-source-index"]
    require(len(indices) == 1, "expected exactly one classic-source-index asset")
    index = indices[0]
    require(index.get("resourceType") is None and index.get("resourceId") is None,
            "source index must be inert and have no resource identity")
    receipt_bytes = blobs.get(index.get("path"))
    require(isinstance(receipt_bytes, bytes), "source index payload is missing")
    require(index.get("bytes") == len(receipt_bytes) and index.get("sha256") == sha(receipt_bytes),
            "source index payload digest or length differs")
    receipt_hash = sha(receipt_bytes)
    require(index.get("id") == "classic-source-index-" + receipt_hash and
            index.get("path") == f"assets/media/{receipt_hash}.json",
            "source index identity differs from its payload")
    receipt = read_json(receipt_bytes, "source index")
    require(receipt.get("kind") == "realmz2.classic-source-retention" and receipt.get("schemaVersion") == 1,
            "source index has an unsupported format")
    retained = receipt.get("sources")
    require(isinstance(retained, list), "source index sources are missing")
    facts_by_path = {row.get("nativePath"): row for row in source_facts if isinstance(row, dict)}
    receipt_by_path = {row.get("nativePath"): row for row in retained if isinstance(row, dict)}
    require(len(facts_by_path) == len(source_facts) and len(receipt_by_path) == len(retained),
            "source paths are missing or duplicated")
    require(set(facts_by_path) == set(receipt_by_path), "classic source facts differ from retention index paths")
    raw_by_path = {}
    effective_by_path = {}
    accounting = []
    source_assets = [a for a in assets_list if isinstance(a, dict) and a.get("kind") == "classic-source"]
    source_payload_by_hash = {}
    source_path_by_hash = {}
    for asset in source_assets:
        digest = asset.get("sha256")
        require(isinstance(digest, str) and SHA_RE.fullmatch(digest), "source asset has invalid digest")
        data = blobs.get(asset.get("path"))
        require(isinstance(data, bytes) and len(data) == asset.get("bytes") and sha(data) == digest,
                "retained source payload differs from asset index")
        require(asset.get("resourceType") is None and asset.get("resourceId") is None,
                "retained source bytes must be inert")
        shared_paths = sorted({a['path'] for a in assets_list if isinstance(a, dict)
                               and a.get('kind') not in ('classic-source', 'classic-source-index')
                               and a.get('sha256') == digest and a.get('bytes') == len(data)
                               and blobs.get(a.get('path')) == data})
        expected_path = shared_paths[0] if shared_paths else f"assets/media/{digest}.bin"
        require(asset.get("id") == "classic-source-" + digest and asset.get("path") == expected_path,
                "retained source asset identity differs from its payload")
        require(digest not in source_payload_by_hash, "retained source payload asset is duplicated")
        source_payload_by_hash[digest] = data
        source_path_by_hash[digest] = expected_path
    for path, facts in facts_by_path.items():
        require(isinstance(path, str) and safe_name(path), "source index contains an unsafe native path")
        require(set(facts) == {"nativePath", "sha256", "byteLength", "effectiveSha256",
                               "effectiveByteLength", "edits", "layouts"},
                "classic source facts have invalid fields")
        receipt_row = receipt_by_path[path]
        digest = facts.get("sha256")
        length = facts.get("byteLength")
        effective_digest = facts.get("effectiveSha256")
        effective_length = facts.get("effectiveByteLength")
        edits = facts.get("edits")
        require(isinstance(digest, str) and SHA_RE.fullmatch(digest) and type(length) is int and length >= 0 and
                isinstance(effective_digest, str) and SHA_RE.fullmatch(effective_digest) and
                type(effective_length) is int and effective_length >= 0 and isinstance(edits, list),
                "source facts contain an invalid digest or length")
        require(receipt_row.get("sha256") == digest and receipt_row.get("byteLength") == length,
                "source facts disagree with retained-source receipt")
        require(receipt_row.get("blob") == "sha256:" + digest, "source receipt blob identity differs")
        raw = source_payload_by_hash.get(digest)
        require(isinstance(raw, bytes) and len(raw) == length, "native source payload is absent or wrong length")
        require(sha(raw) == digest, "native source payload hash differs")
        require(receipt_row.get("assetPath") == source_path_by_hash[digest] and
                receipt_row.get("assetPath") in blobs and blobs[receipt_row["assetPath"]] == raw,
                "source receipt path does not resolve to exact retained bytes")
        raw_by_path[path] = raw
        if is_resource_fork_path(path):
            require(not edits, "resource-fork edits are unsupported")
        effective = source_edit_bytes(raw, edits, effective_length)
        require(len(effective) == effective_length and sha(effective) == effective_digest,
                "reconstructed effective source identity differs")
        effective_by_path[path] = effective
        layouts = facts.get("layouts")
        require(isinstance(layouts, list), "source layouts are missing")
        require(all(isinstance(x, dict) for x in layouts) and
                len({x.get("family") for x in layouts}) == len(layouts),
                "source layouts are malformed or duplicate a family")
        expected_layout = fixed_layout(path, layouts)
        claimed_layouts = layouts
        if expected_layout:
            family, stride = expected_layout
            original_count, original_tail = divmod(length, stride)
            count, tail = divmod(effective_length, stride)
            require(original_count * stride + original_tail == length and count * stride + tail == effective_length,
                    "independent record extent does not account for source bytes")
            require(len(claimed_layouts) == 1 and all(x.get("family") == family and x.get("recordBytes") == stride and
                        x.get("completeRecords") == count and x.get("trailingBytes") == tail
                        for x in claimed_layouts),
                    "compiler layout claim differs from independent family extent")
            receipt_framing = receipt_row.get("framing", {})
            require(isinstance(receipt_framing, dict), "source index framing is malformed")
            index_framing = receipt_framing.get("codecs", [])
            require(isinstance(index_framing, list), "source index codec framing is malformed")
            require(any(x.get("family") == family and x.get("framing", {}).get("recordBytes") == stride and
                            x.get("framing", {}).get("completeRecordCount") == original_count and
                            x.get("framing", {}).get("trailingBytes") == original_tail
                            for x in index_framing if isinstance(x, dict)),
                    "source index framing differs from original retained family extent")
            accounting.append({"family": family,
                               "originalCompleteRecords": original_count, "originalTrailingBytes": original_tail,
                               "effectiveCompleteRecords": count, "effectiveTrailingBytes": tail,
                               "originalByteLength": length, "effectiveByteLength": effective_length,
                               "disposition": "complete-records-plus-partial-tail",
                               "proof": "full-field-comparison" if path in THREE else "codec-framing-only",
                               "compilerLayout": "reported" if claimed_layouts else "not-reported"})
        else:
            startup_claims = [layout for layout in claimed_layouts
                              if isinstance(layout, dict) and layout.get("family") in STARTUP_LAYOUT_FAMILIES]
            require(len(startup_claims) == len(claimed_layouts),
                    "unrecognized source path claims a non-startup registered layout")
            framing = receipt_row.get("framing", {})
            if not claimed_layouts:
                require(framing.get("status") == "opaque" and framing.get("byteLength") == length,
                        "opaque source byte accounting differs")
            accounting.append({"family": "compiler-startup-layout-claim" if claimed_layouts else "opaque",
                               "originalByteLength": length,
                               "effectiveByteLength": effective_length,
                               "disposition": "compiler-declared-startup-framing" if claimed_layouts else "opaque-byte-span",
                               "proof": "framing-only" if claimed_layouts else "extent-only"})
    require(set(source_payload_by_hash) == {row.get("sha256") for row in facts_by_path.values()},
            "retained source payload inventory has orphaned or missing hashes")
    resource_facts = content["classicRecords"].get("resources")
    undecodable = content["classicRecords"].get("undecodableResourceSources")
    require(isinstance(resource_facts, list) and isinstance(undecodable, list),
            "resource fork facts or undecodable-source list is missing")
    candidates = [path for path in raw_by_path if is_resource_fork_path(path)]
    expected_resources, expected_undecodable = [], []
    for path in candidates:
        try:
            entries = parse_resource_inventory(raw_by_path[path])
        except (CheckError, struct.error, OverflowError):
            expected_undecodable.append(path)
            continue
        expected_resources.extend({"nativePath": path, **entry} for entry in entries)
    require(resource_facts == expected_resources,
            "resource exact-key inventory differs from retained source forks")
    require(undecodable == expected_undecodable,
            "undecodable resource-source disposition differs from retained source forks")
    keys = [(row["nativePath"], tuple(row["resourceTypeBytes"]), row["resourceId"])
            for row in expected_resources]
    unique_keys = set(keys)
    resource_report = {"decodedForkSources": len(candidates) - len(expected_undecodable),
                       "undecodableForkSources": len(expected_undecodable),
                       "entries": len(expected_resources), "uniqueExactKeys": len(unique_keys),
                       "duplicateExactKeys": len(keys) - len(unique_keys),
                       "proof": "exact-key-and-payload-hash-comparison"}
    startup_report = verify_startup_source_contexts(campaign_id, facts_by_path, raw_by_path,
                                                    effective_by_path, source_contexts or {},
                                                    source_contexts is not None)
    return raw_by_path, effective_by_path, accounting, resource_report, startup_report


def verify_simple_operational(content: dict, scenario: dict, raw: bytes, corrections, used) -> None:
    stride = CODEC_LAYOUTS["Data ED"][1]
    rows = content.get("simpleEncounters")
    require(isinstance(rows, list) and len(rows) == len(raw) // stride,
            "simple encounter definitions do not cover every complete source record")
    programs = {p.get("id") for p in scenario.get("programs", []) if isinstance(p, dict)}
    for rid, row in enumerate(rows):
        require(row.get("id") == rid, "simple encounter definition IDs are not contiguous")
        responses = row.get("responses")
        require(isinstance(responses, list) and len(responses) == 4,
                "simple encounter must preserve four response slots")
        native = native_fact("Data ED", raw[rid * stride:(rid + 1) * stride])
        for slot, response in enumerate(responses):
            require(response.get("id") == f"simple:{rid}:choice:{slot}", "simple response slot identity drifted")
            text = bytes(native["textSlots"][slot])
            label = text[1:1 + min(text[0], 79)].split(b"\x00")[0].decode("mac_roman").replace("\r", "\n").rstrip(" ")
            require(response.get("label") == label,
                    "simple response display differs from its bounded native C-string field")
            program_id = f"simple:{rid}:result:{native['choiceResults'][slot] - 1}"
            require(response.get("resultProgramId") == program_id,
                    "simple response result program is missing or mislinked")
        require(all(f"simple:{rid}:result:{result}" in programs for result in range(4)),
                "simple result program bodies must preserve all four native results")
        for field, expected in (("promptMessageId", native["promptMessageId"]),
                                ("maxTimes", native["maxTimes"]), ("casteSuccess", native["casteSuccess"]),
                                ("canBackOut", native["canBackOutByte"] != 0)):
            compare_or_correct(row.get(field), expected, ("simple", "Data ED", rid, field),
                corrections, used, f"simple encounter {field} comparison")


def native_program_instructions(record: bytes, slots: int, action_point: bool,
                                extra_codes: dict[int, list[int]]) -> list[dict]:
    actions = []
    for slot in range(slots):
        if action_point:
            raw = struct.unpack_from(">h", record, 8 + slot * 2)[0]
            operand = struct.unpack_from(">h", record, 24 + slot * 2)[0]
        else:
            raw = struct.unpack_from("b", record, slot)[0]
            operand = struct.unpack_from(">h", record, 32 + slot * 2)[0]
        if not raw and not operand:
            continue
        gosub = raw < 0 and raw not in (-14, -23)
        opcode = -raw if gosub and raw != -32768 else raw
        values = extra_codes.get(operand)
        if opcode == 92 and values is not None and operand + 1 in extra_codes:
            values = values + extra_codes[operand + 1]
        actions.append({"kind": "classicAction", "slot": slot, "rawOpcode": raw,
                        "opcode": opcode, "id": operand, "gosub": gosub,
                        "extraCode": values})
    return actions


def native_program_facts(raw_by_path: dict[str, bytes]) -> list[dict]:
    """Decode fixed program fields independently of the compiler's fact projection."""
    result = []
    for path in sorted(("Data DD", "Data DDD", "Data ED2", "Data ED3")):
        data = raw_by_path.get(path, b"")
        width = CODEC_LAYOUTS[path][1]
        for rid in range(len(data) // width):
            record = data[rid * width:(rid + 1) * width]
            complex_record = path == "Data ED2"
            prefix = 0 if complex_record else 8
            count = 32 if complex_record else 8
            codes = list(struct.unpack_from(">32b" if complex_record else ">8h", record, prefix))
            operand_offset = 32 if complex_record else 24
            operands = list(struct.unpack_from(f">{count}h", record, operand_offset))
            result.append({"nativePath": path, "id": rid, "prefix": list(record[:prefix]),
                           "codes": codes, "operands": operands,
                           "suffix": list(record[operand_offset + count * 2:])})
    return result


def verify_program_facts(facts: dict, raw_by_path: dict[str, bytes]) -> None:
    actual = facts.get("programs")
    require(isinstance(actual, list) and all(isinstance(row, dict) for row in actual),
            "typed program facts are missing or malformed")
    expected_programs = native_program_facts(raw_by_path)
    identities = [(row.get("nativePath"), row.get("id")) for row in actual]
    require(len(set(identities)) == len(identities), "typed program facts duplicate a native identity")
    # Family ordering reflects import/edit order. Record positions within each
    # native table remain exact and must never be compacted or reordered.
    for native_path in {row["nativePath"] for row in expected_programs}:
        require([row["id"] for row in actual if row.get("nativePath") == native_path] ==
                [row["id"] for row in expected_programs if row["nativePath"] == native_path],
                "typed program facts changed native table ordering")
    require(sorted(actual, key=lambda row: (row.get("nativePath", ""), row.get("id", -1))) == expected_programs,
            "typed program facts differ from complete native records")
    data = raw_by_path.get("Data EDCD", b"")
    expected = [{"id": rid, "values": list(struct.unpack_from(">5h", data, rid * 10))}
                for rid in range(len(data) // 10)]
    require(facts.get("extraCodes") == expected,
            "typed Extra Code facts differ from complete native records or native ordering")


def expected_native_programs(raw_by_path: dict[str, bytes]) -> dict[str, tuple[str, int, dict]]:
    """Decode native program bodies directly from retained effective bytes."""
    extra_raw = raw_by_path.get("Data EDCD", b"")
    extra_codes = {i: list(struct.unpack_from(">5h", extra_raw, i * 10))
                   for i in range(len(extra_raw) // 10)}
    result = {}
    specs = (("Data DD", 8, "trigger", "trigger", True),
             ("Data DDD", 8, "trigger", "trigger", True),
             ("Data ED3", 8, "xap", "extra-action-point", True),
             ("Data ED", 32, "simple", "simple-encounter-result", False),
             ("Data ED2", 32, "complex", "complex-encounter-result", False))
    for path, slots, prefix, owner_kind, ap in specs:
        raw = raw_by_path.get(path)
        if raw is None:
            continue
        width = CODEC_LAYOUTS[path][1]
        for rid in range(len(raw) // width):
            record = raw[rid * width:(rid + 1) * width]
            actions = native_program_instructions(record, slots, ap, extra_codes)
            if prefix == "trigger":
                program_id = f"trigger:{path}:{rid // 100}:{rid % 100}"
                body = {"id": program_id, "ownerId": f"{path}:{rid // 100}:{rid % 100}",
                        "ownerKind": owner_kind, "instructions": actions}
                result[program_id] = (path, rid, body)
            elif prefix == "xap":
                program_id = f"xap:{rid}"
                body = {"id": program_id, "ownerId": f"Data ED3:macro:{rid}",
                        "ownerKind": owner_kind, "instructions": actions}
                result[program_id] = (path, rid, body)
            else:
                for group in range(4):
                    program_id = f"{prefix}:{rid}:result:{group}"
                    selected = [{**a, "slot": a["slot"] % 8} for a in actions
                                if a["slot"] // 8 == group]
                    body = {"id": program_id, "ownerId": str(rid),
                            "ownerKind": owner_kind, "instructions": selected}
                    result[program_id] = (path, rid, body)
    return result


def verify_native_programs(scenario: dict, raw_by_path: dict[str, bytes], corrections, used) -> None:
    actual_rows = scenario.get("programs")
    require(isinstance(actual_rows, list) and all(isinstance(row, dict) for row in actual_rows),
            "scenario program inventory is missing or malformed")
    actual = {row.get("id"): row for row in actual_rows}
    require(len(actual) == len(actual_rows), "scenario program IDs are duplicated")
    expected = expected_native_programs(raw_by_path)
    prefixes = ("trigger:Data DD:", "trigger:Data DDD:", "xap:", "simple:", "complex:")
    expected_ids = set(expected)
    actual_native_ids = {program_id for program_id in actual
                         if isinstance(program_id, str) and program_id.startswith(prefixes)}
    require(actual_native_ids == expected_ids,
            "native program identities add to or omit from retained source families")
    for program_id, (path, rid, body) in expected.items():
        require(program_id in actual, f"native program body is missing: {program_id}")
        row = actual[program_id]
        require(set(row) == {"id", "ownerId", "ownerKind", "instructions"},
                f"native program fields differ from its source-backed shape: {program_id}")
        require(row.get("id") == program_id, f"native program ID differs: {program_id}")
        for field in ("ownerId", "ownerKind"):
            compare_or_correct(row.get(field), body[field],
                ("programs", path, rid, f"{program_id}.{field}"), corrections, used,
                f"native program {program_id} {field}")
        instructions = row.get("instructions")
        require(isinstance(instructions, list) and len(instructions) == len(body["instructions"]),
                f"native program instruction count differs: {program_id}")
        for index, expected_action in enumerate(body["instructions"]):
            actual_action = instructions[index]
            require(isinstance(actual_action, dict), f"native program instruction is malformed: {program_id}")
            require(set(actual_action) == set(expected_action),
                    f"native program instruction fields differ: {program_id} slot {index}")
            for field, value in expected_action.items():
                compare_or_correct(actual_action.get(field), value,
                    ("programs", path, rid,
                     f"{program_id}.instructions[{index}].{field}"), corrections, used,
                    f"native program {program_id} instruction {index} {field}")


def decode_random_level(path: str, record: bytes, level_index: int) -> dict:
    """Decode the complete signed Classic random-level layout independently."""
    level_type = "land" if path == "Data RD" else "dungeon"
    rectangles = []
    for slot in range(20):
        base = slot * 8
        rectangle = {
            "id": f"{level_type}:{level_index}:rect:{slot}",
            "top": struct.unpack_from(">h", record, base)[0],
            "left": struct.unpack_from(">h", record, base + 2)[0],
            "bottom": struct.unpack_from(">h", record, base + 4)[0],
            "right": struct.unpack_from(">h", record, base + 6)[0],
            "chanceTenThousand": struct.unpack_from(">h", record, 160 + slot * 2)[0],
            "battleRange": list(struct.unpack_from(">2h", record, 200 + slot * 4)),
            "randomDoors": list(struct.unpack_from(">3h", record, 280 + slot * 6)),
            "randomDoorPercent": list(struct.unpack_from(">3h", record, 400 + slot * 6)),
            "only": record[523 + slot] != 0,
            "option": struct.unpack_from("b", record, 543 + slot)[0],
            "soundId": struct.unpack_from(">h", record, 564 + slot * 2)[0],
            "textId": struct.unpack_from(">h", record, 604 + slot * 2)[0],
        }
        rectangles.append((rectangle, record[523 + slot]))
    return {
        "id": f"{level_type}:{level_index}",
        "levelType": level_type,
        "levelIndex": level_index,
        "dark": record[521] != 0,
        "usesLos": record[522] != 0,
        "landlookByte": struct.unpack_from("b", record, 520)[0],
        "randomRectangles": rectangles,
    }


def verify_random_level_records(world: dict, raw_by_path: dict[str, bytes], corrections, used) -> list[str]:
    maps = world.get("maps")
    require(isinstance(maps, list) and all(isinstance(row, dict) for row in maps),
            "world map inventory is missing or malformed")
    compared = []
    for path in ("Data RD", "Data RDD"):
        if path not in raw_by_path:
            continue
        data = raw_by_path[path]
        width = CODEC_LAYOUTS[path][1]
        count = len(data) // width
        expected_type = "land" if path == "Data RD" else "dungeon"
        actual_rows = [row for row in maps if row.get("levelType") == expected_type]
        by_index = {}
        for row in actual_rows:
            index = row.get("levelIndex")
            require(type(index) is int and index not in by_index,
                    f"{path} world map indices are invalid or duplicated")
            by_index[index] = row
        require(set(by_index) == set(range(count)),
                f"{path} world maps do not match every complete native level")
        for level_index in range(count):
            record = data[level_index * width:(level_index + 1) * width]
            expected = decode_random_level(path, record, level_index)
            actual = by_index[level_index]
            require(actual.get("id") == expected["id"], f"{path} world map identity differs at {level_index}")
            metadata = actual.get("metadata")
            require(isinstance(metadata, dict), f"{path} world map metadata is missing at {level_index}")
            for field, value in (("dark", expected["dark"]), ("usesLos", expected["usesLos"])):
                compare_or_correct(metadata.get(field), value,
                    ("random-levels", path, level_index, f"map.metadata.{field}"),
                    corrections, used, f"{path} level {level_index} metadata {field}")
            # Classic stores a landlook byte in both files; the current world
            # schema projects it only for land maps, leaving dungeon metadata null.
            landlook = expected["landlookByte"] if expected_type == "land" else None
            compare_or_correct(metadata.get("landlook"), landlook,
                ("random-levels", path, level_index, "map.metadata.landlook"),
                corrections, used, f"{path} level {level_index} metadata landlook")
            actual_rectangles = actual.get("randomRectangles")
            require(isinstance(actual_rectangles, list) and len(actual_rectangles) == 20,
                    f"{path} level {level_index} must retain exactly 20 native random slots")
            actual_by_id = {row.get("id"): row for row in actual_rectangles if isinstance(row, dict)}
            expected_ids = [rectangle["id"] for rectangle, _ in expected["randomRectangles"]]
            require(len(actual_by_id) == 20 and set(actual_by_id) == set(expected_ids),
                    f"{path} level {level_index} random slot identities differ")
            for slot, (rectangle, raw_only_byte) in enumerate(expected["randomRectangles"]):
                actual_rectangle = actual_by_id[rectangle["id"]]
                require(isinstance(actual_rectangle, dict) and
                        set(actual_rectangle) == set(rectangle),
                        f"{path} level {level_index} random slot {slot} fields differ")
                for field, value in rectangle.items():
                    if field == "id":
                        continue
                    compare_or_correct(actual_rectangle.get(field), value,
                        ("random-levels", path, level_index, f"randomRectangles[{slot}].{field}"),
                        corrections, used,
                        f"{path} level {level_index} random slot {slot} {field}" +
                        (f" (native only byte {raw_only_byte})" if field == "only" else ""))
            actual_order = [row.get("id") for row in actual_rectangles if isinstance(row, dict)]
            require(actual_order == expected_ids,
                    f"{path} level {level_index} random slots are not in numeric native slot order")
        compared.append("land-random-levels" if path == "Data RD" else "dungeon-random-levels")
    return compared


def verify_program_coverage(content: dict, world: dict, scenario: dict, raw_by_path: dict) -> None:
    programs = [p for p in scenario.get("programs", []) if isinstance(p, dict)]
    ids = [p.get("id") for p in programs]
    require(len(ids) == len(set(ids)), "scenario program IDs are duplicated")
    program_ids = set(ids)
    if "Data ED2" in raw_by_path:
        complex_rows = content.get("complexEncounters")
        count = len(raw_by_path["Data ED2"]) // CODEC_LAYOUTS["Data ED2"][1]
        require(isinstance(complex_rows, list) and len(complex_rows) == count and
                [r.get("id") for r in complex_rows] == list(range(count)),
                "complex encounter definitions do not cover every native record")
    for path, prefix in (("Data ED2", "complex"),):
        if path not in raw_by_path:
            continue
        width = CODEC_LAYOUTS[path][1]
        for rid in range(len(raw_by_path[path]) // width):
            for slot in range(4):
                require(f"{prefix}:{rid}:result:{slot}" in program_ids,
                        "complex encounter result program is missing")
    if "Data ED3" in raw_by_path:
        for rid in range(len(raw_by_path["Data ED3"]) // CODEC_LAYOUTS["Data ED3"][1]):
            require(f"xap:{rid}" in program_ids, "XAP program is missing")
    if "Data TD2" in raw_by_path:
        rogue = content.get("thiefEncounters")
        count = len(raw_by_path["Data TD2"]) // CODEC_LAYOUTS["Data TD2"][1]
        require(isinstance(rogue, list) and len(rogue) == count and
                [r.get("id") for r in rogue] == list(range(count)),
                "rogue encounter definitions do not cover every native record")


def verify_timed_and_shops(content: dict, world: dict, facts: dict, raw_by_path: dict, corrections, used) -> list:
    findings = []
    if "Data TD3" in raw_by_path:
        raw = raw_by_path["Data TD3"]
        rows = world.get("timedEncounters")
        stride = CODEC_LAYOUTS["Data TD3"][1]
        require(isinstance(rows, list) and len(rows) == len(raw) // stride,
                "timed encounter definitions do not cover every complete source record")
        for rid, record in enumerate(rows):
            require(record.get("id") == rid, "timed encounter IDs are not contiguous")
            words = list(struct.unpack(">20h", raw[rid * stride:(rid + 1) * stride]))
            checks = {"day": words[0], "increment": words[1], "chancePercent": words[2],
                      "classicMacroId": words[3], "requiredLevel": words[4],
                      "requiredRandomRectangle": words[5], "requiredX": words[6], "requiredY": words[7],
                      "requiredItemId": words[8], "requiredQuestId": words[9]}
            for field, expected in checks.items():
                compare_or_correct(record.get(field), expected,
                                   ("timed", "Data TD3", rid, field), corrections, used,
                                   f"timed encounter {field} comparison")
            require(record.get("programId") == f"xap:{words[3]}",
                    "timed macro identity differs from the native reference")
            location = words[10]
            normalized = record.get("locationKind")
            if location == 1:
                require(normalized == "land", "timed location kind differs from native code")
            elif location == 2:
                require(normalized == "dungeon", "timed location kind differs from native code")
            else:
                require(normalized == "any", "unknown native location code was replaced with a specific kind")
            findings.append({"type": "unknown-location-code", "family": "timed-encounters"})
    if "Data SD" in raw_by_path:
        raw = raw_by_path["Data SD"]
        facts_rows = facts.get("shops", [])
        shops = content.get("shops")
        require(isinstance(shops, list), "shop definitions are missing")
        by_id = {s.get("classicId"): s for s in shops if isinstance(s, dict)}
        require(len(by_id) == len(shops), "shop classic IDs are duplicated")
        stride = CODEC_LAYOUTS["Data SD"][1]
        require(len(facts_rows) == len(raw) // stride, "shop facts do not cover complete source records")
        require(set(by_id) == set(range(len(raw) // stride)),
                "shop definitions do not cover the native shop namespace exactly")
        for rid in range(len(raw) // stride):
            shop = by_id.get(rid)
            require(shop is not None, "native shop has no operational definition")
            row = raw[rid * stride:(rid + 1) * stride]
            ids = struct.unpack(">1000h", row[:2000])
            quantities = row[2000:3000]
            expected = []
            for category in range(5):
                start = category * 200
                for slot in range(start, start + 200):
                    item = ids[slot]
                    if item < 0:
                        break
                    if item > 0:
                        expected.append({"slot": slot, "itemId": f"classic.item.{item}", "quantity": quantities[slot]})
            stock = shop.get("stock")
            require(isinstance(stock, list), "shop stock is missing")
            for item in stock:
                require(isinstance(item, dict) and item.get("slot") in range(1000), "shop stock slot is invalid")
            compare_or_correct(stock, expected, ("shops", "Data SD", rid, "stock"), corrections, used,
                               "shop active stock")
            inflation = struct.unpack(">h", row[3000:3002])[0]
            compare_or_correct(shop.get("inflationPercent"), inflation,
                               ("shops", "Data SD", rid, "inflationPercent"), corrections, used,
                               "shop inflation")
    return findings


def verify_namespaces(content: dict, raw_by_path: dict) -> list:
    checked, findings = [], []
    for path, (container, set_id) in NAMESPACE.items():
        if path not in raw_by_path:
            continue
        count = len(raw_by_path[path]) // CODEC_LAYOUTS[path][1]
        if path == "Data BD":
            rows = content.get("battles")
        elif path == "Data MD":
            rows = content.get("monsters")
        else:
            sets = content.get("monsterSets", [])
            matches = [s for s in sets if isinstance(s, dict) and s.get("setId") == set_id]
            require(len(matches) == 1, "monster variant set is missing or ambiguous")
            rows = matches[0].get("monsters")
        require(isinstance(rows, list), f"typed {container} namespace is missing")
        ids = [r.get("classicId") for r in rows if isinstance(r, dict)]
        require(len(ids) == count and ids == list(range(count)),
                f"typed record count or IDs differ in native namespace")
        checked.append({"namespaceOrdinal": len(checked), "completeRecords": count})
    for path in raw_by_path:
        if ((path.endswith(" BD") and not path.startswith("Data Custom ")) or
                (path.endswith(" MD") and path not in NAMESPACE)):
            findings.append({"type": "typed-namespace-unmapped", "family": "battle-or-monster"})
    return checked + findings


def verify_package(path: Path, corrections: dict, package_index: int,
                   source_contexts: dict[str, dict] | None = None, application: dict | None = None,
                   application_assets: list | None = None) -> dict:
    blobs, manifest = read_archive(path)
    content = read_json(blobs.get("content.json", b""), "content")
    require(all(isinstance(content.get("classicRecords", {}).get(key), list) for key in ("races", "castes")),
            "Native Race/Caste fact arrays are required independently of operational selection")
    world = read_json(blobs.get("world.json", b""), "world")
    scenario = read_json(blobs.get("scenario.json", b""), "scenario")
    assets = read_json(blobs.get("assets/index.json", b""), "assets index")
    local_corrections = {
        key[2:]: value for key, value in corrections.items()
        if key[0] == manifest.get("campaignId") and key[1] == manifest.get("packageHash")
    }
    raw_by_path, effective_by_path, accounting, resource_report, startup_report = verify_source_retention(
        content, assets, blobs, manifest.get("campaignId", ""), source_contexts)
    used = set()
    for path_key, (field_key, _) in THREE.items():
        verify_facts(path_key, content["classicRecords"].get(field_key), effective_by_path.get(path_key, b""), local_corrections, used)
    verify_program_facts(content["classicRecords"], effective_by_path)
    verify_simple_operational(content, scenario, effective_by_path.get("Data ED", b""), local_corrections, used)
    verify_native_programs(scenario, effective_by_path, local_corrections, used)
    random_level_families = verify_random_level_records(
        world, effective_by_path, local_corrections, used)
    verify_program_coverage(content, world, scenario, effective_by_path)
    findings = verify_timed_and_shops(content, world, content["classicRecords"], effective_by_path, local_corrections, used)
    namespaces = verify_namespaces(content, effective_by_path)
    def compare_projection(actual, expected, native_path, record_id, field):
        compare_or_correct(actual, expected, ("projection", native_path, record_id, field),
                           local_corrections, used,
                           f"{native_path} #{record_id}.{field} operational projection")
    projection_report = classic_projection_checks.verify(
        content, world, effective_by_path, compare_projection, require, application)
    rule_projection_report = classic_projection_checks.verify_rule_selection(content, application, require)
    world_projection_report = classic_world_projection_checks.verify(
        content, world, effective_by_path, compare_projection, require, assets['assets'], application_assets)
    support_projection_report = classic_support_projection_checks.verify(
        content, world, scenario, manifest, effective_by_path, compare_projection, require)
    require(used == set(local_corrections), "correction receipt contains unused or unmatched entries")
    return {"packageIndex": package_index,
            "sourceFiles": len(raw_by_path), "byteAccounting": accounting,
            "sourceInventory": [{"nativePath": key, "sha256": sha(value), "byteLength": len(value)}
                                for key, value in sorted(raw_by_path.items())],
            "fullFieldComparisonFamilies": ["simple-encounters", "timed-encounters", "shop-records"],
            "fullProgramComparisonFamilies": [family for path, family in (
                ("Data DD", "land-action-points"), ("Data DDD", "dungeon-action-points"),
                ("Data ED3", "extra-action-points"), ("Data ED", "simple-encounters"),
                ("Data ED2", "complex-encounters")) if path in raw_by_path],
            "fullRandomLevelComparisonFamilies": random_level_families,
            "originalPartialSpanBytes": sum(row.get("originalTrailingBytes", 0) for row in accounting),
            "effectivePartialSpanBytes": sum(row.get("effectiveTrailingBytes", 0) for row in accounting),
            "opaqueSpanBytes": sum(row.get("originalByteLength", 0) for row in accounting
                                    if row["disposition"] == "opaque-byte-span"),
            "effectiveOpaqueSpanBytes": sum(row.get("effectiveByteLength", 0) for row in accounting
                                             if row["disposition"] == "opaque-byte-span"),
            "startupSourceContext": startup_report,
            "startupRoleVerified": startup_report["startupRoleVerified"],
            "resourceInventory": resource_report,
            "typedNamespaces": namespaces, "operationalProjectionFields": projection_report,
            "ruleProjectionFields": rule_projection_report,
            "worldProjectionFields": world_projection_report,
            "supportProjectionFields": support_projection_report, "findings": findings,
            "correctionsUsed": len(used), "passed": True}


def projection_self_test() -> list[dict]:
    tests = []
    monster = bytearray(210)
    monster[170:175] = b"\x8eA \x00B"
    description = bytes((4, 0x8e, 0, ord("B"), 13)) + bytes(251)
    projected = classic_projection_checks.monster_expected(monster, 0, {0: "é B\n"}, 0)
    projected.update(classicId=0, id="classic.monster.0")
    require(projected["name"] == "éA " and projected["description"] == "é B\n",
            "Monster C-prefix and Pascal text framing changed")
    native = {"Data MD": bytes(monster), "Data DES": description}
    content = {"monsters": [projected]}
    def compare(actual, expected, path, index, field):
        require(actual == expected, f"{path} #{index}.{field}: projection mismatch")
    classic_projection_checks.verify(content, {}, native, compare, require)
    tests.append({"case": "monster-macroman-c-prefix-and-pascal-framing", "passed": True})
    for label, altered in [("omitted-unreferenced-monster-rejected", {"monsters": []}),
                           ("changed-monster-signed-field-rejected",
                            {"monsters": [{**projected, "spellPoints": -1}]})]:
        try:
            classic_projection_checks.verify(altered, {}, native, compare, require)
        except CheckError:
            tests.append({"case": label, "passed": True})
        else:
            raise CheckError(f"{label} did not reject corruption")
    raw = bytes(340)
    facts = {"id": 0, "words": [0] * 42, "noteBytes": [0] * 256}
    world = {"playerMaps": [], "maps": []}
    content = {"classicRecords": {"playerMaps": [facts]}}
    classic_world_projection_checks.verify(content, world, {"Data MD2": raw}, compare, require)
    for label, altered in [("omitted-dormant-player-map-facts-rejected", []),
                           ("changed-player-map-signed-word-rejected", [{**facts, "words": [1] + [0] * 41}])]:
        try:
            classic_world_projection_checks.verify({"classicRecords": {"playerMaps": altered}},
                                                   world, {"Data MD2": raw}, compare, require)
        except CheckError:
            tests.append({"case": label, "passed": True})
        else:
            raise CheckError(f"{label} did not reject corruption")
    return tests


def shared_source_payload_self_test() -> list[dict]:
    raw = b'MADGsource and presentation bytes'
    digest = sha(raw)
    shared = f'assets/media/{digest}.mad'
    later = f'assets/media/{digest}.wav'
    source = {'nativePath': 'opaque-source', 'sha256': digest, 'byteLength': len(raw),
              'effectiveSha256': digest, 'effectiveByteLength': len(raw), 'edits': [], 'layouts': []}
    content = {'classicRecords': {'sources': [source], 'resources': [], 'undecodableResourceSources': []}}

    def check(source_path, receipt_path):
        receipt = {'kind': 'realmz2.classic-source-retention', 'schemaVersion': 1, 'sources': [{
            'nativePath': 'opaque-source', 'sha256': digest, 'byteLength': len(raw),
            'blob': 'sha256:' + digest, 'assetPath': receipt_path,
            'framing': {'status': 'opaque', 'byteLength': len(raw)}}]}
        encoded = json.dumps(receipt, separators=(',', ':')).encode()
        index_hash = sha(encoded)
        index_path = f'assets/media/{index_hash}.json'
        common = {'sha256': digest, 'bytes': len(raw), 'resourceType': None, 'resourceId': None}
        assets = {'assets': [
            {**common, 'kind': 'music', 'id': 'music', 'path': shared},
            {**common, 'kind': 'classic-source', 'id': 'classic-source-' + digest, 'path': source_path},
            {'kind': 'classic-source-index', 'id': 'classic-source-index-' + index_hash, 'path': index_path,
             'sha256': index_hash, 'bytes': len(encoded), 'resourceType': None, 'resourceId': None}]}
        return verify_source_retention(content, assets, {shared: raw, later: raw, index_path: encoded})

    require(check(shared, shared)[0]['opaque-source'] == raw, 'shared source payload did not retain exact bytes')
    probes = [{'case': 'source-and-media-share-exact-payload', 'passed': True}]
    for label, source_path, receipt_path in [
            ('noncanonical-shared-source-path-rejected', later, later),
            ('source-descriptor-receipt-path-mismatch-rejected', shared, later)]:
        try:
            check(source_path, receipt_path)
        except CheckError:
            probes.append({'case': label, 'passed': True})
        else:
            raise CheckError('shared source corruption accepted: ' + label)
    return probes


def run_self_test() -> dict:
    raw = {"Data ED": bytearray(426), "Data TD3": bytearray(40), "Data SD": bytearray(3002)}
    raw["Data ED"][32:34] = struct.pack(">h", -30000)  # invalid-looking signed operand remains source fact
    facts = {p: [dict(id=0, **native_fact(p, bytes(b)))] for p, b in raw.items()}
    verify_facts("Data ED", facts["Data ED"], bytes(raw["Data ED"]))
    verify_facts("Data TD3", facts["Data TD3"], bytes(raw["Data TD3"]))
    verify_facts("Data SD", facts["Data SD"], bytes(raw["Data SD"]))
    tests = []
    documents = {name: b"{}" for name in ("content.json", "world.json", "scenario.json", "assets/index.json")}
    framed = b"".join(len(name).to_bytes(8, "big") + name.encode() + len(data).to_bytes(8, "big") + data
                      for name, data in documents.items())
    identity = {"contentId": sha(framed), "compiler": {"commit": "current"}}
    identity["packageHash"] = sha(json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode())
    verify_manifest_identities(documents, identity)
    try:
        verify_manifest_identities({**documents, "world.json": b'{"changed":true}'}, identity)
    except CheckError:
        tests.append({"case": "stale-content-identity-with-current-file-inventory-rejected", "passed": True})
    try:
        verify_manifest_identities(documents, {**identity, "packageHash": "0" * 64})
    except CheckError:
        tests.append({"case": "forged-package-identity-rejected", "passed": True})
    # The checks intentionally run on in-memory structures and never mutate an archive.
    tests.append({"case": "source-invalid-reference-retained", "passed": True})
    try:
        verify_facts("Data ED", [], bytes(raw["Data ED"]))
    except CheckError:
        tests.append({"case": "deleted-defined-record", "passed": True})
    bad = json.loads(json.dumps(facts["Data ED"]))
    bad[0]["id"] = 1
    try:
        verify_facts("Data ED", bad, bytes(raw["Data ED"]))
    except CheckError:
        tests.append({"case": "index-drift", "passed": True})
    bad = json.loads(json.dumps(facts["Data ED"]))
    bad[0]["operands"][0] = 2
    try:
        verify_facts("Data ED", bad, bytes(raw["Data ED"]))
    except CheckError:
        tests.append({"case": "signed-operand-corruption", "passed": True})
    # A claimed current compiler identity never overrides independent source mismatch.
    try:
        verify_facts("Data ED", bad, bytes(raw["Data ED"]))
    except CheckError:
        tests.append({"case": "stale-content-with-current-stamp", "passed": True,
                      "claimedStamp": "current"})
    # Missing operational response program is caught by the independent coverage rule.
    simple = {"simpleEncounters": [{"id": 0, "responses": [
        {"id": f"simple:0:choice:{i}", "resultProgramId": f"simple:0:result:{i}"} for i in range(3)]}]}
    try:
        verify_simple_operational(simple, {"programs": []}, bytes(raw["Data ED"]), {}, set())
    except CheckError:
        tests.append({"case": "missing-defined-result-slot", "passed": True})

    def make_resource_fork(resource_type: bytes, entries: list[tuple[int, bytes]]) -> bytes:
        require(len(resource_type) == 4, "self-test resource type must be four bytes")
        data = bytearray()
        refs = bytearray()
        for resource_id, payload in entries:
            relative = len(data)
            data.extend(struct.pack(">I", len(payload)))
            data.extend(payload)
            refs.extend(struct.pack(">hhB", resource_id, -1, 0))
            refs.extend(relative.to_bytes(3, "big"))
            refs.extend(b"\0\0\0\0")
        type_list = struct.pack(">H4sHH", 0, resource_type, len(entries) - 1, 10) + refs
        map_length = 28 + len(type_list)
        header = struct.pack(">IIII", 16, 16 + len(data), len(data), map_length)
        map_header = bytearray(28)
        map_header[:16] = header
        name_offset = 28 + len(type_list)
        struct.pack_into(">HH", map_header, 24, 28, name_offset)
        return header + data + map_header + type_list

    fork = make_resource_fork(bytes((0, 0x7f, 0x80, 0xff)), [(7, b"a"), (7, b"bc")])
    inventory = parse_resource_inventory(fork)
    require([(row["resourceTypeBytes"], row["resourceId"], row["occurrence"], row["sha256"], row["byteLength"])
             for row in inventory] == [([0, 0x7f, 0x80, 0xff], 7, 0, sha(b"a"), 1),
                                       ([0, 0x7f, 0x80, 0xff], 7, 1, sha(b"bc"), 2)],
            "resource exact-key occurrence inventory self-test failed")
    encoded_inventory = json.dumps(inventory, ensure_ascii=True).encode("utf-8")
    require(b"\x00" not in encoded_inventory and
            json.loads(encoded_inventory)[0]["resourceTypeBytes"] == [0, 0x7f, 0x80, 0xff],
            "resource type byte JSON round-trip or NUL escaping self-test failed")
    tests.append({"case": "resource-exact-key-occurrences-and-payloads", "passed": True})
    apple_double = (struct.pack(">II16sH", 0x00051607, 0x00020000, bytes(16), 1) +
                    struct.pack(">III", 2, 38, len(fork)) + fork)
    require(parse_resource_inventory(apple_double) == inventory,
            "AppleDouble resource payload self-test failed")
    tests.append({"case": "appledouble-resource-payload", "passed": True})
    require(fixed_layout("Data ED3", []) == ("extra-action-points", 40) and
            fixed_layout("Data TD2", []) == ("rogue-encounters", 118),
            "source-backed codec family path mapping self-test failed")
    xap_records, xap_tail = divmod(41, fixed_layout("Data ED3", [])[1])
    rogue_records, rogue_tail = divmod(119, fixed_layout("Data TD2", [])[1])
    require((xap_records, xap_tail, rogue_records, rogue_tail) == (1, 1, 1, 1),
            "Data ED3/Data TD2 partial-span self-test failed")
    tests.append({"case": "ed3-td2-family-strides-and-tail", "passed": True})
    edit = {"offset": 2, "before": list(b"cd"), "after": list(b"WXYZ")}
    effective = source_edit_bytes(b"abcdef", [edit], 8)
    require(effective == b"abWXYZef", "source edit reconstruction self-test failed")
    tests.append({"case": "effective-source-edit-reconstruction", "passed": True})
    forged = {"offset": 2, "before": list(b"zz"), "after": list(b"WXYZ")}
    try:
        source_edit_bytes(b"abcdef", [forged], 8)
    except CheckError:
        tests.append({"case": "forged-source-edit-preimage-rejected", "passed": True})
    program_sources = {"Data ED": bytes(raw["Data ED"])}
    expected_programs = expected_native_programs(program_sources)
    program_rows = [body for _, _, body in expected_programs.values()]
    verify_native_programs({"programs": program_rows}, program_sources, {}, set())
    tests.append({"case": "native-encounter-result-bodies", "passed": True})
    bad_programs = json.loads(json.dumps(program_rows))
    bad_programs[0]["ownerId"] = "wrong-caller"
    try:
        verify_native_programs({"programs": bad_programs}, program_sources, {}, set())
    except CheckError:
        tests.append({"case": "native-program-caller-context-corruption", "passed": True})
    ap = bytearray(40)
    struct.pack_into(">h", ap, 8, 7)
    struct.pack_into(">h", ap, 24, 321)
    ap_sources = {"Data DD": bytes(ap)}
    ap_programs = [body for _, _, body in expected_native_programs(ap_sources).values()]
    require(len(ap_programs) == 1 and ap_programs[0]["id"] == "trigger:Data DD:0:0",
            "unplaced complete AP instruction body must remain in program accounting")
    tests.append({"case": "unplaced-ap-program-body-retained", "passed": True})
    ed3 = bytearray(40)
    struct.pack_into(">h", ed3, 8, 7)
    struct.pack_into(">h", ed3, 24, 321)
    ed3_sources = {"Data ED3": bytes(ed3)}
    ed3_programs = [body for _, _, body in expected_native_programs(ed3_sources).values()]
    require(len(ed3_programs) == 1 and ed3_programs[0]["id"] == "xap:0" and
            ed3_programs[0]["instructions"] == [{"kind": "classicAction", "slot": 0,
                "rawOpcode": 7, "opcode": 7, "id": 321, "gosub": False, "extraCode": None}],
            "ED3 extra-action-point instruction body must use the shared action-point offsets")
    verify_native_programs({"programs": ed3_programs}, ed3_sources, {}, set())
    tests.append({"case": "ed3-shared-action-point-instruction-layout", "passed": True})
    changed_operand = json.loads(json.dumps(ap_programs))
    changed_operand[0]["instructions"][0]["id"] = 322
    try:
        verify_native_programs({"programs": changed_operand}, ap_sources, {}, set())
    except CheckError:
        tests.append({"case": "native-program-operand-corruption", "passed": True})
    correction_key = ("programs", "Data DD", 0,
                      "trigger:Data DD:0:0.instructions[0].id")
    exact_program_delta = {correction_key: {"sourceValue": 321, "packageValue": 322}}
    consumed = set()
    verify_native_programs({"programs": changed_operand}, ap_sources, exact_program_delta, consumed)
    require(consumed == {correction_key}, "exact native program correction receipt was not consumed")
    wrong_program_delta = {correction_key: {"sourceValue": 321, "packageValue": 323}}
    try:
        verify_native_programs({"programs": changed_operand}, ap_sources, wrong_program_delta, set())
    except CheckError:
        tests.append({"case": "native-program-exact-correction-required", "passed": True})
    signed_ap = bytearray(ap)
    struct.pack_into(">h", signed_ap, 8, -92)
    struct.pack_into(">h", signed_ap, 24, 0)
    signed_sources = {"Data DD": bytes(signed_ap),
                      "Data EDCD": struct.pack(">5h", -30000, 2, -3, 4, -5) +
                                   struct.pack(">5h", 6, -7, 8, -9, 10)}
    signed_programs = [body for _, _, body in expected_native_programs(signed_sources).values()]
    signed_instruction = signed_programs[0]["instructions"][0]
    require(signed_instruction["rawOpcode"] == -92 and signed_instruction["opcode"] == 92 and
            signed_instruction["gosub"] and signed_instruction["extraCode"] ==
            [-30000, 2, -3, 4, -5, 6, -7, 8, -9, 10],
            "native program signed opcode or Extra Code decoding self-test failed")
    tests.append({"case": "signed-opcode-gosub-and-extra-code-rows", "passed": True})
    struct.pack_into(">h", signed_ap, 8, -32768)
    signed_sources["Data DD"] = bytes(signed_ap)
    minimum_instruction = next(iter(expected_native_programs(signed_sources).values()))[2]["instructions"][0]
    require(minimum_instruction["opcode"] == -32768 and minimum_instruction["gosub"],
            "signed-short minimum must preserve Providence's checked-negation result")
    facts = {"programs": native_program_facts(signed_sources), "extraCodes": [
        {"id": rid, "values": list(struct.unpack_from(">5h", signed_sources["Data EDCD"], rid * 10))}
        for rid in range(2)]}
    verify_program_facts(facts, signed_sources)
    tests.append({"case": "signed-short-minimum-program-facts", "passed": True})
    facts["programs"][0]["operands"][0] = -1
    try:
        verify_program_facts(facts, signed_sources)
    except CheckError:
        tests.append({"case": "typed-program-fact-signed-operand-corruption", "passed": True})
    missing_program = [p for p in program_rows if p["id"] != "simple:0:result:3"]
    try:
        verify_native_programs({"programs": missing_program}, program_sources, {}, set())
    except CheckError:
        tests.append({"case": "native-program-body-missing", "passed": True})
    require(fixed_layout("Data Custom 1 BD", []) == ("custom-landlook-metadata", 40) and
            fixed_layout("Data BD", []) == ("battle-records", 346) and
            fixed_layout("Data Custom 1 BD", []) != fixed_layout("Data BD", []),
            "custom landlook metadata framing self-test failed")
    tests.append({"case": "custom-landlook-is-not-battle-record-framing", "passed": True})
    random_source = bytearray(CODEC_LAYOUTS["Data RD"][1])
    slot = 7
    struct.pack_into(">4h", random_source, slot * 8, -4, 101, -8, 900)
    struct.pack_into(">h", random_source, 160 + slot * 2, -123)
    struct.pack_into(">2h", random_source, 200 + slot * 4, -2, 30000)
    struct.pack_into(">3h", random_source, 280 + slot * 6, -17, 0, 45)
    struct.pack_into(">3h", random_source, 400 + slot * 6, 3, -400, 700)
    random_source[520] = 0xFB  # signed landlook -5
    random_source[521] = 2    # nonzero byte normalizes to true
    random_source[522] = 0
    random_source[523 + slot] = 7  # raw only byte is distinct from normalized bool
    random_source[543 + slot] = 0xFE  # signed option -2
    struct.pack_into(">h", random_source, 564 + slot * 2, -1234)
    struct.pack_into(">h", random_source, 604 + slot * 2, -32768)
    random_expected = decode_random_level("Data RD", bytes(random_source), 0)
    random_map = {"id": "land:0", "levelType": "land", "levelIndex": 0,
                  "metadata": {"dark": True, "usesLos": False, "landlook": -5},
                  "randomRectangles": [row for row, _ in random_expected["randomRectangles"]]}
    random_world = {"maps": [random_map]}
    random_paths = {"Data RD": bytes(random_source)}
    verify_random_level_records(random_world, random_paths, {}, set())
    decoded_slot = random_map["randomRectangles"][slot]
    require(decoded_slot["top"] == -4 and decoded_slot["bottom"] == -8 and
            decoded_slot["left"] == 101 and decoded_slot["right"] == 900 and
            decoded_slot["option"] == -2 and decoded_slot["only"] is True and
            decoded_slot["battleRange"] == [-2, 30000] and
            decoded_slot["randomDoors"] == [-17, 0, 45] and
            decoded_slot["randomDoorPercent"] == [3, -400, 700] and
            decoded_slot["soundId"] == -1234 and decoded_slot["textId"] == -32768,
            "signed or unbounded random-level source fields were normalized incorrectly")
    tests.append({"case": "random-level-signed-inverted-offmap-slots", "passed": True})
    reordered_random_slots = json.loads(json.dumps(random_world))
    reordered_random_slots["maps"][0]["randomRectangles"] = list(
        reversed(reordered_random_slots["maps"][0]["randomRectangles"]))
    try:
        verify_random_level_records(reordered_random_slots, random_paths, {}, set())
    except CheckError as error:
        require("numeric native slot order" in str(error),
                "random-level order corruption was not distinguished from field-value corruption")
        tests.append({"case": "random-level-numeric-slot-order-required", "passed": True})
    missing_random_slot = json.loads(json.dumps(random_world))
    missing_random_slot["maps"][0]["randomRectangles"].pop()
    try:
        verify_random_level_records(missing_random_slot, random_paths, {}, set())
    except CheckError:
        tests.append({"case": "random-level-missing-slot-rejected", "passed": True})
    extra_random_slot = json.loads(json.dumps(random_world))
    extra_random_slot["maps"][0]["randomRectangles"].append(
        dict(extra_random_slot["maps"][0]["randomRectangles"][-1]))
    try:
        verify_random_level_records(extra_random_slot, random_paths, {}, set())
    except CheckError:
        tests.append({"case": "random-level-fabricated-slot-rejected", "passed": True})
    changed_random_field = json.loads(json.dumps(random_world))
    changed_random_field["maps"][0]["randomRectangles"][slot]["top"] = 4
    try:
        verify_random_level_records(changed_random_field, random_paths, {}, set())
    except CheckError:
        tests.append({"case": "random-level-signed-coordinate-corruption", "passed": True})
    changed_only = json.loads(json.dumps(random_world))
    changed_only["maps"][0]["randomRectangles"][slot]["only"] = False
    only_key = ("random-levels", "Data RD", 0, f"randomRectangles[{slot}].only")
    only_receipt = {only_key: {"sourceValue": True, "packageValue": False}}
    only_used = set()
    verify_random_level_records(changed_only, random_paths, only_receipt, only_used)
    require(only_used == {only_key}, "normalized random-level only correction was not consumed")
    wrong_only_receipt = {only_key: {"sourceValue": 7, "packageValue": False}}
    try:
        verify_random_level_records(changed_only, random_paths, wrong_only_receipt, set())
    except CheckError:
        tests.append({"case": "random-level-raw-only-byte-vs-normalized-bool", "passed": True})
    dungeon_source = bytearray(CODEC_LAYOUTS["Data RDD"][1])
    dungeon_source[520] = 4  # decoder retains it, world schema omits dungeon landlook
    dungeon_source[522] = 1
    dungeon_expected = decode_random_level("Data RDD", bytes(dungeon_source), 0)
    dungeon_map = {"id": "dungeon:0", "levelType": "dungeon", "levelIndex": 0,
                   "metadata": {"dark": False, "usesLos": True, "landlook": None},
                   "randomRectangles": [row for row, _ in dungeon_expected["randomRectangles"]]}
    require(dungeon_expected["landlookByte"] == 4 and
            verify_random_level_records({"maps": [dungeon_map]},
                {"Data RDD": bytes(dungeon_source)}, {}, set()) == ["dungeon-random-levels"],
            "dungeon random-level fields or normalized world metadata differ")
    tests.append({"case": "dungeon-random-level-world-projection", "passed": True})
    startup_raw = bytes(value % 256 for value in range(316)) + b"TAIL"
    startup_layouts = [
        {"family": "scenario-startup", "recordBytes": 316, "completeRecords": 1,
         "trailingBytes": 4, "ownedByteRanges": [{"start": 0, "end": 20}, {"start": 60, "end": 316}]},
        {"family": "scenario-security-startup", "recordBytes": 316, "completeRecords": 1,
         "trailingBytes": 4, "ownedByteRanges": [{"start": 0, "end": 316}]},
    ]
    _startup_layout_pair({"layouts": startup_layouts}, startup_raw, startup_raw)
    context_fact = {"nativePath": "opaque native name", "sha256": sha(startup_raw),
                    "byteLength": len(startup_raw), "layouts": startup_layouts}
    verified_context = verify_startup_source_contexts(
        "scenario-context-self-test", {"opaque native name": context_fact},
        {"opaque native name": startup_raw}, {"opaque native name": startup_raw},
        {"scenario-context-self-test": {"evidenceBasis": "self-test pinned source bytes",
                                        "source": {"nativePath": "opaque native name",
                                                   "sha256": sha(startup_raw), "byteLength": 320}}}, True)
    require(verified_context["startupRoleVerified"] is True,
            "strict source context did not verify startup role")
    tests.append({"case": "startup-layout-pair-and-explicit-source-context", "passed": True})
    context_fact_bad = dict(context_fact)
    context_fact_bad["layouts"] = [dict(startup_layouts[0]), dict(startup_layouts[1])]
    context_fact_bad["layouts"][0]["ownedByteRanges"] = [{"start": 0, "end": 316}]
    try:
        _startup_layout_pair(context_fact_bad, startup_raw, startup_raw)
    except CheckError:
        tests.append({"case": "startup-layout-owned-range-mismatch-rejected", "passed": True})
    try:
        _startup_layout_pair({"layouts": startup_layouts}, startup_raw, startup_raw[:-1])
    except CheckError:
        tests.append({"case": "startup-four-byte-tail-loss-rejected", "passed": True})
    try:
        verify_startup_source_contexts(
            "scenario-context-self-test", {"opaque native name": context_fact},
            {"opaque native name": startup_raw}, {"opaque native name": startup_raw},
            {"scenario-context-self-test": {"evidenceBasis": "self-test pinned source bytes",
                                            "source": {"nativePath": "opaque native name",
                                                       "sha256": sha(b"wrong"), "byteLength": 320}}}, True)
    except CheckError:
        tests.append({"case": "startup-context-hash-mismatch-rejected", "passed": True})
    uncontextualized = verify_startup_source_contexts(
        "scenario-context-self-test", {"opaque native name": context_fact},
        {"opaque native name": startup_raw}, {"opaque native name": startup_raw}, {}, False)
    require(uncontextualized["startupRoleVerified"] is False and
            uncontextualized["framingEvidence"] == "compiler-declared",
            "compiler framing claim was misreported as independently verified")
    tests.append({"case": "compiler-layout-is-not-semantic-startup-proof", "passed": True})
    required_rejections = {"stale-content-identity-with-current-file-inventory-rejected",
        "forged-package-identity-rejected", "deleted-defined-record", "index-drift",
        "signed-operand-corruption", "stale-content-with-current-stamp", "missing-defined-result-slot",
        "native-program-caller-context-corruption", "native-program-body-missing",
        "random-level-signed-coordinate-corruption", "startup-context-hash-mismatch-rejected"}
    require(required_rejections <= {row["case"] for row in tests} and all(t["passed"] for t in tests),
            "a required corruption probe did not reject its altered input")
    tests.extend(projection_self_test())
    tests.extend(classic_projection_checks.self_test_rule_selection(require, CheckError))
    tests.extend(classic_projection_checks.self_test_spell_banks(require, CheckError))
    tests.extend(shared_source_payload_self_test())
    return {"selfTest": True, "cases": tests, "passed": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", action="append", default=[], type=Path, help="schema-v7 .realmz2 archive (repeatable)")
    parser.add_argument("--output", type=Path, help="write sanitized JSON verification report")
    parser.add_argument("--correction-receipt", type=Path, help="explicit exact field-delta receipt; default allows no differences")
    parser.add_argument("--source-contexts", type=Path,
                        help="explicit campaign startup source identities for strict startup-role verification")
    parser.add_argument("--application-package", type=Path, help="exact composed application .realmz2 input")
    parser.add_argument("--application-sha256", help="SHA-256 of the explicit application archive")
    parser.add_argument("--self-test", action="store_true", help="run in-memory corruption probes")
    args = parser.parse_args()
    if not args.package and not args.self_test:
        parser.error("provide --package at least once, or use --self-test")
    try:
        corrections = correction_map(read_json(args.correction_receipt.read_bytes(), "correction receipt")) if args.correction_receipt else {}
    except (OSError, CheckError):
        parser.error("correction receipt could not be read or validated")
    try:
        source_contexts = source_context_campaigns(
            read_json(args.source_contexts.read_bytes(), "source contexts")) if args.source_contexts else None
    except (OSError, CheckError):
        parser.error("source contexts could not be read or validated")
    application = None
    application_assets = None
    if args.application_package or args.application_sha256:
        if not args.application_package or not args.application_sha256:
            parser.error("application package and SHA-256 must be supplied together")
        try:
            require(sha(args.application_package.read_bytes()) == args.application_sha256.lower(), "application archive hash differs")
            with zipfile.ZipFile(args.application_package) as archive:
                application = read_json(archive.read("content.json"), "application content")
                application_assets = read_json(archive.read("assets/index.json"), "application assets")['assets']
        except (OSError, zipfile.BadZipFile, CheckError):
            parser.error("application archive could not be read or validated")
    reports = []
    if args.self_test:
        reports.append(run_self_test())
    failed = False
    for package_index, path in enumerate(args.package):
        if args.output:
            protected = {path.resolve(), Path(__file__).resolve()}
            if args.correction_receipt:
                protected.add(args.correction_receipt.resolve())
            if args.source_contexts:
                protected.add(args.source_contexts.resolve())
            if args.application_package:
                protected.add(args.application_package.resolve())
            if args.output.resolve() in protected:
                parser.error("--output must not overwrite an input archive, receipt, or tool")
        package_identity = {"packagePath": str(path.resolve()),
                            "packageSha256": sha(path.read_bytes()) if path.is_file() else None}
        try:
            package_report = verify_package(path, corrections, package_index, source_contexts, application, application_assets)
            package_report.update(package_identity)
            reports.append(package_report)
        except CheckError as exc:
            failed = True
            reports.append({"packageIndex": package_index, **package_identity,
                            "passed": False, "error": str(exc)})
        except Exception as exc:
            failed = True
            reports.append({"packageIndex": package_index, **package_identity,
                            "passed": False, "error": type(exc).__name__})
    if corrections and sum(int(row.get("correctionsUsed", 0)) for row in reports) != len(corrections):
        failed = True
        for row in reports:
            if row.get("passed"):
                row["passed"] = False
                row["error"] = "correction receipt entries were not all consumed"
    verifier_paths = [Path(__file__), Path(classic_projection_checks.__file__),
                      Path(classic_world_projection_checks.__file__), Path(classic_support_projection_checks.__file__)]
    report = {"kind": "realmz.independent-classic-record-check", "version": 2,
              "inputs": {"verifiers": {path.name: sha(path.read_bytes()) for path in verifier_paths},
                         "sourceContextsSha256": sha(args.source_contexts.read_bytes()) if args.source_contexts else None,
                         "correctionReceiptSha256": sha(args.correction_receipt.read_bytes()) if args.correction_receipt else None,
                         "applicationArchiveSha256": sha(args.application_package.read_bytes()) if args.application_package else None},
              "packages": reports,
              "passed": not failed and all(x.get("passed") for x in reports)}
    encoded = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8", newline="\n")
    print(json.dumps({"packages": len(args.package), "selfTest": args.self_test, "passed": report["passed"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
