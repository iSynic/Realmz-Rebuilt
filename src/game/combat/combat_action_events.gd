## Builds physical-combat feedback and owns fumble and death-macro event transitions.

class_name CombatActionEvents
extends RefCounted

const CHARACTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 10123, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": false},
]
const MONSTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": true},
]

var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context


static func character_attack_event(actor_id: String, target_id: String, target_kind: StringName, resolution: AttackResolution, armed: bool) -> DomainEvent:
	var event := DomainEvent.new(&"combat_attack_resolved", {
		"actorId": actor_id,
		"targetId": target_id,
		"targetKind": String(target_kind),
		"hit": resolution.hit,
		"damage": resolution.damage,
		"physicalDamage": resolution.physical_damage,
		"defeated": resolution.killed,
		"chance": resolution.chance,
		"roll": resolution.roll,
		"reflected": resolution.reflected,
		"blocked": resolution.blocked,
		"blockReason": String(resolution.block_reason),
		"fumbled": resolution.fumbled,
		"fumbleRoll": resolution.fumble_roll,
		"fumbleBlockReason": String(resolution.fumble_block_reason),
		"weaponEffects": resolution.weapon_effects.duplicate(true),
		"weaponConditionIndex": resolution.weapon_condition_index,
		"weaponConditionBefore": resolution.weapon_condition_before,
		"weaponConditionAfter": resolution.weapon_condition_after,
		"criticalRolls": resolution.critical_rolls.duplicate(),
	})
	append_physical_result_effect(event, resolution.hit, armed)
	return event


static func append_physical_result_effect(event: DomainEvent, hit: bool, armed: bool) -> void:
	if event == null or not hit:
		return
	event.payload["classicResultEffectResourceId"] = 160 if armed else 161


func commit_character_fumble(state: GameState, character: CharacterState, equipment: CharacterCombatEquipment, events: Array[DomainEvent]) -> bool:
	if state.combat == null or equipment == null or equipment.melee_weapon == null or equipment.melee_weapon_instance_id.is_empty() or not state.combat.dropped_items.can_queue():
		return false
	var instance: ItemInstance = null
	for carried: ItemInstance in character.inventory():
		if carried.id == equipment.melee_weapon_instance_id and carried.definition_id == equipment.melee_weapon.id and carried.equipped:
			instance = carried
			break
	if instance == null or not state.combat.dropped_items.queue(instance):
		return false
	var removed := _context.inventory.remove_item(character, instance.id, equipment.melee_weapon)
	if removed == null:
		state.combat.dropped_items.remove(instance.id)
		instance.equipped = true
		return false
	# FD-COMBAT-005 preserves the exact runtime item and its remaining charges.
	# Castle's short-only queue reconstructs the item from its definition at booty.
	removed.identified = true
	append_fumble_feedback(events, character.id, removed, true)
	return true


static func commit_monster_fumble(monster: MonsterState, events: Array[DomainEvent]) -> void:
	var weapon_id := monster.weapon_id
	monster.weapon_id = ""
	append_fumble_feedback(events, monster.id, null, false, weapon_id)


static func append_fumble_feedback(events: Array[DomainEvent], actor_id: String, item: ItemInstance, player_weapon: bool, monster_weapon_id: String = "") -> void:
	var sounds := CHARACTER_FUMBLE_SOUNDS if player_weapon else MONSTER_FUMBLE_SOUNDS
	for sound: Dictionary in sounds:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound["soundId"], "waitForCompletion": sound["waitForCompletion"], "source": "classic-combat-fumble"}))
	events.append(DomainEvent.new(&"combatant_fumbled", {
		"combatantId": actor_id,
		"instanceId": item.id if item != null else "",
		"itemId": item.definition_id if item != null else monster_weapon_id,
		"playerWeapon": player_weapon,
		"changed": true,
		"source": "classic",
	}))


static func append_monster_special_events(events: Array[DomainEvent], actor_id: String, target_id: String, target_kind: StringName, resolution: AttackResolution) -> void:
	events.append(DomainEvent.new(&"combat_monster_special_resolved", {
		"actorId": actor_id,
		"targetId": target_id,
		"targetKind": String(target_kind),
		"specialCode": resolution.special_code,
		"potency": resolution.special_potency,
		"saveIndex": resolution.special_save_index,
		"saveChance": resolution.special_save_chance,
		"saveRoll": resolution.special_save_roll,
		"saved": resolution.special_saved,
		"conditionIndex": resolution.special_condition_index,
		"conditionBefore": resolution.special_condition_before,
		"conditionAfter": resolution.special_condition_after,
		"blocked": resolution.special_blocked,
		"blockReason": String(resolution.special_block_reason),
		"applied": resolution.special_applied,
		"ageDays": resolution.special_age_days,
		"resource": String(resolution.special_resource),
		"amount": resolution.special_amount,
		"targetBefore": resolution.special_target_before,
		"targetAfter": resolution.special_target_after,
		"actorBefore": resolution.special_actor_before,
		"actorAfter": resolution.special_actor_after,
		"element": String(resolution.special_element),
		"damageRolled": resolution.special_damage_rolled,
		"damageAmount": resolution.special_damage_amount,
		"displayAmount": resolution.special_display_amount,
		"allegianceBefore": resolution.special_allegiance_before,
		"allegianceAfter": resolution.special_allegiance_after,
		"physicalDamageSkipped": resolution.physical_damage_skipped,
		"soundId": resolution.special_sound_id,
		"source": "classic",
	}))
	if resolution.special_announced and resolution.special_sound_id != 0:
		var sound_source := "classic-monster-status" if resolution.special_condition_index >= 0 else "classic-monster-special"
		events.append(DomainEvent.new(&"sound_requested", {"soundId": resolution.special_sound_id, "waitForCompletion": false, "source": sound_source}))


static func append_monster_physical_feedback(events: Array[DomainEvent], sound_id: int) -> void:
	if sound_id > 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": true, "source": "classic-party-dragon-hide"}))


static func append_character_attack_audio(events: Array[DomainEvent], attacker: CharacterState, equipment: CharacterCombatEquipment, resolution: AttackResolution, target_kind: StringName) -> void:
	if attacker == null or equipment == null or resolution == null:
		return
	if resolution.blocked:
		append_attack_sound(events, weapon_requirement_sound(resolution.block_reason))
		return
	if not resolution.hit:
		append_attack_sound(events, 650)
		return
	var sound_id := 600 + (equipment.melee_weapon.sound_id if equipment.melee_weapon != null else 30 + attacker.gender * 8)
	if resolution.killed and target_kind == &"character":
		append_attack_sound(events, 132)
	append_attack_sound(events, sound_id)
	if resolution.killed and target_kind != &"character":
		append_attack_sound(events, 132)


static func append_monster_attack_audio(events: Array[DomainEvent], attacker: MonsterState, definition: MonsterDefinition, attack_index: int, weapon: ItemDefinition, resolution: AttackResolution, rng: RealmzRng) -> void:
	if attacker == null or definition == null or resolution == null or rng == null:
		return
	if resolution.blocked:
		append_attack_sound(events, weapon_requirement_sound(resolution.block_reason))
		return
	if not resolution.hit:
		append_attack_sound(events, 650)
		return
	var sound_id := 0
	if weapon != null:
		if weapon.blunt == -2:
			sound_id = rng.draw_between(635, 637, &"combat.monster-attack.sound")
		else:
			sound_id = 632 if rng.draw(100, &"combat.monster-attack.sound") < 50 else 639
	else:
		var attacks := definition.attacks()
		var selected := MonsterAttackDefinition.new(1, 1)
		if not attacks.is_empty():
			selected = attacks[clampi(attack_index, 0, attacks.size() - 1)]
			if selected.damage_min == 0:
				selected = attacks[0]
		sound_id = 600 + selected.sound_or_type
		if sound_id == 631:
			sound_id = 632
	append_attack_sound(events, sound_id)
	if resolution.killed:
		append_attack_sound(events, 132)


static func weapon_requirement_sound(reason: StringName) -> int:
	match reason:
		&"classic_blunt_weapon_required":
			return 621
		&"classic_sharp_weapon_required":
			return 639
		&"classic_magic_weapon_required", &"classic_specific_weapon_required":
			return 698
	return 0


static func append_attack_sound(events: Array[DomainEvent], native_sound_id: int) -> void:
	if native_sound_id == 0:
		return
	events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(native_sound_id), "waitForCompletion": native_sound_id < 0, "source": "classic-combat-attack"}))


static func request_monster_death_macro(monster: MonsterState, definition: MonsterDefinition, events: Array[DomainEvent]) -> bool:
	if monster == null or definition == null or definition.death_macro <= 0:
		return false
	append_monster_death_macro_request(monster, definition, events, false)
	return true


static func queue_spell_death_macro(combat: CombatState, monster: MonsterState, definition: MonsterDefinition) -> bool:
	return combat != null and monster != null and definition != null and definition.death_macro > 0 and combat.spell_runtime.queue_death_macro(monster.id)


static func request_next_spell_death_macro(combat: CombatState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	var combatant_id := combat.spell_runtime.pending_death_macro_id() if combat != null else ""
	var monster := combat.roster.monster_by_id(combatant_id) if combat != null else null
	var definition := content.combat.monster_by_id(monster.definition_id) if monster != null and content != null else null
	if monster == null or definition == null or definition.death_macro <= 0:
		return false
	append_monster_death_macro_request(monster, definition, events, true)
	return true


static func append_monster_death_macro_request(monster: MonsterState, definition: MonsterDefinition, events: Array[DomainEvent], queued_by_spell: bool) -> void:
	events.append(DomainEvent.new(&"monster_death_macro_requested", {
		"combatantId": monster.id,
		"definitionId": monster.definition_id,
		"classicMonsterId": definition.classic_id,
		"programId": "xap:%d" % definition.death_macro,
		"macroId": definition.death_macro,
		"traitor": monster.traitor,
		"queuedBySpell": queued_by_spell,
		"resetTraitorOnComplete": not queued_by_spell,
	}))
