#!/usr/bin/env python3
"""Convert the six Realmz 7.1.2 starter files into the trusted Rebuilt catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import zipfile
from pathlib import Path

FORMAT = "realmz2.classic-starter-characters"
FORMAT_VERSION = 1
SOURCE_VERSION = "Realmz 7.1.2"
CASTLE_REVISION = "491816ad60037394f92c428e99c004494d3c28b3"
LIBRARY_ID = "realmz-classic-character-library"
LIBRARY_HASH = "6e3f23c9a452f70b25040c729e17533de5ddf0c420ff35484fc52f6e0dd25e68"
RULES_VERSION = "realmz-classic-1"
EXPECTED = {
    "Kevlar": "6a5124c03e41977002d93fcfbc52d206c84e4b0b1948a84bcaf41052aa5b41a2",
    "Lothlorian": "0cf31e9ec12d6435f266689548bb1bc7201cdf66da414bc3fea88e51ef7e6b54",
    "Silver Leaf": "ee736cec9c32eb6226b239d0d79d3ee9f270cf87f29a0d6b1c48268b78bf70d9",
    "Traskelion": "62a785a49d93f7aebfb4abca4aa3eb8d347e6f6dea1b0526b5483c20d8a1a262",
    "Trevor": "06e65b0ae81a0d0cb220a7f46ab8e2daf28ecf4575396e71d269603b1e3aa15b",
    "Vormale": "440e0b9cb675f7cc68553ab3414b830bb8d1889518e095ba4e16d00805f957f5",
}


def canonical(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def s16(data: bytes, offset: int) -> int:
    return struct.unpack_from(">h", data, offset)[0]


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from(">H", data, offset)[0]


def s32(data: bytes, offset: int) -> int:
    return struct.unpack_from(">i", data, offset)[0]


def spell_id(caste: int, level: int, number: int) -> str:
    return f"classic.spell.{1101 + caste * 1000 + level * 100 + number}"


def appearance_lookup(package_path: Path) -> dict[tuple[str, int], str]:
    with zipfile.ZipFile(package_path) as archive:
        payload = json.loads(archive.read("assets/index.json"))
    return {(entry["kind"], int(entry["resourceId"])): entry["id"] for entry in payload["assets"]}


def convert(source_path: Path, appearance: dict[tuple[str, int], str]) -> tuple[dict, dict]:
    data = source_path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if len(data) != 872 or EXPECTED.get(source_path.name) != digest:
        raise ValueError(f"{source_path.name}: expected the pinned 872-byte Realmz 7.1.2 source")
    if s16(data, 0) != -3:
        raise ValueError(f"{source_path.name}: unsupported Classic character version {s16(data, 0)}")
    name = data[607:637].split(b"\0", 1)[0].decode("mac_roman")
    if name != source_path.name:
        raise ValueError(f"{source_path.name}: embedded name is {name!r}")
    character_id = "classic.starter." + name.lower().replace(" ", "-")
    portrait_id = appearance.get(("portrait", s16(data, 82)), "")
    combat_icon_id = appearance.get(("combat-icon", s16(data, 84)), "")
    if not portrait_id or not combat_icon_id:
        raise ValueError(f"{source_path.name}: stock appearance resources are absent from the application library")

    inventory = []
    for slot in range(30):
        offset = 292 + slot * 6
        item_id = s16(data, offset)
        if item_id == 0:
            continue
        inventory.append({
            "id": f"{character_id}.item.{slot + 1}",
            "definitionId": f"classic.item.{item_id}",
            "equipped": struct.unpack_from(">b", data, offset + 2)[0] != 0,
            "identified": struct.unpack_from(">b", data, offset + 3)[0] != 0,
            "charges": s16(data, offset + 4),
        })

    known_spells = []
    caster_type = s16(data, 52)
    for level in range(7):
        for number in range(12):
            if data[523 + level * 12 + number] != 0:
                known_spells.append(spell_id(caster_type - 1, level, number))

    scroll_case = []
    for slot in range(5):
        caste, level, number, power = struct.unpack_from(">bbbb", data, 472 + slot * 4)
        scroll_case.append({"spellId": spell_id(caste, level, number) if power > 0 else "", "power": power if power > 0 else 0})

    fast_spells = []
    for slot in range(10):
        values = [s16(data, 692 + slot * 8 + index * 2) for index in range(4)]
        caste, level, number, power = values
        fast_spells.append({"spellId": spell_id(caste, level, number) if power > 0 else "", "power": power if power > 0 else 0})

    lifetime_values = [s32(data, 640 + index * 4) for index in range(13)]
    lifetime_names = ["damageTaken", "damageGiven", "hitsGiven", "hitsTaken", "attacksMissed", "enemyMisses", "kills", "deaths", "knockouts", "spellsCast", "destroyed", "turns"]
    state = {
        "id": character_id,
        "name": name,
        "currentHealth": s16(data, 78),
        "maximumHealth": s16(data, 80),
        "raceId": f"classic.race.{s16(data, 48)}",
        "casteId": f"classic.caste.{s16(data, 50)}",
        "gender": s16(data, 54),
        "portraitId": portrait_id,
        "combatIconId": combat_icon_id,
        "level": s16(data, 56),
        "experience": s32(data, 496),
        "ageDays": s32(data, 492),
        "ageGroup": s16(data, 288),
        "attributes": list(struct.unpack_from(">bbbbbb", data, 517)),
        "toHit": s16(data, 4),
        "dodge": s16(data, 6),
        "missile": s16(data, 8),
        "twoHand": s16(data, 10),
        "handToHand": s16(data, 96),
        "damageBonus": s16(data, 46),
        "armor": s16(data, 44),
        "magicResistance": s16(data, 40),
        "movement": s16(data, 58),
        "maximumMovement": s16(data, 60),
        "normalAttacks": s16(data, 14),
        "attackBonus": s16(data, 30),
        "attacksRemaining": s16(data, 62),
        "maximumSpellAttacks": s16(data, 772),
        "spellcasterType": caster_type,
        "spellPoints": s16(data, 86),
        "maximumSpellPoints": s16(data, 88),
        "load": u16(data, 500),
        "maximumLoad": u16(data, 502),
        "prestigePenalty": lifetime_values[12],
        "lifetimeRecord": dict(zip(lifetime_names, lifetime_values[:12])),
        "traitor": s16(data, 12) != 0,
        "conditions": {"count": 40, "values": [s16(data, 98 + index * 2) for index in range(40)]},
        "money": {"gold": u16(data, 504), "gems": u16(data, 506), "jewelry": u16(data, 508)},
        "saves": [s16(data, 272 + index * 2) for index in range(8)],
        "specials": [s16(data, 178 + index * 2) for index in range(12)],
        "abilities": [s16(data, 242 + index * 2) for index in range(15)],
        "inventory": inventory,
        "knownSpells": known_spells,
        "scrollCase": scroll_case,
        "fastSpells": fast_spells,
    }
    record = {
        "format": "realmz2-character",
        "formatVersion": 1,
        "characterId": character_id,
        "revisionHash": "",
        "rulesVersion": RULES_VERSION,
        "sourceCampaignId": LIBRARY_ID,
        "sourcePackageHash": LIBRARY_HASH,
        "publication": {"name": name, "level": state["level"], "source": f"{SOURCE_VERSION} starter character"},
        "sourceRevision": digest,
        "state": state,
    }
    record["revisionHash"] = hashlib.sha256(canonical(record).encode("utf-8")).hexdigest()
    source = {"name": source_path.name, "bytes": len(data), "sha256": digest}
    return source, record


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("tools/fixtures/classic-character-files/7.1.2"))
    parser.add_argument("--library", type=Path, default=Path("src/infrastructure/characters/realmz-classic-character-library.realmz2"))
    parser.add_argument("--output", type=Path, default=Path("src/infrastructure/characters/realmz-classic-starter-characters.json"))
    args = parser.parse_args()
    appearance = appearance_lookup(args.library)
    sources, records = [], []
    for filename in EXPECTED:
        source, record = convert(args.source / filename, appearance)
        sources.append(source)
        records.append(record)
    catalog = {
        "format": FORMAT,
        "formatVersion": FORMAT_VERSION,
        "sourceVersion": SOURCE_VERSION,
        "castleSourceRevision": CASTLE_REVISION,
        "applicationCharacterLibraryPackageHash": LIBRARY_HASH,
        "sources": sources,
        "records": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(canonical(catalog) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
