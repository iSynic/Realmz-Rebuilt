## Projects authoritative battle state into the typed, detached combat command request.

class_name CombatInteractionRequestBuilder
extends RefCounted

## Keeps request projection read-only and separate from battle lifecycle mutation.

var _content: RealmzContent
var _game_state: GameState
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rules = rules


func build(request_id: String) -> InteractionRequest:
	var combat_view := CombatView.new(_game_state.combat, _game_state.party.characters(), _content, _rules.equipment, _rules.battlefield, _rules.combat_flow, _game_state)
	var actions := _base_actions(combat_view)
	var spell_casts := _spell_cast_payloads(combat_view.active_actor_id)
	var item_casts := _item_cast_payloads(combat_view.active_actor_id)
	var scroll_casts := _scroll_cast_payloads(combat_view.active_actor_id)
	if not spell_casts.is_empty():
		actions.append("cast_spell")
	if not item_casts.is_empty():
		actions.append("use_item")
	if not scroll_casts.is_empty():
		actions.append("use_scroll")
	var payload := _request_payload(combat_view, actions, spell_casts, item_casts, scroll_casts)
	var request := InteractionRequest.from_payload(request_id, InteractionRequest.COMBAT, payload)
	if request != null:
		request.transient_combat_view = combat_view
	return request


func _base_actions(combat_view: CombatView) -> Array[String]:
	var actions: Array[String] = []
	for action: StringName in combat_view.legal_actions:
		actions.append(String(action))
	return actions


func _request_payload(combat_view: CombatView, actions: Array[String], spell_casts: Array[Dictionary], item_casts: Array[Dictionary], scroll_casts: Array[Dictionary]) -> Dictionary:
	return {
		"battleId": combat_view.battle_id,
		"round": combat_view.round_number,
		"actorId": combat_view.active_actor_id,
		"attackUnitsRemaining": combat_view.attack_units_remaining,
		"movementRemaining": combat_view.movement_remaining,
		"enemiesRemaining": combat_view.hostile_actor_ids.size(),
		"actions": actions,
		"weaponMode": String(combat_view.weapon_mode),
		"weaponSwitch": _weapon_switch_payload(combat_view),
		"rangedAttack": _ranged_attack_payload(combat_view),
		"retreat": _retreat_payload(combat_view),
		"meleeAttackReason": combat_view.melee_attack_unavailable_reason,
		"targets": _target_payloads(combat_view),
		"combatants": _combatant_payloads(combat_view),
		"movement": _movement_payloads(combat_view),
		"spellCasts": spell_casts,
		"spellCastReason": _rules.combat_flow.magic.selection().character_spell_unavailable_reason(_game_state, _content, combat_view.active_actor_id),
		"fastSpells": _fast_spell_payloads(combat_view.active_actor_id, spell_casts),
		"itemCasts": item_casts,
		"itemCastReason": _rules.combat_flow.magic.character_item_spell_unavailable_reason(_game_state, _content, combat_view.active_actor_id),
		"scrollCasts": scroll_casts,
		"scrollCastReason": _rules.combat_flow.magic.selection().character_scroll_unavailable_reason(_game_state, _content, combat_view.active_actor_id),
		"autoTurn": {"enabled": combat_view.auto_turn.enabled, "reason": combat_view.auto_turn.reason},
		"autoCharacterIds": combat_view.auto_character_ids.duplicate(),
		"delay": {"enabled": combat_view.delay.enabled, "reason": combat_view.delay.reason},
		"bandage": {"enabled": combat_view.bandage.enabled, "reason": combat_view.bandage.reason, "targets": _bandage_target_payloads(combat_view)},
		"turnUndead": {"enabled": combat_view.turn_undead.enabled, "reason": combat_view.turn_undead.reason, "targets": _turn_target_payloads(combat_view)},
		"undo": {"enabled": combat_view.undo.enabled, "reason": combat_view.undo.reason},
	}


static func _weapon_switch_payload(combat_view: CombatView) -> Dictionary:
	return {
		"enabled": combat_view.weapon_switch_available,
		"targetMode": String(combat_view.weapon_switch_target_mode),
		"reason": combat_view.weapon_switch_unavailable_reason,
	}


static func _ranged_attack_payload(combat_view: CombatView) -> Dictionary:
	return {
		"enabled": combat_view.weapon_mode == &"missile" and combat_view.legal_actions.has(&"attack"),
		"reason": combat_view.ranged_attack_unavailable_reason,
	}


static func _retreat_payload(combat_view: CombatView) -> Dictionary:
	return {
		"enabled": combat_view.retreat_available,
		"reason": combat_view.retreat_unavailable_reason,
		"nearestEnemyRange": combat_view.nearest_enemy_range,
	}


static func _target_payloads(combat_view: CombatView) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for monster: MonsterView in combat_view.targets:
		targets.append({"id": monster.id, "kind": "monster", "name": monster.name, "currentHealth": monster.current_health, "maximumHealth": monster.maximum_health})
	for character: CharacterView in combat_view.character_targets:
		targets.append({"id": character.id, "kind": "character", "name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health})
	return targets


func _combatant_payloads(combat_view: CombatView) -> Array[Dictionary]:
	var combatants_by_id: Dictionary = {}
	var terrain_set := _combat_terrain_set()
	for character_state: CharacterState in _game_state.party.characters():
		if _game_state.combat.battlefield == null or not _game_state.combat.battlefield.actors.has_actor(character_state.id):
			continue
		var character := CharacterView.new(character_state, _content)
		var equipment := _rules.equipment.combat_equipment(character_state, _content.items.definitions())
		character.apply_equipment(equipment)
		var payload := _character_combatant_payload(character, equipment)
		_append_combatant_position_facts(payload, combat_view.active_actor_id, character.id, terrain_set)
		_append_character_weapon_facts(payload, character_state, equipment, combat_view.weapon_mode if character.id == combat_view.active_actor_id else &"melee")
		combatants_by_id[character.id] = payload
	for monster: MonsterView in combat_view.monsters:
		if _game_state.combat.battlefield == null or not _game_state.combat.battlefield.actors.has_actor(monster.id):
			continue
		var payload := _monster_combatant_payload(monster, _content.combat.monster_by_id(monster.definition_id))
		_append_combatant_position_facts(payload, combat_view.active_actor_id, monster.id, terrain_set)
		combatants_by_id[monster.id] = payload
	return _ordered_combatants(combat_view.turn_order, combatants_by_id)


static func _ordered_combatants(turn_order: Array[String], combatants_by_id: Dictionary) -> Array[Dictionary]:
	var combatants: Array[Dictionary] = []
	for combatant_id: String in turn_order:
		if combatants_by_id.has(combatant_id):
			combatants.append(combatants_by_id[combatant_id])
			combatants_by_id.erase(combatant_id)
	for remaining: Dictionary in combatants_by_id.values():
		combatants.append(remaining)
	return combatants


static func _movement_payloads(combat_view: CombatView) -> Array[Dictionary]:
	var movement: Array[Dictionary] = []
	for option: CombatMoveOptionView in combat_view.movement_options:
		movement.append({"direction": [option.direction.x, option.direction.y], "destination": [option.destination.x, option.destination.y], "cost": option.movement_cost, "enabled": option.enabled, "reasonCode": String(option.reason), "reason": option.reason_text, "retreat": option.retreats_from_battle, "forcedRetreat": option.forced_retreat, "attackTargetId": option.attack_target_id, "attackTargetName": option.attack_target_name})
	return movement


func _spell_cast_payloads(actor_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for option: CombatSpellOptionView in _rules.combat_flow.magic.selection().character_spell_options(_game_state, _content, actor_id):
		var payload := {"spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "cost": option.cost, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)}
		_append_spell_target_payload(payload, option)
		result.append(payload)
	return result


func _item_cast_payloads(actor_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for option: CombatItemOptionView in _rules.combat_flow.magic.character_item_spell_options(_game_state, _content, actor_id):
		var payload := {"itemInstanceId": option.item_instance_id, "itemId": option.item_definition_id, "itemName": option.item_name, "charges": option.charges, "powerStaged": option.power_staged, "spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)}
		_append_spell_target_payload(payload, option)
		result.append(payload)
	return result


func _scroll_cast_payloads(actor_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for option: Variant in _rules.combat_flow.magic.selection().character_scroll_options(_game_state, _content, actor_id):
		var payload := {"scrollSlot": option.scroll_slot, "spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)}
		_append_spell_target_payload(payload, option)
		result.append(payload)
	return result


static func _append_spell_target_payload(payload: Dictionary, option: Variant) -> void:
	if option.target_mode in [&"sequence", &"coordinate_sequence"]:
		payload["maximumTargets"] = option.maximum_targets
	if option.target_mode == &"sequence":
		var candidates: Array[Dictionary] = []
		for candidate: CombatSpellTargetView in option.target_candidates:
			candidates.append({"id": candidate.id, "kind": String(candidate.kind), "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
		payload["targetCandidates"] = candidates
	if option.target_mode == &"area":
		payload["areaShape"] = option.area_shape
		payload["defaultTargetCoordinate"] = [option.default_target_coordinate.x, option.default_target_coordinate.y]
		payload["areaOffsets"] = option.area_offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y])
		payload["areaRotationOffsets"] = option.area_rotation_offsets.map(func(offsets: Array) -> Array: return offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y]))
		payload["legalTargetCoordinates"] = option.legal_target_coordinates.map(func(coordinate: Vector2i) -> Array[int]: return [coordinate.x, coordinate.y])


func _fast_spell_payloads(actor_id: String, spell_casts: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var character := _game_state.party.character_by_id(actor_id)
	if character == null:
		return result
	for index: int in character.fast_spells().size():
		var binding := character.fast_spell_at(index)
		var spell := _content.magic.spell_by_id(binding.spell_id) if binding != null and not binding.is_empty() else null
		var enabled := _fast_spell_is_available(binding, spell, spell_casts)
		var reason := "This Fast Spell slot is undefined." if binding == null or binding.is_empty() else "The stored spell is unavailable to this character." if spell == null or not character.known_spells().has(binding.spell_id) else "No legal target or casting action is currently available."
		result.append({"slot": index, "spellId": binding.spell_id if binding != null else "", "spellName": spell.name if spell != null else "Undefined Spell", "power": binding.power if binding != null else 0, "enabled": enabled, "reason": "" if enabled else reason})
	return result


static func _fast_spell_is_available(binding: FastSpellBindingState, spell: SpellDefinition, spell_casts: Array[Dictionary]) -> bool:
	if binding == null or binding.is_empty() or spell == null:
		return false
	for cast: Dictionary in spell_casts:
		if cast.get("spellId") == binding.spell_id and int(cast.get("power", 0)) == binding.power:
			return true
	return false


static func _bandage_target_payloads(combat_view: CombatView) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for candidate: CharacterView in combat_view.bandage_candidates:
		targets.append({"id": candidate.id, "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
	return targets


static func _turn_target_payloads(combat_view: CombatView) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for target: MonsterView in combat_view.turn_undead_targets:
		targets.append({"id": target.id, "name": target.name, "hitDice": target.hit_dice, "magicResistance": target.magic_resistance})
	return targets


static func _character_combatant_payload(character: CharacterView, equipment: CharacterCombatEquipment) -> Dictionary:
	var items: Array[String] = []
	for item: ItemView in character.items:
		var row := "%s • %s" % [item.name, "Equipped" if item.equipped else "Carried"]
		if item.charges >= 0:
			row += " • %d charge%s" % [item.charges, "" if item.charges == 1 else "s"]
		items.append(row)
	var attack_rows: Array[String] = []
	var melee: ItemDefinition = equipment.melee_weapon if equipment != null and equipment.valid else null
	var missile: ItemDefinition = equipment.missile_weapon if equipment != null and equipment.valid else null
	attack_rows.append(_character_attack_row("Melee", melee, character.attacks_per_round))
	if missile != null:
		attack_rows.append(_character_attack_row("Missile", missile, character.attacks_per_round))
	return {"id": character.id, "kind": "character", "name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health, "spellPoints": character.spell_points, "maximumSpellPoints": character.maximum_spell_points, "armor": character.armor, "magicResistance": character.magic_resistance, "attacks": character.attacks_per_round, "movement": character.movement, "maximumMovement": character.maximum_movement, "traitor": character.traitor, "helpless": character.condition_values[ConditionRules.HELPLESS] != 0, "conditions": character.conditions.map(func(condition: CharacterMetricView) -> String: return condition.name), "items": items, "attackRows": attack_rows}


static func _monster_combatant_payload(monster: MonsterView, definition: MonsterDefinition) -> Dictionary:
	var attack_rows: Array[String] = []
	if definition != null:
		var attacks := definition.attacks()
		for index: int in attacks.size():
			var attack := attacks[index]
			attack_rows.append("Attack %d • %d–%d damage" % [index + 1, attack.damage_min, attack.damage_max])
	var items: Array[String] = []
	if not monster.weapon_name.is_empty() and monster.weapon_name != "Unarmed":
		items.append("%s • Equipped" % monster.weapon_name)
	return {"id": monster.id, "kind": "monster", "name": monster.name, "currentHealth": monster.current_health, "maximumHealth": monster.maximum_health, "spellPoints": monster.spell_points, "maximumSpellPoints": monster.maximum_spell_points, "armor": monster.armor, "magicResistance": monster.magic_resistance, "hitDice": monster.hit_dice, "attacks": str(monster.attack_count), "movement": monster.movement_maximum, "maximumMovement": monster.movement_maximum, "traitor": monster.traitor, "helpless": monster.helpless, "conditions": monster.conditions.duplicate(), "items": items, "attackRows": attack_rows, "immunities": monster.immunities.duplicate(), "vulnerabilities": monster.vulnerabilities.duplicate(), "weapon": monster.weapon_name}


static func _character_attack_row(label: String, weapon: ItemDefinition, attacks: String) -> String:
	if weapon == null:
		return "%s • Unarmed • %s attack%s" % [label, attacks, "" if attacks == "1" else "s"]
	var damage := ""
	if weapon.vs_small > 0:
		damage = " • %d–%d damage" % [1 + weapon.damage_bonus, weapon.damage_bonus + weapon.vs_small]
	return "%s • %s%s • %s attack%s" % [label, weapon.name, damage, attacks, "" if attacks == "1" else "s"]


func _append_combatant_position_facts(payload: Dictionary, active_actor_id: String, combatant_id: String, terrain_set: BattleTerrainSetDefinition) -> void:
	if _game_state.combat == null or _game_state.combat.battlefield == null or active_actor_id.is_empty() or combatant_id.is_empty():
		return
	payload["range"] = _rules.battlefield.classic_range(_game_state.combat.battlefield, active_actor_id, combatant_id)
	payload["blocked"] = terrain_set == null or not _rules.battlefield.has_line_of_sight(_game_state.combat.battlefield, terrain_set, active_actor_id, combatant_id)


static func _append_character_weapon_facts(payload: Dictionary, character: CharacterState, equipment: CharacterCombatEquipment, weapon_mode: StringName) -> void:
	if equipment == null or not equipment.valid:
		return
	var weapon := equipment.missile_weapon if weapon_mode == &"missile" else equipment.melee_weapon
	var instance_id := equipment.missile_weapon_instance_id if weapon_mode == &"missile" else equipment.melee_weapon_instance_id
	payload["weapon"] = weapon.name if weapon != null else "Unarmed"
	payload["weaponCharges"] = -1
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			payload["weaponCharges"] = instance.charges
			break


func _combat_terrain_set() -> BattleTerrainSetDefinition:
	if _game_state.combat == null or _game_state.combat.battlefield == null:
		return null
	var map := _content.world.map_by_id(_game_state.combat.battlefield.map_id)
	return _content.world.battle_terrain_set_for_map(map, _game_state.world) if map != null else null
