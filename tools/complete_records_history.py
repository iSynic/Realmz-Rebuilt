#!/usr/bin/env python3
"""Build and verify compact, byte-exact recipes for the pinned v6 campaign ZIPs.

The recipe keeps the original archive framing and central directory, and reuses
candidate DEFLATE streams only when they are byte-identical to the baseline.
Changed or unavailable entries carry their original compressed streams in
base64 plus uncompressed length and SHA-256 for integrity verification.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import pathlib
import stat
import struct
import sys
import zlib
import zipfile


EXPECTED = {
    "scenario-assault-on-giant-mountain.realmz2",
    "scenario-castle-in-the-clouds.realmz2",
    "scenario-city-of-bywater.realmz2",
    "scenario-destroy-the-necronomicon.realmz2",
    "scenario-grilochs-revenge.realmz2",
    "scenario-half-truth.realmz2",
    "scenario-mithril-vault.realmz2",
    "scenario-prelude-to-pestilence.realmz2",
    "scenario-trouble-in-the-sword-lands.realmz2",
    "scenario-twin-sands-of-time.realmz2",
    "scenario-war-in-the-sword-lands.realmz2",
    "scenario-white-dragon.realmz2",
    "scenario-wrath-of-the-mind-lords.realmz2",
}
EOCD = b"PK\x05\x06"
LOCAL = b"PK\x03\x04"
CENTRAL = b"PK\x01\x02"
VERSION = 3


class RecipeError(RuntimeError):
    pass


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_identity(path: pathlib.Path) -> dict:
    if path.is_symlink() or not path.is_file():
        raise RecipeError(f"input is not a regular file: {path}")
    data = path.read_bytes()
    return {"filename": path.name, "bytes": len(data), "sha256": sha(data)}


def safe_member(info: zipfile.ZipInfo) -> None:
    name = info.filename
    parts = name.replace("\\", "/").split("/")
    mode = (info.external_attr >> 16) & 0xFFFF
    if (not name or name.startswith(("/", "\\")) or "\\" in name
            or (len(parts[0]) >= 2 and parts[0][1] == ":")
            or any(part in ("", ".", "..") for part in parts if part)
            or (mode and stat.S_ISLNK(mode))):
        raise RecipeError(f"unsafe ZIP member path or symlink: {name!r}")


def archive_parts(path: pathlib.Path):
    raw = path.read_bytes()
    if len(raw) < 22:
        raise RecipeError(f"truncated ZIP: {path}")
    eocd_at = raw.rfind(EOCD)
    if eocd_at < 0 or eocd_at + 22 > len(raw):
        raise RecipeError(f"missing ZIP end record: {path}")
    disk, central_disk, entries_disk, entries, central_size, central_at, comment_len = struct.unpack_from("<HHHHIIH", raw, eocd_at + 4)
    if disk or central_disk or entries_disk != entries:
        raise RecipeError(f"multi-disk ZIP is unsupported: {path}")
    if entries == 0xFFFF or central_size == 0xFFFFFFFF or central_at == 0xFFFFFFFF or b"PK\x06\x06" in raw:
        raise RecipeError(f"ZIP64 is unsupported by this bounded recipe: {path}")
    if central_at + central_size != eocd_at:
        raise RecipeError(f"unexpected central-directory framing: {path}")
    with zipfile.ZipFile(path, "r") as zf:
        infos = zf.infolist()
        if len(infos) != entries:
            raise RecipeError(f"central entry count mismatch: {path}")
        names = set()
        for info in infos:
            safe_member(info)
            if info.filename in names:
                raise RecipeError(f"duplicate ZIP member name: {info.filename!r}")
            names.add(info.filename)
            if info.flag_bits & 8:
                raise RecipeError(f"data-descriptor ZIP member unsupported: {info.filename!r}")
            if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                raise RecipeError(f"unsupported compression method {info.compress_type}: {info.filename}")
        central_bytes = raw[central_at:eocd_at]
        if central_bytes.count(CENTRAL) != entries:
            raise RecipeError(f"central record count mismatch: {path}")
        locals_by_offset = sorted(infos, key=lambda x: x.header_offset)
        prefix = raw[:locals_by_offset[0].header_offset] if locals_by_offset else raw[:central_at]
        local_records = []
        for idx, info in enumerate(locals_by_offset):
            offset = info.header_offset
            if raw[offset:offset + 4] != LOCAL:
                raise RecipeError(f"missing local header at {offset}: {path}")
            name_len, extra_len = struct.unpack_from("<HH", raw, offset + 26)
            end_header = offset + 30 + name_len + extra_len
            end_member = end_header + info.compress_size
            limit = locals_by_offset[idx + 1].header_offset if idx + 1 < len(locals_by_offset) else central_at
            if end_member > limit:
                raise RecipeError(f"overlapping local records: {info.filename}")
            local_records.append({
                "info": info,
                "localHeader": raw[offset:end_header],
                "compressed": raw[end_header:end_member],
                "gapAfter": raw[end_member:limit],
            })
        return raw, infos, prefix, local_records, central_bytes, raw[eocd_at:]


def write_new(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as f:
        f.write(data)


def json_bytes(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def recipe_path(directory: pathlib.Path, filename: str) -> pathlib.Path:
    return directory / (filename + ".recipe.json.zlib")


def generate_one(base: pathlib.Path, candidate: pathlib.Path, target: pathlib.Path) -> dict:
    baseline_identity = file_identity(base)
    candidate_identity = file_identity(candidate)
    base_raw, base_infos, prefix, local_records, central_bytes, tail = archive_parts(base)
    cand_raw, cand_infos, _, cand_local_records, _, _ = archive_parts(candidate)
    if sha(base_raw) != baseline_identity["sha256"] or sha(cand_raw) != candidate_identity["sha256"]:
        raise RecipeError("an input archive changed while its recipe was being generated")
    base_zip = zipfile.ZipFile(base, "r")
    cand_zip = zipfile.ZipFile(candidate, "r")
    cand_by_name = {i.filename: i for i in cand_infos}
    cand_payload = {r["info"].filename: r["compressed"] for r in cand_local_records}
    entries = []
    for rec in local_records:
        info = rec["info"]
        baseline_data = base_zip.read(info)
        original_payload = rec["compressed"]
        candidate_info = cand_by_name.get(info.filename)
        candidate_data = cand_zip.read(candidate_info) if candidate_info is not None else None
        candidate_payload = cand_payload.get(info.filename)
        reuse = (candidate_info is not None and candidate_data == baseline_data
                 and candidate_info.compress_type == info.compress_type
                 and candidate_payload == original_payload)
        reason = "candidate-member-byte-identical" if reuse else (
            "missing-in-candidate" if candidate_info is None else
            "candidate-content-differs" if candidate_data != baseline_data else
            "candidate-compressed-stream-differs")
        entry = {
            "name": info.filename,
            "crc32": info.CRC,
            "contentBytes": info.file_size,
            "contentSha256": sha(baseline_data),
            "compression": info.compress_type,
            "compressedBytes": info.compress_size,
            "compressedSha256": sha(original_payload),
            "localHeaderB64": base64.b64encode(rec["localHeader"]).decode("ascii"),
            "gapAfterB64": base64.b64encode(rec["gapAfter"]).decode("ascii"),
            "payloadSource": "candidate" if reuse else "recipe",
            "payloadReason": reason,
        }
        if not reuse:
            entry["compressedPayloadB64"] = base64.b64encode(original_payload).decode("ascii")
        entries.append(entry)
    obj = {
        "format": "realmz-v6-raw-zip-reconstruction-recipe",
        "formatVersion": VERSION,
        "baseline": baseline_identity,
        "candidate": candidate_identity,
        "zip": {
            "prefixB64": base64.b64encode(prefix).decode("ascii"),
            "centralDirectoryB64": base64.b64encode(central_bytes).decode("ascii"),
            "endRecordB64": base64.b64encode(tail).decode("ascii"),
            "entryCount": len(entries),
            "centralOrder": [i.filename for i in base_infos],
            "localOrder": [r["info"].filename for r in local_records],
            "entries": entries,
        },
    }
    plain = json_bytes(obj)
    compressed = zlib.compress(plain, level=9)
    write_new(target, compressed)
    return {"filename": base.name, "baselineBytes": len(base_raw),
            "baselineSha256": baseline_identity["sha256"],
            "candidateBytes": candidate_identity["bytes"],
            "candidateSha256": candidate_identity["sha256"],
            "recipeBytes": len(compressed),
            "recipeSha256": sha(compressed), "entryCount": len(entries),
            "candidateReusedEntries": sum(e["payloadSource"] == "candidate" for e in entries),
            "storedEntries": sum(e["payloadSource"] == "recipe" for e in entries)}


def load_recipe(path: pathlib.Path) -> dict:
    try:
        raw = zlib.decompress(path.read_bytes())
        value = json.loads(raw)
    except Exception as exc:
        raise RecipeError(f"invalid compressed recipe {path}: {exc}") from exc
    if value.get("format") != "realmz-v6-raw-zip-reconstruction-recipe" or value.get("formatVersion") != VERSION:
        raise RecipeError(f"unsupported recipe format: {path}")
    return value


def verify_identity(path: pathlib.Path, expected: dict) -> None:
    actual = file_identity(path)
    if (actual["filename"] != expected["filename"] or actual["bytes"] != expected["bytes"]
            or actual["sha256"] != expected["sha256"]):
        raise RecipeError(f"pinned input identity changed: {path} (expected {expected['sha256']}, got {actual['sha256']})")


def reconstruct_one(recipe: dict, candidate_path: pathlib.Path, output_path: pathlib.Path) -> dict:
    verify_identity(candidate_path, recipe["candidate"])
    raw, infos, _, local_records, _, _ = archive_parts(candidate_path)
    if sha(raw) != recipe["candidate"]["sha256"]:
        raise RecipeError(f"candidate changed while being read: {candidate_path}")
    zf = zipfile.ZipFile(candidate_path, "r")
    candidate_infos = {i.filename: i for i in infos}
    candidate_payloads = {r["info"].filename: r["compressed"] for r in local_records}
    parts = [base64.b64decode(recipe["zip"]["prefixB64"], validate=True)]
    inventory = {}
    for e in recipe["zip"]["entries"]:
        name = e["name"]
        safe_member(zipfile.ZipInfo(name))
        if e["payloadSource"] == "candidate":
            info = candidate_infos.get(name)
            payload = candidate_payloads.get(name)
            if (info is None or info.compress_type != e["compression"] or payload is None
                    or info.CRC != e["crc32"]):
                raise RecipeError(f"candidate no longer provides reusable member: {name}")
            content = zf.read(info)
            if (len(content) != e["contentBytes"] or sha(content) != e["contentSha256"]
                    or sha(payload) != e["compressedSha256"]):
                raise RecipeError(f"candidate member identity mismatch: {name}")
        else:
            payload = base64.b64decode(e["compressedPayloadB64"], validate=True)
            if len(payload) != e["compressedBytes"] or sha(payload) != e["compressedSha256"]:
                raise RecipeError(f"stored compressed payload identity mismatch: {name}")
            decoded = zf_for_method(e["compression"], payload)
            content = decoded
            if len(content) != e["contentBytes"] or sha(content) != e["contentSha256"]:
                raise RecipeError(f"stored uncompressed content identity mismatch: {name}")
        if zlib.crc32(content) & 0xFFFFFFFF != e["crc32"]:
            raise RecipeError(f"member CRC-32 mismatch: {name}")
        header = base64.b64decode(e["localHeaderB64"], validate=True)
        if header[:4] != LOCAL:
            raise RecipeError(f"bad stored local header: {name}")
        h_name_len, h_extra_len = struct.unpack_from("<HH", header, 26)
        flags = struct.unpack_from("<H", header, 6)[0]
        if len(header) != 30 + h_name_len + h_extra_len or header[30:30+h_name_len].decode("utf-8" if flags & 0x800 else "cp437", "replace") != name:
            raise RecipeError(f"stored local header name/length mismatch: {name}")
        parts.extend((header, payload, base64.b64decode(e["gapAfterB64"], validate=True)))
        inventory[name] = {"bytes": len(content), "sha256": sha(content)}
    entry_names = [e["name"] for e in recipe["zip"]["entries"]]
    if (len(entry_names) != recipe["zip"]["entryCount"] or len(set(entry_names)) != len(entry_names)
            or recipe["zip"]["localOrder"] != entry_names
            or len(recipe["zip"]["centralOrder"]) != len(entry_names)
            or len(set(recipe["zip"]["centralOrder"])) != len(entry_names)
            or set(recipe["zip"]["centralOrder"]) != set(entry_names)):
        raise RecipeError("recipe ZIP member index/order is inconsistent")
    parts.append(base64.b64decode(recipe["zip"]["centralDirectoryB64"], validate=True))
    parts.append(base64.b64decode(recipe["zip"]["endRecordB64"], validate=True))
    rebuilt = b"".join(parts)
    if len(rebuilt) != recipe["baseline"]["bytes"] or sha(rebuilt) != recipe["baseline"]["sha256"]:
        raise RecipeError(f"raw-member reconstruction did not reproduce baseline archive bytes: {output_path}")
    with zipfile.ZipFile(io.BytesIO(rebuilt), "r") as out:
        actual_names = [i.filename for i in out.infolist()]
        if actual_names != recipe["zip"]["centralOrder"]:
            raise RecipeError(f"reconstructed central entry order differs: {output_path}")
        for name, expected in inventory.items():
            data = out.read(name)
            if len(data) != expected["bytes"] or sha(data) != expected["sha256"]:
                raise RecipeError(f"reconstructed extracted-byte inventory differs: {name}")
    if output_path.exists() or output_path.is_symlink():
        raise RecipeError(f"refusing to overwrite output: {output_path}")
    write_new(output_path, rebuilt)
    return {"filename": output_path.name, "bytes": len(rebuilt), "sha256": sha(rebuilt),
            "baselineSha256": recipe["baseline"]["sha256"], "archiveByteIdentical": True,
            "entryCount": len(inventory), "extractedInventoryIdentical": True}


def zf_for_method(method: int, payload: bytes) -> bytes:
    if method == zipfile.ZIP_STORED:
        return payload
    if method == zipfile.ZIP_DEFLATED:
        return zlib.decompress(payload, -15)
    raise RecipeError(f"unsupported stored compression method {method}")


def create_fresh_dir(path: pathlib.Path) -> None:
    if path.exists() or path.is_symlink():
        raise RecipeError(f"output directory already exists; use a fresh path: {path}")
    path.mkdir(parents=True)


def package_set(directory: pathlib.Path) -> list[pathlib.Path]:
    if directory.is_symlink() or not directory.is_dir():
        raise RecipeError(f"package root must be a non-symlink directory: {directory}")
    files = sorted(directory.glob("*.realmz2"))
    names = {p.name for p in files}
    if names != EXPECTED or len(files) != len(EXPECTED):
        raise RecipeError(f"expected exact 13-package set in {directory}; missing={sorted(EXPECTED-names)}, extra={sorted(names-EXPECTED)}")
    return files


def command_generate(args) -> int:
    base_files = package_set(args.baseline_dir)
    cand_files = package_set(args.candidate_dir)
    create_fresh_dir(args.recipe_dir)
    rows = []
    for base, cand in zip(base_files, cand_files):
        if base.name != cand.name:
            raise RecipeError("baseline/candidate name ordering mismatch")
        rows.append(generate_one(base, cand, recipe_path(args.recipe_dir, base.name)))
    manifest = {"format": "realmz-v6-reconstruction-recipe-manifest", "formatVersion": VERSION,
                "campaignCount": len(rows), "recipes": rows,
                "recipeBytesTotal": sum(r["recipeBytes"] for r in rows),
                "candidateReusedEntries": sum(r["candidateReusedEntries"] for r in rows),
                "storedEntries": sum(r["storedEntries"] for r in rows)}
    write_new(args.recipe_dir / "manifest.json", json_bytes(manifest))
    print(json.dumps(manifest, indent=2))
    return 0


def command_reconstruct(args) -> int:
    recipe_files = sorted(args.recipe_dir.glob("*.realmz2.recipe.json.zlib"))
    if len(recipe_files) != len(EXPECTED) or {p.name[:-len(".recipe.json.zlib")] for p in recipe_files} != EXPECTED:
        raise RecipeError(f"recipe directory must contain exactly 13 per-campaign recipes: {args.recipe_dir}")
    manifest_path = args.recipe_dir / "manifest.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise RecipeError(f"missing or unsafe recipe manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if (manifest.get("format") != "realmz-v6-reconstruction-recipe-manifest"
            or manifest.get("formatVersion") != VERSION):
        raise RecipeError(f"recipe manifest format mismatch: {manifest_path}")
    manifest_rows = {row["filename"]: row for row in manifest.get("recipes", [])}
    if set(manifest_rows) != EXPECTED or manifest.get("campaignCount") != len(EXPECTED):
        raise RecipeError(f"recipe manifest campaign inventory mismatch: {manifest_path}")
    for path in recipe_files:
        expected = manifest_rows[path.name[:-len(".recipe.json.zlib")]]
        identity = file_identity(path)
        if identity["bytes"] != expected["recipeBytes"] or identity["sha256"] != expected["recipeSha256"]:
            raise RecipeError(f"recipe file differs from its manifest pin: {path}")
    create_fresh_dir(args.output_dir)
    results = []
    for path in recipe_files:
        name = path.name[:-len(".recipe.json.zlib")]
        recipe = load_recipe(path)
        if recipe["baseline"]["filename"] != name:
            raise RecipeError(f"recipe baseline filename mismatch: {path}")
        candidate = args.candidate_dir / name
        output = args.output_dir / name
        results.append(reconstruct_one(recipe, candidate, output))
    report = {"format": "realmz-v6-reconstruction-verification", "formatVersion": VERSION,
              "campaignCount": len(results), "archiveByteIdenticalCount": sum(x["archiveByteIdentical"] for x in results),
              "extractedInventoryIdenticalCount": sum(x["extractedInventoryIdentical"] for x in results),
              "allExact": all(x["archiveByteIdentical"] and x["extractedInventoryIdentical"] for x in results),
              "results": results}
    write_new(args.output_dir / "verification.json", json_bytes(report))
    print(json.dumps(report, indent=2))
    return 0 if report["allExact"] else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="command", required=True)
    gen = subs.add_parser("generate")
    gen.add_argument("--baseline-dir", type=pathlib.Path, required=True)
    gen.add_argument("--candidate-dir", type=pathlib.Path, required=True)
    gen.add_argument("--recipe-dir", type=pathlib.Path, required=True)
    gen.set_defaults(func=command_generate)
    rec = subs.add_parser("reconstruct")
    rec.add_argument("--recipe-dir", type=pathlib.Path, required=True)
    rec.add_argument("--candidate-dir", type=pathlib.Path, required=True)
    rec.add_argument("--output-dir", type=pathlib.Path, required=True)
    rec.set_defaults(func=command_reconstruct)
    args = parser.parse_args()
    try:
        return args.func(args)
    except (RecipeError, OSError, zipfile.BadZipFile, KeyError, ValueError, struct.error, zlib.error) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
