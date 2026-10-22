"""Read-only native/import/compiler/bundle comparison; outputs go to a new evidence file."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def blob(project, identity):
    assert identity.startswith("sha256:") and len(identity) == 71
    data = (project / "blobs/sha256" / identity[7:]).read_bytes()
    assert sha(data) == identity[7:], "project blob integrity failure"
    return data


def snapshot(project):
    manifest = json.loads((project / "project.providence.json").read_bytes())
    return {name: json.loads(blob(project, identity)) for name, identity in manifest["segments"].items()}


def archive(path):
    with zipfile.ZipFile(path) as z:
        assert len(z.namelist()) == len(set(z.namelist())), "duplicate archive entries"
        manifest = json.loads(z.read("manifest.json"))
        assert set(z.namelist()) == {"manifest.json", *manifest["files"]}
        for name, record in manifest["files"].items():
            data = z.read(name)
            assert len(data) == record["bytes"] and sha(data) == record["sha256"]
        return {"manifest": manifest, **{name: json.loads(z.read(name + ".json"))
                                        for name in ("scenario", "content", "world")}}


def instruction(slot, raw, operand, extra):
    gosub = raw < 0 and raw not in (-14, -23)
    opcode = -raw if gosub else raw
    values = extra.get(operand)
    if opcode == 92 and values is not None and operand + 1 in extra:
        values = values + extra[operand + 1]
    return dict(kind="classicAction", slot=slot, rawOpcode=raw, opcode=opcode,
                id=operand, gosub=gosub, extraCode=values)


def native_programs(imported, native_sources):
    extra_bytes = native_sources.get("Data EDCD", b"")
    extra_count, extra_tail = divmod(len(extra_bytes), 10)
    extra = {i // 10: list(struct.unpack_from(">5h", extra_bytes, i))
             for i in range(0, len(extra_bytes) - 9, 10)}
    assert extra == {r["nativeId"]: r["values"] for r in imported["extraCodes"]}, "Extra Code import loss"
    programs, families, issues = {}, [], []
    placed = imported["world"]["actionPoints"]
    specifications = [("Data DD", 40, 8, "land", placed), ("Data DDD", 40, 8, "dungeon", placed),
                      ("Data ED3", 40, 8, "xap", imported["extraActionPoints"]),
                      ("Data ED", 426, 32, "simple", imported["simpleEncounters"]),
                      ("Data ED2", 520, 32, "complex", imported["complexEncounters"])]
    for filename, size, slots, kind, rows in specifications:
        data = native_sources.get(filename, b"")
        placed_family = kind in ("land", "dungeon")
        if placed_family:
            rows = [r for r in rows if r["levelType"] == kind]
        imported_rows = {(r["levelIndex"] * 100 + r["recordIndex"] if placed_family else r["nativeId"]): r for r in rows}
        count, tail = divmod(len(data), size)
        assert len(imported_rows) == len(rows), "duplicate imported identity"
        if len(imported_rows) != count:
            issues.append(dict(kind="import-record-count", file=filename, native=count, imported=len(rows)))
        for index in range(count):
            record = data[index * size:(index + 1) * size]
            actions = []
            for slot in range(slots):
                raw = struct.unpack_from(">h", record, 8 + slot * 2)[0] if size == 40 else struct.unpack_from("b", record, slot)[0]
                operand = struct.unpack_from(">h", record, (24 if size == 40 else 32) + slot * 2)[0]
                if raw or operand:
                    actions.append(instruction(slot, raw, operand, extra))
            expected = [dict(slot=a["slot"], rawOpcode=a["rawOpcode"], targetNativeId=a["id"]) for a in actions]
            actual = imported_rows.get(index, {}).get("actions")
            if actual != expected:
                issues.append(dict(kind="import-slot-difference", file=filename, record=index,
                                   native=expected, imported=actual))
            if placed_family:
                identity = f"trigger:{filename}:{index // 100}:{index % 100}"
                programs[identity] = dict(id=identity, ownerId=identity[8:], ownerKind="trigger", instructions=actions)
            elif kind == "xap":
                identity = f"xap:{index}"
                programs[identity] = dict(id=identity, ownerId=f"Data ED3:macro:{index}",
                                          ownerKind="extra-action-point", instructions=actions)
            else:
                for group in range(4):
                    identity = f"{kind}:{index}:result:{group}"
                    selected = [{**a, "slot": a["slot"] % 8} for a in actions if a["slot"] // 8 == group]
                    programs[identity] = dict(id=identity, ownerId=str(index), ownerKind=f"{kind}-encounter-result", instructions=selected)
        partial = None
        if kind == "simple" and tail >= 106:
            record = data[count * size:]
            partial = dict(record=count, offset=count * size, headerHex=record[:106].hex(),
                           textHex=record[106:].hex(),
                           instructions=[instruction(slot, struct.unpack_from("b", record, slot)[0],
                                                     struct.unpack_from(">h", record, 32 + slot * 2)[0], extra)
                                         for slot in range(32)],
                           choiceResults=list(struct.unpack_from("4b", record, 96)),
                           missingTextBytes=426 - tail,
                           framing="Castle accepts the complete header; unchecked text reads leave default buffer bytes.")
        families.append(dict(file=filename, bytes=len(data), sha256=sha(data), recordBytes=size,
                             completeRecords=count, inspectedSlots=count * slots, trailingBytes=tail,
                             trailingSha256=sha(data[count * size:]) if tail else None,
                             partialRecord=partial,
                             tailDisposition="unresolved-partial-record" if tail else "none"))
    extra_tail_disposition = dict(classification="retained-incomplete-source-record",
        reason="incomplete native Extra Code row; exact bytes remain raw source rather than a fabricated operand vector",
        trailingBytes=extra_tail, trailingSha256=sha(extra_bytes[extra_count * 10:])) if extra_tail else None
    extra_code_source = dict(file="Data EDCD", bytes=len(extra_bytes), sha256=sha(extra_bytes),
        recordBytes=10, completeRecords=extra_count, trailingBytes=extra_tail,
        trailingSha256=sha(extra_bytes[extra_count * 10:]) if extra_tail else None,
        tailDisposition=extra_tail_disposition)
    return programs, families, issues, extra_code_source


def resolve_imported_source(native_sources, native_path):
    candidates = [native_path]
    if native_path.endswith(".rsrc"):
        base = native_path[:-5]
        candidates.extend((base + ".rsf", "._" + base, ".rsrc/" + base))
    return next((path for path in candidates if path in native_sources), None)


def program_projection_by_family(native, projected, source_families, extra_code_source):
    prefixes = {
        "Data DD": "trigger:Data DD:",
        "Data DDD": "trigger:Data DDD:",
        "Data ED3": "xap:",
        "Data ED": "simple:",
        "Data ED2": "complex:",
    }
    projected_by_id = {program["id"]: program for program in projected}
    result = {}
    for filename, prefix in prefixes.items():
        expected = {key: value for key, value in native.items() if key.startswith(prefix)}
        actual = {key: value for key, value in projected_by_id.items() if key.startswith(prefix)}
        difference = compare(expected, list(actual.values()))
        source_family = next((row for row in source_families if row["file"] == filename), {})
        result[filename] = dict(kind="native-program-family",
            status="complete" if not any(difference.values()) else "incomplete-projection",
            nativeProgramCount=len(expected), projectedProgramCount=len(actual),
            missingProgramIds=difference["missing"], extraProgramIds=difference["extra"],
            changedProgramIds=difference["changed"],
            incompleteSourceRecord=source_family.get("tailDisposition") if source_family.get("partialRecord") else None)
    result["Data EDCD"] = dict(kind="instruction-operand-table", status="validated-by-native-program-decoder",
                                incompleteSourceRecord=extra_code_source["tailDisposition"])
    return result


def compare(expected, actual):
    actual_rows = list(actual)
    actual = {p["id"]: p for p in actual_rows}
    assert len(actual) == len(actual_rows), "duplicate program identity in compared projection"
    return dict(missing=sorted(expected.keys() - actual.keys()), extra=sorted(actual.keys() - expected.keys()),
                changed=[key for key in sorted(expected.keys() & actual.keys()) if expected[key] != actual[key]])


def run(args):
    from audit_native_references import verify as verify_native_references
    from audit_program_references import inventory
    from audit_record_quarantines import account, verify_projection
    intake = json.loads(args.intake.read_bytes())
    catalog = json.loads((args.bundle / "castle-bundled-scenarios.provenance.json").read_bytes())
    assert len(intake["results"]) == len(catalog["scenarios"]) == 13
    results = []
    for entry in catalog["scenarios"]:
        previous = next(r for r in intake["results"] if r["name"] == entry["name"])
        project = Path(previous["projectPath"])
        imported = snapshot(project)
        native_sources = {}
        native_file_records = previous["sourceIdentity"]["files"]
        assert len(native_file_records) == previous["sourceIdentity"]["fileCount"], "native source file count differs"
        # Verify and independently load every native source byte against the retained intake.
        for record in previous["sourceIdentity"]["files"]:
            relative = record["path"]
            assert isinstance(relative, str) and relative and "\\" not in relative and ":" not in relative \
                and all(part not in ("", ".", "..") for part in relative.split("/")), "unsafe native source path"
            assert relative not in native_sources, "duplicate native source path"
            data = (Path(previous["sourcePath"]) / relative).read_bytes()
            assert len(data) == record["bytes"] and sha(data) == record["sha256"], "native source drift"
            native_sources[relative] = data
        assert sum(record["bytes"] for record in native_file_records) == previous["sourceIdentity"]["byteCount"], \
            "native source byte count differs"
        imported_source_paths = set()
        for record in imported["classicSources"]:
            source_path = resolve_imported_source(native_sources, record["nativePath"])
            assert source_path is not None, "imported source path has no pinned native input: " + record["nativePath"]
            assert blob(project, record["blob"]) == native_sources[source_path], "imported/native source bytes differ"
            imported_source_paths.add(source_path)
        native, families, issues, extra_code_source = native_programs(imported, native_sources)
        metadata = verify_native_references(project, imported, args.application_items.read_bytes())
        baseline = archive(args.bundle / entry["file"])
        record_dispositions = account(entry["campaignId"], native_sources, imported, baseline)
        quarantined = {(row["path"], row["nativeIndex"]) for row in record_dispositions}
        for hook in metadata["dormantHookCandidates"]:
            if (hook["path"], hook["nativeIndex"]) in quarantined:
                hook["projectionStatus"] = "retained-raw-certified-quarantine"
        graph = inventory(native, imported)
        for family in families:
            if family["partialRecord"] is None:
                continue
            partial_id = family["partialRecord"]["record"]
            from audit_program_references import action_edges
            direct = [(p["id"], a["slot"]) for p in native.values() for a in p["instructions"]
                      if ("simple", partial_id) in action_edges(a, (None, None, None))]
            installed = [r for r in graph["nativeDataReferences"] if r["relation"] == "installs-encounter-result"
                         and r["ownerKind"] == "simple" and r["owner"] == partial_id]
            retained = [r for r in graph["dynamicContexts"] if r["targetKind"] == "retained-simple-result"]
            family["tailDisposition"] = dict(classification="retained-incomplete-source-record",
                reason="header-complete-text-incomplete EOF record; exact bytes remain source data rather than fabricated complete dialogue",
                sourcePreservation="exact header, instructions, choices and available text retained in the inventory and package source payload",
                directCallers=direct, installationCallers=installed, retainedContextCallers=retained,
                limitation="Castle unchecked short reads and incidental global buffer bytes are not invented as authored text")
        tracked_path = args.bundle / entry["file"]
        assert sha(tracked_path.read_bytes()) == entry["archiveSha256"]
        tracked = archive(tracked_path)
        final_path = Path(previous["finalPackage"]["path"])
        assert sha(final_path.read_bytes()) == previous["finalPackage"]["archiveSha256"]
        final = archive(final_path)
        intermediate = archive(Path(previous["packagePath"]))
        fresh = json.loads((args.projections / (entry["campaignId"] + ".json")).read_bytes())
        selected_rows = fresh["runtime"]["scenario"]["programs"]
        selected = {p["id"]: p for p in selected_rows}
        assert len(selected) == len(selected_rows), "duplicate projected native program identity"
        semantic_projection = program_projection_by_family(native, selected_rows, families, extra_code_source)
        assert fresh["projectManifestSha256"] == sha((project / "project.providence.json").read_bytes())
        assert fresh["compilerRevision"] == args.compiler_commit
        compiler_reachable = set(fresh["reachability"]["reachableProgramIds"])
        independently_reachable = set(graph["reachableProgramIds"])
        missing = selected.keys() - {p["id"] for p in tracked["scenario"]["programs"]}
        affected = [r for r in graph["references"] if r["targetKind"] == "program" and r["target"] in missing]
        unique_sites = {(str(r["source"]), r["slot"], r["target"]) for r in affected}
        retained_compiler_ids = {p["id"] for p in intermediate["scenario"]["programs"]}
        retained_final_ids = {p["id"] for p in final["scenario"]["programs"]}
        import_missing_ids = set()
        for issue in issues:
            if issue.get("kind") != "import-slot-difference" or issue.get("imported") is not None:
                continue
            file, number = issue["file"], issue["record"]
            if file in ("Data DD", "Data DDD"):
                import_missing_ids.add(f"trigger:{file}:{number // 100}:{number % 100}")
            elif file == "Data ED3":
                import_missing_ids.add(f"xap:{number}")
            else:
                kind = "simple" if file == "Data ED" else "complex"
                import_missing_ids.update(f"{kind}:{number}:result:{result}" for result in range(4))
        discrepancies = [dict(programId=key, nativeAvailable=key in native,
            classification="import-loss" if key in import_missing_ids else "stale-bundle-promotion" if key in retained_final_ids else "compiler-dependency-omission",
            firstAbsentStage="imported-project" if key in import_missing_ids else "tracked-bundle" if key in retained_final_ids else "compiler-output",
            retainedCompilerAvailable=key in retained_compiler_ids, retainedFinalAvailable=key in retained_final_ids,
            callers=[r for r in affected if r["target"] == key]) for key in sorted(missing)]
        candidate_path = args.candidates / entry["file"]
        assert candidate_path.is_file(), "missing explicit audit candidate: " + str(candidate_path)
        candidate = archive(candidate_path)
        verify_projection(record_dispositions, fresh, candidate)
        release_stages = []
        for directory in args.release_payloads:
            released = archive(directory / entry["file"])
            release_stages.append(dict(platform=directory.name, archiveSha256=sha((directory / entry["file"]).read_bytes()),
                                       packageHash=released["manifest"]["packageHash"],
                                       projectionToRelease=compare(selected, released["scenario"]["programs"])))
        imported_source_omissions = [dict(path=row["path"], bytes=row["bytes"], sha256=row["sha256"],
            rawSourceDisposition="pinned-native-source-awaiting-package-annex",
            semanticProjection=semantic_projection.get(row["path"],
                dict(kind="not-a-native-program-family", status="raw-source-only")))
            for row in previous["sourceIdentity"]["files"] if row["path"] not in imported_source_paths]
        results.append(dict(campaignId=entry["campaignId"], sourceIdentity=previous["sourceIdentity"]["treeSha256"],
                            nativeSourceFiles=previous["sourceIdentity"]["files"],
                            importedSourceOmissions=imported_source_omissions,
                            semanticProgramFamilies=semantic_projection,
                            extraCodeSource=extra_code_source,
                            sourceFiles=families, importIssues=issues, nativeProgramCount=len(native),
                            currentArchiveSha256=entry["archiveSha256"], currentPackageHash=entry["packageHash"],
                            freshCompiler=fresh["compilerRevision"], selectedProgramCount=len(selected),
                            nativeToProjection=compare(native, selected_rows),
                            projectionToBundle=compare(selected, tracked["scenario"]["programs"]),
                            retainedCompilerToFinal=compare({p["id"]: p for p in intermediate["scenario"]["programs"]}, final["scenario"]["programs"]),
                            selectedIds=sorted(selected), nativeIds=sorted(native), nativePrograms=list(native.values()),
                            nativeReferenceMetadata=metadata, independentReferences=graph,
                            nativeRecordDispositions=record_dispositions,
                            independentOnly=sorted(independently_reachable - compiler_reachable),
                            compilerOnly=sorted(compiler_reachable - independently_reachable),
                            emittedBeyondReachability=sorted(selected.keys() - compiler_reachable),
                            uniqueMissingPrograms=len(missing), affectedCallSites=len(unique_sites),
                            affectedReferencesWithContext=affected, discrepancies=discrepancies,
                            candidatePackageHash=candidate["manifest"]["packageHash"],
                            projectionToCandidate=compare(selected, candidate["scenario"]["programs"]),
                            releaseStages=release_stages,
                            executionEvidence="not established by this static command"))
        print(entry["campaignId"], "imports", len(issues), "missing", len(results[-1]["projectionToBundle"]["missing"]),
              "changed", len(results[-1]["projectionToBundle"]["changed"]))
    castle_head = subprocess.check_output(["git", "-C", str(args.castle), "rev-parse", "HEAD"], text=True).strip()
    assert castle_head == args.castle_commit
    castle_files = ["newland.c", "setupnewgame.c", "structs.h", "encounters.c", "items.c", "getup.c",
                    "misc.c", "share-movecost-dialog.c", "textbox-time.c", "buttonchoice.c"]
    castle = {name: sha(subprocess.check_output(["git", "-C", str(args.castle), "show",
                                               args.castle_commit + ":src/realmz_orig/" + name])) for name in castle_files}
    report = dict(kind="realmz-rebuilt.omitted-program-audit", formatVersion=1,
                  intakeSha256=sha(args.intake.read_bytes()), compilerRevision=args.compiler_commit,
                  castleRevision=args.castle_commit, castleSources=castle,
                  applicationArchiveSha256=sha(args.application.read_bytes()),
                  toolSources={p.name: sha(p.read_bytes()) for p in [Path(__file__), Path(__file__).with_name("audit_native_references.py"), Path(__file__).with_name("audit_program_references.py"), Path(__file__).with_name("audit_record_quarantines.py")]},
                  results=results)
    with args.output.open("x", encoding="utf-8", newline="\n") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
        f.write("\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--intake", type=Path, required=True)
    parser.add_argument("--projections", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--candidates", type=Path, required=True)
    parser.add_argument("--application", type=Path, required=True)
    parser.add_argument("--application-items", type=Path, required=True)
    parser.add_argument("--castle", type=Path, required=True)
    parser.add_argument("--castle-commit", required=True)
    parser.add_argument("--compiler-commit", required=True)
    parser.add_argument("--release-payloads", type=Path, nargs="+", required=True)
    run(parser.parse_args())
