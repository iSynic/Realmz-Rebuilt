"""Verify encoding-only bundled scenario revisions and their pinned receipts."""
import argparse
import copy
from functools import lru_cache
import hashlib
import json
import re
import struct
import sys
import zipfile
from pathlib import Path


BUNDLE_RELATIVE = Path("src/storage/packages/bundled_campaigns")
RECEIPT_NAME = "source-compression.json"
RUNTIME_RECEIPT_NAME = "program-restoration.json.zlib"
PROGRAM_RECEIPT_SOURCE_NAME = "program-restoration.json"
CAMPAIGN_COUNT = 13
COMPRESSED = zipfile.ZIP_DEFLATED
STORED = zipfile.ZIP_STORED


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")


def valid_sha256(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def runtime_receipt_pin(root):
    policy = (root / "src/storage/saves/compression_package_delta.gd").read_text(encoding="utf-8")
    match = re.search(r'const RECEIPT_SHA256 := "([0-9a-f]{64})"', policy)
    require(match is not None, "source-compression runtime receipt pin is missing")
    return match.group(1)


@lru_cache(maxsize=8)
def load_receipt(root, package_root=None):
    bundle = root / BUNDLE_RELATIVE
    receipt_path = (package_root / RECEIPT_NAME) if package_root is not None else bundle / RECEIPT_NAME
    data = receipt_path.read_bytes()
    require(sha(data) == runtime_receipt_pin(root), "source-compression receipt differs from runtime pin")
    receipt = json.loads(data)
    require(receipt.get("kind") == "realmz-rebuilt.source-compression" and
            receipt.get("formatVersion") == 1, "source-compression receipt kind or version differs")

    application_lock = json.loads((root / "src/storage/packages/application/application-library.lock.json").read_bytes())
    require(receipt.get("applicationPackageHash") == application_lock.get("packageHash"),
            "source-compression receipt application identity differs")
    compiler_revision = receipt.get("compilerRevision")
    require(isinstance(compiler_revision, str) and re.fullmatch(r"[0-9a-f]{40}", compiler_revision),
            "source-compression compiler revision is malformed")

    provenance = json.loads((bundle / "castle-bundled-scenarios.provenance.json").read_bytes())
    inventory = json.loads((bundle / "program-inventory.json").read_bytes())
    require(receipt.get("applicationPackageHash") ==
            provenance.get("acceptedApplicationLibrary", {}).get("packageHash"),
            "source-compression application identity differs from bundled provenance")
    scenarios = {row["campaignId"]: row for row in provenance.get("scenarios", [])}
    reviewed = {row["campaignId"]: row for row in inventory.get("campaigns", [])}
    rows = receipt.get("campaigns")
    require(isinstance(rows, list) and len(rows) == CAMPAIGN_COUNT,
            "source-compression receipt must contain exactly thirteen campaigns")
    require(len(scenarios) == CAMPAIGN_COUNT and len(reviewed) == CAMPAIGN_COUNT,
            "source-compression source catalogs must contain exactly thirteen campaigns")
    by_campaign = {}
    for row in rows:
        require(isinstance(row, dict), "source-compression campaign entry is malformed")
        campaign_id = row.get("campaignId")
        require(isinstance(campaign_id, str) and campaign_id not in by_campaign,
                "duplicate or invalid source-compression campaign identity")
        require(campaign_id in scenarios and campaign_id in reviewed,
                "source-compression campaign is absent from a pinned catalog")
        source = scenarios[campaign_id]
        previous = row.get("previousPackage")
        source_compression = source.get("sourceCompression", {})
        require(source_compression.get("operation") == "compress-retained-native-sources" and
                source_compression.get("receiptFile") == RECEIPT_NAME,
                "bundled provenance lacks the source-compression operation identity")
        expected_previous = source_compression.get("previousPackage")
        require(isinstance(expected_previous, dict) and previous == expected_previous,
                "source-compression predecessor differs from the provenance catalog")
        inventory_row = reviewed[campaign_id]
        require(row.get("file") == source.get("file") == inventory_row.get("file") and
                row.get("campaignId") == inventory_row.get("campaignId"),
                "source-compression campaign filename differs from the pinned catalogs")
        for field in ("packageHash", "contentId", "archiveSha256", "bytes", "compilerRevision"):
            require(row.get(field) == source.get(field),
                    "source-compression " + field + " differs from the bundled provenance catalog")
        require(previous.get("packageHash") == inventory_row.get("packageHash") and
                previous.get("archiveSha256") == inventory_row.get("archiveSha256"),
                "source-compression predecessor differs from the reviewed program inventory")
        require(row.get("compilerRevision") == compiler_revision,
                "source-compression campaign compiler differs from receipt compiler")
        for field in ("packageHash", "contentId", "archiveSha256", "manifestSha256",
                      "previousManifestSha256"):
            require(valid_sha256(row.get(field)), "source-compression " + field + " is malformed")
        require(isinstance(row.get("bytes"), int) and not isinstance(row["bytes"], bool) and
                row["bytes"] > 0, "source-compression archive length is malformed")
        require(isinstance(row.get("previousCompiler"), dict) and
                row["previousCompiler"].get("commit") == previous.get("compilerRevision"),
                "source-compression predecessor compiler identity differs")
        require(isinstance(previous.get("bytes"), int) and not isinstance(previous.get("bytes"), bool) and
                previous["bytes"] > 0 and valid_sha256(previous.get("packageHash")) and
                valid_sha256(previous.get("contentId")) and
                valid_sha256(previous.get("archiveSha256")) and
                isinstance(previous.get("compilerRevision"), str),
                "source-compression predecessor identity is malformed")
        by_campaign[campaign_id] = row
    require(set(by_campaign) == set(scenarios) == set(reviewed),
            "source-compression campaign coverage differs from source catalogs")
    return receipt, by_campaign


def _manifest_package_hash(manifest):
    unhashed = copy.deepcopy(manifest)
    unhashed.pop("packageHash", None)
    return sha(canonical(unhashed))


def _source_only_asset_paths(archive):
    index = json.loads(archive.read("assets/index.json"))
    assets = index.get("assets")
    require(isinstance(assets, list), "scenario asset descriptor list is malformed")
    manifest = json.loads(archive.read("manifest.json"))
    files = manifest.get("files")
    require(isinstance(files, dict), "scenario manifest file inventory is malformed")
    descriptors_by_path = {}
    for asset in assets:
        require(isinstance(asset, dict), "scenario asset descriptor is malformed")
        descriptors_by_path.setdefault(asset.get("path"), []).append(asset)
    source_only = set()
    for path, descriptors in descriptors_by_path.items():
        integrity = files.get(path)
        if not isinstance(integrity, dict):
            continue
        if all(asset.get("kind") == "classic-source" and
               asset.get("id") == "classic-source-" + str(asset.get("sha256")) and
               asset.get("mimeType") == "application/octet-stream" and
               asset.get("resourceType") is None and asset.get("resourceId") is None and
               path == "assets/media/" + str(asset.get("sha256")) + ".bin" and
               asset.get("bytes") == integrity.get("bytes") and
               asset.get("sha256") == integrity.get("sha256")
               for asset in descriptors):
            source_only.add(path)
    return source_only


def _expected_compression(name, source_only_paths):
    if name.endswith(".json") or name in source_only_paths:
        return COMPRESSED
    return STORED


def _raw_member(path, info):
    with path.open("rb") as stream:
        stream.seek(info.header_offset)
        header = stream.read(30)
        require(len(header) == 30 and header[:4] == b"PK\x03\x04", "ZIP local header is malformed")
        values = struct.unpack("<IHHHHHIIIHH", header)
        require(values[2] == info.flag_bits and values[3] == info.compress_type,
                "ZIP local and central compression metadata differ")
        name_length, extra_length = values[-2:]
        name = stream.read(name_length)
        stream.seek(extra_length, 1)
        require(name.decode("utf-8") == info.filename, "ZIP local and central member names differ")
        compressed = stream.read(info.compress_size)
        require(len(compressed) == info.compress_size, "ZIP member payload is truncated")
        return compressed


def _verify_member_encoding(path, archive, source_only_paths):
    infos = archive.infolist()
    names = [info.filename for info in infos]
    require(len(names) == len(set(names)), "duplicate ZIP entries")
    require(names == sorted(names), "ZIP entry order is not canonical")
    for info in infos:
        data = archive.read(info.filename)
        expected = _expected_compression(info.filename, source_only_paths)
        require(info.compress_type == expected,
                "ZIP compression method differs from policy for " + info.filename)
        raw = _raw_member(path, info)
        if expected == STORED:
            require(raw == data, "stored ZIP member bytes differ for " + info.filename)
        # ZIP records the Deflate method, not its level. The pinned receipt binds exact archive bytes;
        # level-9 reproduction belongs to the pinned Providence writer, not this Python reader.
    return infos


def _verify_metadata_retained(candidate_infos, baseline_infos):
    require([row.filename for row in candidate_infos] == [row.filename for row in baseline_infos],
            "ZIP member order differs from the predecessor")
    stable_fields = ("date_time", "comment", "extra", "create_system", "flag_bits",
                     "volume", "internal_attr", "external_attr")
    for candidate, baseline in zip(candidate_infos, baseline_infos):
        for field in stable_fields:
            require(getattr(candidate, field) == getattr(baseline, field),
                    "ZIP member metadata changed for " + candidate.filename + ": " + field)
        versions = ("create_version", "extract_version")
        if candidate.compress_type == baseline.compress_type:
            for field in versions:
                require(getattr(candidate, field) == getattr(baseline, field),
                        "ZIP member metadata changed for " + candidate.filename + ": " + field)
        else:
            expected_version = 20 if candidate.compress_type == COMPRESSED else 10
            require(all(getattr(candidate, field) == expected_version for field in versions),
                    "ZIP version metadata does not match the changed compression method for " +
                    candidate.filename)
        if candidate.filename != "manifest.json":
            for field in ("file_size", "CRC"):
                require(getattr(candidate, field) == getattr(baseline, field),
                        "ZIP member metadata changed for " + candidate.filename + ": " + field)


def validate_candidate_archive(path, row, baseline_path=None):
    archive_bytes = path.read_bytes()
    require(len(archive_bytes) == row.get("bytes") and sha(archive_bytes) == row.get("archiveSha256"),
            "compressed campaign archive size or SHA-256 differs from receipt")
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "duplicate ZIP entries")
        raw_manifest = archive.read("manifest.json")
        manifest = json.loads(raw_manifest)
        require(raw_manifest == canonical(manifest), "compressed campaign manifest is not canonical JSON")
        require(sha(raw_manifest) == row.get("manifestSha256"), "compressed campaign manifest hash differs")
        require(manifest.get("campaignId") == row.get("campaignId") and
                manifest.get("contentId") == row.get("contentId") and
                manifest.get("compiler", {}).get("commit") == row.get("compilerRevision"),
                "compressed campaign manifest identity differs from receipt")
        require(_manifest_package_hash(manifest) == manifest.get("packageHash") == row.get("packageHash"),
                "compressed campaign package hash is not canonical")
        require(set(names) == {"manifest.json", *manifest.get("files", {})},
                "ZIP inventory differs from the campaign manifest")
        require(names == sorted(names), "ZIP entry order is not canonical")
        for name, item in manifest["files"].items():
            data = archive.read(name)
            require(len(data) == item.get("bytes") and sha(data) == item.get("sha256"),
                    "campaign payload integrity failure: " + name)

        source_only_paths = _source_only_asset_paths(archive)
        candidate_infos = _verify_member_encoding(path, archive, source_only_paths)
        normalized = copy.deepcopy(manifest)
        normalized["compiler"] = row["previousCompiler"]
        normalized["packageHash"] = row["previousPackage"]["packageHash"]
        require(sha(canonical(normalized)) == row.get("previousManifestSha256"),
                "reversed manifest differs from pinned predecessor")
        previous = row["previousPackage"]
        require(normalized.get("campaignId") == row["campaignId"] and
                normalized.get("contentId") == previous.get("contentId") and
                normalized.get("compiler", {}).get("commit") == previous.get("compilerRevision"),
                "reversed manifest identity differs from predecessor receipt")

    if baseline_path is not None:
        baseline_bytes = baseline_path.read_bytes()
        require(len(baseline_bytes) == row["previousPackage"].get("bytes") and
                sha(baseline_bytes) == row["previousPackage"].get("archiveSha256"),
                "baseline archive size or SHA-256 differs from predecessor receipt")
        with zipfile.ZipFile(path) as candidate, zipfile.ZipFile(baseline_path) as baseline:
            candidate_infos = candidate.infolist()
            baseline_infos = baseline.infolist()
            _verify_metadata_retained(candidate_infos, baseline_infos)
            require(candidate.namelist() == baseline.namelist(), "campaign ZIP inventory changed")
            for name in candidate.namelist():
                if name != "manifest.json":
                    require(candidate.read(name) == baseline.read(name),
                            "campaign payload changed beyond manifest encoding: " + name)
            baseline_manifest_bytes = baseline.read("manifest.json")
            baseline_manifest = json.loads(baseline_manifest_bytes)
            require(baseline_manifest_bytes == canonical(baseline_manifest) and
                    baseline_manifest.get("compiler") == row["previousCompiler"] and
                    baseline_manifest.get("packageHash") == row["previousPackage"].get("packageHash") and
                    baseline_manifest.get("contentId") == row["previousPackage"].get("contentId"),
                    "baseline manifest differs from exact predecessor identity")
            require(sha(baseline_manifest_bytes) == row["previousManifestSha256"],
                    "baseline manifest SHA differs from predecessor pin")
            require(candidate.comment == baseline.comment,
                    "ZIP archive comment changed")
            source_only_paths = _source_only_asset_paths(candidate)
            candidate_info = _verify_member_encoding(path, candidate, source_only_paths)
            _verify_metadata_retained(candidate_info, baseline_infos)
    return normalized


def verify_runtime_receipt(root, package_root=None):
    bundle = root / BUNDLE_RELATIVE
    if package_root is None:
        output_path = bundle / RUNTIME_RECEIPT_NAME
        receipt_path = bundle / PROGRAM_RECEIPT_SOURCE_NAME
    else:
        output_path = package_root / RUNTIME_RECEIPT_NAME
        receipt_path = bundle / PROGRAM_RECEIPT_SOURCE_NAME
    import compress_program_receipt
    return compress_program_receipt.verify_files(receipt_path, output_path, reproduce=False)


def verify(root, package_root=None, baseline_root=None):
    bundle = root / BUNDLE_RELATIVE
    if package_root is None:
        package_root = bundle
    receipt, rows = load_receipt(root, package_root if package_root != bundle else None)
    verify_runtime_receipt(root, package_root if package_root != bundle else None)
    for campaign_id, row in rows.items():
        path = package_root / row["file"]
        baseline_path = baseline_root / row["file"] if baseline_root is not None else None
        validate_candidate_archive(path, row, baseline_path)
    print("Verified source-compressed package encoding for", len(rows), "campaigns.")
    return receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", type=Path,
                        help="package directory (default: bundled campaign directory)")
    parser.add_argument("--baseline-root", type=Path,
                        help="optional directory containing the exact predecessor archives")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="repository root (default: resolved from this script)")
    args = parser.parse_args(argv)
    try:
        verify(args.root, args.package_root, args.baseline_root)
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
        print("Source-compression verification failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
