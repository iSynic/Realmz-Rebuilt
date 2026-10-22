"""Verify the reviewed native-program inventory and exact reversible corrections."""
import argparse
import copy
import json
import re
from pathlib import Path
import zipfile
from audit_native_programs import canonical, sha


def require(condition, message):
    if not condition:
        raise ValueError(message)


def require_campaign_coverage(rows, expected_campaigns, message):
    campaign_ids = [row["campaignId"] for row in rows]
    require(len(campaign_ids) == len(expected_campaigns) and len(set(campaign_ids)) == len(campaign_ids) and
            set(campaign_ids) == set(expected_campaigns), message)
    return {row["campaignId"]: row for row in rows}


def remove_rows(target, additions):
    for row in reversed(additions):
        matches = [r for r in target if r["id"] == row["id"]]
        require(matches == [row], "missing, duplicate, or altered restored record " + str(row["id"]))
        target.remove(row)


def reverse(documents, correction):
    recipe = correction["recipe"]
    for addition in recipe["monsterSetIntroductions"]:
        sets = documents["content.json"]["monsterSets"]
        matches = [row for row in sets if row["setId"] == addition["setId"]]
        require(matches == [addition], "introduced monster set changed")
        sets.remove(matches[0])
    for change in reversed(recipe["cellChanges"]):
        target = next(m for m in documents["world.json"]["maps"] if m["id"] == change["mapId"])
        cell = target["cells"][change["index"]]
        require(cell[4] == change["after"], "restored AP cell references changed")
        cell[4] = copy.deepcopy(change["before"])
    for change in recipe["randomRectangleAdditions"]:
        target = next(m for m in documents["world.json"]["maps"] if m["id"] == change["mapId"])
        remove_rows(target["randomRectangles"], [change["record"]])
    for change in recipe["randomRectangleLayouts"]:
        target = next(m for m in documents["world.json"]["maps"] if m["id"] == change["mapId"])
        require(target["randomRectangles"] == change["after"], "native random-slot layout differs")
        target["randomRectangles"] = copy.deepcopy(change["before"])
    for group in recipe["monsterSetAdditions"]:
        target = next(s for s in documents["content.json"]["monsterSets"] if s["setId"] == group["setId"])
        remove_rows(target["monsters"], group["monsters"])
    for change in recipe["programReplacements"]:
        target = documents["scenario.json"]["programs"]
        matches = [(i, p) for i, p in enumerate(target) if p["id"] == change["after"]["id"]]
        require(len(matches) == 1 and matches[0][1] == change["after"], "native operand restoration changed")
        target[matches[0][0]] = copy.deepcopy(change["before"])
    for change in recipe.get("textReplacements", []):
        require(change["family"] == "items", "unapproved text replacement family")
        target = documents["content.json"][change["family"]]
        matches = [(i, row) for i, row in enumerate(target) if row["id"] == change["after"]["id"]]
        require(len(matches) == 1 and matches[0][1] == change["after"], "source text restoration changed")
        target[matches[0][0]] = copy.deepcopy(change["before"])
    for document, groups in recipe["additions"].items():
        for field, rows in groups.items():
            remove_rows(documents[document][field], rows)
    if "assets/index.json" in documents and "assetIndexAdditions" in recipe:
        asset_index = documents["assets/index.json"]
        remove_rows(asset_index["assets"], recipe["assetIndexAdditions"])
        for change in recipe["assetMetadataChanges"]:
            matches = [row for row in asset_index["assets"] if row["id"] == change["after"]["id"]]
            require(matches == [change["after"]], "derived PNG metadata differs")
            asset_index["assets"][asset_index["assets"].index(matches[0])] = copy.deepcopy(change["before"])
        require(sha(canonical(asset_index)) == recipe["previousAssetIndexSha256"],
                "undeclared change in assets/index.json")
    for name, expected in recipe["previousDocuments"].items():
        require(sha(canonical(documents[name])) == expected, "undeclared change in " + name)
    return documents


def verify_programs(programs, expected):
    actual = {p["id"]: sha(canonical(p)) for p in programs}
    require(len(actual) == len(programs), "duplicate program identity")
    require(actual.keys() == expected.keys(), "program inventory differs: missing=" + str(sorted(expected.keys() - actual.keys())) +
            " extra=" + str(sorted(actual.keys() - expected.keys())))
    require(actual == expected, "program instructions or branch context differ from the reviewed native inventory")


def source_annex_recipe(correction):
    require(isinstance(correction, dict), "campaign lacks an exact source-preservation correction")
    recipe = correction.get("recipe")
    require(isinstance(recipe, dict), "source-preservation correction recipe is missing")
    require({"assetIndexAdditions", "payloadAdditions", "previousAssetIndexSha256"} <= recipe.keys(),
            "source annex recipe is incomplete")
    require(isinstance(recipe["assetIndexAdditions"], list) and isinstance(recipe["payloadAdditions"], list),
            "source annex inventories must be arrays")
    require(isinstance(recipe["previousAssetIndexSha256"], str) and
            re.fullmatch(r"[0-9a-f]{64}", recipe["previousAssetIndexSha256"]) is not None,
            "source annex prior asset index digest is malformed")
    return recipe


def verify_source_diagnostics(finding):
    native_files = finding.get("nativeSourceFiles")
    require(isinstance(native_files, list), "independent native source inventory is missing")
    sources = {}
    for source in native_files:
        require(isinstance(source, dict) and isinstance(source.get("path"), str) and
                isinstance(source.get("bytes"), int) and not isinstance(source.get("bytes"), bool) and
                isinstance(source.get("sha256"), str), "independent native source entry is malformed")
        require(source["path"] not in sources, "duplicate independent native source path")
        sources[source["path"]] = (source["bytes"], source["sha256"])
    families = finding.get("semanticProgramFamilies")
    require(isinstance(families, dict), "semantic program family inventory is missing")
    for filename in ("Data DD", "Data DDD", "Data ED3", "Data ED", "Data ED2"):
        require(families.get(filename, {}).get("status") == "complete",
                "semantic projection is incomplete for native program family " + filename)
    require(families.get("Data EDCD", {}).get("status") == "validated-by-native-program-decoder",
            "native Extra Code operand table was not validated")
    omissions = finding.get("importedSourceOmissions")
    require(isinstance(omissions, list), "imported source omission classifications are missing")
    seen = set()
    for omission in omissions:
        require(isinstance(omission, dict), "imported source omission is malformed")
        path = omission.get("path")
        require(isinstance(path, str) and path not in seen and path in sources,
                "imported source omission is not in the independent source inventory")
        seen.add(path)
        require(sources[path] == (omission.get("bytes"), omission.get("sha256")),
                "imported source omission identity differs from independent source inventory")
        require(omission.get("rawSourceDisposition") == "retained-by-verified-package-source-annex" and
                isinstance(omission.get("semanticProjection"), dict),
                "raw source retention and semantic projection are not separately classified")
        expected_semantics = families.get(path, dict(kind="not-a-native-program-family", status="raw-source-only"))
        require(omission["semanticProjection"] == expected_semantics,
                "imported source omission semantic classification differs from its native family")


def verify_archive(path, record, correction=None, finding=None, normalized_manifest=None,
                  expected_archive_sha256=None):
    recipe = source_annex_recipe(correction)
    require(finding is not None, "source annex requires independent native source findings")
    verify_source_diagnostics(finding)
    expected_archive_sha256 = expected_archive_sha256 or record["archiveSha256"]
    require(sha(path.read_bytes()) == expected_archive_sha256, "archive differs from audited content")
    with zipfile.ZipFile(path) as archive:
        from audit_record_quarantines import verify_retained
        verify_retained(record["campaignId"], finding["nativeRecordDispositions"], archive)
        require(len(archive.namelist()) == len(set(archive.namelist())), "duplicate ZIP entries")
        manifest_bytes = archive.read("manifest.json")
        manifest = json.loads(manifest_bytes)
        if normalized_manifest is not None:
            require(manifest.get("packageHash") != record["packageHash"] and
                    normalized_manifest.get("packageHash") == record["packageHash"],
                    "compressed package manifest was not reversed to the audited identity")
            manifest = normalized_manifest
        require(manifest["packageHash"] == record["packageHash"], "package identity differs")
        require(correction.get("packageHash") == record["packageHash"],
                "source-preservation correction package identity differs")
        require(set(archive.namelist()) == {"manifest.json", *manifest["files"]}, "manifest inventory differs")
        for name, info in manifest["files"].items():
            data = archive.read(name)
            require(sha(data) == info["sha256"] and len(data) == info["bytes"], "payload integrity failure")
        scenario = json.loads(archive.read("scenario.json"))
        native_digests = finding.get("nativeProgramDigests")
        require(isinstance(native_digests, dict) and
                len(native_digests) == finding.get("nativeProgramCount"),
                "independent native program digest inventory is missing or incomplete")
        reviewed_digests = dict(native_digests)
        for disposition in finding.get("approvedDifferences", []):
            program_id = disposition.get("programId")
            require(program_id in reviewed_digests and
                    reviewed_digests[program_id] == disposition.get("nativeSha256"),
                    "approved correction does not match independent native program digest")
            reviewed_digests[program_id] = disposition.get("reviewedSha256")
        require(reviewed_digests == record["programDigests"],
                "reviewed package program inventory differs from independent native digests")
        verify_programs(scenario["programs"], reviewed_digests)
        documents = {name: json.loads(archive.read(name)) for name in recipe["previousDocuments"]}
        documents["assets/index.json"] = json.loads(archive.read("assets/index.json"))
        reverse(documents, correction)
        coverage = verify_source_annex(archive, manifest, correction, finding["nativeSourceFiles"])
        require(correction.get("sourceAnnexCoverage") == coverage and
                record.get("sourceAnnexCoverage") == coverage and
                finding.get("sourceAnnexCoverage") == coverage,
                "recorded source preservation coverage differs from verified inventory")
        require({name: info["sha256"] for name, info in manifest["files"].items()
                 if name not in documents and name not in set(coverage["payloadPaths"])} == correction["unchangedPayloads"],
                "unrelated payload changed")


def expected_descriptor(identity, label, kind, mime_type, digest, byte_length, path):
    return dict(id=identity, label=label, kind=kind, mimeType=mime_type,
                resourceType=None, resourceId=None, scenarioMusicSlot=None,
                bytes=byte_length, sha256=digest, path=path,
                width=None, height=None, durationMs=None, sampleRate=None, channels=None,
                tileWidth=None, tileHeight=None, columns=None, rows=None, landlook=None, baseTile=None)


def verify_source_annex(archive, manifest, correction, native_source_files):
    recipe = correction["recipe"]
    additions = recipe["assetIndexAdditions"]
    payload_rows = recipe["payloadAdditions"]
    require(isinstance(additions, list) and isinstance(payload_rows, list), "source annex inventories must be arrays")
    require(isinstance(native_source_files, list), "independent native source inventory is missing")
    require(native_source_files, "independent native source inventory is empty")
    expected_sources = {}
    for source in native_source_files:
        path = source.get("path")
        digest = source.get("sha256")
        byte_length = source.get("bytes")
        require(isinstance(path, str) and isinstance(digest, str) and
                isinstance(byte_length, int) and not isinstance(byte_length, bool) and byte_length >= 0,
                "independent native source entry is malformed")
        require(re.fullmatch(r"[0-9a-f]{64}", digest) is not None, "independent source hash is malformed")
        require(path and not path.startswith("/") and "\\" not in path and ":" not in path and
                all(part not in ("", ".", "..") for part in path.split("/")),
                "independent native source path is unsafe")
        require(path not in expected_sources, "duplicate independent native source path")
        expected_sources[path] = (digest, byte_length)

    payload_by_path = {}
    for row in payload_rows:
        require(isinstance(row, dict) and set(row) == {"path", "bytes", "sha256"},
                "source payload addition shape differs")
        path, byte_length, digest = row["path"], row["bytes"], row["sha256"]
        require(isinstance(path, str) and path.startswith("assets/media/") and
                "/" not in path[len("assets/media/"):] and "\\" not in path,
                "source payload path is unsafe")
        require(isinstance(byte_length, int) and not isinstance(byte_length, bool) and byte_length >= 0 and
                isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
                "source payload metadata is malformed")
        require(path not in payload_by_path, "duplicate source payload path")
        require(path in manifest["files"], "source payload is missing from archive manifest")
        data = archive.read(path)
        require(len(data) == byte_length and sha(data) == digest, "source payload bytes or hash differ")
        payload_by_path[path] = (digest, byte_length, data)

    expected_payloads = {}
    unique_sources = {}
    for path, (digest, byte_length) in expected_sources.items():
        payload_path = "assets/media/" + digest + ".bin"
        existing = unique_sources.setdefault(digest, byte_length)
        require(existing == byte_length, "identical source hashes declare different lengths")
        expected_payloads[payload_path] = (digest, byte_length)

    added_by_id = {}
    for descriptor in additions:
        require(isinstance(descriptor, dict) and isinstance(descriptor.get("id"), str),
                "source asset descriptor is malformed")
        require(descriptor["id"] not in added_by_id, "duplicate source asset descriptor")
        added_by_id[descriptor["id"]] = descriptor
    receipt_descriptors = [row for row in additions if row.get("kind") == "classic-source-index"]
    source_descriptors = [row for row in additions if row.get("kind") == "classic-source"]
    require(len(receipt_descriptors) == 1 and len(source_descriptors) == len(unique_sources),
            "source asset descriptor count differs from native source inventory")
    require(len(receipt_descriptors) + len(source_descriptors) == len(additions),
            "unexpected asset index annex descriptor")

    expected_descriptors = {}
    for digest, byte_length in unique_sources.items():
        path = "assets/media/" + digest + ".bin"
        expected_descriptors["classic-source-" + digest] = expected_descriptor(
            "classic-source-" + digest, "Retained Classic source bytes", "classic-source",
            "application/octet-stream", digest, byte_length, path)

    receipt_descriptor = receipt_descriptors[0]
    receipt_path = receipt_descriptor.get("path")
    require(isinstance(receipt_path, str) and receipt_path.startswith("assets/media/") and
            receipt_path.endswith(".json") and "/" not in receipt_path[len("assets/media/"):],
            "source receipt asset path is malformed")
    require(receipt_path in payload_by_path, "source receipt payload is missing")
    receipt_digest, receipt_length, receipt_bytes = payload_by_path[receipt_path]
    require(receipt_path == "assets/media/" + receipt_digest + ".json", "source receipt path is not content-addressed")
    require(receipt_bytes == canonical(json.loads(receipt_bytes)), "source receipt is not canonical JSON")
    expected_descriptors["classic-source-index-" + receipt_digest] = expected_descriptor(
        "classic-source-index-" + receipt_digest, "Retained Classic source index", "classic-source-index",
        "application/json", receipt_digest, receipt_length, receipt_path)
    require(added_by_id == expected_descriptors, "source asset descriptors differ from exact inert inventory")
    expected_payloads[receipt_path] = (receipt_digest, receipt_length)
    require({path: (digest, byte_length) for path, (digest, byte_length, _) in payload_by_path.items()} ==
            expected_payloads, "source payload inventory has missing or extra annex payloads")

    receipt = json.loads(receipt_bytes)
    require(receipt.get("kind") == "realmz2.classic-source-retention" and receipt.get("schemaVersion") == 1,
            "source receipt kind or version differs")
    source_rows = receipt.get("sources")
    require(isinstance(source_rows, list), "source receipt inventory is malformed")
    receipt_sources = {}
    for source in source_rows:
        require(isinstance(source, dict), "source receipt entry is malformed")
        path = source.get("nativePath")
        digest = source.get("sha256")
        byte_length = source.get("byteLength")
        require(isinstance(path, str) and path not in receipt_sources, "duplicate or invalid source receipt path")
        require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None and
                isinstance(byte_length, int) and not isinstance(byte_length, bool) and byte_length >= 0,
                "source receipt hash or length is malformed")
        require(source.get("blob") == "sha256:" + str(digest), "source receipt blob identity differs")
        require(source.get("assetPath") == "assets/media/" + str(digest) + ".bin",
                "source receipt payload mapping differs")
        receipt_sources[path] = (digest, byte_length)
    require(receipt_sources == expected_sources, "source receipt differs from independent native source inventory")

    index = json.loads(archive.read("assets/index.json"))
    index_assets = index.get("assets", [])
    require(isinstance(index_assets, list), "assets/index.json inventory is malformed")
    require(all(sum(1 for item in index_assets if item.get("id") == row["id"] and item == row) == 1
                for row in additions),
            "source annex descriptor is missing or altered in assets/index.json")
    return dict(sourceCount=len(expected_sources), uniquePayloadCount=len(unique_sources),
                payloadPaths=sorted(payload_by_path), sourceBytes=sum(v[1] for v in expected_sources.values()),
                receiptPath=receipt_path, receiptSha256=receipt_digest)


def restoration(root):
    path = root / "src/storage/packages/bundled_campaigns/program-restoration.json"
    policy = (root / "src/storage/saves/program_package_delta.gd").read_text(encoding="utf-8")
    pin = re.search(r'const RECEIPT_SHA256 := "([0-9a-f]{64})"', policy)
    require(pin and sha(path.read_bytes()) == pin[1], "program restoration receipt differs from runtime pin")
    report = json.loads(path.read_bytes())
    require(report["kind"] == "realmz-rebuilt.program-restoration" and report["formatVersion"] == 1,
            "program restoration receipt version")
    return report


def source_compression(root, package_root=None, verify_endpoint=False):
    from verify_source_compression import load_receipt, verify_runtime_receipt
    receipt, rows = load_receipt(root, package_root)
    if verify_endpoint:
        verify_runtime_receipt(root, package_root)
    return receipt, rows


def correction_for(root, campaign_id, package_hash):
    _, compression_rows = source_compression(root)
    compression = compression_rows.get(campaign_id)
    if compression is not None and package_hash == compression.get("packageHash"):
        package_hash = compression["previousPackage"]["packageHash"]
    matches = [row for row in restoration(root)["campaigns"]
               if row["campaignId"] == campaign_id and row["packageHash"] == package_hash]
    require(len(matches) <= 1, "duplicate program correction")
    return matches[0] if matches else None


def reverse_current_documents(archive, documents, root):
    manifest = json.loads(archive.read("manifest.json"))
    correction = correction_for(root, manifest["campaignId"], manifest["packageHash"])
    if correction:
        reverse(documents, correction)
    return correction


def verify(root, package_root=None):
    bundle = root / "src/storage/packages/bundled_campaigns"
    report = json.loads((bundle / "program-inventory.json").read_bytes())
    require(report["kind"] == "realmz-rebuilt.reviewed-program-inventory" and report["formatVersion"] == 1, "inventory version")
    require(len(report["campaigns"]) == 13, "inventory must cover all thirteen campaigns")
    catalog = json.loads((bundle / "castle-bundled-scenarios.provenance.json").read_bytes())
    actual_pairs = [(r["campaignId"], r["file"]) for r in report["campaigns"]]
    expected_pairs = [(r["campaignId"], r["file"]) for r in catalog["scenarios"]]
    require(len(set(actual_pairs)) == len(actual_pairs) and set(actual_pairs) == set(expected_pairs),
            "reviewed campaign identities or filenames differ from bundled provenance")
    receipt = restoration(root)
    _, compression_rows = source_compression(root, package_root, verify_endpoint=True)
    findings_report = json.loads((bundle / "program-audit-findings.json").read_bytes())
    require(findings_report["kind"] == "realmz-rebuilt.program-audit-findings" and
            findings_report["formatVersion"] == 1, "program audit findings version")
    findings = require_campaign_coverage(findings_report["campaigns"], {r[0] for r in expected_pairs},
                                         "program audit findings campaign inventory differs")
    require(sha((bundle / "program-restoration.json").read_bytes()) == report["restorationSha256"], "restoration receipt differs")
    require(sha((bundle / "program-audit-findings.json").read_bytes()) == report["findingsSha256"],
            "independent native program/source findings differ from inventory pin")
    expected_campaigns = {r[0] for r in expected_pairs}
    corrections = require_campaign_coverage(receipt["campaigns"], expected_campaigns,
                                            "program restoration must contain one correction for every bundled campaign")
    from audit_definition_comparison import verify_comparison, verify_native_text
    comparisons = require_campaign_coverage(findings_report["definitionComparisons"]["campaigns"], expected_campaigns,
                                             "definition comparison must cover all thirteen campaigns")
    with zipfile.ZipFile(root / "src/storage/packages/application/realmz-classic-application-library.realmz2") as app_archive:
        application = json.loads(app_archive.read("content.json"))
    verify_native_text(findings_report["nativeTextDispositions"], package_root or bundle, comparisons, application)
    for record in report["campaigns"]:
        comparison = comparisons[record["campaignId"]]
        require(comparison["packageHash"] == record["packageHash"] and comparison["archiveSha256"] == record["archiveSha256"],
                "definition comparison differs from exact package identity")
        archive_path = (package_root or bundle) / record["file"]
        compression = compression_rows[record["campaignId"]]
        from verify_source_compression import validate_candidate_archive
        normalized_manifest = validate_candidate_archive(archive_path, compression)
        with zipfile.ZipFile(archive_path) as source:
            verify_comparison(json.loads(source.read("content.json")), comparison, corrections[record["campaignId"]], application)
        require(Path(record["file"]).name == record["file"], "nonlocal package filename")
        verify_archive((package_root or bundle) / record["file"], record,
                       corrections.get(record["campaignId"]), findings[record["campaignId"]],
                       normalized_manifest, compression["archiveSha256"])
    print("Verified all 13 reviewed program inventories and exact reversible package deltas.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", type=Path)
    args = parser.parse_args()
    verify(Path(__file__).resolve().parent.parent, args.package_root)
