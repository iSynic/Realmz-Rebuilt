"""Independently verify native fields that select or enable scenario programs.

Offsets follow Castle structs.h, convert.c and the corresponding native loaders.
This is intentionally separate from Providence's dependency visitor.
"""
import struct
from audit_native_programs import blob, sha


def verify(project, imported, application_items):
    sources = {r["nativePath"]: blob(project, r["blob"]) for r in imported["classicSources"]}
    evidence, issues = [], []
    unprojected_native_records, dormant_hook_candidates = [], []

    def check(file, number, row, expected):
        for key, value in expected.items():
            if row.get(key) != value:
                issues.append(dict(file=file, record=number, field=key, native=value, imported=row.get(key)))
        evidence.append(dict(file=file, record=number, fields=expected))
        # The graph consumes this detached native-normalized view. Import
        # discrepancies remain in the report, including old unsigned byte fields.
        row.update(expected)

    def words(data, offset, count=1):
        values = list(struct.unpack_from(">" + "h" * count, data, offset))
        return values[0] if count == 1 else values

    def rows(file, size, field):
        data = sources.get(file, b"")
        actual = imported[field]
        if len(data) // size != len(actual) or (len(data) % size and file != "Data ED"):
            issues.append(dict(file=file, kind="record-framing", bytes=len(data), importedRecords=len(actual)))
        for row in actual:
            number = row["nativeId"]
            yield number, data[number * size:(number + 1) * size], row

    def native_hook_record(file, index, size, data, field, native_field, field_offset,
                           value, imported_row=None):
        identity = dict(path=file, nativeIndex=index, offset=index * size, bytes=size,
                        sha256=sha(data), fields={field: value},
                        fieldLayout={field: dict(nativeField=native_field, offset=field_offset,
                                                 offsetBasis="record-start", bytes=2,
                                                 encoding="big-endian signed 16-bit")},
                        macro=dict(field=field, value=value))
        if imported_row is None:
            unprojected_native_records.append({**identity, "reason": "retained-source-unprojected"})
            projection_status = "retained-source-unprojected"
        else:
            projection_status = "imported"
        if value:
            dormant_hook_candidates.append(dict(path=file, nativeIndex=index, offset=index * size,
                recordSha256=identity["sha256"], field=field, fieldOffset=field_offset,
                fieldOffsetBasis="record-start", nativeField=native_field,
                nativeValue=value, candidateOnly=True,
                projectionStatus=projection_status,
                assessment="candidate-for-independent-root-review"))

    def physical_hook_rows(file, size, imported_rows, field, native_field, field_offset,
                           fields_for_row):
        data = sources.get(file, b"")
        count, tail = divmod(len(data), size)
        by_index = {}
        for row in imported_rows:
            index = row["nativeId"]
            if index in by_index:
                issues.append(dict(file=file, kind="duplicate-imported-identity", record=index))
            by_index[index] = row
        if count != len(imported_rows):
            issues.append(dict(file=file, kind="record-framing", bytes=len(data),
                               nativeRecords=count, importedRecords=len(imported_rows)))
        if tail:
            issues.append(dict(file=file, kind="record-framing", bytes=len(data),
                               completeRecords=count, incompleteTailBytes=tail))
        for index in range(count):
            offset = index * size
            raw = data[offset:offset + size]
            row = by_index.get(index)
            expected = fields_for_row(raw)
            if row is None:
                value = expected[field]
                native_hook_record(file, index, size, raw, field, native_field, field_offset,
                                   value)
            else:
                check(file, index, row, expected)
                evidence[-1].update(nativeIndex=index, offset=offset, bytes=size,
                                    sha256=sha(raw),
                                    fieldLayout={field: dict(nativeField=native_field,
                                        offset=field_offset, offsetBasis="record-start", bytes=2,
                                        encoding="big-endian signed 16-bit")})
                native_hook_record(file, index, size, raw, field, native_field, field_offset,
                                   expected[field], row)
        for index in sorted(by_index.keys() - set(range(count))):
            issues.append(dict(file=file, kind="imported-record-outside-source", record=index,
                               nativeRecords=count))

    for row in imported["world"]["actionPoints"]:
        file = "Data DD" if row["levelType"] == "land" else "Data DDD"
        index = row["levelIndex"] * 100 + row["recordIndex"]
        data = sources[file][index * 40:(index + 1) * 40]
        check(file, index, row, dict(classicDoorId=struct.unpack_from(">i", data)[0],
                                    chancePercent=struct.unpack_from("b", data, 7)[0]))
    physical_hook_rows("Data BD", 346, imported["battles"], "battleMacro", "battlemacro", 344,
                       lambda data: dict(grid=words(data, 0, 169), battleMacro=words(data, 344)))
    for number, data, row in rows("Data TD3", 40, "timedEncounters"):
        check("Data TD3", number, row, {key: words(data, offset) for key, offset in
                                      [("day", 0), ("increment", 2), ("percent", 4), ("door", 6)]})
    for source in imported["monsterSets"]:
        physical_hook_rows(source["nativePath"], 210, source["monsters"], "deathMacro",
                           "todoondeath", 166,
                           lambda data: dict(deathMacro=words(data, 166)))
    for number, data, row in rows("Data ED", 426, "simpleEncounters"):
        check("Data ED", number, row, dict(choiceResults=list(struct.unpack_from("4b", data, 96))))
        # Visibility affects which native result choice can be invoked.
        native_visible = [bool(data[106 + slot * 80 + 1:106 + slot * 80 + 1 + min(data[106 + slot * 80], 79)].decode("mac_roman").strip())
                          for slot in range(4)]
        if native_visible != [bool(text.strip()) for text in row["texts"]]:
            issues.append(dict(file="Data ED", record=number, kind="choice-visibility", native=native_visible))
    for number, data, row in rows("Data TD2", 118, "rogueEncounters"):
        check("Data TD2", number, row, dict(successCodes=list(struct.unpack_from("8b", data, 18)),
                                           failureCodes=list(struct.unpack_from("8b", data, 26))))
    for number, data, row in rows("Data ED2", 520, "complexEncounters"):
        fields = {key: struct.unpack_from("b", data, offset)[0] for key, offset in
                  [("actionResult", 96), ("wordResult", 97), ("maxTimes", 153), ("thiefSuccess", 155), ("thiefFail", 156)]}
        fields.update(thief=bool(data[152]), spellIds=words(data, 106, 10),
                      spellResults=list(struct.unpack_from("10b", data, 126)), itemIds=words(data, 136, 5),
                      itemResults=list(struct.unpack_from("5b", data, 146)))
        check("Data ED2", number, row, fields)
    for world_map in imported["world"]["maps"]:
        filename = "Data RD" if world_map["identity"].startswith("land:") else "Data RDD"
        index = world_map["nativeIndex"]
        data = sources[filename][index * 644:(index + 1) * 644]
        existing = {int(r["identity"].rsplit(":", 1)[1]): r for r in world_map["runtime"]["randomRectangles"]}
        for slot in range(20):
            fields = dict(battleRange=words(data, 200 + slot * 4, 2), randomDoors=words(data, 280 + slot * 6, 3),
                          randomDoorPercent=words(data, 400 + slot * 6, 3))
            row = existing.get(slot)
            if row is not None:
                check(filename, f"{index}:{slot}", row, fields)
            elif any(v for values in fields.values() for v in values):
                issues.append(dict(file=filename, record=f"{index}:{slot}", kind="omitted-random-roots", native=fields))
    for field, filename, data, base in [("itemRules", "Data ID", application_items, 0),
                                      ("scenarioItemRules", "Data NI", sources["Data NI"], 800)]:
        for row in imported[field]:
            definition = row["definition"]
            index = definition["classicId"] - base
            check(filename, index, definition, dict(itemType=words(data, index * 100 + 6),
                                                     special=words(data, index * 100 + 86, 5)))
    values = words(sources["Global"], 0, 30)
    hook_slots = {"startGame": 0, "partyDeath": 1, "endAdventure": 2, "shop": 4, "temple": 5}
    check("Global", 0, imported["scenarioApplication"]["hooks"],
          {key: f"extra-action-point:{values[index]}" if values[index] else None for key, index in hook_slots.items()})
    unused = {str(i): value for i, value in enumerate(values) if i not in hook_slots.values() and value}
    return dict(records=evidence, issues=issues, applicationItemsSha256=sha(application_items),
                unusedGlobalWords=unused, unprojectedNativeRecords=unprojected_native_records,
                dormantHookCandidates=dormant_hook_candidates)
