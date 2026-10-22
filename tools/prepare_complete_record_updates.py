#!/usr/bin/env python3
"""Prepare review-only schema-v7 package/save-update receipts from pinned archives.

This tool reads explicit package directories and emits metadata receipts plus a
semantic delta report. It never mutates packages, saves, or player storage.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
import zipfile
from pathlib import Path
from typing import Any

EXPECTED_CAMPAIGNS = {
    "scenario-assault-on-giant-mountain",
    "scenario-castle-in-the-clouds",
    "scenario-city-of-bywater",
    "scenario-destroy-the-necronomicon",
    "scenario-grilochs-revenge",
    "scenario-half-truth",
    "scenario-mithril-vault",
    "scenario-prelude-to-pestilence",
    "scenario-trouble-in-the-sword-lands",
    "scenario-twin-sands-of-time",
    "scenario-war-in-the-sword-lands",
    "scenario-white-dragon",
    "scenario-wrath-of-the-mind-lords",
}
SHA256 = re.compile(r"^[0-9a-f]{64}$")
DOCUMENTS = ("content.json", "world.json", "scenario.json", "assets/index.json", "manifest.json")


class ReceiptError(ValueError):
    pass


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")).encode("utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ReceiptError(message)


def validate_identity(manifest: dict, path: Path) -> str:
    package_hash = manifest.get("packageHash")
    require(isinstance(package_hash, str) and SHA256.fullmatch(package_hash) is not None,
            f"{path}: packageHash is malformed")
    unsigned = dict(manifest)
    unsigned.pop("packageHash", None)
    require(sha(canonical(unsigned)) == package_hash,
            f"{path}: packageHash does not match the manifest")
    return package_hash


def read_package(path: Path, schema_version: int | None = None) -> dict:
    require(path.is_file(), f"package does not exist: {path}")
    archive_bytes = path.read_bytes()
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            require(len(names) == len(set(names)), f"{path}: duplicate archive entries")
            for name in names:
                candidate = Path(name)
                require(not candidate.is_absolute() and ".." not in candidate.parts and "\\" not in name,
                        f"{path}: unsafe archive path {name!r}")
            require("manifest.json" in names, f"{path}: manifest.json is missing")
            manifest_bytes = archive.read("manifest.json")
            manifest = json.loads(manifest_bytes)
            require(isinstance(manifest, dict) and isinstance(manifest.get("files"), dict),
                    f"{path}: manifest files inventory is malformed")
            package_hash = validate_identity(manifest, path)
            files = manifest["files"]
            require(set(names) == {"manifest.json", *files},
                    f"{path}: ZIP entries differ from manifest file inventory")
            payloads: dict[str, bytes] = {}
            for name, record in files.items():
                require(isinstance(record, dict) and set(record) == {"bytes", "sha256"},
                        f"{path}: malformed manifest file entry {name}")
                data = archive.read(name)
                require(type(record["bytes"]) is int and record["bytes"] == len(data),
                        f"{path}: byte length mismatch for {name}")
                require(isinstance(record["sha256"], str) and SHA256.fullmatch(record["sha256"]) is not None and
                        record["sha256"] == sha(data), f"{path}: SHA-256 mismatch for {name}")
                payloads[name] = data
            require(archive.testzip() is None, f"{path}: ZIP CRC check failed")
    except (OSError, zipfile.BadZipFile, json.JSONDecodeError, KeyError) as exc:
        raise ReceiptError(f"{path}: cannot read package: {exc}") from exc
    documents = {}
    for name in DOCUMENTS:
        if name in payloads:
            try:
                value = json.loads(payloads[name])
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise ReceiptError(f"{path}: invalid JSON in {name}: {exc}") from exc
            if name == "world.json":
                if schema_version is not None:
                    require(isinstance(value, dict) and value.get("schemaVersion") == schema_version,
                            f"{path}: {name} is not schema version {schema_version}")
            else:
                documents[name] = value
    if schema_version is not None:
        for document_name in ("content.json", "scenario.json"):
            document = documents.get(document_name)
            require(isinstance(document, dict) and document.get("schemaVersion") == schema_version,
                    f"{path}: {document_name} is not schema version {schema_version}")
    campaign_id = manifest.get("campaignId")
    require(isinstance(campaign_id, str) and campaign_id, f"{path}: campaignId is missing")
    if "content.json" in payloads and "world.json" in payloads and "scenario.json" in payloads:
        content_id = manifest.get("contentId")
        if content_id is not None:
            hasher = hashlib.sha256()
            for name in ("content.json", "world.json", "scenario.json", "assets/index.json"):
                data = payloads[name]
                hasher.update(len(name).to_bytes(8, "big"))
                hasher.update(name.encode())
                hasher.update(len(data).to_bytes(8, "big"))
                hasher.update(data)
            require(hasher.hexdigest() == content_id, f"{path}: contentId does not match documents")
    return {
        "path": path,
        "archiveSha256": sha(archive_bytes),
        "archiveBytes": len(archive_bytes),
        "packageHash": package_hash,
        "campaignId": campaign_id,
        "manifest": manifest,
        "manifestBytes": manifest_bytes,
        "files": payloads,
        "documents": documents,
    }


def directory_package_paths(directory: Path) -> dict[str, Path]:
    require(directory.is_dir(), f"package directory does not exist: {directory}")
    paths = sorted(directory.glob("*.realmz2"), key=lambda path: path.name)
    require(len(paths) == 13, f"{directory}: expected exactly thirteen direct .realmz2 packages, found {len(paths)}")
    result: dict[str, Path] = {}
    for path in paths:
        try:
            with zipfile.ZipFile(path) as archive:
                manifest = json.loads(archive.read("manifest.json"))
        except (OSError, zipfile.BadZipFile, json.JSONDecodeError, KeyError) as exc:
            raise ReceiptError(f"{path}: cannot read package manifest: {exc}") from exc
        require(isinstance(manifest, dict), f"{path}: manifest is malformed")
        campaign_id = manifest.get("campaignId")
        require(isinstance(campaign_id, str) and campaign_id,
                f"{path}: campaignId is missing")
        require(campaign_id not in result, f"{directory}: duplicate campaignId {campaign_id}")
        result[campaign_id] = path
    require(set(result) == EXPECTED_CAMPAIGNS,
            f"{directory}: campaign inventory differs; missing={sorted(EXPECTED_CAMPAIGNS - result.keys())}, "
            f"extra={sorted(result.keys() - EXPECTED_CAMPAIGNS)}")
    return result


def pointer(path: str, part: str | int) -> str:
    escaped = str(part).replace("~", "~0").replace("/", "~1")
    return path + "/" + escaped


def semantic_diff(before: Any, after: Any, path: str = "") -> list[dict]:
    changes: list[dict] = []
    if isinstance(before, dict) and isinstance(after, dict):
        for key in sorted(before.keys() | after.keys()):
            child = pointer(path, key)
            if key not in before:
                changes.append({"path": child, "change": "added", "after": after[key]})
            elif key not in after:
                changes.append({"path": child, "change": "removed", "before": before[key]})
            else:
                changes.extend(semantic_diff(before[key], after[key], child))
    elif isinstance(before, list) and isinstance(after, list):
        # Identity-bearing record lists are compared by stable ID so harmless
        # compiler ordering changes do not appear as edits to every row.
        def keyed_rows(rows: list) -> dict[str, Any] | None:
            keyed: dict[str, Any] = {}
            occurrences: dict[str, int] = {}
            for row in rows:
                if not isinstance(row, dict):
                    return None
                if isinstance(row.get("id"), (str, int)):
                    identity = f"id={row['id']}"
                elif isinstance(row.get("nativePath"), str):
                    identity = f"nativePath={row['nativePath']}"
                elif isinstance(row.get("slot"), (str, int)):
                    identity = f"slot={row['slot']}"
                else:
                    return None
                occurrence = occurrences.get(identity, 0)
                occurrences[identity] = occurrence + 1
                if occurrence:
                    identity = f"{identity}#occurrence={occurrence}"
                keyed[identity] = row
            return keyed
        old, new = keyed_rows(before), keyed_rows(after)
        if old is not None and new is not None:
            for identity in sorted(old.keys() | new.keys()):
                child = pointer(path, identity)
                if identity not in old:
                    changes.append({"path": child, "change": "added", "afterSha256": sha(canonical(new[identity]))})
                elif identity not in new:
                    changes.append({"path": child, "change": "removed", "beforeSha256": sha(canonical(old[identity]))})
                else:
                    changes.extend(semantic_diff(old[identity], new[identity], child))
            return changes
        shared = min(len(before), len(after))
        for index in range(shared):
            changes.extend(semantic_diff(before[index], after[index], pointer(path, index)))
        for index in range(shared, len(before)):
            changes.append({"path": pointer(path, index), "change": "removed", "before": before[index]})
        for index in range(shared, len(after)):
            changes.append({"path": pointer(path, index), "change": "added", "after": after[index]})
    elif before != after:
        changes.append({"path": path or "/", "change": "changed", "before": before, "after": after})
    return changes


def world_map_diff(old_world: dict, new_world: dict) -> dict:
    """Compare world maps by native identity and cell position, never list order."""
    def keyed_maps(world: dict) -> dict[str, dict]:
        rows = world.get("maps", [])
        require(isinstance(rows, list), "world maps must be an array")
        result = {}
        for row in rows:
            require(isinstance(row, dict) and isinstance(row.get("id"), str), "world map lacks string id")
            require(row["id"] not in result, f"duplicate world map id {row['id']}")
            result[row["id"]] = row
        return result
    old, new = keyed_maps(old_world), keyed_maps(new_world)
    maps = []
    for map_id in sorted(old.keys() | new.keys()):
        a, b = old.get(map_id), new.get(map_id)
        if a is None or b is None:
            row = b if a is None else a
            maps.append({"mapId": map_id, "change": "added" if a is None else "removed",
                         "mapSha256": sha(canonical(row))})
            continue
        fields = []
        for field in sorted(a.keys() | b.keys()):
            if field in ("cells", "classicTileValues") or a.get(field) == b.get(field):
                continue
            before, after = a.get(field), b.get(field)
            fields.append({"field": field,
                           "beforeSha256": None if field not in a else sha(canonical(before)),
                           "afterSha256": None if field not in b else sha(canonical(after)),
                           "beforeCount": len(before) if isinstance(before, (list, dict)) else None,
                           "afterCount": len(after) if isinstance(after, (list, dict)) else None})
        ac, bc = a.get("cells", []), b.get("cells", [])
        require(isinstance(ac, list) and isinstance(bc, list), f"{map_id}: cells must be arrays")
        changed = [i for i in range(min(len(ac), len(bc))) if ac[i] != bc[i]]
        changed.extend(range(min(len(ac), len(bc)), max(len(ac), len(bc))))
        if fields or changed or len(ac) != len(bc) or a.get("classicTileValues") != b.get("classicTileValues"):
            # Runs enumerate every native cell index compactly. Hashes bind the
            # complete arrays; exact changed row contents remain in packages.
            runs = []
            for index in changed:
                if runs and index == runs[-1][1] + 1:
                    runs[-1][1] = index
                else:
                    runs.append([index, index])
            maps.append({"mapId": map_id, "changedFields": fields,
                         "cellCountBefore": len(ac), "cellCountAfter": len(bc),
                         "changedCellCount": len(changed), "changedCellIndexRuns": runs,
                         "cellsBeforeSha256": sha(canonical(ac)), "cellsAfterSha256": sha(canonical(bc)),
                         "classicTileValuesBeforeSha256": sha(canonical(a.get("classicTileValues"))),
                         "classicTileValuesAfterSha256": sha(canonical(b.get("classicTileValues")))})
    top_fields = [field for field in sorted(old_world.keys() | new_world.keys())
                  if field != "maps" and old_world.get(field) != new_world.get(field)]
    return {"beforeSha256": sha(canonical(old_world)), "afterSha256": sha(canonical(new_world)),
            "beforeMapCount": len(old), "afterMapCount": len(new), "changedMaps": maps,
            "changedTopLevelFields": [{"field": f,
                "beforeSha256": None if f not in old_world else sha(canonical(old_world[f])),
                "afterSha256": None if f not in new_world else sha(canonical(new_world[f]))}
                for f in top_fields]}


def document_semantic_diff(before: dict, after: dict) -> list[dict]:
    result = []
    before_json = {**before["files"], "manifest.json": before["manifestBytes"]}
    after_json = {**after["files"], "manifest.json": after["manifestBytes"]}
    paths = sorted(name for name in before_json.keys() | after_json.keys()
                   if name.lower().endswith(".json"))
    for name in paths:
        old_bytes = before_json.get(name)
        new_bytes = after_json.get(name)
        if name == "world.json" and old_bytes is not None and new_bytes is not None:
            if old_bytes != new_bytes:
                old_value, new_value = json.loads(old_bytes), json.loads(new_bytes)
                result.append({"document": name, "change": "keyed-world-map-diff",
                               **world_map_diff(old_value, new_value)})
            continue
        try:
            old_value = None if old_bytes is None else json.loads(old_bytes)
            new_value = None if new_bytes is None else json.loads(new_bytes)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            result.append({"document": name, "path": "/", "change": "unparseable-json",
                           "beforeSha256": None if old_bytes is None else sha(old_bytes),
                           "afterSha256": None if new_bytes is None else sha(new_bytes),
                           "reason": str(exc)})
            continue
        if old_bytes is None:
            result.append({"document": name, "path": "/", "change": "added", "after": new_value})
        elif new_bytes is None:
            result.append({"document": name, "path": "/", "change": "removed", "before": old_value})
        else:
            if name == "content.json" and isinstance(old_value, dict) and isinstance(new_value, dict):
                for key in sorted(old_value.keys() | new_value.keys()):
                    if key == "classicRecords" and key not in old_value and key in new_value:
                        value = new_value[key]
                        tables = {table: rows for table, rows in value.items() if isinstance(rows, list)} if isinstance(value, dict) else {}
                        result.append({"document": name, "path": "/classicRecords", "change": "schema-v7-fact-tables-added",
                            "subtreeSha256": sha(canonical(value)),
                            "tables": {table: {"count": len(rows), "identitySha256": sha(canonical([
                                row.get("id", row.get("nativePath", index)) if isinstance(row, dict) else index
                                for index, row in enumerate(rows)]))} for table, rows in sorted(tables.items())}})
                    elif old_value.get(key) != new_value.get(key):
                        result.extend({"document": name, **change} for change in semantic_diff(old_value.get(key), new_value.get(key), pointer("", key)))
            else:
                result.extend({"document": name, **change} for change in semantic_diff(old_value, new_value))
    return result


def file_inventory(package: dict) -> dict[str, dict]:
    return {name: {"sha256": sha(data), "bytes": len(data)}
            for name, data in sorted({**package["files"], "manifest.json": package["manifestBytes"]}.items())}


def changed_paths(before: dict, after: dict) -> list[str]:
    a, b = before["files"], after["files"]
    result = {name for name in a.keys() | b.keys() if a.get(name) != b.get(name)}
    if before["manifestBytes"] != after["manifestBytes"]:
        result.add("manifest.json")
    return sorted(result)


def file_change(package: dict, name: str) -> dict | None:
    data = package["manifestBytes"] if name == "manifest.json" else package["files"].get(name)
    return None if data is None else {"sha256": sha(data), "bytes": len(data)}


def source_index_payloads(package: dict, required: bool = True) -> dict[str, dict]:
    index = package["documents"].get("assets/index.json")
    if not isinstance(index, dict) or not isinstance(index.get("assets"), list):
        require(not required, f"{package['path']}: assets/index.json inventory is malformed")
        return {}
    result: dict[str, dict] = {}
    for asset in index["assets"]:
        if not isinstance(asset, dict) or asset.get("kind") not in ("classic-source", "classic-source-index"):
            continue
        path = asset.get("path")
        identity = asset.get("id")
        require(isinstance(identity, str) and identity not in result,
                f"{package['path']}: source asset identity is malformed or duplicated")
        payload = package["files"].get(path) if isinstance(path, str) else None
        if required:
            require(payload is not None and asset.get("bytes") == len(payload) and asset.get("sha256") == sha(payload),
                    f"{package['path']}: retained source asset identity differs from its payload")
        result[identity] = {"path": path, "payload": payload,
                            "kind": asset.get("kind"),
                            "declaredSha256": asset.get("sha256"), "declaredBytes": asset.get("bytes")}
    if required:
        require(any(asset.get("kind") == "classic-source-index" for asset in index["assets"] if isinstance(asset, dict)),
                f"{package['path']}: classic-source-index asset is missing")
    return result


def shared_source_descriptor_relocation(package: dict, descriptor: dict) -> bool:
    try:
        assets = source_index_payloads(package)
        indices = [asset for asset in assets.values() if asset['kind'] == 'classic-source-index']
        if len(indices) != 1:
            return False
        rows = [row for row in json.loads(indices[0]['payload'])['sources']
                if row.get('sha256') == descriptor['declaredSha256']]
        return bool(rows) and all(row.get('assetPath') == descriptor['path']
                                  and shared_source_relocation(package, row) for row in rows)
    except (ReceiptError, KeyError, TypeError, UnicodeDecodeError, json.JSONDecodeError):
        return False


def source_retention_blockers(before: dict, after: dict) -> list[dict]:
    old_sources = source_index_payloads(before)
    try:
        new_sources = source_index_payloads(after, required=False)
    except ReceiptError:
        new_sources = {}
    blockers = []
    for identity in sorted(old_sources.keys() | new_sources.keys()):
        old = old_sources.get(identity)
        new = new_sources.get(identity)
        if (old or new).get("kind") == "classic-source-index":
            continue
        old_payload = None if old is None else old["payload"]
        new_payload = None if new is None else new["payload"]
        if old != new and not (old is not None and new is not None
                and {key: value for key, value in old.items() if key != 'path'} ==
                {key: value for key, value in new.items() if key != 'path'}
                and shared_source_descriptor_relocation(after, new)):
            blocker = {"kind": "retained-source-or-index-bytes-changed", "identity": identity,
                       "assetKind": (old or new).get("kind"),
                       "before": None if old is None else {"path": old["path"],
                                 "sha256": None if old_payload is None else sha(old_payload),
                                 "bytes": None if old_payload is None else len(old_payload),
                                 "declaredSha256": old["declaredSha256"], "declaredBytes": old["declaredBytes"]},
                             "after": None if new is None else {"path": new["path"],
                                 "sha256": None if new_payload is None else sha(new_payload),
                                 "bytes": None if new_payload is None else len(new_payload),
                                 "declaredSha256": new["declaredSha256"], "declaredBytes": new["declaredBytes"]}}
            if blocker["assetKind"] == "classic-source-index":
                try:
                    old_index = None if old is None else json.loads(old["payload"])
                    new_index = None if new is None else json.loads(new["payload"])
                    blocker["sourceIndexDiff"] = semantic_diff(old_index, new_index)
                except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                    blocker["sourceIndexDiff"] = {"change": "unparseable-json",
                        "beforeSha256": None if old_payload is None else sha(old_payload),
                        "afterSha256": None if new_payload is None else sha(new_payload),
                        "reason": str(exc)}
            blockers.append(blocker)
    index_diagnostic = source_index_diagnostic(before, after, old_sources, new_sources)
    if index_diagnostic["blockingChanges"]:
        blockers.append({"kind": "retained-source-or-index-bytes-changed",
                         "assetKind": "classic-source-index", **index_diagnostic})
    return blockers


def shared_source_relocation(package: dict, row: dict) -> bool:
    path, digest, length = row.get('assetPath'), row.get('sha256'), row.get('byteLength')
    payload = package['files'].get(path)
    if payload is None or sha(payload) != digest or len(payload) != length:
        return False
    assets = package['documents']['assets/index.json']['assets']
    sources = [asset for asset in assets if asset.get('kind') == 'classic-source'
               and asset.get('id') == 'classic-source-' + digest
               and asset.get('sha256') == digest and asset.get('bytes') == length]
    shared = sorted({asset['path'] for asset in assets
                     if asset.get('kind') not in ('classic-source', 'classic-source-index')
                     and asset.get('sha256') == digest and asset.get('bytes') == length
                     and package['files'].get(asset.get('path')) == payload})
    return len(sources) == 1 and sources[0].get('path') == path and bool(shared) and path == shared[0]


def source_index_diagnostic(before: dict, after: dict, old_assets: dict | None = None,
                            new_assets: dict | None = None) -> dict:
    old_assets = source_index_payloads(before) if old_assets is None else old_assets
    new_assets = source_index_payloads(after, required=False) if new_assets is None else new_assets
    old_rows = [(key, value) for key, value in old_assets.items() if value.get("kind") == "classic-source-index"]
    new_rows = [(key, value) for key, value in new_assets.items() if value.get("kind") == "classic-source-index"]
    old_index = old_rows[0][1] if len(old_rows) == 1 else None
    new_index = new_rows[0][1] if len(new_rows) == 1 else None
    diag = {"classification": "missing-or-ambiguous-index" if old_index is None or new_index is None else "unchanged",
            "before": None if old_index is None else {"assetId": old_rows[0][0], "assetPath": old_index["path"],
                "sha256": sha(old_index["payload"]), "bytes": len(old_index["payload"])},
            "after": None if new_index is None else {"assetId": new_rows[0][0], "assetPath": new_index["path"],
                "sha256": sha(new_index["payload"]), "bytes": len(new_index["payload"])},
            "sourceIndexDiff": [], "sourcePayloadDifferences": [], "sourcePayloadRelocations": [],
            "sourceOrderChanged": False, "sourceOrderNormalization": None,
            "sourceOrderBefore": [], "sourceOrderAfter": [],
            "blockingChanges": []}
    if old_index is None or new_index is None:
        diag["blockingChanges"].append("index-count-or-identity")
        return diag
    try:
        old_doc, new_doc = json.loads(old_index["payload"]), json.loads(new_index["payload"])
        require(isinstance(old_doc, dict) and isinstance(new_doc, dict) and
                isinstance(old_doc.get("sources"), list) and isinstance(new_doc.get("sources"), list),
                "classic-source-index payload must contain source arrays")
        def rows_by_path(package: dict, doc: dict) -> tuple[dict, list, list]:
            counts: dict[str, int] = {}
            rows = {}
            order = []
            payloads = []
            for row in doc["sources"]:
                require(isinstance(row, dict) and isinstance(row.get("nativePath"), str),
                        f"{package['path']}: source row lacks nativePath")
                path = row["nativePath"]
                require(path not in counts, 'source-index native paths must be unique')
                occurrence = counts.get(path, 0)
                counts[path] = occurrence + 1
                key = (path, occurrence)
                rows[key] = row
                order.append(key)
                asset_path = row.get("assetPath")
                payload = package["files"].get(asset_path) if isinstance(asset_path, str) else None
                require(payload is not None and row.get('sha256') == sha(payload)
                        and row.get('byteLength') == len(payload),
                        'source-index row does not resolve to its exact declared payload')
                payloads.append({"identity": list(key), "nativePath": path, "assetPath": asset_path,
                    "blob": row.get("blob"), "declaredSha256": row.get("sha256"),
                    "declaredByteLength": row.get("byteLength"),
                    "payloadSha256": None if payload is None else sha(payload),
                    "payloadByteLength": None if payload is None else len(payload)})
            return rows, order, payloads
        old_map, old_order, old_payloads = rows_by_path(before, old_doc)
        new_map, new_order, new_payloads = rows_by_path(after, new_doc)
        row_changes = []
        for key in sorted(old_map.keys() | new_map.keys()):
            old, new = old_map.get(key), new_map.get(key)
            if old != new:
                row_changes.append({"identity": list(key), "before": old, "after": new,
                    "changedFields": sorted(set(old or {}) | set(new or {})) if old is None or new is None else
                        [name for name in sorted(old.keys() | new.keys()) if old.get(name) != new.get(name)]})
        payload_by = lambda rows: {tuple(r["identity"]): r for r in rows}
        old_payload_map, new_payload_map = payload_by(old_payloads), payload_by(new_payloads)
        payload_differences = [{"identity": list(key), "before": old_payload_map.get(key), "after": new_payload_map.get(key)}
            for key in sorted(old_payload_map.keys() | new_payload_map.keys())
            if old_payload_map.get(key) != new_payload_map.get(key)]
        payload_content_differences = [change for change in payload_differences
            if change['before'] is None or change['after'] is None or
            {key: value for key, value in change['before'].items() if key != 'assetPath'} !=
            {key: value for key, value in change['after'].items() if key != 'assetPath'}]
        relocations = [change for change in payload_differences if change not in payload_content_differences]
        framing_only = True
        for change in row_changes:
            old, new = change["before"], change["after"]
            if old is None or new is None or {k: v for k, v in old.items() if k not in ("framing", "assetPath")} != {k: v for k, v in new.items() if k not in ("framing", "assetPath")}:
                framing_only = False
        diag.update({"sourceIndexDiff": row_changes, "sourcePayloadDifferences": payload_differences,
                     "sourcePayloadRelocations": relocations,
                     "sourcePayloadInventoryCounts": {"before": len(old_payloads), "after": len(new_payloads)},
                     "sourceOrderChanged": old_order != new_order,
                     "sourceOrderNormalization": 'native-path-sort' if old_order != new_order and new_order == sorted(old_order) else None,
                     "sourceOrderBefore": [list(key) for key in old_order],
                     "sourceOrderAfter": [list(key) for key in new_order],
                     "classification": ("compiler-framing-and-payload-paths-only" if relocations else "compiler-framing-only") if framing_only and not payload_content_differences and
                         old_doc.get("schemaVersion") == new_doc.get("schemaVersion") and
                         set(old_doc.keys()) == set(new_doc.keys()) else "source-index-content-changed",
                     "documentFieldsChanged": [key for key in sorted(old_doc.keys() | new_doc.keys())
                         if key != "sources" and old_doc.get(key) != new_doc.get(key)]})
        for change in row_changes:
            old, new = change["before"], change["after"]
            if old is None or new is None or any(
                    old.get(name) != new.get(name) for name in ("nativePath", "blob", "sha256", "byteLength")):
                diag["blockingChanges"].append({"kind": "source-row-identity-or-payload", "identity": change["identity"],
                    "changedFields": change["changedFields"]})
            elif any(name not in ("framing", "assetPath") for name in change["changedFields"]):
                diag["blockingChanges"].append({"kind": "source-row-field-change", "identity": change["identity"],
                    "changedFields": change["changedFields"]})
            if old is not None and new is not None and old.get('assetPath') != new.get('assetPath') and not shared_source_relocation(after, new):
                diag['blockingChanges'].append({'kind': 'unverified-source-payload-relocation',
                                                'identity': change['identity']})
        if payload_content_differences:
            diag["blockingChanges"].append({"kind": "source-payload-inventory", "count": len(payload_content_differences)})
        if old_order != new_order and new_order != sorted(old_order):
            diag['blockingChanges'].append({'kind': 'source-index-order'})
        if diag["documentFieldsChanged"]:
            diag["blockingChanges"].append({"kind": "source-index-document-field-change",
                "fields": diag["documentFieldsChanged"]})
    except (UnicodeDecodeError, json.JSONDecodeError, ReceiptError) as exc:
        diag["classification"] = "unparseable-or-invalid-source-index"
        diag["blockingChanges"].append({"kind": "invalid-source-index", "reason": str(exc)})
    return diag


def checked_slice(data: bytes, offset: int, length: int, label: str) -> bytes:
    require(offset >= 0 and length >= 0 and offset + length <= len(data), f"malformed resource fork: {label}")
    return data[offset:offset + length]


def resource_fork_bytes(data: bytes) -> bytes:
    if len(data) < 4 or int.from_bytes(data[:4], "big") not in (0x00051600, 0x00051607):
        return data
    require(len(data) >= 26, "malformed AppleSingle/AppleDouble resource source")
    count = int.from_bytes(data[24:26], "big")
    require(26 + count * 12 <= len(data), "malformed AppleSingle/AppleDouble descriptor list")
    for index in range(count):
        row = 26 + index * 12
        entry_id = int.from_bytes(data[row:row + 4], "big")
        offset = int.from_bytes(data[row + 4:row + 8], "big")
        length = int.from_bytes(data[row + 8:row + 12], "big")
        if entry_id == 2:
            return checked_slice(data, offset, length, "AppleDouble resource entry")
    raise ReceiptError("AppleSingle/AppleDouble resource source has no resource entry")


def parse_native_resources(data: bytes, native_path: str) -> list[dict]:
    fork = resource_fork_bytes(data)
    require(len(fork) >= 32, f"{native_path}: resource fork is too short")
    data_offset = int.from_bytes(fork[0:4], "big")
    map_offset = int.from_bytes(fork[4:8], "big")
    data_length = int.from_bytes(fork[8:12], "big")
    map_length = int.from_bytes(fork[12:16], "big")
    checked_slice(fork, data_offset, data_length, "resource data area")
    checked_slice(fork, map_offset, map_length, "resource map")
    checked_slice(fork, map_offset, 28, "resource map header")
    type_list = map_offset + int.from_bytes(fork[map_offset + 24:map_offset + 26], "big")
    checked_slice(fork, type_list, 2, "resource type list")
    raw_type_count = int.from_bytes(fork[type_list:type_list + 2], "big")
    if raw_type_count == 0xFFFF:
        return []
    require(raw_type_count < 10000, f"{native_path}: unreasonable resource type count")
    checked_slice(fork, type_list + 2, (raw_type_count + 1) * 8, "resource type entries")
    occurrences: dict[tuple[str, int], int] = {}
    result = []
    for type_index in range(raw_type_count + 1):
        row = type_list + 2 + type_index * 8
        resource_type = tuple(fork[row:row + 4])
        raw_count = int.from_bytes(fork[row + 4:row + 6], "big")
        refs_relative = int.from_bytes(fork[row + 6:row + 8], "big")
        require(raw_count < 100000, f"{native_path}: unreasonable resource count")
        refs = type_list + refs_relative
        checked_slice(fork, refs, (raw_count + 1) * 12, "resource references")
        for ref_index in range(raw_count + 1):
            ref = refs + ref_index * 12
            resource_id = int.from_bytes(fork[ref:ref + 2], "big", signed=True)
            relative = int.from_bytes(fork[ref + 5:ref + 8], "big")
            length_at = data_offset + relative
            length = int.from_bytes(checked_slice(fork, length_at, 4, "resource payload length"), "big")
            payload = checked_slice(fork, length_at + 4, length, "resource payload")
            key = (resource_type, resource_id)
            occurrence = occurrences.get(key, 0)
            occurrences[key] = occurrence + 1
            result.append({"nativePath": native_path, "resourceTypeBytes": list(resource_type),
                           "resourceId": resource_id, "occurrence": occurrence,
                           "sha256": sha(payload), "byteLength": len(payload)})
    return result


def source_rows(package: dict) -> list[dict]:
    index = package["documents"].get("assets/index.json", {})
    if not isinstance(index, dict) or not isinstance(index.get("assets"), list):
        return []
    index_asset = next((row for row in index.get("assets", [])
                        if isinstance(row, dict) and row.get("kind") == "classic-source-index"), None)
    if index_asset is None:
        return []
    raw_index = package["files"].get(index_asset.get("path"))
    require(raw_index is not None, f"{package['path']}: source index payload is missing")
    value = json.loads(raw_index)
    require(isinstance(value, dict) and isinstance(value.get("sources"), list),
            f"{package['path']}: source index document is malformed")
    return value["sources"]


def is_resource_fork_path(path: str) -> bool:
    """Match the independent native checker’s resource and AppleDouble path boundary."""
    return path.endswith((".rsrc", ".rsf")) or any(
        part == ".rsrc" or part.startswith("._") for part in path.split("/"))


def resource_inventory(package: dict) -> dict:
    """Independently inventory source resource forks; retain undecodable states explicitly."""
    result, undecodable = [], []
    try:
        rows = source_rows(package)
    except (ReceiptError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        return {"resources": [], "undecodable": [{"nativePath": "<classic-source-index>", "reason": str(exc)}]}
    for row in rows:
        if not isinstance(row, dict):
            undecodable.append({"nativePath": "<classic-source-index>", "reason": "source row is not an object"})
            continue
        path = row.get("nativePath")
        asset_path = row.get("assetPath")
        if not isinstance(path, str):
            undecodable.append({"nativePath": "<classic-source-index>", "reason": "nativePath is missing"})
            continue
        if not is_resource_fork_path(path):
            continue
        payload = package["files"].get(asset_path)
        if payload is None:
            undecodable.append({"nativePath": path, "reason": "retained source payload missing"})
            continue
        try:
            result.extend(parse_native_resources(payload, path))
        except (ReceiptError, UnicodeDecodeError) as exc:
            undecodable.append({"nativePath": path, "reason": str(exc)})
    result.sort(key=lambda row: (row["nativePath"], tuple(row["resourceTypeBytes"]), row["resourceId"], row["occurrence"]))
    return {"resources": result, "undecodable": undecodable}


def resource_inventory_diff(before: dict, after: dict) -> dict:
    old_result, new_result = resource_inventory(before), resource_inventory(after)
    old, new = old_result["resources"], new_result["resources"]
    old_by_key = {(r["nativePath"], tuple(r["resourceTypeBytes"]), r["resourceId"], r["occurrence"]): r for r in old}
    new_by_key = {(r["nativePath"], tuple(r["resourceTypeBytes"]), r["resourceId"], r["occurrence"]): r for r in new}
    changes = []
    for key in sorted(old_by_key.keys() | new_by_key.keys()):
        a, b = old_by_key.get(key), new_by_key.get(key)
        if a != b:
            changes.append({"identity": list(key), "before": a, "after": b,
                            "change": "added" if a is None else "removed" if b is None else "changed"})
    old_facts = before["documents"].get("content.json", {}).get("classicRecords", {}).get("resources", [])
    new_classic = after["documents"].get("content.json", {}).get("classicRecords", {})
    require(isinstance(new_classic, dict), f"{after['path']}: v7 Classic record facts are missing")
    new_facts = new_classic.get("resources", [])
    declared_undecodable = new_classic.get("undecodableResourceSources", [])
    require(isinstance(old_facts, list) and isinstance(new_facts, list) and isinstance(declared_undecodable, list),
            f"{after['path']}: Classic resource inventory fields are malformed")
    actual_undecodable = [row["nativePath"] for row in new_result["undecodable"]]
    independent = {canonical(row): row for row in new_result["resources"]}
    declared = {canonical(row): row for row in new_facts}
    return {"beforeCount": len(old), "afterCount": len(new), "changes": changes,
            "undecodableBefore": old_result["undecodable"],
            "undecodableAfter": new_result["undecodable"],
            "declaredFactCounts": {"before": len(old_facts), "after": len(new_facts)},
            "declaredFactsMissingFromIndependentInventory": [declared[key] for key in sorted(declared.keys() - independent.keys())],
            "independentInventoryMissingFromDeclaredFacts": [independent[key] for key in sorted(independent.keys() - declared.keys())],
            "declaredUndecodableResourceSources": declared_undecodable,
            "undecodableSourceDiagnosticsMatch": set(actual_undecodable) == set(declared_undecodable)}


def asset_inventory_diff(before: dict, after: dict) -> dict:
    def keyed(package: dict) -> dict:
        index = package["documents"].get("assets/index.json", {})
        rows = index.get("assets", []) if isinstance(index, dict) else []
        result = {}
        for row in rows:
            if isinstance(row, dict):
                identity = row.get("id")
                if isinstance(identity, str):
                    require(identity not in result, f"{package['path']}: duplicate asset ID {identity}")
                    result[identity] = row
        return result
    old, new = keyed(before), keyed(after)
    changes = []
    for identity in sorted(old.keys() | new.keys()):
        a, b = old.get(identity), new.get(identity)
        if a != b:
            changes.append({"identity": identity, "before": a, "after": b,
                            "change": "added" if a is None else "removed" if b is None else "changed"})
    return {"beforeCount": len(old), "afterCount": len(new), "changes": changes}


def exact_simple_mapping(before: dict, after: dict, campaign_id: str, blockers: list) -> dict[str, list[int]]:
    old_rows = before["documents"].get("content.json", {}).get("simpleEncounters", [])
    new_rows = after["documents"].get("content.json", {}).get("simpleEncounters", [])
    old_by_id = {row.get("id"): row for row in old_rows if isinstance(row, dict)}
    new_by_id = {row.get("id"): row for row in new_rows if isinstance(row, dict)}
    require(len(old_by_id) == len(old_rows) and len(new_by_id) == len(new_rows),
            f"{campaign_id}: duplicate or malformed Simple Encounter identities")
    mapping = {}
    for encounter_id in sorted(old_by_id):
        old_responses = old_by_id[encounter_id].get("responses")
        new_responses = new_by_id.get(encounter_id, {}).get("responses")
        if not isinstance(old_responses, list) or not isinstance(new_responses, list):
            blockers.append({"kind": "simple-response-map-unavailable", "encounterId": encounter_id,
                             "reason": "responses missing"})
            continue
        if len(new_responses) != 4:
            blockers.append({"kind": "simple-v7-response-order-invalid", "encounterId": encounter_id,
                             "reason": "v7 candidate must contain exactly four native-order choice slots"})
            continue
        candidate_by_response_id: dict[str, dict] = {}
        malformed = False
        for response in new_responses:
            match = re.fullmatch(rf"simple:{encounter_id}:choice:(\d+)", str(response.get("id", ""))) if isinstance(response, dict) else None
            if match is None:
                malformed = True
                break
            response_id = response["id"]
            if response_id in candidate_by_response_id:
                malformed = True
                break
            candidate_by_response_id[response_id] = response
        if not malformed and {int(re.fullmatch(rf"simple:{encounter_id}:choice:(\d+)", rid).group(1))
                              for rid in candidate_by_response_id} != {0, 1, 2, 3}:
            malformed = True
        slots = []
        old_seen = set()
        for response in old_responses:
            match = re.fullmatch(rf"simple:{encounter_id}:choice:(\d+)", str(response.get("id", ""))) if isinstance(response, dict) else None
            if match is None:
                malformed = True
                break
            slot = int(match.group(1))
            response_id = response["id"]
            target = candidate_by_response_id.get(response_id)
            result_id = response.get("resultProgramId") if isinstance(response, dict) else None
            if (slot in old_seen or target is None or
                    not isinstance(result_id, str) or
                    re.fullmatch(rf"simple:{encounter_id}:result:[0-3]", result_id) is None or
                    result_id != target.get("resultProgramId")):
                malformed = True
                break
            old_seen.add(slot)
            slots.append(slot)
        if malformed:
            blockers.append({"kind": "simple-response-map-ambiguous-or-changed", "encounterId": encounter_id,
                             "beforeResponses": old_responses, "afterResponses": new_responses})
        else:
            mapping[str(encounter_id)] = slots
    return mapping


def simple_label_deltas(before: dict, after: dict) -> list[dict]:
    old_rows = before["documents"].get("content.json", {}).get("simpleEncounters", [])
    new_rows = after["documents"].get("content.json", {}).get("simpleEncounters", [])
    old_by_id = {row.get("id"): row for row in old_rows if isinstance(row, dict)}
    new_by_id = {row.get("id"): row for row in new_rows if isinstance(row, dict)}
    deltas = []
    for encounter_id in sorted(old_by_id.keys() & new_by_id.keys()):
        def responses(row: dict) -> tuple[dict[str, dict], dict[str, int]]:
            values = [(response.get("id"), response) for response in row.get("responses", [])
                      if isinstance(response, dict) and isinstance(response.get("id"), str)]
            return ({identity: response for identity, response in values},
                    {identity: index for index, (identity, _) in enumerate(values)})
        old_responses, old_positions = responses(old_by_id[encounter_id])
        new_responses, new_positions = responses(new_by_id[encounter_id])
        for response_id in sorted(old_responses.keys() | new_responses.keys()):
            old_label = None if response_id not in old_responses else old_responses[response_id].get("label")
            new_label = None if response_id not in new_responses else new_responses[response_id].get("label")
            if old_label != new_label:
                match = re.fullmatch(rf"simple:{encounter_id}:choice:(\d+)", response_id)
                deltas.append({"encounterId": encounter_id, "responseId": response_id,
                    "nativeSlot": None if match is None else int(match.group(1)),
                    "beforePosition": old_positions.get(response_id),
                    "afterPosition": new_positions.get(response_id),
                    "before": old_label, "after": new_label})
    return deltas


def exact_shop_mapping(before: dict, after: dict, campaign_id: str, blockers: list) -> dict[str, list[int | None]]:
    old_rows = before["documents"].get("content.json", {}).get("shops", [])
    new_rows = after["documents"].get("content.json", {}).get("shops", [])
    old_by_id = {row.get("classicId"): row for row in old_rows if isinstance(row, dict)}
    new_by_id = {row.get("classicId"): row for row in new_rows if isinstance(row, dict)}
    require(len(old_by_id) == len(old_rows) and len(new_by_id) == len(new_rows),
            f"{campaign_id}: duplicate or malformed shop identities")
    mapping: dict[str, list[int | None]] = {}
    for shop_id in sorted(old_by_id):
        old_stock = old_by_id[shop_id].get("stock")
        new_stock = new_by_id.get(shop_id, {}).get("stock")
        if not isinstance(old_stock, list) or not isinstance(new_stock, list):
            blockers.append({"kind": "shop-index-map-unavailable", "shopClassicId": shop_id,
                             "reason": "stock missing"})
            continue
        indexes: list[int | None] = []
        failed = False
        claimed_targets: set[int] = set()
        for old_index, row in enumerate(old_stock):
            if not isinstance(row, dict):
                failed = True
                indexes.append(None)
                continue
            identity = (row.get("slot"), row.get("itemId"), row.get("quantity"))
            candidates = [index for index, candidate in enumerate(new_stock)
                          if isinstance(candidate, dict) and (candidate.get("slot"), candidate.get("itemId"), candidate.get("quantity")) == identity]
            if len(candidates) == 1 and candidates[0] not in claimed_targets:
                indexes.append(candidates[0])
                claimed_targets.add(candidates[0])
            else:
                indexes.append(None)
                failed = True
        if failed:
            blockers.append({"kind": "shop-index-unmapped", "shopClassicId": shop_id,
                             "unmappedOldCompactIndexes": [i for i, value in enumerate(indexes) if value is None]})
        mapping[str(shop_id)] = indexes
    return mapping


def timer_ids(package: dict, campaign_id: str) -> list[int]:
    rows = package["documents"].get("content.json", {}).get("timedEncounters", [])
    require(isinstance(rows, list), f"{campaign_id}: timed encounter list is malformed")
    result = []
    for row in rows:
        require(isinstance(row, dict) and type(row.get("id")) is int,
                f"{campaign_id}: timed encounter has invalid native ID")
        result.append(row["id"])
    require(len(result) == len(set(result)), f"{campaign_id}: duplicate timed encounter native ID")
    return result


_RANDOM_REGION_ID = re.compile(r"^(land|dungeon):(\d+):(?:(randlevel):)?rect:(\d+)$")


def parse_random_region_id(value: Any) -> tuple[str, int] | None:
    if not isinstance(value, str):
        return None
    match = _RANDOM_REGION_ID.fullmatch(value)
    if match is None:
        return None
    slot = int(match.group(4))
    if slot < 0 or slot > 19:
        return None
    return (f"{match.group(1)}:{match.group(2)}", slot)


def random_region_mapping(before: dict, after: dict) -> dict:
    """Map only exact native region IDs and conservatively gate pending-region compatibility."""
    old_world = json.loads(before["files"]["world.json"])
    new_world = json.loads(after["files"]["world.json"])
    def maps_by_id(world: dict) -> dict[str, dict]:
        rows = world.get("maps", [])
        require(isinstance(rows, list), "world maps must be an array")
        result = {}
        for row in rows:
            require(isinstance(row, dict) and isinstance(row.get("id"), str), "world map requires string ID")
            require(row["id"] not in result, f"duplicate world map ID {row['id']}")
            result[row["id"]] = row
        return result
    old_maps, new_maps = maps_by_id(old_world), maps_by_id(new_world)
    per_map: dict[str, dict] = {}
    compatible: dict[str, bool] = {}
    mapping_rows = []
    for map_id in sorted(old_maps.keys() | new_maps.keys()):
        old_map, new_map = old_maps.get(map_id), new_maps.get(map_id)
        if old_map is None or new_map is None:
            compatible[map_id] = False
            per_map[map_id] = {"mapId": map_id, "randomPendingCompatibleByMap": False,
                               "reason": "map-missing-on-one-side"}
            continue

        def definitions(map_record: dict, side: str) -> tuple[dict[int, dict], list, list]:
            rows = map_record.get("randomRectangles", [])
            require(isinstance(rows, list), f"{map_id}: randomRectangles must be an array")
            by_slot: dict[int, dict] = {}
            order, invalid = [], []
            for physical_index, row in enumerate(rows):
                if not isinstance(row, dict):
                    invalid.append({"physicalIndex": physical_index, "reason": "record-not-object"})
                    continue
                raw_id = row.get("id")
                parsed = parse_random_region_id(raw_id)
                # Legacy v6 may carry synthetic rows beyond the native 20-slot range.
                legacy_match = _RANDOM_REGION_ID.fullmatch(raw_id) if isinstance(raw_id, str) else None
                if side == "old" and legacy_match is not None and int(legacy_match.group(4)) > 19:
                    invalid.append({"physicalIndex": physical_index, "id": raw_id,
                                    "reason": "old-synthetic-out-of-range", "mappedTo": None})
                    mapping_rows.append({"mapId": map_id, "oldId": raw_id,
                                         "oldSlot": int(legacy_match.group(4)), "newId": None,
                                         "newSlot": None, "reason": "old-synthetic-out-of-range"})
                    continue
                if parsed is None or parsed[0] != map_id:
                    invalid.append({"physicalIndex": physical_index, "id": raw_id,
                                    "reason": "unrecognized-or-map-mismatched-id"})
                    continue
                slot = parsed[1]
                if slot in by_slot:
                    invalid.append({"physicalIndex": physical_index, "id": raw_id,
                                    "reason": "duplicate-native-slot", "slot": slot})
                    continue
                by_slot[slot] = row
                order.append(slot)
            return by_slot, order, invalid

        old_defs, old_order, old_invalid = definitions(old_map, "old")
        new_defs, new_order, new_invalid = definitions(new_map, "new")
        old_slots, new_slots = set(old_defs), set(new_defs)
        added, removed = sorted(new_slots - old_slots), sorted(old_slots - new_slots)
        geometry_changes = []
        for slot in sorted(old_slots & new_slots):
            old_data = {k: v for k, v in old_defs[slot].items() if k != "id"}
            new_data = {k: v for k, v in new_defs[slot].items() if k != "id"}
            if old_data != new_data:
                keys = sorted(old_data.keys() | new_data.keys())
                geometry_changes.append({"slot": slot, "oldId": old_defs[slot]["id"],
                    "newId": new_defs[slot]["id"],
                    "changedFields": [key for key in keys if old_data.get(key) != new_data.get(key)],
                    "beforeSha256": sha(canonical(old_data)), "afterSha256": sha(canonical(new_data))})
        for slot in sorted(old_slots):
            old_id = old_defs[slot]["id"]
            new_id = new_defs.get(slot, {}).get("id")
            mapping_rows.append({"mapId": map_id, "oldId": old_id, "oldSlot": slot,
                                 "newId": new_id, "newSlot": slot if new_id is not None else None,
                                 "reason": "exact-native-map-slot" if new_id is not None else "candidate-slot-missing"})

        def cell_memberships(map_record: dict, available_slots: set[int]) -> tuple[list[list[tuple[str, int] | None]], list[dict]]:
            cells = map_record.get("cells", [])
            require(isinstance(cells, list), f"{map_id}: cells must be an array")
            memberships, invalid_refs = [], []
            for cell_index, cell in enumerate(cells):
                found = []
                def visit(value: Any) -> None:
                    if isinstance(value, str) and (":rect:" in value or ":randlevel:" in value):
                        parsed = parse_random_region_id(value)
                        if parsed is None or parsed[0] != map_id or parsed[1] not in available_slots:
                            invalid_refs.append({"cellIndex": cell_index, "id": value,
                                                 "reason": "unrecognized-or-map-mismatched-reference"})
                            found.append(None)
                        else:
                            found.append(parsed)
                    elif isinstance(value, list):
                        for entry in value:
                            visit(entry)
                    elif isinstance(value, dict):
                        for entry in value.values():
                            visit(entry)
                visit(cell)
                memberships.append(found)
            return memberships, invalid_refs
        old_memberships, bad_old_refs = cell_memberships(old_map, old_slots)
        new_memberships, bad_new_refs = cell_memberships(new_map, new_slots)
        mapped_memberships = []
        for refs in old_memberships:
            converted = []
            for ref in refs:
                if ref is None or ref[1] not in new_defs:
                    converted.append(None)
                else:
                    converted.append(ref)
            mapped_memberships.append(converted)
        membership_equal = mapped_memberships == new_memberships and len(old_memberships) == len(new_memberships)
        order_equal = old_order == new_order
        geometry_equal = not geometry_changes
        compatible[map_id] = (not old_invalid and not new_invalid and not bad_old_refs and not bad_new_refs and
                              not added and not removed and membership_equal and order_equal and geometry_equal)
        per_map[map_id] = {"mapId": map_id,
            "randomPendingCompatibleByMap": compatible[map_id],
            "nativeSlotOrderBefore": old_order, "nativeSlotOrderAfter": new_order,
            "newNativeSlots": [{"slot": slot, "id": new_defs[slot]["id"],
                                "geometrySha256": sha(canonical({k: v for k, v in new_defs[slot].items() if k != "id"}))}
                               for slot in added],
            "removedNativeSlots": [{"slot": slot, "id": old_defs[slot]["id"],
                                    "geometrySha256": sha(canonical({k: v for k, v in old_defs[slot].items() if k != "id"}))}
                                   for slot in removed],
            "geometryChangedNativeSlots": geometry_changes,
            "oldInvalidDefinitions": old_invalid, "newInvalidDefinitions": new_invalid,
            "oldInvalidReferences": bad_old_refs, "newInvalidReferences": bad_new_refs,
            "membershipMatchesEveryNativeCell": membership_equal,
            "geometryAndOrderEquivalent": geometry_equal and order_equal}
    return {"oldToNew": mapping_rows, "byMap": per_map,
            "randomPendingCompatibleByMap": compatible,
            "allMapsCompatible": bool(compatible) and all(compatible.values())}


def state_revision(before: dict, after: dict, campaign_id: str) -> tuple[dict, dict]:
    """Map recorded typed positions without inferring missing historical native data."""
    mapping_blockers = []
    timer_blockers = []
    simple = exact_simple_mapping(before, after, campaign_id, mapping_blockers)
    random_regions = random_region_mapping(before, after)
    shops = exact_shop_mapping(before, after, campaign_id, mapping_blockers)
    old_timers = timer_ids(before, campaign_id)
    new_timers = timer_ids(after, campaign_id)
    new_positions = {native_id: index for index, native_id in enumerate(new_timers)}
    timer_positions = [0]
    for old_position, native_id in enumerate(old_timers):
        if native_id not in new_positions:
            timer_blockers.append({"kind": "timer-position-unmapped", "nativeId": native_id,
                                   "beforePosition": old_position, "afterTimerIds": new_timers})
            timer_positions.append(None)
        else:
            timer_positions.append(new_positions[native_id] + 1)
    revision = {
        "packageHash": before["packageHash"],
        "archiveSha256": before["archiveSha256"],
        "bytes": before["archiveBytes"],
        "files": file_inventory(before),
        "changedPaths": changed_paths(before, after),
        "simpleSlots": simple,
        "shopIndexes": shops,
        "timerIds": old_timers,
        "timerPositions": timer_positions,
        "randomRegionIds": {row["oldId"]: row["newId"] for row in random_regions["oldToNew"]},
        "randomPendingCompatibleByMap": random_regions["randomPendingCompatibleByMap"],
    }
    return revision, {"simpleSlotMapping": simple, "randomRegionIds": random_regions,
                      "mappingBlockers": mapping_blockers,
                      "timerPositionBlockers": timer_blockers}


def revision_receipt(before: dict, after: dict, campaign_id: str) -> tuple[dict, dict]:
    revision, mappings = state_revision(before, after, campaign_id)
    resources = resource_inventory_diff(before, after)
    report = {
        "campaignId": campaign_id,
        "before": {"file": before["path"].name, "packageHash": before["packageHash"], "archiveSha256": before["archiveSha256"]},
        "after": {"file": after["path"].name, "packageHash": after["packageHash"], "archiveSha256": after["archiveSha256"]},
        "changedPaths": revision["changedPaths"],
        "fileChanges": [{"path": name,
                         "before": file_change(before, name),
                         "after": file_change(after, name)}
                        for name in revision["changedPaths"]],
        "semanticDiff": document_semantic_diff(before, after),
        "semanticDiffCoverage": {"assets/index.json": "asset rows keyed by ID; source index rows keyed by nativePath",
                                 "world.json": "maps keyed by ID, cells keyed by native index and listed as changed-index runs, map fields and region-bearing fields keyed by name",
                                 "other JSON documents": "identity-bearing record arrays keyed by ID; scalar and nested fields retained"},
        "resourceInventoryDiff": resources,
        "assetInventoryDiff": asset_inventory_diff(before, after),
        "sourceRetentionBlockers": source_retention_blockers(before, after),
        "sourceIndexDiagnostics": source_index_diagnostic(before, after),
        "simpleLabelDeltas": simple_label_deltas(before, after),
        **mappings,
        "resourceInventoryBlockers": ([{"kind": "declared-resource-inventory-does-not-match-retained-forks"}]
            if resources["declaredFactsMissingFromIndependentInventory"] or
               resources["independentInventoryMissingFromDeclaredFacts"] or
               not resources["undecodableSourceDiagnosticsMatch"] else []),
    }
    return revision, report


def load_additional_manifests(path: Path | None, expected: set[str]) -> dict[str, list[dict]]:
    if path is None:
        return {campaign: [] for campaign in expected}
    value = json.loads(path.read_bytes())
    require(isinstance(value, list), "additional-before manifest must be a JSON array")
    result = {campaign: [] for campaign in expected}
    seen = set()
    for row in value:
        require(isinstance(row, dict) and set(row) == {"campaignId", "file", "packageHash", "archiveSha256"},
                "additional-before entries require exactly campaignId, file, packageHash, and archiveSha256")
        campaign_id = row["campaignId"]
        require(campaign_id in expected, f"additional-before entry has unknown campaignId {campaign_id}")
        pinned_file = Path(row["file"])
        if not pinned_file.is_absolute():
            pinned_file = path.parent / pinned_file
        package = read_package(pinned_file.resolve())
        require(package["campaignId"] == campaign_id, f"{pinned_file}: campaignId differs from explicit pin")
        require(package["packageHash"] == row["packageHash"] and package["archiveSha256"] == row["archiveSha256"],
                f"{pinned_file}: archive or package hash differs from explicit pin")
        for document_name in ("content.json", "world.json", "scenario.json"):
            require(package["documents"].get(document_name, {}).get("schemaVersion") == 6,
                    f"{pinned_file}: additional historical package must be schema v6")
        identity = (campaign_id, package["packageHash"])
        require(identity not in seen, f"duplicate additional-before pin {identity}")
        seen.add(identity)
        result[campaign_id].append(package)
    return result


def prepare(before_dir: Path, after_dir: Path, application_package: Path, output: Path,
            additional_before_manifests: Path | None = None) -> dict:
    require(not output.exists(), f"output must be fresh and absent: {output}")
    before = directory_package_paths(before_dir)
    after = directory_package_paths(after_dir)
    require(set(before) == set(after), "before and after campaign inventories differ")
    app = read_package(application_package)
    require(app["campaignId"] == "realmz-classic-application-library",
            "application package is not the Realmz Classic application library")
    application_hash = app["packageHash"]
    del app
    additional = load_additional_manifests(additional_before_manifests, set(before))
    receipt_campaigns = []
    reports = []
    for campaign_id in sorted(before):
        old = read_package(before[campaign_id], 6)
        new = read_package(after[campaign_id], 7)
        require(new["campaignId"] == old["campaignId"] == campaign_id,
                f"{campaign_id}: package campaign identity changed")
        revisions = []
        campaign_reports = []
        for previous in [old, *additional[campaign_id]]:
            revision, report = revision_receipt(previous, new, campaign_id)
            revisions.append(revision)
            campaign_reports.append(report)
        receipt_campaigns.append({
            "campaignId": campaign_id,
            "file": new["path"].name,
            "packageHash": new["packageHash"],
            "archiveSha256": new["archiveSha256"],
            "bytes": new["archiveBytes"],
            "files": file_inventory(new),
            "previousRevisions": revisions,
        })
        reports.extend(campaign_reports)
        del old, new
    blockers = [{"campaignId": report["campaignId"], "beforePackageHash": report["before"]["packageHash"], **blocker}
                for report in reports for blocker in
                [*report["sourceRetentionBlockers"], *report["mappingBlockers"],
                 *report["timerPositionBlockers"], *report["resourceInventoryBlockers"]]]
    receipt = {"kind": "realmz-rebuilt.complete-records", "formatVersion": 1,
               "applicationPackageHash": application_hash, "campaigns": receipt_campaigns}
    report = {"kind": "realmz-rebuilt.v7-update-generation-report", "formatVersion": 1,
              "applicationPackageHash": application_hash,
              "status": "blocked" if blockers else "review-required",
              "blockers": blockers, "campaigns": reports}
    output.mkdir(parents=True, exist_ok=False)
    (output / "receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    (output / "generation-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return {"campaigns": len(receipt_campaigns), "revisions": sum(len(c["previousRevisions"]) for c in receipt_campaigns),
            "blockers": len(blockers), "output": str(output)}


def self_test_shared_sources() -> None:
    raw = b'MADGretained source and music'
    digest = sha(raw)
    shared = f'assets/media/{digest}.mad'
    source_only = f'assets/media/{digest}.bin'

    def package(path, include_media=True, descriptor_path=None):
        row = {'nativePath': 'Custom 2 Music', 'assetPath': path, 'sha256': digest,
               'byteLength': len(raw), 'blob': 'sha256:' + digest, 'framing': {'status': 'opaque'}}
        index = canonical({'sources': [row]})
        assets = [{'id': 'source-index', 'kind': 'classic-source-index', 'path': 'index.json',
                   'sha256': sha(index), 'bytes': len(index)},
                  {'id': 'classic-source-' + digest, 'kind': 'classic-source',
                   'path': descriptor_path or path, 'sha256': digest, 'bytes': len(raw)}]
        if include_media:
            assets.append({'id': 'music', 'kind': 'music', 'path': shared, 'sha256': digest, 'bytes': len(raw)})
        return {'path': Path('shared-source.realmz2'), 'documents': {'assets/index.json': {'assets': assets}},
                'files': {source_only: raw, shared: raw, path: raw, 'index.json': index}}

    before, after = package(source_only), package(shared)
    diagnostic = source_index_diagnostic(before, after)
    require(not source_retention_blockers(before, after)
            and diagnostic['classification'] == 'compiler-framing-and-payload-paths-only'
            and len(diagnostic['sourcePayloadRelocations']) == 1,
            'source relocation must share the exact declared operational payload')
    for invalid in [package('assets/media/not-a-content-address.mad'),
                    package(shared, include_media=False), package(shared, descriptor_path=source_only),
                    package(source_only, descriptor_path=shared)]:
        require(source_retention_blockers(before, invalid),
                'source relocation without matching source and operational descriptors must block')
    altered = {**after, 'files': {**after['files'], shared: b'x' * len(raw)}}
    require(source_retention_blockers(before, altered), 'changed relocated source bytes must block')

    def ordered(names):
        value = package(source_only)
        index = json.loads(value['files']['index.json'])
        index['sources'] = [{**index['sources'][0], 'nativePath': name} for name in names]
        encoded = canonical(index)
        value['files']['index.json'] = encoded
        value['documents']['assets/index.json']['assets'][0].update(sha256=sha(encoded), bytes=len(encoded))
        return value

    unsorted, canonical_order = ordered(['Source B', 'Source A']), ordered(['Source A', 'Source B'])
    require(not source_retention_blockers(unsorted, canonical_order) and
            source_index_diagnostic(unsorted, canonical_order)['sourceOrderNormalization'] == 'native-path-sort',
            'exact native-path canonicalization must be explicit without changing source identities')
    require(source_retention_blockers(canonical_order, unsorted), 'unexplained source order changes must block')


def self_test() -> dict:
    before = {"simpleEncounters": [{"id": 4, "responses": [
        {"id": "simple:4:choice:2", "label": "Two", "resultProgramId": "simple:4:result:1"},
        {"id": "simple:4:choice:0", "label": "Zero", "resultProgramId": "simple:4:result:0"}]}],
        "shops": [{"classicId": 8, "stock": [
            {"slot": 40, "itemId": "classic.item.5", "quantity": 2},
            {"slot": 41, "itemId": "classic.item.6", "quantity": 1}]}]}
    after = {"simpleEncounters": [{"id": 4, "responses": [
        {"id": "simple:4:choice:0", "label": "Zero corrected", "resultProgramId": "simple:4:result:0"},
        {"id": "simple:4:choice:1", "label": "One", "resultProgramId": "simple:4:result:1"},
        {"id": "simple:4:choice:2", "label": "Two", "resultProgramId": "simple:4:result:1"},
        {"id": "simple:4:choice:3", "label": "Three", "resultProgramId": "simple:4:result:3"}]}],
        "shops": [{"classicId": 8, "stock": [
            {"slot": 41, "itemId": "classic.item.6", "quantity": 1},
            {"slot": 40, "itemId": "classic.item.5", "quantity": 2}]}]}
    source_raw = b"raw native record"
    source_asset = {"nativePath": "Data DD", "assetPath": "source.bin",
                    "blob": "sha256:" + sha(source_raw), "sha256": sha(source_raw),
                    "byteLength": len(source_raw), "framing": {"status": "opaque"}}
    source_index_bytes = canonical({"sources": [source_asset]})
    source_row = {"id": "classic-source-index-test", "kind": "classic-source-index", "path": "index.bin",
                  "sha256": sha(source_index_bytes), "bytes": len(source_index_bytes)}
    source_doc = {"assets": [source_row]}
    old_map = {"id": "land:0", "width": 1, "height": 1,
        "cells": [["land:0:randlevel:rect:0"]], "classicTileValues": [0],
        "randomRectangles": [{"id": "land:0:randlevel:rect:0", "top": 1, "bottom": 2}]}
    new_map = {"id": "land:0", "width": 1, "height": 1,
        "cells": [["land:0:rect:0"]], "classicTileValues": [0],
        "randomRectangles": [{"id": "land:0:rect:0", "top": 1, "bottom": 2}]}
    old_world = {"schemaVersion": 6, "maps": [old_map]}
    new_world = {"schemaVersion": 7, "maps": [new_map]}
    new_source_asset = {**source_asset, "framing": {"status": "fixed-record", "recordBytes": 40}}
    new_source_index_bytes = canonical({"sources": [new_source_asset]})
    new_source_doc = {"assets": [{**source_row, "sha256": sha(new_source_index_bytes),
                                  "bytes": len(new_source_index_bytes)}]}
    package_before = {"documents": {"content.json": before, "world.json": {},
                                    "scenario.json": {}, "assets/index.json": source_doc, "manifest.json": {}},
                      "files": {"content.json": b"old", "world.json": canonical(old_world),
                                "index.bin": source_index_bytes, "source.bin": source_raw,
                                "assets/index.json": canonical(source_doc)}, "path": Path("old.realmz2"),
                      "manifestBytes": b"{}", "packageHash": "a" * 64, "archiveSha256": "b" * 64, "archiveBytes": 0}
    package_after = {"documents": {"content.json": after, "world.json": {},
                                   "scenario.json": {}, "assets/index.json": new_source_doc, "manifest.json": {}},
                     "files": {"content.json": b"new", "world.json": canonical(new_world),
                               "index.bin": new_source_index_bytes, "source.bin": source_raw,
                               "assets/index.json": canonical(new_source_doc)}, "path": Path("new.realmz2"),
                     "manifestBytes": b"{}", "packageHash": "c" * 64, "archiveSha256": "d" * 64, "archiveBytes": 0}
    blockers: list = []
    require(exact_simple_mapping(package_before, package_after, "test", blockers) == {"4": [2, 0]} and not blockers,
            "simple choice identity mapping must ignore label-only changes")
    require(simple_label_deltas(package_before, package_after) == [{"encounterId": 4,
                "responseId": "simple:4:choice:0", "nativeSlot": 0,
                "beforePosition": 1, "afterPosition": 0,
                "before": "Zero", "after": "Zero corrected"},
                {"encounterId": 4, "responseId": "simple:4:choice:1", "nativeSlot": 1,
                 "beforePosition": None, "afterPosition": 1, "before": None, "after": "One"},
                {"encounterId": 4, "responseId": "simple:4:choice:3", "nativeSlot": 3,
                 "beforePosition": None, "afterPosition": 3, "before": None, "after": "Three"}],
            "label-only Simple differences were not retained as diagnostics")
    region_probe = random_region_mapping(package_before, package_after)
    require(region_probe["randomPendingCompatibleByMap"] == {"land:0": True} and
            region_probe["oldToNew"] == [{"mapId": "land:0", "oldId": "land:0:randlevel:rect:0",
                "oldSlot": 0, "newId": "land:0:rect:0", "newSlot": 0, "reason": "exact-native-map-slot"}],
            "exact random-region ID mapping and membership compatibility probe failed")
    changed_region_world = {"schemaVersion": 7, "maps": [{**new_map,
        "randomRectangles": [{"id": "land:0:rect:0", "top": 1, "bottom": 3}]}]}
    changed_region_package = {**package_after, "files": {**package_after["files"],
        "world.json": canonical(changed_region_world)}}
    changed_region_probe = random_region_mapping(package_before, changed_region_package)
    require(changed_region_probe["randomPendingCompatibleByMap"] == {"land:0": False} and
            changed_region_probe["byMap"]["land:0"]["geometryChangedNativeSlots"][0]["changedFields"] == ["bottom"],
            "changed random-region geometry must disable pending compatibility")
    out_of_range_old_map = {"id": "land:0", "width": 1, "height": 1,
        "cells": [["land:0:randlevel:rect:20"]], "randomRectangles": [
            {"id": "land:0:randlevel:rect:20", "top": 1, "bottom": 2}]}
    out_of_range_old_package = {**package_before, "files": {**package_before["files"],
        "world.json": canonical({"schemaVersion": 6, "maps": [out_of_range_old_map]})}}
    out_of_range_probe = random_region_mapping(out_of_range_old_package, package_after)
    require(any(row.get("oldSlot") == 20 and row.get("newId") is None and
                row.get("reason") == "old-synthetic-out-of-range" for row in out_of_range_probe["oldToNew"]) and
            out_of_range_probe["randomPendingCompatibleByMap"]["land:0"] is False,
            "out-of-range old synthetic random region must map to null and disable pending compatibility")
    framing_diagnostic = source_index_diagnostic(package_before, package_after)
    require(framing_diagnostic["classification"] == "compiler-framing-only" and
            not framing_diagnostic["blockingChanges"] and
            framing_diagnostic["sourceIndexDiff"][0]["changedFields"] == ["framing"],
            "framing-only native source index updates must retain hashes and diagnostics without blocking")
    self_test_shared_sources()
    shop_blockers: list = []
    require(exact_shop_mapping(package_before, package_after, "test", shop_blockers) == {"8": [1, 0]} and not shop_blockers,
            "physical shop-slot mapping probe failed")
    changed_shop = {"shops": [{"classicId": 8, "stock": [
        {"slot": 41, "itemId": "classic.item.6", "quantity": 1},
        {"slot": 40, "itemId": "classic.item.5", "quantity": 3}]}]}
    changed_shop_package = {**package_after, "documents": {**package_after["documents"],
                                                               "content.json": changed_shop}}
    changed_shop_blockers: list = []
    require(exact_shop_mapping(package_before, changed_shop_package, "test", changed_shop_blockers) == {"8": [None, 0]} and
            changed_shop_blockers, "changed shop stock was not held as an unmapped blocker")
    package_before["documents"]["content.json"]["timedEncounters"] = [{"id": 12}, {"id": 7}]
    require(timer_ids(package_before, "test") == [12, 7], "timer ID order probe failed")
    package_after["documents"]["content.json"]["timedEncounters"] = [{"id": 7}]
    runtime_pair, timer_report = revision_receipt(package_before, package_after, "test")
    require(runtime_pair["randomRegionIds"] == {"land:0:randlevel:rect:0": "land:0:rect:0"} and
            runtime_pair["randomPendingCompatibleByMap"] == {"land:0": True},
            "runtime receipt must expose flat native region mappings and independent pending eligibility")
    require(timer_report["timerPositionBlockers"] == [{"kind": "timer-position-unmapped", "nativeId": 12,
                "beforePosition": 0, "afterTimerIds": [7]}] and
            timer_report["sourceRetentionBlockers"] == [] and timer_report["mappingBlockers"] == [],
            "unmapped timer positions were not retained as a distinct blocker")
    edits = semantic_diff({"rows": [1]}, {"rows": [1, 2]})
    require(edits == [{"path": "/rows/1", "change": "added", "after": 2}], "array addition diff probe failed")
    world_before = {"schemaVersion": 6, "maps": [
        {"id": "land:1", "width": 2, "height": 2, "region": [1, 2],
         "cells": [["a"], ["b"], ["c"], ["d"]], "classicTileValues": [1, 2, 3, 4]},
        {"id": "land:0", "width": 1, "height": 1, "cells": [["x"]], "classicTileValues": [9]}]}
    world_after = {"schemaVersion": 7, "maps": [
        {"id": "land:0", "width": 1, "height": 1, "cells": [["x"]], "classicTileValues": [9]},
        {"id": "land:1", "width": 2, "height": 2, "region": [1, 3],
         "cells": [["a"], ["b2"], ["c2"], ["d"]], "classicTileValues": [1, 2, 3, 4]}]}
    world_delta = world_map_diff(world_before, world_after)
    require(world_delta["changedTopLevelFields"] == [{
                "field": "schemaVersion", "beforeSha256": sha(canonical(6)), "afterSha256": sha(canonical(7))}] and
            world_delta["changedMaps"][0]["mapId"] == "land:1" and
            world_delta["changedMaps"][0]["changedFields"][0]["field"] == "region" and
            world_delta["changedMaps"][0]["changedCellIndexRuns"] == [[1, 2]],
            "map identity, region field, or native cell-position comparison failed")
    document_probe_before = {"files": {"content.json": b'{"rows":[1]}'}, "manifestBytes": b'{}'}
    document_probe_after = {"files": {"content.json": b'{"rows":[1,2]}'}, "manifestBytes": b'{"version":2}'}
    document_edits = document_semantic_diff(document_probe_before, document_probe_after)
    require(any(row.get("document") == "content.json" and row.get("path") == "/rows/1" and row.get("change") == "added"
                for row in document_edits) and any(row.get("document") == "manifest.json" for row in document_edits),
            "multi-document semantic diff probe failed")
    unsafe_after = {**package_after, "files": {**package_after["files"], "index.bin": b"tampered"}}
    require(source_retention_blockers(package_before, unsafe_after),
            "changed source-index payload was not reported as a blocker")
    metadata_after = {**package_after,
                      "documents": {**package_after["documents"],
                                    "assets/index.json": {"assets": [*source_doc["assets"],
                                        {"id": "reviewed-metadata", "kind": "presentation", "path": "ui.bin"}]}},
                      "files": {**package_after["files"], "ui.bin": b"ui",
                                "assets/index.json": canonical({"assets": [*source_doc["assets"],
                                    {"id": "reviewed-metadata", "kind": "presentation", "path": "ui.bin"}]})}}
    require(not source_retention_blockers(package_before, metadata_after) and
            asset_inventory_diff(package_before, metadata_after)["changes"] == [{
                "identity": "reviewed-metadata", "before": None,
                "after": {"id": "reviewed-metadata", "kind": "presentation", "path": "ui.bin"},
                "change": "added"}],
            "assets/index.json metadata changes were not reported separately from exact source-byte retention")
    bad_responses = [dict(row) for row in after["simpleEncounters"][0]["responses"]]
    bad_responses[2]["resultProgramId"] = "simple:4:result:3"
    bad = {"simpleEncounters": [{"id": 4, "responses": bad_responses}], "shops": after["shops"]}
    bad_package = {**package_after, "documents": {**package_after["documents"], "content.json": bad}}
    bad_blockers: list = []
    require(exact_simple_mapping(package_before, bad_package, "test", bad_blockers) == {} and bad_blockers,
            "ambiguous/changed simple mapping was not blocked")
    fork = bytearray(312)
    struct.pack_into(">IIII", fork, 0, 256, 262, 6, 50)
    fork[256:262] = b"\x00\x00\x00\x02xy"
    struct.pack_into(">HH", fork, 262 + 24, 28, 50)
    fork[290:292] = b"\x00\x00"
    fork[292:296] = b"TEST"
    struct.pack_into(">HH", fork, 296, 0, 10)
    struct.pack_into(">hH", fork, 300, 7, 0xffff)
    fork[304] = 0
    fork[305:308] = b"\x00\x00\x00"
    fork[308:312] = b"\x00\x00\x00\x00"
    native_rows = parse_native_resources(bytes(fork), "Scenario.rsrc")
    require(native_rows == [{"nativePath": "Scenario.rsrc", "resourceTypeBytes": [84, 69, 83, 84], "resourceId": 7,
                             "occurrence": 0, "sha256": sha(b"xy"), "byteLength": 2}],
            "native resource inventory parser probe failed")
    index_doc = {"assets": [
        {"id": "source-index", "kind": "classic-source-index", "path": "index.json", "sha256": "ignored", "bytes": 0},
        {"id": "resource-source", "kind": "classic-source", "path": "fork.bin", "sha256": sha(bytes(fork)), "bytes": len(fork)}]}
    source_index_bytes = json.dumps({"sources": [{"nativePath": "Scenario.rsrc", "assetPath": "fork.bin"}]}, separators=(",", ":")).encode()
    index_doc["assets"][0].update(sha256=sha(source_index_bytes), bytes=len(source_index_bytes))
    nested_rows = [{"nativePath": ".rsrc/Scenario", "assetPath": "fork.bin"},
                   {"nativePath": "Texts/._Scenario", "assetPath": "fork.bin"},
                   {"nativePath": "Data.rsf", "assetPath": "fork.bin"}]
    source_index_bytes = json.dumps({"sources": [
        {"nativePath": "Scenario.rsrc", "assetPath": "fork.bin"}, *nested_rows]}, separators=(",", ":")).encode()
    index_doc["assets"][0].update(sha256=sha(source_index_bytes), bytes=len(source_index_bytes))
    resource_package = {"path": Path("resource.realmz2"),
                        "documents": {"assets/index.json": index_doc, "content.json": {"classicRecords": {"resources": [
                            *native_rows, *[dict(native_rows[0], nativePath=row["nativePath"]) for row in nested_rows]]}}},
                        "files": {"assets/index.json": canonical(index_doc), "index.json": source_index_bytes, "fork.bin": bytes(fork)}}
    resource_diff = resource_inventory_diff(resource_package, resource_package)
    require(not resource_diff["changes"] and not resource_diff["declaredFactsMissingFromIndependentInventory"] and
            not resource_diff["independentInventoryMissingFromDeclaredFacts"] and
            resource_diff["afterCount"] == 4,
            "resource inventory cross-check probe failed")
    return {"selfTest": True, "cases": 23, "passed": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before-dir", type=Path)
    parser.add_argument("--after-dir", type=Path)
    parser.add_argument("--application-package", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--additional-before-manifests", type=Path,
                        help="explicit JSON pinlist of historical packages (campaignId, file, packageHash, archiveSha256)")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(self_test(), sort_keys=True))
        return 0
    required = ["before_dir", "after_dir", "application_package", "output"]
    missing = [name.replace("_", "-") for name in required if getattr(args, name) is None]
    require(not missing, "missing required arguments: " + ", ".join("--" + name for name in missing))
    result = prepare(args.before_dir, args.after_dir, args.application_package, args.output,
                     args.additional_before_manifests)
    print(json.dumps(result, sort_keys=True))
    return 2 if result["blockers"] else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ReceiptError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
