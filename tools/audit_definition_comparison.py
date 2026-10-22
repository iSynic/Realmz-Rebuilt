"""Inventory retained baseline definitions against a pinned fresh projection."""
import argparse
import json
import struct
from pathlib import Path
from audit_native_programs import archive, canonical, sha
from verify_program_restoration import require


def records(content):
    result = {}
    for family, rows in content.items():
        if not isinstance(rows, list):
            continue
        if family == "monsterSets":
            for variant in rows:
                for row in variant["monsters"]:
                    result[(family, str(variant["setId"]), str(row["classicId"]))] = row
            continue
        for index, row in enumerate(rows):
            key = str(row.get("id", row.get("classicId", index))) if isinstance(row, dict) else str(index)
            result[(family, "", key)] = row
    return result


def trimmed(value):
    if isinstance(value, str):
        return value.rstrip()
    if isinstance(value, list):
        return [trimmed(item) for item in value]
    if isinstance(value, dict):
        return {key: trimmed(item) for key, item in value.items()}
    return value


def compare(bundle, baseline, projections, receipt_path, application):
    catalog = json.loads((baseline / "castle-bundled-scenarios.provenance.json").read_bytes())
    receipt = json.loads(receipt_path.read_bytes())
    app_rows = records(archive(application)["content"])
    campaigns = []
    for entry in catalog["scenarios"]:
        path = projections / (entry["campaignId"] + ".json")
        projected = json.loads(path.read_bytes())
        current = archive(bundle / entry["file"])
        previous = archive(baseline / entry["file"])
        fresh_rows, current_rows, old_rows = (records(value) for value in
                                            (projected["content"], current["content"], previous["content"]))
        differences = []
        for key in sorted(fresh_rows.keys() & current_rows.keys()):
            native, retained = fresh_rows[key], current_rows[key]
            if native == retained:
                continue
            unchanged = old_rows.get(key) == retained
            require(unchanged, "unexplained changed definition: " + str(key))
            fields = {field: {"projected": native.get(field), "retained": retained.get(field)}
                      for field in sorted(native.keys() | retained.keys()) if native.get(field) != retained.get(field)}
            whitespace = trimmed(native) == trimmed(retained)
            presentation = set(fields) <= {"name", "unidentifiedName", "description", "text", "texts"}
            classification = ("retained-baseline-trailing-whitespace" if whitespace else
                              "retained-baseline-display-decoding" if presentation else "retained-approved-stock-profile")
            require(presentation or key[0] == "castes" and entry["campaignId"] == "scenario-city-of-bywater",
                    "unresolved nonprogram gameplay difference: " + str(key))
            if not whitespace and key[0] in ("messages", "optionLabels"):
                classification = "retained-castle-c-string-display"
            if key[0] == "items":
                require(entry["campaignId"] == "scenario-trouble-in-the-sword-lands" and key[2] == "classic.item.992",
                        "unreviewed retained item text difference")
                classification = "retained-malformed-native-text-display"
            differences.append(dict(family=key[0], setId=key[1], recordId=key[2],
                classification=classification, baselineUnchanged=True, projectedSha256=sha(canonical(native)),
                retainedSha256=sha(canonical(retained)), fields=fields))
        correction = next(row for row in receipt["campaigns"] if row["campaignId"] == entry["campaignId"])
        projected_only = sorted(fresh_rows.keys() - current_rows.keys())
        require(all(key in app_rows for key in projected_only), "defined nonapplication projection record is omitted")
        projected_only_evidence = []
        for key in projected_only:
            native, accepted = fresh_rows[key], app_rows[key]
            fields = {name: {"projected": native.get(name), "application": accepted.get(name)}
                      for name in native.keys() | accepted.keys() if native.get(name) != accepted.get(name)}
            if fields:
                require(key == ("spells", "", "classic.spell.2712") and fields == {
                    "durationMin": {"projected": -1, "application": 1},
                    "durationMax": {"projected": -1, "application": 1},
                    "special": {"projected": 0, "application": 2}}, "unresolved application/scenario definition difference")
            projected_only_evidence.append(dict(identity=list(key), disposition="approved-application-stun-correction" if fields else "application-owned-identical-record",
                projectedSha256=sha(canonical(native)), applicationSha256=sha(canonical(accepted)), fields=fields))
        candidate_only = sorted(current_rows.keys() - fresh_rows.keys())
        require(all(current_rows[key] == old_rows.get(key) for key in candidate_only),
                "unexplained candidate-only definition")
        text_changes = correction["recipe"].get("textReplacements", [])
        for change in text_changes:
            key = (change["family"], "", str(change["after"]["id"]))
            require(old_rows.get(key) == change["before"] and current_rows.get(key) == change["after"],
                    "text correction differs from exact baseline or candidate")
            require(current_rows[key] == fresh_rows[key], "text correction differs from fresh projection")
        restored = correction["recipe"]["additions"].get("scenario.json", {}).get("programs", [])
        campaigns.append(dict(campaignId=entry["campaignId"], file=entry["file"],
            packageHash=current["manifest"]["packageHash"], archiveSha256=sha((bundle / entry["file"]).read_bytes()),
            baselineArchiveSha256=sha((baseline / entry["file"]).read_bytes()), projectionSha256=sha(path.read_bytes()),
            comparedSharedRecords=len(fresh_rows.keys() & current_rows.keys()),
            projectedOnlyRecords=projected_only_evidence,
            candidateOnlyRecords=[dict(identity=list(key), disposition="unchanged-baseline-definition", sha256=sha(canonical(current_rows[key]))) for key in candidate_only],
            restoredSourceText=text_changes,
            restoredProgramIds=[row["id"] for row in restored], differences=differences))
    return dict(kind="realmz-rebuilt.definition-projection-comparison", formatVersion=1,
        compilerRevision=receipt["compilerRevision"], campaigns=campaigns)


def resources(b):
    do, mo, _, ml = struct.unpack_from('>IIII', b)
    tl = mo + struct.unpack_from('>H', b, mo + 24)[0]
    result = {}
    for i in range(struct.unpack_from('>H', b, tl)[0] + 1):
        e = tl + 2 + i * 8
        kind = b[e:e+4].decode('mac_roman')
        count, off = struct.unpack_from('>HH', b, e+4)
        for j in range(count+1):
            ref = tl+off+j*12
            rid = struct.unpack_from('>h', b, ref)[0]
            at = do+int.from_bytes(b[ref+5:ref+8], 'big')
            size = struct.unpack_from('>I', b, at)[0]
            assert at+4+size <= len(b)
            if kind == 'STR#':
                data = b[at+4:at+4+size]
                pos = 2
                rows = []
                for k in range(struct.unpack_from('>H', data)[0]):
                    if pos >= len(data):
                        break
                    length = data[pos]
                    if pos+1+length > len(data):
                        rows.append(dict(row=k, nativeStringIndex=k+1, pascalOffset=at+4+pos,
                                         rawHex=data[pos+1:].hex(), declaredLength=length,
                                         availableLength=len(data)-pos-1, incomplete=True))
                        break
                    rows.append(dict(row=k, nativeStringIndex=k+1, pascalOffset=at+4+pos,
                                     rawHex=data[pos+1:pos+1+length].hex()))
                    pos += 1+length
                result[rid] = rows
    return result

def verify_native_text(proof, package_root, comparisons, application):
    import zipfile
    require(proof["castleRevision"] == "491816ad60037394f92c428e99c004494d3c28b3", "text adjudication Castle pin differs")
    native_cache = {}
    def native(campaign, source):
        key = campaign, source["nativePath"]
        if key not in native_cache:
            with zipfile.ZipFile(package_root / (campaign + ".realmz2")) as z:
                assets = json.loads(z.read("assets/index.json"))["assets"]
                index = next(row for row in assets if row["kind"] == "classic-source-index")
                sources = json.loads(z.read(index["path"]))["sources"]
                row = next(row for row in sources if row["nativePath"] == source["nativePath"])
                native_cache[key] = z.read(row["assetPath"])
        data = native_cache[key]
        require(sha(data) == source["nativeSha256"] and len(data) == source["bytes"], "text source identity differs")
        return data
    ascii_text = lambda data: ''.join(chr(x) if 32 <= x < 127 else ' ' for x in data).rstrip()
    for row in proof["messages"]:
        data = native(row["campaignId"], row["source"])
        offset = row["id"] * 256
        raw = data[offset + 1:offset + 1 + data[offset]]
        require(offset == row["recordOffset"] and raw.hex() == row["rawHex"] and
                ascii_text(raw.split(b'\0')[0]) == row["candidateText"] and ascii_text(raw) == row["projectionText"],
                "message NUL-boundary adjudication differs")
    for row in proof["castleOptionLabels"]:
        data = native("scenario-castle-in-the-clouds", row["source"])
        offset = row["id"] * 25
        record = data[offset:offset + 25]
        raw = record[1:1 + min(record[0], 24)]
        require(record.hex() == row["rawRecordHex"] and ascii_text(raw.split(b'\0')[0]) == row["candidateText"],
                "option-caption source adjudication differs")
    changes = comparisons["scenario-wrath-of-the-mind-lords"]["restoredSourceText"]
    require(len(changes) == len(proof["wrathItems"]) == 109, "Wrath text restoration coverage differs")
    for row in proof["wrathItems"]:
        data = native("scenario-wrath-of-the-mind-lords", row["source"])
        table = resources(data)
        change = next(item for item in changes if item["after"]["id"] == row["id"])
        fields = {key for key in change["before"] if change["before"][key] != change["after"][key]}
        require(fields == row["fields"].keys(), "Wrath text field inventory differs")
        for field, evidence in row["fields"].items():
            decoded = table[evidence["resourceId"]][row["classicId"] - 800]
            raw = bytes.fromhex(decoded["rawHex"])
            require(not decoded.get("incomplete") and decoded["pascalOffset"] == evidence["pascalOffset"] and
                    raw.hex() == evidence["rawHex"] and b'\0' not in raw and
                    raw.decode('mac_roman').replace('\r', '\n').strip() == change["after"][field] == evidence["after"] and
                    change["before"][field] == evidence["before"], "Wrath native text differs")
    overrides = proof["wrathStockIdentityOverrides"]
    require({row["classicId"] for row in overrides} == {805, 877, 883}, "Wrath source override inventory differs")
    with zipfile.ZipFile(package_root / "scenario-wrath-of-the-mind-lords.realmz2") as z:
        items = {row["classicId"]: row for row in json.loads(z.read("content.json"))["items"]}
    app_items = {row["classicId"]: row for row in application["items"]}
    for row in overrides:
        data = native("scenario-wrath-of-the-mind-lords", row["itemRecordSource"])
        offset = (row["classicId"] - 800) * 100
        require(offset == row["itemRecordOffset"] and len(data[offset:offset + 100]) == 100 and any(data[offset:offset + 100]),
                "Wrath source-owned item record differs")
        table = resources(native("scenario-wrath-of-the-mind-lords", row["source"]))
        item = items[row["classicId"]]
        for field, rid in [("unidentifiedName", 800), ("name", 801), ("description", 802)]:
            evidence = row["fields"][str(rid)]
            raw = table[rid][row["classicId"] - 800]
            require(raw == evidence and not raw.get("incomplete") and bytes.fromhex(raw["rawHex"]).decode('mac_roman').strip() == item[field],
                    "Wrath stock-identity text override differs")
        require({key: value for key, value in item.items() if key not in ("name", "unidentifiedName", "description")} ==
                {key: value for key, value in app_items[row["classicId"]].items() if key not in ("name", "unidentifiedName", "description")},
                "Wrath text-only stock-identity override changes gameplay")
    reviewed_cstrings = {(campaign, row["family"], int(row["recordId"])): row for campaign, comparison in comparisons.items()
                        for row in comparison["differences"] if row["classification"] == "retained-castle-c-string-display"}
    proofs = [(row["campaignId"], "messages", row) for row in proof["messages"]] + [
        ("scenario-castle-in-the-clouds", "optionLabels", row) for row in proof["castleOptionLabels"]]
    require(len(proofs) == len(reviewed_cstrings) == 25, "C-string disposition coverage differs")
    seen = set()
    for campaign, family, row in proofs:
        key = campaign, family, row["id"]
        require(key not in seen and key in reviewed_cstrings and reviewed_cstrings[key]["fields"]["text"] ==
                {"retained": row["candidateText"], "projected": row["projectionText"]}, "C-string evidence is not joined to exact definition")
        seen.add(key)
    row = proof["troubleItem992"]
    partial = resources(native("scenario-trouble-in-the-sword-lands", row["source"]))[801][192]
    require(partial == row["nativeFields"]["801"] and partial.get("incomplete") and partial["availableLength"] == 3,
            "Trouble incomplete native name differs")
    row = proof["bywaterCastes"]
    data = native("scenario-city-of-bywater", row["source"])
    require(len(data) == 30 * 576 and not any(data), "Bywater empty native caste table differs")
    with zipfile.ZipFile(package_root / "scenario-city-of-bywater.realmz2") as z:
        castes = json.loads(z.read("content.json"))["castes"]
    app_castes = {row["id"]: row for row in application["castes"]}
    expected = {row["id"]: row["applicationDifference"] for row in proof["bywaterCastes"]["comparison"]}
    require(len(castes) == len(expected) == 30, "Bywater approved-profile coverage differs")
    for caste in castes:
        reference = app_castes[caste["id"]]
        differences = {key: {"application": reference[key], "candidate": value} for key, value in caste.items()
                       if value != reference[key] and not (key == "eligibleRaceIds" and sorted(value) == sorted(reference[key]))}
        require(differences == expected[caste["id"]] and set(differences) <= {"name"}, "Bywater approved stock gameplay profile differs")



def verify_comparison(content, comparison, correction, application):
    current = records(content)
    app = records(application)
    require(comparison["restoredSourceText"] == correction["recipe"].get("textReplacements", []),
            "source text correction inventory differs")
    for row in comparison["projectedOnlyRecords"]:
        key = tuple(row["identity"])
        require(key in app and sha(canonical(app[key])) == row["applicationSha256"], "application definition changed")
        if row["disposition"] == "application-owned-identical-record":
            require(row["projectedSha256"] == row["applicationSha256"] and not row["fields"], "application record differs")
        else:
            require(row["disposition"] == "approved-application-stun-correction" and key == ("spells", "", "classic.spell.2712") and
                    set(row["fields"]) == {"durationMin", "durationMax", "special"} and app[key]["durationMin"] == 1 and
                    app[key]["durationMax"] == 1 and app[key]["special"] == 2, "unresolved application/scenario definition difference")
    for row in comparison["candidateOnlyRecords"]:
        key = tuple(row["identity"])
        require(key in current and sha(canonical(current[key])) == row["sha256"], "retained definition changed")
    for row in comparison["differences"]:
        key = (row["family"], row["setId"], row["recordId"])
        require(key in current and sha(canonical(current[key])) == row["retainedSha256"],
                "reviewed definition difference changed")
        fields = row["fields"]
        require(all(current[key].get(name) == change["retained"] for name, change in fields.items()),
                "definition field evidence differs")
        classification = row["classification"]
        if classification == "retained-baseline-trailing-whitespace":
            require(all(trimmed(change["retained"]) == trimmed(change["projected"]) for change in fields.values()),
                    "trailing whitespace disposition changes visible content")
        elif classification == "retained-castle-c-string-display":
            require(row["family"] in ("messages", "optionLabels") and set(fields) == {"text"},
                    "C-string display disposition changes gameplay")
        elif classification == "retained-malformed-native-text-display":
            require(comparison["campaignId"] == "scenario-trouble-in-the-sword-lands" and key == ("items", "", "classic.item.992") and set(fields) == {"name"},
                    "unreviewed malformed native name disposition")
        else:
            require(classification == "retained-approved-stock-profile" and row["family"] == "castes" and
                    comparison["campaignId"] == "scenario-city-of-bywater",
                    "unresolved nonprogram semantics")


def main(args):
    report = compare(args.bundle, args.baseline, args.projections, args.receipt, args.application)
    with args.output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print("Compared definitions in", len(report["campaigns"]), "campaigns;", sum(len(row["differences"]) for row in report["campaigns"]), "differences.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("bundle", "baseline", "projections", "receipt", "application", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    main(parser.parse_args())
