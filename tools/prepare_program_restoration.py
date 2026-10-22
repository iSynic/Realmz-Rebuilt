"""Prepare additive, reviewable restoration inputs; never modify tracked packages."""
import argparse
import json
from pathlib import Path
import zipfile
import struct
from audit_native_programs import archive, canonical, sha


def prepare(bundle, projections, application, output):
    catalog = json.loads((bundle / "castle-bundled-scenarios.provenance.json").read_bytes())
    with zipfile.ZipFile(application) as z:
        app = json.loads(z.read("content.json"))
    output.mkdir(exist_ok=False)
    for entry in catalog["scenarios"]:
        old = archive(bundle / entry["file"])
        with zipfile.ZipFile(bundle / entry["file"]) as z:
            old_asset_index = json.loads(z.read("assets/index.json"))
            metadata_changes = []
            for before in old_asset_index["assets"]:
                if before["mimeType"] != "image/png" or before["width"] is not None or before["height"] is not None:
                    continue
                data = z.read(before["path"])
                assert sha(data) == before["sha256"] and data[:16] == b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR', "invalid retained PNG header"
                width, height = struct.unpack_from(">II", data, 16)
                assert 0 < width <= 32767 and 0 < height <= 32767
                metadata_changes.append(dict(before=before, after={**before, "width": width, "height": height},
                                             reason="derive-missing-dimensions-from-retained-png-ihdr"))
        source = projections / (entry["campaignId"] + ".json")
        projected = json.loads(source.read_bytes())
        projected_monsters = projected["content"]["monsters"] + [
            monster for variant in projected["content"]["monsterSets"] for monster in variant["monsters"]]
        required_icon_ids = {monster["iconId"] for monster in projected_monsters if monster["iconId"] > 0}
        metadata_changes = [change for change in metadata_changes
                            if change["before"]["resourceType"] == "cicn" and
                            change["before"]["resourceId"] in required_icon_ids]
        additions = {}

        def add(document, field, rows, allowed=None, application_owned=False):
            previous = old[document][field]
            existing = {r["id"] for r in previous}
            if application_owned:
                source_owned = ({"classic.item.805", "classic.item.877", "classic.item.883"}
                                if field == "items" and entry["campaignId"] == "scenario-wrath-of-the-mind-lords" else set())
                existing.update(r["id"] for r in app.get(field, []) if r["id"] not in source_owned)
            values = [r for r in rows if r["id"] not in existing and (allowed is None or r["id"] in allowed)]
            if values:
                additions.setdefault(document + ".json", {})[field] = values
            return values

        programs = add("scenario", "programs", projected["runtime"]["scenario"]["programs"])
        triggers = add("world", "triggers", projected["triggers"])
        monsters = add("content", "monsters", projected["content"]["monsters"])
        for field in ["simpleEncounters", "complexEncounters", "treasures", "shops", "battles", "timedEncounters"]:
            add("content", field, projected["content"][field])
        add("content", "thiefEncounters", projected["content"]["thiefEncounters"])
        add("world", "timedEncounters", projected["runtime"]["timedEncounters"])
        # Definitions already supplied by the application are not scenario payloads.
        for field in ["items", "spells"]:
            add("content", field, projected["content"][field], application_owned=True)
        add("content", "messages", projected["content"]["messages"])
        add("content", "monsterDescriptions", projected["content"]["monsterDescriptions"])
        variants = []
        introduced_sets = []
        for variant in projected["content"]["monsterSets"]:
            existing = next((s for s in old["content"]["monsterSets"] if s["setId"] == variant["setId"]), None)
            if existing is None:
                introduced_sets.append(variant)
                continue
            ids = {r["classicId"] for r in existing["monsters"]}
            values = [r for r in variant["monsters"] if r["classicId"] not in ids]
            if values:
                variants.append(dict(setId=variant["setId"], monsters=values))
        cells = []
        for trigger in triggers:
            world_map = next(m for m in old["world"]["maps"] if m["id"] == trigger["mapId"])
            coordinate = trigger["coordinate"]
            index = coordinate["y"] * world_map["width"] + coordinate["x"]
            prior = next((r["after"] for r in reversed(cells) if r["mapId"] == world_map["id"] and r["index"] == index),
                         world_map["cells"][index][4])
            assert trigger["id"] not in prior
            cells.append(dict(mapId=world_map["id"], index=index, before=prior,
                              after=sorted(prior + [trigger["id"]], key=lambda s: int(s.rsplit(":", 1)[1]))))
        rectangles = []
        rectangle_layouts = []
        for native_map in projected["mapRandomRectangles"]:
            target = next(m for m in old["world"]["maps"] if m["id"] == native_map["id"])
            before = target["randomRectangles"]
            slot = lambda row: int(row["id"].rsplit(":rect:", 1)[1])
            existing = {slot(row): row for row in before}
            assert len(existing) == len(before), "duplicate native random slot"
            native = native_map["randomRectangles"]
            assert len({slot(row) for row in native}) == len(native), "duplicate projected random slot"
            after = []
            for row in sorted(native, key=slot):
                previous = existing.get(slot(row))
                normalized = {**row, "id": previous["id"]} if previous else row
                after.append(normalized)
            assert existing.keys() <= {slot(row) for row in native}, "native projection lost an existing slot"
            if before != after:
                rectangle_layouts.append(dict(mapId=target["id"], before=before, after=after))
        replacements = []
        capabilities = (["realmz.scenario.deferred-references-v1"]
                        if projected["runtime"]["deferredReferences"] else [])
        native_by_id = {p["id"]: p for p in projected["runtime"]["scenario"]["programs"]}
        for before in old["scenario"]["programs"]:
            after = native_by_id.get(before["id"])
            if after is None or before == after:
                continue
            # Restore only the previously stripped source-proven fallthrough instructions.
            stripped = {**after, "instructions": [i for i in after["instructions"] if i["opcode"] != 200]}
            if stripped == before:
                replacements.append(dict(before=before, after=after, reason="preserve-native-fallthrough-instructions"))
        if entry["campaignId"] == "scenario-mithril-vault":
            before = next(p for p in old["scenario"]["programs"] if p["id"] == "xap:410")
            after = next(p for p in projected["runtime"]["scenario"]["programs"] if p["id"] == "xap:410")
            assert before["instructions"][0]["extraCode"] == [851, 0, 12, 411, 0]
            assert after["instructions"][0]["extraCode"] == [851, 0, 12, 411, -1]
            replacements.append(dict(before=before, after=after, reason="restore-native-signed-failure-target"))
            if "realmz.scenario.deferred-references-v1" not in capabilities:
                capabilities.append("realmz.scenario.deferred-references-v1")
        text_replacements = []
        for family, fields in [("items", {"name", "unidentifiedName", "description"})]:
            if family == "items" and entry["campaignId"] != "scenario-wrath-of-the-mind-lords":
                continue
            native_rows = {row["id"]: row for row in projected["content"][family]}
            for before in old["content"][family]:
                native = native_rows.get(before["id"])
                if native is None or native == before:
                    continue
                changed_fields = {key for key in before.keys() | native.keys() if before.get(key) != native.get(key)}
                assert changed_fields <= fields, "text restoration would change gameplay fields"
                after = {**before, **{key: native[key] for key in changed_fields}}
                text_replacements.append(dict(family=family, before=before, after=after,
                    reason="restore-source-owned-text", sourcePath="Scenario.rsrc" if family == "items" else "Data SD2"))
        if not additions and not variants and not replacements and not rectangles and not projected["sourceAssets"]:
            continue
        recipe = dict(kind="realmz-rebuilt.program-restoration-input", formatVersion=1,
                      campaignId=entry["campaignId"], compilerRevision=projected["compilerRevision"],
                      originalArchiveSha256=sha((bundle / entry["file"]).read_bytes()),
                      projectionSha256=sha(source.read_bytes()), applicationArchiveSha256=sha(application.read_bytes()),
                      previousDocuments={k + ".json": sha(canonical(old[k])) for k in ["scenario", "content", "world"]},
                      previousAssetIndexSha256=sha(canonical(old_asset_index)),
                      additions=additions, monsterSetAdditions=variants, cellChanges=cells,
                      monsterSetIntroductions=introduced_sets,
                      assetMetadataChanges=metadata_changes,
                      programReplacements=replacements, textReplacements=text_replacements, addedCapabilities=capabilities,
                      randomRectangleAdditions=rectangles,
                      randomRectangleLayouts=rectangle_layouts,
                      assetIndexAdditions=projected["sourceAssets"], payloadAdditions=projected["sourcePayloads"])
        path = output / (entry["campaignId"] + ".json")
        path.write_text(json.dumps(recipe, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(entry["campaignId"], len(programs), "programs", len(triggers), "placed records",
              {key: len(rows) for key, rows in additions.get("content.json", {}).items()})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["bundle", "projections", "application", "output"]:
        parser.add_argument("--" + name, required=True, type=Path)
    prepare(**vars(parser.parse_args()))
