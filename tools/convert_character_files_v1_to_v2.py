#!/usr/bin/env python3
"""Explicitly convert selected Character Files v1 records into preserved v2 revisions."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path


def canonical(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def revision_hash(record: dict) -> str:
    hashed = copy.deepcopy(record)
    hashed["revisionHash"] = ""
    return hashlib.sha256(canonical(hashed).encode("utf-8")).hexdigest()


def load_current(identity_dir: Path) -> tuple[Path, dict] | None:
    index_path = identity_dir / "current.json"
    if not index_path.is_file():
        return None
    index = json.loads(index_path.read_text(encoding="utf-8"))
    digest = index.get("revisionHash")
    if index.get("characterId") != identity_dir.name or not isinstance(digest, str):
        raise ValueError(f"{index_path}: invalid current identity")
    record_path = identity_dir / f"{digest}.r2char"
    record = json.loads(record_path.read_text(encoding="utf-8"))
    if record.get("characterId") != identity_dir.name or record.get("revisionHash") != digest:
        raise ValueError(f"{record_path}: record identity does not match its index")
    if revision_hash(record) != digest:
        raise ValueError(f"{record_path}: revision hash is invalid")
    return record_path, record


def convert(record: dict) -> dict:
    if record.get("format") != "realmz2-character" or record.get("formatVersion") != 1:
        raise ValueError("record is not a Character Files v1 revision")
    state = record.get("state")
    inventory = state.get("inventory") if isinstance(state, dict) else None
    if not isinstance(inventory, list):
        raise ValueError("record inventory is invalid")
    equipment_order: list[str] = []
    for item in inventory:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str) or not isinstance(item.get("equipped"), bool):
            raise ValueError("record inventory contains an invalid item")
        if item["equipped"]:
            equipment_order.append(item["id"])
    result = copy.deepcopy(record)
    result["formatVersion"] = 2
    result["state"]["equipmentOrder"] = equipment_order
    result["revisionHash"] = revision_hash(result)
    return result


def selected_records(vault: Path, minimum_level: int) -> list[tuple[str, str, dict]]:
    selected: list[tuple[str, str, dict]] = []
    for identity_dir in sorted((path for path in vault.iterdir() if path.is_dir()), key=lambda path: path.name):
        loaded = load_current(identity_dir)
        if loaded is None:
            continue
        _, record = loaded
        state = record.get("state")
        level = state.get("level") if isinstance(state, dict) else None
        if record.get("formatVersion") == 1 and isinstance(level, int) and level >= minimum_level:
            converted = convert(record)
            selected.append((identity_dir.name, str(state.get("name", identity_dir.name)), converted))
    return selected


def validate_converted(vault: Path, selected: list[tuple[str, str, dict]]) -> None:
    for character_id, _, expected in selected:
        loaded = load_current(vault / character_id)
        if loaded is None or loaded[1] != expected or loaded[1].get("formatVersion") != 2:
            raise ValueError(f"{character_id}: converted readback failed")


def apply_conversion(vault: Path, selected: list[tuple[str, str, dict]]) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup = vault.parent / f"{vault.name}.v1-backup-{timestamp}"
    stage = vault.parent / f".{vault.name}.v2-stage-{timestamp}"
    if backup.exists() or stage.exists():
        raise ValueError("backup or staging path already exists; retry after the current UTC second")
    shutil.copytree(vault, stage)
    try:
        for character_id, _, record in selected:
            identity_dir = stage / character_id
            digest = record["revisionHash"]
            record_path = identity_dir / f"{digest}.r2char"
            record_path.write_text(canonical(record), encoding="utf-8")
            (identity_dir / "current.json").write_text(
                canonical({"characterId": character_id, "revisionHash": digest}), encoding="utf-8"
            )
        validate_converted(stage, selected)
        vault.rename(backup)
        try:
            stage.rename(vault)
        except Exception:
            backup.rename(vault)
            raise
        validate_converted(vault, selected)
        return backup
    except Exception:
        if stage.exists():
            shutil.rmtree(stage)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vault", type=Path, required=True)
    parser.add_argument("--minimum-level", type=int, default=9)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    vault = args.vault.expanduser().resolve()
    if not vault.is_dir() or vault.name != "characters":
        raise ValueError("--vault must resolve to an existing directory named 'characters'")
    selected = selected_records(vault, args.minimum_level)
    for character_id, name, record in selected:
        print(f"{name}\tlevel {record['state']['level']}\t{character_id}")
    print(f"Selected {len(selected)} Character Files v1 record(s).")
    if not args.apply or not selected:
        return 0
    backup = apply_conversion(vault, selected)
    print(f"Converted {len(selected)} record(s); complete backup: {backup}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Conversion failed: {error}", file=sys.stderr)
        sys.exit(1)
