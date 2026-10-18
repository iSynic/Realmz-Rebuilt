## Formats the detached active combatant facts shown in the battle command deck.
class_name BattleCombatantFacts
extends RefCounted


static func find_combatant(combatants: Array[InteractionRequestValue.Combatant], combatant_id: String) -> InteractionRequestValue.Combatant:
	for combatant: InteractionRequestValue.Combatant in combatants:
		if combatant.id == combatant_id:
			return combatant
	return null


static func find_combatant_index(combatants: Array[InteractionRequestValue.Combatant], combatant_id: String) -> int:
	for index: int in combatants.size():
		if combatants[index].id == combatant_id:
			return index
	return -1


static func active_summary(actor: InteractionRequestValue.Combatant, body: CombatRequestBody, actor_name: String) -> String:
	var lines: Array[String] = ["Active • %s" % actor_name]
	if actor == null:
		lines.append("%d attacks  •  %d movement  •  %s" % [body.attack_units_remaining, body.movement_remaining, String(body.weapon_mode).capitalize()])
		return "\n".join(lines)
	var vitals := "ST %d/%d  •  AR %d" % [actor.current_health, actor.maximum_health, actor.armor]
	if actor.maximum_spell_points > 0:
		vitals += "  •  SP %d/%d" % [actor.spell_points, actor.maximum_spell_points]
	lines.append(vitals + "  •  MV %d/%d" % [body.movement_remaining, actor.maximum_movement])
	var weapon := actor.weapon if not actor.weapon.is_empty() else String(body.weapon_mode).capitalize()
	var action := "%s  •  %s attack%s" % [weapon, actor.attacks, "" if actor.attacks == "1" else "s"]
	if actor.has_weapon_charges and actor.weapon_charges >= 0:
		action += "  •  %d charge%s" % [actor.weapon_charges, "" if actor.weapon_charges == 1 else "s"]
	if not actor.conditions.is_empty():
		action += "  •  " + actor.conditions[0]
	lines.append(action)
	return "\n".join(lines)


static func inspection_summary(combatant: InteractionRequestValue.Combatant) -> Dictionary:
	var details: Array[String] = ["HP %d/%d" % [combatant.current_health, combatant.maximum_health]]
	if combatant.maximum_spell_points > 0: details.append("SP %d/%d" % [combatant.spell_points, combatant.maximum_spell_points])
	details.append("AR %d" % combatant.armor)
	details.append("MR %d" % combatant.magic_resistance)
	if combatant.has_hit_dice: details.append("HD %d" % combatant.hit_dice)
	if combatant.has_position_facts: details.append("Range %d%s" % [combatant.range, " • Blocked" if combatant.blocked else ""])
	var secondary: Array[String] = []
	if not combatant.weapon.is_empty(): secondary.append("%s%s" % [combatant.weapon, " (%d)" % combatant.weapon_charges if combatant.has_weapon_charges and combatant.weapon_charges >= 0 else ""])
	secondary.append("Attacks %s" % combatant.attacks)
	secondary.append("Move %d" % combatant.maximum_movement)
	if not combatant.conditions.is_empty(): secondary.append("Conditions: %s" % ", ".join(combatant.conditions))
	var defenses: Array[String] = []
	if not combatant.immunities.is_empty(): defenses.append("Immune: %s" % ", ".join(combatant.immunities))
	if not combatant.vulnerabilities.is_empty(): defenses.append("Vulnerable: %s" % ", ".join(combatant.vulnerabilities))
	var defense_line := "\n%s" % " • ".join(defenses) if not defenses.is_empty() else ""
	var visible_facts: Array[String] = ["HP %d/%d" % [combatant.current_health, combatant.maximum_health], "AR %d" % combatant.armor]
	if combatant.maximum_spell_points > 0: visible_facts.append("SP %d/%d" % [combatant.spell_points, combatant.maximum_spell_points])
	var visible_action: Array[String] = []
	if not combatant.weapon.is_empty(): visible_action.append(combatant.weapon)
	visible_action.append("%s attacks" % combatant.attacks)
	visible_action.append("Move %d" % combatant.maximum_movement)
	return {
		"label": "Shown • %s\n%s\n%s" % [combatant.name, " • ".join(visible_facts), " • ".join(visible_action)],
		"tooltip": "Shown • %s\n%s\n%s%s" % [combatant.name, " • ".join(details), " • ".join(secondary), defense_line],
	}


static func refresh_inspection(label: Label, icon: TextureRect, combatants: Array[InteractionRequestValue.Combatant], index: int, icons: Dictionary) -> void:
	if label == null:
		return
	if index < 0 or index >= combatants.size():
		label.text = "Shown • No combatant selected"
		icon.texture = null
		icon.visible = false
		return
	var combatant := combatants[index]
	icon.texture = icons.get(combatant.id) as Texture2D
	icon.visible = icon.texture != null
	var summary := inspection_summary(combatant)
	label.text = String(summary["label"])
	label.tooltip_text = String(summary["tooltip"])
