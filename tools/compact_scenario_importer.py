#!/usr/bin/env python3
"""Pack importer support while reusing exact entries from Rebuilt's stock library."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any


MANIFEST = "build-manifest.json"
MARKER = ".gdignore"
SUPPORT_ARCHIVE = "support.zip"
MAX_APP_ENTRIES = 100_000
MAX_APP_MEMBER_BYTES = 512 * 1024 * 1024
MAX_APP_TOTAL_BYTES = 4 * 1024 * 1024 * 1024
MAX_ZIP_RATIO = 10_000
MAX_SUPPORT_FILES = 100_000
MAX_SUPPORT_MEMBER_BYTES = 512 * 1024 * 1024
MAX_SUPPORT_TOTAL_BYTES = 4 * 1024 * 1024 * 1024
CHUNK = 1024 * 1024


class CompactError(Exception):
    pass


def fail(message: str) -> None:
    raise CompactError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hash_file(path: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(CHUNK)
            if not chunk:
                break
            size += len(chunk)
            digest.update(chunk)
    return size, digest.hexdigest()


def safe_relative(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value or ":" in value:
        fail(f"{label} is not a safe relative POSIX path")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in value.split("/")):
        fail(f"{label} is not a safe relative POSIX path")
    if path.as_posix() != value:
        fail(f"{label} is not a normalized relative POSIX path")
    for part in value.split("/"):
        base = part.split(".", 1)[0].upper()
        if any(ord(char) < 32 or char in '<>"|?*' for char in part) or part.endswith((".", " ")) or base in {
            "CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))
        }:
            fail(f"{label} contains a path component unsafe on Windows")
    return value


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"{label} is missing or invalid JSON: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def ensure_plain_tree(root: Path) -> list[str]:
    root = root.resolve(strict=True)
    files: list[str] = []
    for current, dirs, names in os.walk(root, followlinks=False):
        current_path = Path(current)
        for name in list(dirs):
            path = current_path / name
            if path.is_symlink() or _is_reparse(path):
                fail(f"Importer source contains a symlink or reparse point: {path}")
        for name in names:
            path = current_path / name
            if path.is_symlink() or _is_reparse(path) or not path.is_file():
                fail(f"Importer source contains a link or special file: {path}")
            files.append(path.relative_to(root).as_posix())
    return files


def _is_reparse(path: Path) -> bool:
    try:
        return bool(path.lstat().st_file_attributes & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
    except (AttributeError, OSError):
        return False


def validate_inventory(manifest: dict[str, Any], expected_version: int = 1) -> list[dict[str, Any]]:
    rows = manifest.get("supportFiles")
    if manifest.get("formatVersion") != expected_version or not isinstance(rows, list):
        fail(f"Importer must have a version {expected_version} build manifest and supportFiles inventory")
    if len(rows) > MAX_SUPPORT_FILES:
        fail("Importer support inventory exceeds the supported file-count bound")
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    total_bytes = 0
    for row in rows:
        if not isinstance(row, dict):
            fail("Source support inventory contains a non-object row")
        relative = safe_relative(row.get("path"), "support path")
        key = relative.casefold()
        if key in seen:
            fail(f"Source support inventory contains duplicate case-insensitive path: {relative}")
        seen.add(key)
        size = row.get("bytes")
        digest = row.get("sha256")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            fail(f"Support inventory has invalid byte length: {relative}")
        if size > MAX_SUPPORT_MEMBER_BYTES:
            fail(f"Support file exceeds the supported size bound: {relative}")
        total_bytes += size
        if total_bytes > MAX_SUPPORT_TOTAL_BYTES:
            fail("Support inventory exceeds the supported total size bound")
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            fail(f"Support inventory has invalid SHA-256: {relative}")
        result.append(row)
    return result


def app_archive(path: Path) -> tuple[zipfile.ZipFile, dict[str, Any], str, dict[str, zipfile.ZipInfo]]:
    if not path.is_file() or path.is_symlink() or _is_reparse(path):
        fail("Application library must be a regular archive file")
    app_bytes, app_hash = hash_file(path)
    if app_bytes <= 0:
        fail("Application library archive is empty")
    try:
        archive = zipfile.ZipFile(path, "r")
        infos = archive.infolist()
    except (OSError, zipfile.BadZipFile) as exc:
        fail(f"Application library is not a valid ZIP archive: {exc}")
    if len(infos) > MAX_APP_ENTRIES:
        archive.close()
        fail("Application library has too many ZIP members")
    members: dict[str, zipfile.ZipInfo] = {}
    folded: set[str] = set()
    total = 0
    for info in infos:
        name = safe_relative(info.filename.rstrip("/"), "application ZIP member") if info.filename.rstrip("/") else ""
        if not name:
            archive.close()
            fail("Application library contains an empty ZIP member name")
        key = name.casefold()
        if name in members or key in folded:
            archive.close()
            fail(f"Application library contains duplicate ZIP member: {name}")
        folded.add(key)
        mode = (info.external_attr >> 16) & 0xF000
        if mode not in (0, stat.S_IFREG, stat.S_IFDIR):
            archive.close()
            fail(f"Application library contains a link or special ZIP member: {name}")
        if info.flag_bits & 0x1:
            archive.close()
            fail(f"Application library contains an encrypted ZIP member: {name}")
        if info.file_size < 0 or info.file_size > MAX_APP_MEMBER_BYTES:
            archive.close()
            fail(f"Application ZIP member exceeds the supported size bound: {name}")
        total += info.file_size
        if total > MAX_APP_TOTAL_BYTES:
            archive.close()
            fail("Application ZIP contents exceed the supported total size bound")
        if info.file_size and (info.compress_size == 0 or info.file_size > max(info.compress_size, 1) * MAX_ZIP_RATIO):
            archive.close()
            fail(f"Application ZIP member exceeds the supported compression ratio: {name}")
        if not info.is_dir():
            members[name] = info
    if "manifest.json" not in members:
        archive.close()
        fail("Application library ZIP is missing manifest.json")
    try:
        app_manifest = json.loads(archive.read(members["manifest.json"]))
    except (OSError, UnicodeError, json.JSONDecodeError, zipfile.BadZipFile) as exc:
        archive.close()
        fail(f"Application library manifest is invalid: {exc}")
    if not isinstance(app_manifest, dict) or not isinstance(app_manifest.get("campaignId"), str) or not isinstance(app_manifest.get("packageHash"), str):
        archive.close()
        fail("Application library manifest lacks campaignId or packageHash")
    return archive, app_manifest, app_hash, members


def app_payload_index(archive: zipfile.ZipFile, members: dict[str, zipfile.ZipInfo]) -> dict[tuple[int, str], list[tuple[str, bytes]]]:
    index: dict[tuple[int, str], list[tuple[str, bytes]]] = {}
    for name, info in members.items():
        try:
            data = archive.read(info)
        except (OSError, RuntimeError, zipfile.BadZipFile) as exc:
            fail(f"Could not read application ZIP member {name}: {exc}")
        key = (len(data), sha256(data))
        index.setdefault(key, []).append((name, data))
    for rows in index.values():
        rows.sort(key=lambda item: item[0])
    return index


def validate_executable(root: Path, manifest: dict[str, Any]) -> str:
    record = manifest.get("executable")
    if not isinstance(record, dict):
        fail("Source importer manifest is missing executable metadata")
    relative = safe_relative(record.get("path"), "executable path")
    if "/" in relative:
        fail("Importer executable must be at the package root")
    path = root / relative
    if not path.is_file() or path.is_symlink() or _is_reparse(path):
        fail("Source importer executable is missing or not a regular file")
    size, digest = hash_file(path)
    if size != record.get("bytes") or digest != record.get("sha256"):
        fail("Source importer executable failed its manifest length or SHA-256 check")
    return relative


def pack(source: Path, destination: Path, application: Path) -> dict[str, Any]:
    if source.is_symlink() or _is_reparse(source):
        fail("Importer source root may not be a symlink or reparse point")
    source = source.resolve(strict=True)
    destination = destination.resolve()
    if destination.exists():
        fail("Destination must be new; existing output is preserved")
    if destination == source or source in destination.parents:
        fail("Destination must be outside the source importer tree")
    source_files = ensure_plain_tree(source)
    manifest_path = source / MANIFEST
    if MARKER not in source_files or MANIFEST not in source_files:
        fail("Source importer must contain .gdignore and build-manifest.json")
    manifest = read_json(manifest_path, "Source importer manifest")
    rows = validate_inventory(manifest)
    executable = validate_executable(source, manifest)
    if executable.casefold() in {MARKER.casefold(), MANIFEST.casefold(), SUPPORT_ARCHIVE.casefold()}:
        fail("Source importer executable path conflicts with a reserved package file")
    if any("applicationPath" in row for row in rows):
        fail("Version 1 source support rows may not contain applicationPath mappings")
    expected = {MARKER, MANIFEST, executable}
    payloads: dict[str, bytes] = {}
    for row in rows:
        relative = str(row["path"])
        path = source / "support" / Path(*PurePosixPath(relative).parts)
        if not path.is_file() or path.is_symlink() or _is_reparse(path):
            fail(f"Source support file is missing or not regular: {relative}")
        size, digest = hash_file(path)
        if size != row["bytes"] or digest != row["sha256"]:
            fail(f"Source support file failed its manifest length or SHA-256 check: {relative}")
        payloads[relative] = path.read_bytes()
        expected.add("support/" + relative)
    if set(source_files) != expected:
        fail("Source importer has unexpected or missing files")

    app_zip, app_manifest, app_hash, app_members = app_archive(application)
    try:
        app_index = app_payload_index(app_zip, app_members)
        compact_manifest = json.loads(json.dumps(manifest))
        compact_manifest["formatVersion"] = 2
        compact_rows: list[dict[str, Any]] = []
        archive_payloads: dict[str, bytes] = {}
        for row in rows:
            compact_row = dict(row)
            relative = str(row["path"])
            content = payloads[relative]
            candidates = app_index.get((len(content), sha256(content)), [])
            match = next((name for name, app_content in candidates if app_content == content), None)
            if match is not None:
                compact_row["applicationPath"] = match
            else:
                archive_payloads[relative] = content
            compact_rows.append(compact_row)
        compact_manifest["supportFiles"] = compact_rows
        support_zip_bytes = make_support_archive(archive_payloads)
        compact_manifest["supportArchive"] = {
            "path": SUPPORT_ARCHIVE,
            "bytes": len(support_zip_bytes),
            "sha256": sha256(support_zip_bytes),
        }
        compact_manifest["supportApplication"] = {
            "campaignId": app_manifest["campaignId"],
            "packageHash": app_manifest["packageHash"],
            "sha256": app_hash,
        }
    finally:
        app_zip.close()

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.mkdir()
    try:
        shutil.copy2(source / MARKER, destination / MARKER)
        shutil.copy2(source / executable, destination / executable)
        (destination / SUPPORT_ARCHIVE).write_bytes(support_zip_bytes)
        (destination / MANIFEST).write_text(json.dumps(compact_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    except Exception:
        shutil.rmtree(destination, ignore_errors=True)
        raise
    return verify(destination, application)


def make_support_archive(payloads: dict[str, bytes]) -> bytes:
    from io import BytesIO

    output = BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9, strict_timestamps=True) as archive:
        for relative in sorted(payloads):
            info = zipfile.ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            info.flag_bits = 0
            archive.writestr(info, payloads[relative], compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    return output.getvalue()


def verify(root: Path, application: Path) -> dict[str, Any]:
    if root.is_symlink() or _is_reparse(root):
        fail("Packed importer root may not be a symlink or reparse point")
    root = root.resolve(strict=True)
    actual = ensure_plain_tree(root)
    manifest = read_json(root / MANIFEST, "Packed importer manifest")
    if manifest.get("kind") != "realmz-rebuilt.scenario-importer-build" or manifest.get("formatVersion") != 2:
        fail("Packed importer manifest kind or version is unsupported")
    rows = validate_inventory(manifest, expected_version=2)
    executable = validate_executable(root, manifest)
    if executable.casefold() in {MARKER.casefold(), MANIFEST.casefold(), SUPPORT_ARCHIVE.casefold()}:
        fail("Packed importer executable path conflicts with a reserved package file")
    expected = {MARKER, MANIFEST, executable, SUPPORT_ARCHIVE}
    if set(actual) != expected:
        fail("Packed importer must contain exactly .gdignore, build-manifest.json, executable, and support.zip")
    app_info = manifest.get("supportApplication")
    archive_info = manifest.get("supportArchive")
    if not isinstance(app_info, dict) or not isinstance(archive_info, dict):
        fail("Packed importer manifest is missing supportApplication or supportArchive identity")
    archive_path = safe_relative(archive_info.get("path"), "support archive path")
    if archive_path != SUPPORT_ARCHIVE:
        fail("Packed importer support archive path is unsupported")
    app_zip, app_manifest, app_hash, app_members = app_archive(application)
    try:
        if app_info.get("campaignId") != app_manifest["campaignId"] or app_info.get("packageHash") != app_manifest["packageHash"] or app_info.get("sha256") != app_hash:
            fail("Packed importer is bound to a different application library")
        app_index = app_payload_index(app_zip, app_members)
        archive_file = root / archive_path
        archive_size, archive_hash = hash_file(archive_file)
        if archive_size != archive_info.get("bytes") or archive_hash != archive_info.get("sha256"):
            fail("Packed support archive failed its manifest length or SHA-256 check")
        try:
            support_zip = zipfile.ZipFile(archive_file, "r")
            infos = support_zip.infolist()
        except (OSError, zipfile.BadZipFile) as exc:
            fail(f"Packed support archive is invalid: {exc}")
        try:
            inventory: dict[str, dict[str, Any]] = {}
            expected_archive_paths: set[str] = set()
            for row in rows:
                relative = str(row["path"])
                if "applicationPath" in row:
                    app_path = safe_relative(row.get("applicationPath"), "application mapping path")
                    if app_path not in app_members:
                        fail(f"Mapped application ZIP member is missing: {app_path}")
                    try:
                        content = app_zip.read(app_members[app_path])
                    except (OSError, RuntimeError, zipfile.BadZipFile) as exc:
                        fail(f"Could not read mapped application ZIP member {app_path}: {exc}")
                    _check_payload(content, row, relative)
                    matches = app_index.get((len(content), sha256(content)), [])
                    exact_names = [name for name, candidate in matches if candidate == content]
                    if not exact_names or app_path != exact_names[0]:
                        fail(f"Application mapping is not the lexicographically first exact entry: {relative}")
                    inventory[relative] = {"bytes": len(content), "sha256": sha256(content)}
                else:
                    expected_archive_paths.add(relative)
            archive_names: set[str] = set()
            folded: set[str] = set()
            for info in infos:
                name = safe_relative(info.filename, "support ZIP member")
                key = name.casefold()
                if name in archive_names or key in folded:
                    fail(f"Packed support archive contains duplicate member: {name}")
                archive_names.add(name)
                folded.add(key)
                mode = (info.external_attr >> 16) & 0xF000
                if info.is_dir() or mode not in (0, stat.S_IFREG):
                    fail(f"Packed support archive contains a directory, link, or special member: {name}")
                if info.flag_bits & 0x1 or info.file_size > MAX_SUPPORT_MEMBER_BYTES:
                    fail(f"Packed support archive contains an encrypted or oversized member: {name}")
                if info.file_size and (info.compress_size == 0 or info.file_size > max(info.compress_size, 1) * MAX_ZIP_RATIO):
                    fail(f"Packed support member exceeds the supported compression ratio: {name}")
            if archive_names != expected_archive_paths:
                fail("Packed support archive does not exactly match the unmapped support inventory")
            for row in rows:
                if "applicationPath" in row:
                    continue
                relative = str(row["path"])
                try:
                    content = support_zip.read(relative)
                except (KeyError, OSError, RuntimeError, zipfile.BadZipFile) as exc:
                    fail(f"Could not read packed support member {relative}: {exc}")
                _check_payload(content, row, relative)
                key = (len(content), sha256(content))
                if any(candidate == content for _, candidate in app_index.get(key, [])):
                    fail(f"Packed support member duplicates a stock application ZIP payload: {relative}")
                inventory[relative] = {"bytes": len(content), "sha256": sha256(content)}
            if len(inventory) != len(rows):
                fail("Packed support reconstruction does not cover the original support inventory")
        finally:
            support_zip.close()
    finally:
        app_zip.close()
    packed_bytes = sum((root / name).stat().st_size for name in actual)
    return {
        "formatVersion": 2,
        "supportFiles": len(rows),
        "reusedApplicationEntries": sum(1 for row in rows if "applicationPath" in row),
        "archivedSupportFiles": sum(1 for row in rows if "applicationPath" not in row),
        "packedBytes": packed_bytes,
        "applicationSha256": app_hash,
    }


def _check_payload(content: bytes, row: dict[str, Any], relative: str) -> None:
    if len(content) != row.get("bytes") or sha256(content) != row.get("sha256"):
        fail(f"Reconstructed support payload failed its manifest length or SHA-256 check: {relative}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("pack", "verify"):
        sub = commands.add_parser(command)
        if command == "pack":
            sub.add_argument("--source", required=True, type=Path)
            sub.add_argument("--destination", required=True, type=Path)
        else:
            sub.add_argument("--root", required=True, type=Path)
        sub.add_argument("--application", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        result = pack(args.source, args.destination, args.application) if args.command == "pack" else verify(args.root, args.application)
    except (CompactError, OSError, ValueError, zipfile.BadZipFile) as exc:
        print(f"compact_scenario_importer: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
