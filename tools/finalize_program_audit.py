"""Bind independently audited native programs to exact, reversible candidates."""
import argparse
import json
from pathlib import Path
import zipfile
from audit_native_programs import archive, canonical, sha
from audit_definition_comparison import compare as compare_definitions
from verify_program_restoration import (require, require_campaign_coverage, reverse,
                                        source_annex_recipe, verify_programs, verify_source_annex)


# Preserve exact previously reviewed differences while restoring missing native code.
APPROVED = {
    "scenario-trouble-in-the-sword-lands": {"xap:330": "pinned Trouble payment restoration; nonconsuming Extra Code omitted"},
    "scenario-war-in-the-sword-lands": {
        **{key: "approved War branch correction" for key in ("simple:52:result:1", "xap:3329", "xap:3367")},
        **{key: "retained prior projection of incidental Extra Code; source operand unchanged" for key in
           ("trigger:Data DD:10:88", "xap:1670", "xap:1672", "xap:1700", "xap:2059")},
    },
}


def write(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def unique_references(rows):
    result = {}
    for row in rows:
        key = (str(row["source"]), row["slot"], row["targetKind"], str(row["target"]))
        result.setdefault(key, row)
    return list(result.values())


def package_asset_index(path):
    with zipfile.ZipFile(path) as package:
        return json.loads(package.read("assets/index.json"))


def package_payloads(package, excluded):
    return {name: info["sha256"] for name, info in package["manifest"]["files"].items()
            if name not in excluded}


def campaign(bundle, evidence, candidates):
    identity = evidence["campaignId"]
    filename = identity + ".realmz2"
    old = archive(bundle / filename)
    old_asset_index = package_asset_index(bundle / filename)
    path = candidates / filename
    require(path.is_file(), "candidate package is missing: " + filename)
    current = archive(path)
    require(not evidence["nativeToProjection"]["missing"] and not evidence["nativeToProjection"]["extra"] and
            not evidence["nativeToProjection"]["changed"],
            "fresh projection differs from decoded native instructions")
    require(not evidence["projectionToCandidate"]["missing"], "candidate still omits projected programs")
    require(not evidence["independentOnly"], "independently required program missing from compiler closure")
    native = {p["id"]: p for p in evidence["nativePrograms"]}
    previous = {p["id"]: p for p in old["scenario"]["programs"]}
    exceptions = APPROVED.get(identity, {})
    require(set(evidence["projectionToCandidate"]["changed"]) == set(exceptions),
            "unreviewed shared-program difference: " + identity)
    require(len(native) == len(evidence["nativePrograms"]), "duplicate independent native program identity")
    native_digests = {key: sha(canonical(program)) for key, program in native.items()}
    expected = dict(native_digests)
    semantic_families = evidence["semanticProgramFamilies"]
    for source_family in ("Data DD", "Data DDD", "Data ED3", "Data ED", "Data ED2"):
        require(semantic_families.get(source_family, {}).get("status") == "complete",
                "native program family projection is incomplete: " + source_family)
    require(semantic_families.get("Data EDCD", {}).get("status") == "validated-by-native-program-decoder",
            "native Extra Code operand table was not validated")
    dispositions = []
    candidate_by_id = {program["id"]: program for program in current["scenario"]["programs"]}
    for key, reason in exceptions.items():
        require(key in native and key in previous, "approved difference lacks native or original program: " + key)
        require(candidate_by_id.get(key) == previous[key], "previously approved program changed: " + key)
        expected[key] = sha(canonical(previous[key]))
        dispositions.append(dict(programId=key, classification="intentional-correction",
            reason=reason, nativeSha256=sha(canonical(native[key])), reviewedSha256=sha(canonical(previous[key]))))
    verify_programs(current["scenario"]["programs"], expected)
    correction_path = candidates / (identity + ".receipt.json")
    correction = json.loads(correction_path.read_bytes()) if correction_path.exists() else None
    recipe = source_annex_recipe(correction)
    documents = {key + ".json": current[key] for key in ("scenario", "content", "world")}
    documents["assets/index.json"] = package_asset_index(path)
    reverse(documents, correction)
    require(documents["assets/index.json"] == old_asset_index,
            "reversing the source annex does not reproduce the original asset index")
    require("nativeSourceFiles" in evidence,
            "full independent native source inventory is required to finalize source preservation")
    with zipfile.ZipFile(path) as candidate_archive:
        source_annex_coverage = verify_source_annex(candidate_archive, current["manifest"], correction,
                                                    evidence["nativeSourceFiles"])
    native_source_by_path = {row["path"]: row for row in evidence["nativeSourceFiles"]}
    imported_source_omissions = []
    for omission in evidence["importedSourceOmissions"]:
        source = native_source_by_path.get(omission.get("path"))
        require(source is not None and source["bytes"] == omission.get("bytes") and
                source["sha256"] == omission.get("sha256"),
                "imported-source omission differs from independent native source inventory")
        require(omission.get("rawSourceDisposition") == "pinned-native-source-awaiting-package-annex" and
                isinstance(omission.get("semanticProjection"), dict),
                "imported-source omission lacks separate raw and semantic classifications")
        imported_source_omissions.append({**omission,
            "rawSourceDisposition": "retained-by-verified-package-source-annex"})
    added_payload_paths = set(source_annex_coverage["payloadPaths"])
    excluded = set(documents) | added_payload_paths
    old_unchanged = package_payloads(old, excluded)
    candidate_unchanged = package_payloads(current, excluded)
    require(candidate_unchanged == old_unchanged,
            "candidate changed or removed preexisting package payloads")
    correction["unchangedPayloads"] = old_unchanged
    correction["sourceAnnexCoverage"] = source_annex_coverage
    graph = evidence["independentReferences"]
    unsafe = unique_references(graph["unresolved"])
    require(all(row["targetKind"] == "unsafe-inline" and not 0 <= int(row["target"].rsplit(":", 1)[1]) < 4
                for row in unsafe), "unresolved valid control-flow semantics")
    record = dict(campaignId=identity, file=filename, archiveSha256=sha(path.read_bytes()) if path.exists() else sha((bundle / filename).read_bytes()),
                  packageHash=current["manifest"]["packageHash"], programDigests=expected)
    record["sourceAnnexCoverage"] = source_annex_coverage
    findings = dict(campaignId=identity, nativeSourceTreeSha256=evidence["sourceIdentity"],
        sourceFiles=evidence["sourceFiles"], nativeSourceFiles=evidence["nativeSourceFiles"],
        importedSourceOmissions=imported_source_omissions,
        semanticProgramFamilies=evidence["semanticProgramFamilies"],
        historicalImportLosses=[dict(issue=issue, disposition="recovered-by-complete-native-redecode-and-verified-projection")
                                for issue in evidence["importIssues"]],
        sourceAnnexCoverage=source_annex_coverage, nativeProgramCount=evidence["nativeProgramCount"],
        nativeProgramDigests=native_digests,
        emittedProgramCount=len(expected), uniqueRestoredPrograms=evidence["uniqueMissingPrograms"],
        affectedCallSites=evidence["affectedCallSites"], omissions=evidence["discrepancies"],
        approvedDifferences=dispositions,
        unavailableNativeTargets=unique_references(graph["missingNativeRecords"]),
        invalidInlineTargets=unsafe, nativeDataReferences=graph["nativeDataReferences"],
        dynamicEncounterDomains=unique_references(graph["dynamicContexts"]),
        independentRequiredPrograms=graph["reachableProgramIds"],
        compilerConservativePrograms=evidence["compilerOnly"],
        nativeReferenceMetadataDifferences=evidence["nativeReferenceMetadata"]["issues"],
        unprojectedNativeRecords=evidence["nativeReferenceMetadata"]["unprojectedNativeRecords"],
        nativeRecordDispositions=evidence["nativeRecordDispositions"],
        nativeHookCandidates=[{**row, "programBodyAvailable": "xap:%d" % abs(row["nativeValue"]) in native,
                               "executionStatus": "not-demonstrated"}
                              for row in evidence["nativeReferenceMetadata"]["dormantHookCandidates"]],
        releaseStages=evidence["releaseStages"],
        executionEvidence=evidence["executionEvidence"])
    return record, correction, findings


def main(args):
    root = Path(__file__).resolve().parent.parent
    pipeline = json.loads(args.pipeline.read_bytes())
    require(pipeline["kind"] == "realmz-rebuilt.omitted-program-audit" and pipeline["formatVersion"] == 1,
            "unexpected pipeline report")
    catalog = json.loads((args.baseline_bundle / "castle-bundled-scenarios.provenance.json").read_bytes())
    expected_campaigns = {row["campaignId"] for row in catalog["scenarios"]}
    require_campaign_coverage(pipeline["results"], expected_campaigns,
                              "native audit must cover every one of the thirteen bundled campaigns")
    args.output.mkdir(exist_ok=False)
    campaigns, corrections, findings = [], [], []
    for row in pipeline["results"]:
        record, correction, finding = campaign(args.baseline_bundle, row, args.candidates)
        require(record["file"] == next(entry["file"] for entry in catalog["scenarios"]
                                       if entry["campaignId"] == record["campaignId"]),
                "final inventory filename differs from pinned campaign catalog")
        campaigns.append(record)
        corrections.append(correction)
        findings.append(finding)
    receipt = dict(kind="realmz-rebuilt.program-restoration", formatVersion=1,
        compilerRevision=pipeline["compilerRevision"], applicationArchiveSha256=pipeline["applicationArchiveSha256"],
        applicationPackageHash=json.loads((root / "src/storage/packages/application/application-library.lock.json").read_bytes())["packageHash"],
        toolSources={name: sha((root / "tools" / name).read_bytes()) for name in
                     ("audit_program_projection.rs", "restore_scenario_programs.rs", "prepare_program_restoration.py",
                      "finalize_program_audit.py", "verify_program_restoration.py", "audit_definition_comparison.py")},
        campaigns=corrections)
    write(args.output / "program-restoration.json", receipt)
    definition_comparisons = compare_definitions(args.candidates, args.baseline_bundle, args.projections,
        args.output / "program-restoration.json", root / "src/storage/packages/application/realmz-classic-application-library.realmz2")
    findings_report = dict(kind="realmz-rebuilt.program-audit-findings", formatVersion=1,
        compilerRevision=pipeline["compilerRevision"], castleRevision=pipeline["castleRevision"],
        castleSources=pipeline["castleSources"], toolSources=pipeline["toolSources"], campaigns=findings,
        definitionComparisons=definition_comparisons,
        nativeTextDispositions=json.loads(args.text_dispositions.read_bytes()),
        limitations=["Static preservation and reachability are not demonstrated gameplay or campaign certification.",
                     "Authored unavailable targets remain exact; no replacement content is inferred."])
    write(args.output / "program-audit-findings.json", findings_report)
    inventory = dict(kind="realmz-rebuilt.reviewed-program-inventory", formatVersion=1,
        compilerRevision=pipeline["compilerRevision"], castleRevision=pipeline["castleRevision"],
        sourceAuditSha256=sha(args.pipeline.read_bytes()),
        restorationSha256=sha((args.output / "program-restoration.json").read_bytes()),
        findingsSha256=sha((args.output / "program-audit-findings.json").read_bytes()), campaigns=campaigns)
    write(args.output / "program-inventory.json", inventory)
    print("Finalized", len(campaigns), "campaigns,", sum(r["uniqueRestoredPrograms"] for r in findings), "restored programs.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("pipeline", "candidates", "baseline-bundle", "projections", "text-dispositions", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    main(parser.parse_args())
