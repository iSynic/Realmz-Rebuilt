"""Independent operational projections of fixed Classic native record families.

Offsets are zero-based, big endian, transcribed from the pinned Castle structs
and consumers. This is verification tooling, never a production native reader.
"""
from __future__ import annotations

import struct
import hashlib
import json


def short(row, offset):
    return struct.unpack_from(">h", row, offset)[0]


def words(row, offset, count):
    return list(struct.unpack_from(f">{count}h", row, offset))


def signed(row, offset, count=1):
    values = list(struct.unpack_from(f">{count}b", row, offset))
    return values[0] if count == 1 else values


def text(raw):
    return raw.decode("mac_roman").replace("\0", " ").replace("\r", "\n")


def verify_rule_selection(content, application, require):
    facts = content.get('classicRecords', {})
    require('ruleSelection' in facts, 'missing explicit nullable Classic rule selection')
    choice = facts['ruleSelection']
    if choice is None:
        for path, family, stride, label in [('Data Race', 'races', 408, 'race'), ('Data Caste', 'castes', 576, 'caste')]:
            source = next((row for row in facts['sources'] if row['nativePath'] == path), None)
            if source is None: continue
            ids = {row['id'] for row in content[family]}
            require(all(f'classic.{label}.{i}' in ids for i in range(1, min(30, source['effectiveByteLength'] // stride) + 1)),
                    f'{path}: unknown selection cannot conceal missing package-owned rules')
        return {'selection': None, 'disposition': 'no implicit application substitution'}
    require(set(choice) == {'nativeMenuSelection', 'capturedSourceSetSha256', 'raceSource', 'casteSource', 'projectedRules'},
            'Classic rule selection fields differ')
    menu = choice['nativeMenuSelection']
    require(type(menu) is int and 1 <= menu <= 32767, 'Classic rule-selection menu is invalid')
    require(choice['raceSource'] in ('scenario', 'application') and choice['casteSource'] in ('scenario', 'application'),
            'Classic rule-selection family source is invalid')
    captured_paths = {row['nativePath'] for row in facts['sources']}
    for path, field in [('Data Race', 'raceSource'), ('Data Caste', 'casteSource')]:
        expected = 'scenario' if menu >= 20 and path in captured_paths else 'application'
        require(choice[field] == expected, f'{path}: Classic rule selection changed its captured family source')
    # The source-set format uses declared serde field order, not canonical row order.
    sources = [{'nativePath': row['nativePath'], 'blob': 'sha256:' + row['sha256'], 'byteLength': row['byteLength']}
               for row in sorted(facts['sources'], key=lambda row: row['nativePath'])]
    encoded = json.dumps(['providence-classic-source-set-v1', sources], ensure_ascii=False, separators=(',', ':')).encode()
    require(hashlib.sha256(encoded).hexdigest() == choice['capturedSourceSetSha256'], 'Classic rule selection has stale source provenance')
    require(application is not None and set(choice['projectedRules']) == {'races', 'castes'},
            'explicit application and both rule projections are required')
    compared = 0
    unavailable = 0
    for family, label, path, stride, field in [('races', 'race', 'Data Race', 408, 'raceSource'), ('castes', 'caste', 'Data Caste', 576, 'casteSource')]:
        rows = choice['projectedRules'][family]
        require(isinstance(rows, list) and [row.get('id') for row in rows] == [f'classic.{label}.{i}' for i in range(1, 31)],
                f'{family}: fixed rule projection identities differ')
        native_selected = choice[field] == 'scenario'
        source = next((row for row in facts['sources'] if row['nativePath'] == path), None)
        complete = min(30, source['effectiveByteLength'] // stride) if source is not None else 0
        effective = {} if native_selected else {row['id']: row for row in application[family]}
        effective.update({row['id']: row for row in content[family]})
        for index, row in enumerate(rows):
            require(set(row) == {'id', 'sha256'}, f'{family}: rule projection row is invalid')
            if native_selected and index >= complete:
                require(row['sha256'] is None and row['id'] not in effective,
                        f'{family}: unavailable native row was fabricated or hashed')
                unavailable += 1
                continue
            require(row['id'] in effective and row['sha256'] is not None, f'{family}: complete rule was omitted or nulled')
            if native_selected:
                require(any(item['id'] == row['id'] for item in content[family]), f'{family}: stock fallback concealed an omitted native row')
            wire = json.dumps(effective[row['id']], sort_keys=True, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()
            require(hashlib.sha256(wire).hexdigest() == row['sha256'], f'{family}: full rule projection differs for {row["id"]}')
            compared += 1
    return {'nativeMenuSelection': menu, 'raceSource': choice['raceSource'], 'casteSource': choice['casteSource'],
            'fullCanonicalRuleRowsCompared': compared, 'unavailableRuleSlotsVerified': unavailable,
            'sourceSetSha256': choice['capturedSourceSetSha256']}


def self_test_rule_selection(require, error_type=ValueError):
    """Exercise source-derived sparse slots, independently of compiler assertions."""
    import copy
    raw = bytes(408 * 2 + 56)
    source = {'nativePath': 'Data Race', 'sha256': hashlib.sha256(raw).hexdigest(),
              'byteLength': len(raw), 'effectiveByteLength': len(raw)}
    native_rows = [dict(id=f'classic.race.{i}', classicId=i, name='', description='',
                        **race_expected(raw[(i - 1) * 408:i * 408])) for i in range(1, 3)]
    application = {family: [dict(id=f'classic.{label}.{i}', signedValue=-842, **{
        'eligibleCasteIds' if family == 'races' else 'eligibleRaceIds': []})
                            for i in range(1, 31)] for family, label in [('races', 'race'), ('castes', 'caste')]}
    content = {'races': copy.deepcopy(native_rows), 'castes': [],
               'classicRecords': {'sources': [source], 'races': native_rows, 'castes': []}}
    source_wire = json.dumps(['providence-classic-source-set-v1', [
        {'nativePath': source['nativePath'], 'blob': 'sha256:' + source['sha256'], 'byteLength': len(raw)}]], separators=(',', ':')).encode()
    selection = {'nativeMenuSelection': 100, 'capturedSourceSetSha256': hashlib.sha256(source_wire).hexdigest(),
                 'raceSource': 'scenario', 'casteSource': 'application', 'projectedRules': {}}
    for family, label in [('races', 'race'), ('castes', 'caste')]:
        effective = {row['id']: row for row in (native_rows if family == 'races' else application[family])}
        selection['projectedRules'][family] = [{'id': f'classic.{label}.{i}', 'sha256': hashlib.sha256(
            json.dumps(effective[f'classic.{label}.{i}'], sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
            if f'classic.{label}.{i}' in effective else None} for i in range(1, 31)]
    content['classicRecords']['ruleSelection'] = selection
    accepted = verify_rule_selection(content, application, require)
    require(accepted['unavailableRuleSlotsVerified'] == 28 and accepted['fullCanonicalRuleRowsCompared'] == 32,
            'sparse rule self-test did not preserve its native extent')
    mutations = []
    missing = copy.deepcopy(content); missing['races'].pop(); mutations.append(('missing-complete-native-rule', missing))
    nulled = copy.deepcopy(content); nulled['classicRecords']['ruleSelection']['projectedRules']['races'][0]['sha256'] = None
    mutations.append(('complete-zero-native-rule-nulled', nulled))
    substituted = copy.deepcopy(content); substituted['races'].append(application['races'][2]); mutations.append(('stock-substituted-for-native-fragment', substituted))
    signed_row = copy.deepcopy(content); signed_row['races'][0]['attributeLimits'][0] = -842; mutations.append(('signed-native-rule-field-changed', signed_row))
    indexed = copy.deepcopy(content); indexed['classicRecords']['ruleSelection']['projectedRules']['races'][2]['id'] = 'classic.race.4'
    mutations.append(('fixed-native-rule-index-changed', indexed))
    stale = copy.deepcopy(content); stale['classicRecords']['ruleSelection']['raceSource'] = 'application'; mutations.append(('stale-rule-context-with-current-metadata', stale))
    results = [{'case': 'sparse-native-zero-rows-and-fragment-preserved', 'passed': True}]
    for name, changed in mutations:
        try:
            verify_rule_selection(changed, application, require)
        except error_type:
            results.append({'case': name, 'passed': True})
        else:
            require(False, f'rule self-test accepted corruption: {name}')

    def compare(actual, expected, path, native_id, field):
        require(actual == expected, f'{path} #{native_id}.{field}: source/facts mismatch')
    verify(content, {}, {'Data Race': raw}, compare, require, application)
    changed = copy.deepcopy(content)
    changed['classicRecords']['races'][0]['attributeLimits'][0] = -842
    changed['races'][0]['attributeLimits'][0] = -842
    try:
        verify(changed, {}, {'Data Race': raw}, compare, require, application)
    except error_type:
        results.append({'case': 'native-rule-facts-and-active-row-cannot-conceal-source-change', 'passed': True})
    else:
        require(False, 'rule self-test accepted contradictory native facts and active row')
    race_bytes = bytearray(raw); race_bytes[208] = 1
    caste_bytes = bytes(576)
    derived = copy.deepcopy(content)
    derived['classicRecords']['sources'].append({'nativePath': 'Data Caste'})
    derived['classicRecords']['ruleSelection']['casteSource'] = 'scenario'
    derived['classicRecords']['races'][0]['eligibleCasteIds'] = ['classic.caste.1']
    derived['races'][0]['eligibleCasteIds'] = ['classic.caste.1']
    caste_row = dict(id='classic.caste.1', classicId=1, name='', description='', eligibleRaceIds=[], **caste_expected(caste_bytes))
    derived['classicRecords']['castes'] = [caste_row]
    derived['castes'] = [dict(caste_row, eligibleRaceIds=['classic.race.1'])]
    verify(derived, {}, {'Data Race': bytes(race_bytes), 'Data Caste': caste_bytes}, compare, require, application)
    results.append({'case': 'native-caste-facts-and-derived-operational-eligibility-distinguished', 'passed': True})
    derived['castes'][0]['eligibleRaceIds'] = []
    try:
        verify(derived, {}, {'Data Race': bytes(race_bytes), 'Data Caste': caste_bytes}, compare, require, application)
    except error_type:
        results.append({'case': 'missing-derived-native-caste-eligibility-rejected', 'passed': True})
    else:
        require(False, 'rule self-test accepted lost derived caste eligibility')
    return results


def pascal(row):
    return text(row[1:1 + min(row[0], len(row) - 1)])


def item_ref(value):
    return f"classic.item.{abs(value)}" if value else ""


def rows_by_id(rows, field, require, family):
    require(isinstance(rows, list), f"{family}: missing operational catalog")
    result = {row.get(field): row for row in rows if isinstance(row, dict)}
    require(len(result) == len(rows), f"{family}: duplicate or malformed record identity")
    return result


def monster_expected(row, native_id, descriptions, set_id):
    expected = {name: row[offset] for name, offset in {
        "hitDice": 0, "staminaBonus": 1, "agility": 2,
        "classicNameId": 3, "movementMaximum": 4}.items()}
    expected.update({name: signed(row, offset) for name, offset in {
        "armor": 5, "magicResistance": 6, "requiredWeapon": 7, "size": 9,
        "attackCount": 18, "magicAttackCount": 19, "damageBonus": 40,
        "castPercent": 41, "runPercent": 42, "surrenderPercent": 43,
        "missilePercent": 44, "canSummon": 45, "magicToHit": 121}.items()})
    expected.update({name: short(row, offset) for name, offset in {
        "iconId": 98, "spellPoints": 100, "experience": 102, "deathMacro": 166}.items()})
    name = text(row[170:210].split(b"\0", 1)[0])
    weapon = short(row, 96)
    expected.update({
        "name": name or f"Monster {native_id}",
        "description": descriptions.get(native_id, "") if set_id == 0 else "",
        "traitor": row[8] != 0, "notOnMenu": row[118] != 0,
        "typeFlags": signed(row, 10, 8), "saves": signed(row, 46, 6),
        "spellImmunities": signed(row, 52, 6), "conditions": signed(row, 122, 40),
        "money": words(row, 58, 3),
        "spellIds": [f"classic.spell.{value}" if value > 1100 else ""
                     for value in words(row, 64, 10)],
        "itemIds": [item_ref(value) for value in words(row, 84, 6)],
        "weaponId": item_ref(weapon) if weapon > 0 else "",
        "randomWeaponTable": abs(weapon) if weapon < 0 else 0,
        "attacks": [dict(zip(("damageMin", "damageMax", "soundOrType", "special"),
                             signed(row, 20 + index * 4, 4))) for index in range(5)],
    })
    return expected


def item_expected(row):
    fields = {
        "strengthBonus": 0, "iconId": 4, "itemType": 6, "blunt": 8, "hands": 10,
        "luckBonus": 12, "movementBonus": 14, "armorBonus": 16,
        "magicResistanceBonus": 18, "damageBonus": 20, "spellPointBonus": 22,
        "soundId": 24, "weight": 26, "cost": 28, "initialCharges": 30,
        "raceRestrictions": 44, "casteRestrictions": 46,
        "raceClassOnly": 52, "casteClassOnly": 54, "versusSmall": 70,
        "versusLarge": 72, "heat": 74, "cold": 76, "electric": 78,
        "versusUndead": 80, "versusDemonDevil": 82, "versusEvil": 84,
        "weightPerCharge": 96,
    }
    result = {field: short(row, offset) for field, offset in fields.items()}
    for field, kind, offset in [("cursedItemId", "item", 32),
                                 ("specificRaceId", "race", 48),
                                 ("specificCasteId", "caste", 50)]:
        value = short(row, offset)
        result[field] = f"classic.{kind}.{value}" if value else ""
    result.update(magical=short(row, 34) != 0, dropOnEmpty=short(row, 98) != 0,
                  itemCategoryMaskLow=struct.unpack_from(">i", row, 36)[0],
                  itemCategoryMaskHigh=struct.unpack_from(">i", row, 40)[0],
                  special=words(row, 86, 5))
    return result


def spell_expected(row):
    names = ["rangeMin", "rangeMax", "queueIcon", "toHitBonus", "saveBonus",
             "fixedTargetCount", "canRotate", "saveAdjust", "cannot",
             "resistanceAdjust", "cost", "damageMin", "damageMax", "powerDamageMin",
             "powerDamageMax", "durationMin", "durationMax", "powerDurationMin",
             "powerDurationMax", "lookStart", "lookEnd", "soundStart", "soundEnd",
             "targetType", "size", "special", "damageType", "spellClass"]
    result = {name: row[offset] if offset in (25, 27) else signed(row, offset)
              for offset, name in enumerate(names)}
    result["canRotate"] = row[6] != 0
    result.update(inCombat=row[28] != 0, inCamp=row[29] != 0)
    return result


def race_expected(row):
    result = {field: words(row, offset, count) for field, offset, count in [
        ("hitModifiers", 0, 8), ("abilityBonuses", 16, 14), ("saveBonuses", 44, 8),
        ("attributeBonuses", 60, 6), ("attributeLimits", 72, 12), ("conditionLevels", 112, 40)]}
    result.update({field: short(row, offset) for field, offset in {
        "maximumAge": 192, "baseMovement": 196, "magicResistance": 198,
        "twoHandBonus": 200, "missileBonus": 202, "baseAttacks": 204,
        "maximumAttacks": 206, "defaultIconSet": 334, "descriptorFlags": 344}.items()})
    result.update(doesNotDie=short(row, 194) != 0, canRegenerate=row[333] != 0,
                  eligibleCasteIds=[f"classic.caste.{i + 1}" for i, value in enumerate(row[208:238]) if value],
                  ageRanges=[words(row, 238 + i * 4, 2) for i in range(5)],
                  ageChanges=[signed(row, 258 + i * 15, 15) for i in range(5)],
                  itemCategoryMasks=list(struct.unpack_from(">2i", row, 336)))
    return result


def caste_expected(row):
    result = {field: words(row, offset, count) for field, offset, count in [
        ("initialAbilityValues", 0, 14), ("levelAbilityDice", 28, 14),
        ("saveBonuses", 56, 8), ("attributeBonuses", 72, 6),
        ("attributeLimits", 108, 12), ("conditionLevels", 132, 40),
        ("staminaDice", 216, 2), ("strengthValues", 220, 2), ("dodgeValues", 224, 2),
        ("toHitValues", 228, 2), ("missileValues", 232, 2), ("handToHandValues", 236, 2)]}
    result.update({field: short(row, offset) for field, offset in {
        "casteClass": 248, "minimumAgeGroup": 250, "movementBonus": 252,
        "magicResistanceMultiplier": 254, "twoHandBonus": 256,
        "maximumStaminaBonus": 258, "bonusAttacks": 260,
        "maximumAttacks": 262, "startMoney": 384, "defaultIcon": 444}.items()})
    result.update(victoryThresholds=list(struct.unpack_from(">30i", row, 264)),
                  canUseMissile=short(row, 212) != 0, getsMissileBonus=short(row, 214) != 0,
                  startingItemIds=[f"classic.item.{value}" for value in words(row, 386, 20) if value],
                  spellcasterRows=[words(row, 84 + i * 6, 3) for i in range(4)],
                  attackLevels=signed(row, 426, 10),
                  itemCategoryMasks=list(struct.unpack_from(">2i", row, 436)))
    return result


def complex_expected(row):
    result = {name: signed(row, offset) for name, offset in {
        "actionResult": 96, "wordResult": 97, "maxTimes": 153,
        "casteSuccess": 154, "thiefSuccess": 155, "thiefFail": 156}.items()}
    result.update(groups=signed(row, 98, 8), spellIds=words(row, 106, 10),
                  spellResults=signed(row, 126, 10), itemIds=words(row, 136, 5),
                  itemResults=signed(row, 146, 5), canBackOut=row[151] != 0,
                  thief=row[152] != 0, promptMessageId=short(row, 158),
                  texts=[pascal(row[160 + i * 40:200 + i * 40]) for i in range(9)])
    return result


def verify(content, world, native, compare, require, application=None):
    """Compare every field named here; return explicit nonprojection spans."""
    checked = []
    descriptions = {i: pascal(native["Data DES"][i * 256:(i + 1) * 256])
                    for i in range(len(native.get("Data DES", b"")) // 256)}

    def family(path, stride, actual_rows, expected, identity=lambda i: i,
               id_field="classicId", limit=None, unprojected=()):
        if path not in native:
            return
        raw = native[path]
        count = len(raw) // stride
        projected = min(count, limit) if limit is not None else count
        actual = rows_by_id(actual_rows, id_field, require, path)
        fields = 0
        for index in range(projected):
            record_id = identity(index)
            require(record_id in actual, f"{path}: omitted complete native record {index}")
            row = raw[index * stride:(index + 1) * stride]
            for field, value in expected(row, index).items():
                compare(actual[record_id].get(field), value, path, index, field)
                fields += 1
        checked.append({"nativePath": path, "recordsCompared": projected,
                        "fieldsCompared": fields,
                        "unprojectedCompleteRecords": count - projected,
                        "unprojectedByteSpansPerRecord": list(unprojected),
                        "partialBytesRetained": len(raw) % stride})

    for path, set_id in [("Data MD", 0), ("Data MD-1", -1), ("Data MD1", 1)]:
        sets = [row for row in content.get("monsterSets", []) if row.get("setId") == set_id]
        rows = content.get("monsters", []) if set_id == 0 else sets[0]["monsters"] if len(sets) == 1 else None
        family(path, 210, rows, lambda row, index: monster_expected(row, index, descriptions, set_id),
               unprojected=((104, 118, "construction-owned runtime fields"),
                            (119, 121, "construction-owned movement state"),
                            (162, 166, "construction-owned direction/attack state"),
                            (168, 170, "construction-owned maximum spell points")))

    def battle(row, _index):
        cells = words(row, 0, 169)
        return {"distance": signed(row, 338), "messageBeforeId": short(row, 340),
                "messageAfterId": short(row, 342), "macroId": short(row, 344),
                "monsterSlots": [{"monsterId": f"classic.monster.{abs(value)}",
                                  "x": index // 13, "y": index % 13,
                                  "invertTraitor": value < 0}
                                 for index, value in enumerate(cells) if value]}
    family("Data BD", 346, content.get("battles"), battle,
           unprojected=((339, 340, "native alignment byte"),))
    family("Data NI", 100, content.get("items"), lambda row, _: item_expected(row),
           identity=lambda i: 800 + i, limit=200,
           unprojected=((2, 4, "unprojected compatibility short"), (56, 70, "unprojected compatibility shorts")))
    family("Data Spell", 30, content.get("spells"), lambda row, _: spell_expected(row),
           identity=lambda i: 5101 + (i // 15) * 100 + i % 15, limit=105)
    for spell in content.get("spells", []):
        packed = spell.get("classicId", 0)
        require(packed // 1000 in range(1, 6) and packed % 1000 // 100 in range(1, 8)
                and packed % 100 in range(1, 16),
                f"operational spell {packed} exceeds the native five 7-by-15 banks")
    if "Data Spell" in native:
        checked[-1]["unprojectedCompleteRecordDisposition"] = "physical overflow beyond Castle's 105-row custom bank; original bytes and native record lookup retained"
    family("Data TD", 48, content.get("treasures"), lambda row, _: {
        "experience": short(row, 40), "gold": short(row, 42), "gems": short(row, 44),
        "jewelry": short(row, 46),
        "itemIds": [item_ref(value) for value in words(row, 0, 20) if value > 0]})

    def rogue(row, _):
        result = {"typeFlags": [value != 0 for value in row[:10]],
                  "modifiers": signed(row, 10, 8), "successCodes": signed(row, 18, 8),
                  "failureCodes": signed(row, 26, 8)}
        result.update({field: words(row, offset, 8) for field, offset in {
            "successText": 34, "failureText": 50, "successSounds": 66,
            "failureSounds": 82}.items()})
        result.update({field: short(row, offset) for field, offset in {
            "spellId": 98, "lowDamage": 100, "highDamage": 102, "tumblers": 104}.items()})
        result.update(prompts=words(row, 106, 3), promptSounds=words(row, 112, 3))
        return result
    family("Data TD2", 118, content.get("thiefEncounters"), rogue, id_field="id")
    family("Data ED2", 520, content.get("complexEncounters"), lambda row, _: complex_expected(row),
           id_field="id", unprojected=((157, 158, "native alignment byte retained in program suffix"),))
    family("Data SD2", 256, content.get("messages"), lambda row, _: {"text": pascal(row)}, id_field="id")
    family("Data OD", 25, content.get("optionLabels"), lambda row, _: {
        "text": text(row[1:1 + min(row[0], 24)].split(b"\0", 1)[0]).rstrip(" ")}, id_field="id")
    effective_races = _effective_rule_rows(content, application, 'races', 'Data Race', 'raceSource')
    effective_castes = _effective_rule_rows(content, application, 'castes', 'Data Caste', 'casteSource')
    eligibility = {caste_id: sorted({race['id'] for race in effective_races.values()
                                   if caste_id in race.get('eligibleCasteIds', [])}) for caste_id in effective_castes}
    if application is not None:
        for caste_id, row in effective_castes.items():
            require(row.get('eligibleRaceIds') == eligibility[caste_id], f'{caste_id}: derived native creation eligibility differs')
    for path, stride, key, decode, spans in [
            ("Data Race", 408, "races", race_expected,
             ((96, 112, "unprojected compatibility shorts"), (346, 408, "unprojected compatibility tail"))),
            ("Data Caste", 576, "castes", caste_expected,
             ((240, 248, "unprojected compatibility shorts"), (446, 576, "unprojected compatibility tail")))]:
        facts = content.get('classicRecords', {})
        rows = facts.get(key, [])
        if path not in native:
            require(not rows, f'{path}: fabricated native rule facts without source')
            continue
        require(key in facts and isinstance(rows, list), f'{path}: missing native rule facts')
        require(application is not None, f"{path}: explicit application catalog is required for ownership comparison")
        count = min(30, len(native[path]) // stride)
        require([row['classicId'] for row in rows] == list(range(1, count + 1)), f'{path}: native rule identities or extents changed')
        if key == 'castes':
            require(all(row.get('eligibleRaceIds') == [] for row in rows), 'Data Caste: raw facts fabricated derived race eligibility')
        family(path, stride, rows, lambda row, _: decode(row),
               identity=lambda i: i + 1, limit=30, unprojected=spans)
        selection = facts.get('ruleSelection')
        source_field = 'raceSource' if key == 'races' else 'casteSource'
        native_selected = selection is None or selection[source_field] == 'scenario'
        if native_selected:
            effective = {row['classicId']: row for row in content.get(key, [])}
            require(set(effective) == set(range(1, count + 1)), f'{path}: selected native family was compacted or substituted')
            for row in rows:
                expected = {field: value for field, value in row.items() if field not in ('name', 'description')}
                if key == 'castes':
                    expected['eligibleRaceIds'] = eligibility[row['id']]
                actual = {field: value for field, value in effective[row['classicId']].items() if field not in ('name', 'description')}
                require(actual == expected, f'{path}: selected rule differs from native facts at slot {row["classicId"]}')
    return checked


def _effective_rule_rows(content, application, family, path, field):
    facts = content.get('classicRecords', {})
    choice = facts.get('ruleSelection')
    native_selected = choice[field] == 'scenario' if choice is not None else any(row['nativePath'] == path for row in facts.get('sources', []))
    rows = {} if native_selected or application is None else {row['id']: row for row in application[family]}
    rows.update({row['id']: row for row in content.get(family, [])})
    return rows


def self_test_spell_banks(require, error_type=ValueError):
    checks = []
    verify({'spells': [{'classicId': 5715}]}, {}, {}, lambda *args: None, require)
    checks.append({'case': 'last-native-custom-spell-slot-accepted', 'passed': True})
    for packed in (5801, 6101, 7015):
        try:
            verify({'spells': [{'classicId': packed}]}, {}, {}, lambda *args: None, require)
        except error_type:
            checks.append({'case': f'physical-overflow-{packed}-cannot-create-runtime-bank', 'passed': True})
        else:
            raise error_type(f'Operational spell overflow {packed} was accepted')
    return checks
