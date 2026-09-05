## Formats detached spell facts for human-readable spellbook records.
class_name SpellDetailFormatter
extends RefCounted


static func level(spell: SpellView) -> int:
	return ClassicSpellLevel.from_classic_id(spell.classic_id)


static func available_powers(spell: SpellView) -> Array[int]:
	if not spell.power_levels.is_empty():
		return spell.power_levels
	var result: Array[int] = [1]
	return result


static func available_scroll_powers(spell: SpellView) -> Array[int]:
	if not spell.scroll_power_levels.is_empty():
		return spell.scroll_power_levels
	var result: Array[int] = [1]
	return result


static func valid_power(spell: SpellView, preferred: int) -> int:
	var powers := available_powers(spell)
	return preferred if powers.has(preferred) else powers[0]


static func scaled_pair(
	base_min: int,
	base_max: int,
	per_power_min: int,
	per_power_max: int,
	power: int,
	absolute_values: bool = false,
) -> String:
	var low := base_min + per_power_min * power
	var high := base_max + per_power_max * power
	if absolute_values:
		low = absi(low)
		high = absi(high)
	if low == 0 and high == 0:
		return "—"
	return str(low) if low == high else "%d–%d" % [low, high]


static func magic_resistance_label(spell: SpellView, power: int) -> String:
	if spell.damage_type < 1:
		return "Versus"
	if spell.cannot == 1 or spell.cannot > 2:
		return "No"
	if spell.resistance_adjust == 0:
		return "Yes"
	return "%+d" % (power * spell.resistance_adjust)


static func saving_throw_label(spell: SpellView, power: int) -> String:
	if spell.cannot > 1:
		return "No"
	if spell.save_adjust == 0 and spell.save_bonus == 0:
		return "Yes"
	return "%+d" % (spell.save_bonus + power * spell.save_adjust)


static func target_label(spell: SpellView) -> String:
	return {
		0: "Up to power targets",
		1: "One party member",
		3: "Fixed battlefield area",
		4: "Power-sized battlefield area",
		5: "Caster",
		6: "Classic target type 6",
		7: "Party state",
		9: "All friendly",
		10: "All enemies",
		11: "Classic target type 11",
		12: "Everybody",
	}.get(spell.target_type, "Classic target type %d" % spell.target_type)
