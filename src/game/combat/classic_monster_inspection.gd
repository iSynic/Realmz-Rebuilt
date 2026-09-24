## Formats source-backed Classic monster attack and inventory facts for detached views.

class_name ClassicMonsterInspection
extends RefCounted

# Source: Castle src/realmz_orig/beast.c and base/Realmz/Data Files/The Family Jewels.rsrc @ 491816ad60037394f92c428e99c004494d3c28b3.

const NATURAL_ATTACK_NAMES: Dictionary = {
	32: "Pummel",
	33: "Claw",
	34: "Bite",
	35: "Not Used",
	36: "Not Used",
	37: "Not Used",
	38: "Punch • Kick",
	39: "Club",
	40: "Slime",
	41: "Sting",
}

const SPECIAL_ATTACK_NAMES: Dictionary = {
	0: "No Special Attacks",
	1: "Cause Fear",
	2: "Paralyze",
	3: "Curse",
	4: "Stupify",
	5: "Entangle",
	6: "Poison",
	7: "Confuse",
	8: "Drain Spell Points",
	9: "Drain Experience",
	10: "Charm",
	11: "Fire Damage",
	12: "Cold Damage",
	13: "Electric Damage",
	14: "Chemical Damage",
	15: "Mental Damage",
	16: "Cause Disease",
	17: "Cause Age",
	18: "Cause Blindness",
	19: "Turn to Stone",
}


static func natural_attack_name(sound_or_type: int) -> String:
	return String(NATURAL_ATTACK_NAMES.get(sound_or_type, ""))


static func special_attack_name(special: int) -> String:
	return String(SPECIAL_ATTACK_NAMES.get(special, ""))


static func attack_rows(attacks: Array[MonsterAttackDefinition], weapon: ItemDefinition = null, weapon_name: String = "", creature_damage_bonus: int = 0, random_weapon_table: int = 0, weapon_reference_unresolved: bool = false) -> Array[String]:
	var rows: Array[String] = []
	var has_physical_attack := false
	if random_weapon_table > 0:
		rows.append("By weapon: random weapon table %d; selection unresolved" % random_weapon_table)
		has_physical_attack = true
	elif weapon != null:
		rows.append("%s: 1–%d base damage (vs. small)" % [weapon_name, weapon.vs_small])
		has_physical_attack = true
	elif weapon_reference_unresolved:
		rows.append("By weapon: weapon definition unresolved")
		has_physical_attack = true
	else:
		for attack: MonsterAttackDefinition in attacks:
			if attack.damage_min == 0:
				continue
			var attack_name := natural_attack_name(attack.sound_or_type)
			if attack_name.is_empty():
				attack_name = "Unknown Classic attack type %d" % attack.sound_or_type
			rows.append("%s: %d–%d base damage" % [attack_name, attack.damage_min, attack.damage_max])
			has_physical_attack = true
	if has_physical_attack and creature_damage_bonus != 0:
		rows.append("Creature damage bonus: %+d" % creature_damage_bonus)
	var found_special := false
	for attack: MonsterAttackDefinition in attacks:
		if attack.special == 0:
			continue
		found_special = true
		var special_name := special_attack_name(attack.special)
		rows.append("Special: %s" % (special_name if not special_name.is_empty() else "Unknown Classic special %d" % attack.special))
	if not found_special:
		rows.append("No Special Attacks")
	return rows


static func carried_item_name(item: ItemDefinition) -> String:
	return item.unidentified_name if item != null else ""


static func carried_item_row(item: ItemDefinition, equipped: bool, magic_detected: bool) -> String:
	if item == null:
		return ""
	var row := "%s — %s" % [carried_item_name(item), "Equipped" if equipped else "Carried"]
	if magic_detected and item.magical:
		row += " — Magic detected"
	return row
