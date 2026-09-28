## Formats the detached active combatant facts shown in the battle command deck.
class_name BattleCombatantFacts
extends RefCounted


static func find_combatant(combatants: Array[InteractionRequestValue.Combatant], combatant_id: String) -> InteractionRequestValue.Combatant:
	for combatant: InteractionRequestValue.Combatant in combatants:
		if combatant.id == combatant_id:
			return combatant
	return null


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
