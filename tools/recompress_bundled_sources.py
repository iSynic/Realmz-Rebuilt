"""Create no-clobber Providence compression successors from the pinned audited bundle."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def write(path, value):
    path.write_bytes((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode())


def generate(baseline, output, compiler, revision):
    if output.exists():
        raise ValueError("output directory already exists")
    catalog = json.loads((baseline / "castle-bundled-scenarios.provenance.json").read_bytes())
    if len(catalog["scenarios"]) != 13:
        raise ValueError("expected the thirteen audited campaigns")
    output.mkdir(parents=True)
    receipt = dict(kind="realmz-rebuilt.source-compression", formatVersion=1,
                   applicationPackageHash=catalog["acceptedApplicationLibrary"]["packageHash"],
                   compilerRevision=revision, campaigns=[])
    for entry in catalog["scenarios"]:
        source = baseline / entry["file"]
        if source.name != entry["file"] or sha(source.read_bytes()) != entry["archiveSha256"]:
            raise ValueError("baseline differs from pinned catalog")
        previous = {key: entry[key] for key in ("packageHash", "contentId", "archiveSha256", "bytes", "compilerRevision")}
        destination = output / entry["file"]
        subprocess.run([str(compiler), str(source), str(destination)], check=True)
        with zipfile.ZipFile(source) as before, zipfile.ZipFile(destination) as after:
            if before.namelist() != after.namelist():
                raise ValueError("archive inventory/order changed")
            for name in before.namelist():
                if name != "manifest.json" and before.read(name) != after.read(name):
                    raise ValueError("payload changed: " + name)
            original_bytes = before.read("manifest.json")
            current_bytes = after.read("manifest.json")
        original, current = json.loads(original_bytes), json.loads(current_bytes)
        if current["compiler"]["commit"] != revision or current["contentId"] != original["contentId"]:
            raise ValueError("compiler identity or content identity differs")
        reversed_manifest = copy.deepcopy(current)
        reversed_manifest["compiler"] = original["compiler"]
        reversed_manifest["packageHash"] = original["packageHash"]
        if canonical(reversed_manifest) != original_bytes:
            raise ValueError("undeclared manifest change")
        row = dict(campaignId=entry["campaignId"], file=entry["file"],
                   packageHash=current["packageHash"], contentId=current["contentId"],
                   archiveSha256=sha(destination.read_bytes()), bytes=destination.stat().st_size,
                   compilerRevision=revision, manifestSha256=sha(current_bytes),
                   previousManifestSha256=sha(original_bytes), previousCompiler=original["compiler"],
                   previousPackage=previous)
        receipt["campaigns"].append(row)
        entry.update({key: row[key] for key in ("packageHash", "contentId", "archiveSha256", "bytes", "compilerRevision")})
        entry["sourceCompression"] = dict(operation="compress-retained-native-sources",
                                          receiptFile="source-compression.json", previousPackage=previous)
    write(output / "source-compression.json", receipt)
    write(output / "castle-bundled-scenarios.provenance.json", catalog)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--compiler-commit", required=True)
    args = parser.parse_args()
    generate(args.baseline_root.resolve(), args.output.resolve(), args.compiler.resolve(), args.compiler_commit)
