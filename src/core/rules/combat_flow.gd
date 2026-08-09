class_name CombatFlow
extends RefCounted

const MONSTER_ATTACK_COMPLETED := 0
const MONSTER_ATTACK_WAITING := 1
const MONSTER_ATTACK_DEATH_MACRO := 2

var _rules: RealmzRules


func _init(rules: RealmzRules) -> void:
	_rules = rules


func start_battle(state: GameState, content: RealmzContent, battle: BattleDefinition, rng: RealmzRng, surprise: int = 0) -> CombatFlowResult:
	if state == null or content == null or battle == null or rng == null:
		return CombatFlowResult.failed(&"invalid_battle", "Battle setup requires validated state, content, and randomness.")
	if state.combat != null and not state.combat.completed:
		return CombatFlowResult.failed(&"battle_already_active", "A Realmz battle is already active.")
	for character: CharacterState in state.party.characters():
		character.traitor = false
		character.attacks_remaining = 0
		character.movement = character.maximum_movement
	var authored_monsters: Array[MonsterState] = []
	for slot: BattleMonsterSlotDefinition in battle.monster_slots():
		var definition_id := slot.monster_id
		var definition := content.monster_by_id(definition_id)
		if definition == null:
			return CombatFlowResult.failed(&"unknown_monster", "Battle '%s' references unavailable monster '%s'." % [battle.id, definition_id])
		var instance_id := state.next_instance_id("combat.monster")
		var monster := _rules.monsters.build_monster(definition, instance_id, -1, 0, state.clock.day(), rng)
		if monster == null:
			return CombatFlowResult.failed(&"invalid_monster", "Battle '%s' could not construct monster '%s'." % [battle.id, definition_id])
		if slot.invert_traitor:
			monster.traitor = not monster.traitor
		authored_monsters.append(monster)
	if authored_monsters.is_empty():
		return CombatFlowResult.failed(&"empty_battle", "Battle '%s' has no viable monsters." % battle.id)
	var monsters: Array[MonsterState] = []
	var consumed_allies: Array[String] = []
	if not state.allies_suspended:
		for ally: MonsterState in state.party.allies():
			if ally.current_health <= 0:
				continue
			ally.traitor = false
			monsters.append(ally)
			consumed_allies.append(ally.id)
		state.party.set_allies([])
	monsters.append_array(authored_monsters)
	var combat := CombatState.new(battle.id, monsters, battle.macro_id)
	combat.set_turn_order(_rules.combat.initiative_order(state.party.characters(), monsters, surprise, rng))
	state.combat = combat
	var events: Array[DomainEvent] = [DomainEvent.new(&"battle_started", {"battleId": battle.id, "classicId": battle.classic_id, "distance": battle.distance, "surprise": surprise, "turnOrder": combat.turn_order(), "consumedAllyIds": consumed_allies})]
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func submit_action(state: GameState, content: RealmzContent, actor_id: String, action: StringName, target_id: String, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	if combat == null or combat.completed:
		return CombatFlowResult.failed(&"no_active_battle", "No Realmz battle is accepting combat actions.")
	if combat.active_actor_id() != actor_id:
		return CombatFlowResult.failed(&"wrong_combat_actor", "Combat action actor '%s' does not own the current turn." % actor_id)
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0 or actor.traitor:
		return CombatFlowResult.failed(&"invalid_combat_actor", "The current combat actor is unavailable.")
	_prepare_character_turn(combat, actor)
	var events: Array[DomainEvent] = []
	var monster_death_macro_requested := false
	match action:
		&"attack":
			var equipment := _rules.inventory.combat_equipment(actor, content.item_definitions())
			if not equipment.valid:
				return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
			var monster_target := combat.monster_by_id(target_id)
			if monster_target != null and monster_target.current_health > 0 and monster_target.traitor != actor.traitor:
				var definition := content.monster_by_id(monster_target.definition_id)
				var resolution := _rules.combat.resolve_character_attack(actor, equipment, monster_target, definition, rng, state.clock.day())
				events.append(_character_attack_event(actor.id, monster_target.id, &"monster", resolution))
				monster_death_macro_requested = resolution.killed and _request_monster_death_macro(monster_target, definition, events)
			else:
				var character_target := state.party.character_by_id(target_id)
				if character_target == null or character_target.id == actor.id or character_target.current_health <= 0 or character_target.traitor == actor.traitor:
					return CombatFlowResult.failed(&"invalid_combat_target", "The selected combatant is unavailable to this allegiance.")
				var target_equipment := _rules.inventory.combat_equipment(character_target, content.item_definitions())
				if not target_equipment.valid:
					return CombatFlowResult.failed(target_equipment.error_code, target_equipment.error_message)
				var resolution := _rules.combat.resolve_character_attack_character(actor, equipment, character_target, target_equipment, rng)
				events.append(_character_attack_event(actor.id, character_target.id, &"character", resolution))
			_consume_character_attack(actor)
			if not _character_can_continue(actor):
				combat.advance_turn()
			if monster_death_macro_requested:
				return CombatFlowResult.succeeded(events)
		&"defend", &"pass":
			events.append(DomainEvent.new(&"combat_turn_passed", {"actorId": actor.id, "action": String(action)}))
			combat.advance_turn()
		&"retreat":
			combat.completed = true
			combat.outcome = &"retreated"
			combat.clear_active_turn()
			state.last_battle_outcome = combat.outcome
			_restore_party_allegiance(state, events)
			events.append(DomainEvent.new(&"battle_completed", {"battleId": combat.battle_id, "outcome": String(combat.outcome)}))
			return CombatFlowResult.succeeded(events, true)
		_:
			return CombatFlowResult.failed(&"unknown_combat_action", "Combat action '%s' is not available." % action)
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func cast_spell(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell_id: String, power_level: int, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	if combat == null or combat.completed or combat.active_actor_id() != caster_id:
		return CombatFlowResult.failed(&"invalid_spell_turn", "The caster does not own an active combat turn.")
	var caster := state.party.character_by_id(caster_id)
	var target := combat.monster_by_id(target_id)
	var spell := content.spell_by_id(spell_id)
	if caster == null or caster.traitor or target == null or target.current_health <= 0 or not target.traitor or spell == null or power_level < 1:
		return CombatFlowResult.failed(&"invalid_spell_target", "The spell, caster, power, or target is unavailable.")
	if not caster.known_spells().has(spell.id):
		return CombatFlowResult.failed(&"spell_not_known", "The caster does not know '%s'." % spell.id)
	_prepare_character_turn(combat, caster)
	var target_definition := content.monster_by_id(target.definition_id)
	var resolution := _rules.magic.resolve_character_spell(caster, target, target_definition, spell, power_level, caster.level, rng)
	if resolution == null or not resolution.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The spell could not be cast with the available spell points.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_spell_resolved", {"actorId": caster.id, "targetId": target.id, "spellId": spell.id, "power": power_level, "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "duration": resolution.duration, "defeated": resolution.target_defeated})]
	caster.attacks_remaining = _rules.arithmetic.signed_16(caster.attacks_remaining - 2)
	caster.movement = maxi(0, caster.movement - 12)
	combat.advance_turn()
	if resolution.target_defeated and _request_monster_death_macro(target, target_definition, events):
		return CombatFlowResult.succeeded(events)
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func continue_after_monster_death_macro(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null:
		return CombatFlowResult.failed(&"invalid_death_macro_continuation", "Monster death-macro continuation requires an active battle.")
	var events: Array[DomainEvent] = []
	if state.combat.completed or _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func continue_after_age_update(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null or state.combat.pending_monster_attack == null:
		return CombatFlowResult.failed(&"invalid_age_update_continuation", "Monster age-update continuation requires an active battle.")
	var events: Array[DomainEvent] = []
	var combat := state.combat
	var pending := combat.pending_monster_attack
	var target := state.party.character_by_id(pending.target_id)
	if target == null:
		return CombatFlowResult.failed(&"invalid_age_update_continuation", "The pending monster attack target is unavailable.")
	if pending.weapon_condition_index >= 0:
		if target.conditions.value(pending.weapon_condition_index) != pending.weapon_condition_before:
			return CombatFlowResult.failed(&"invalid_age_update_continuation", "The pending monster weapon condition no longer matches its saved boundary.")
		target.conditions.set_value(pending.weapon_condition_index, pending.weapon_condition_after)
	_append_monster_physical_feedback(events, pending.physical_feedback_sound_id)
	target.current_health -= pending.damage
	var defeated := target.current_health <= 0
	var pending_attack_index := maxi(0, combat.active_turn.attack_index - 1) if combat.active_turn != null else 0
	events.append(DomainEvent.new(&"combat_attack_resolved", {"actorId": pending.actor_id, "targetId": pending.target_id, "action": String(pending.action), "attackIndex": pending_attack_index, "hit": true, "damage": pending.damage, "defeated": defeated, "chance": pending.chance, "roll": pending.roll}))
	combat.pending_monster_attack = null
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	var monster := combat.monster_by_id(pending.actor_id)
	var definition := content.monster_by_id(monster.definition_id) if monster != null else null
	if combat.active_turn == null or combat.active_turn.actor_id != pending.actor_id or pending.action != &"advance" or definition == null or combat.active_turn.attack_index >= _monster_attack_limit(definition):
		combat.advance_turn()
	elif defeated:
		combat.active_turn.target_id = ""
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func ally_selection_payload(state: GameState, content: RealmzContent) -> Dictionary:
	if state == null or content == null or state.combat == null or not state.combat.completed or state.allies_suspended:
		return {}
	var candidates: Array[Dictionary] = []
	for monster: MonsterState in state.combat.monsters():
		if candidates.size() >= 32 or monster.current_health <= 0 or monster.traitor:
			continue
		var definition := content.monster_by_id(monster.definition_id)
		if definition == null or definition.can_summon == 0:
			continue
		candidates.append({
			"id": monster.id,
			"name": monster.name,
			"currentHealth": monster.current_health,
			"maximumHealth": monster.maximum_health,
			"classicMonsterId": definition.classic_id,
			"required": definition.can_summon < 0,
			"canSummon": definition.can_summon,
		})
	# bodycount.c promotes mandatory allies and then orders optional survivors by stamina.
	for _pass: int in range(maxi(0, candidates.size() - 1)):
		for index: int in range(maxi(0, candidates.size() - 1)):
			var current: Dictionary = candidates[index]
			var following: Dictionary = candidates[index + 1]
			if int(current["currentHealth"]) < int(following["currentHealth"]) or int(following["canSummon"]) < 0:
				candidates[index] = following
				candidates[index + 1] = current
	var required_ids: Array[String] = []
	for candidate: Dictionary in candidates:
		if candidate["required"]:
			required_ids.append(candidate["id"])
	var maximum := mini(18, 4 + required_ids.size())
	var selected_ids: Array[String] = required_ids.duplicate()
	for index: int in range(mini(10, candidates.size())):
		var candidate_id: String = candidates[index]["id"]
		if selected_ids.size() < maximum and not selected_ids.has(candidate_id):
			selected_ids.append(candidate_id)
	return {
		"prompt": "Choose the allies who will continue with the party.",
		"candidates": candidates,
		"requiredIds": required_ids,
		"maximum": maximum,
		"selectedIds": selected_ids,
	}


func apply_ally_selection(state: GameState, content: RealmzContent, selected_value: Variant) -> CombatFlowResult:
	var payload := ally_selection_payload(state, content)
	if payload.is_empty() or not selected_value is Array:
		return CombatFlowResult.failed(&"invalid_ally_selection", "The post-battle ally selection is unavailable.")
	var selected_ids: Array[String] = []
	for value: Variant in selected_value:
		if not value is String or value.is_empty() or selected_ids.has(value):
			return CombatFlowResult.failed(&"invalid_ally_selection", "Selected allies must be unique stable IDs.")
		selected_ids.append(value)
	if selected_ids.size() > int(payload["maximum"]):
		return CombatFlowResult.failed(&"invalid_ally_selection", "The ally selection exceeds the Classic body-count limit.")
	var candidate_ids: Array[String] = []
	for candidate: Dictionary in payload["candidates"]:
		candidate_ids.append(candidate["id"])
	for required_id: String in payload["requiredIds"]:
		if not selected_ids.has(required_id):
			return CombatFlowResult.failed(&"required_ally_missing", "A scenario-mandatory ally cannot be left behind.")
	for selected_id: String in selected_ids:
		if not candidate_ids.has(selected_id):
			return CombatFlowResult.failed(&"invalid_ally_selection", "The ally selection contains an unavailable combatant.")
	var retained: Array[MonsterState] = []
	for selected_id: String in selected_ids:
		var monster := state.combat.monster_by_id(selected_id)
		if monster == null:
			return CombatFlowResult.failed(&"invalid_ally_selection", "The selected combatant is unavailable.")
		monster.traitor = false
		retained.append(monster)
	state.party.set_allies(retained)
	return CombatFlowResult.succeeded([DomainEvent.new(&"allies_selected", {"battleId": state.combat.battle_id, "allyIds": selected_ids, "maximum": payload["maximum"]})], true)


func _prepare_character_turn(combat: CombatState, character: CharacterState) -> void:
	if combat.active_turn != null:
		return
	combat.begin_active_turn()
	character.movement = character.maximum_movement
	var carried_half_attack := 1 if character.attacks_remaining > 0 else 0
	var haste_half_attacks := 4 if character.conditions.is_active(ConditionRules.SPEEDY) else 0
	character.attacks_remaining = _rules.arithmetic.signed_16(carried_half_attack + character.normal_attacks + character.attack_bonus + haste_half_attacks)


func _consume_character_attack(character: CharacterState) -> void:
	character.attacks_remaining = _rules.arithmetic.signed_16(character.attacks_remaining - 2)
	character.movement = maxi(0, character.movement - 3)


static func _character_can_continue(character: CharacterState) -> bool:
	return character.current_health > 0 and character.attacks_remaining >= 2


func _process_monster_turns(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	var guard := combat.turn_order().size()
	while guard > 0 and not combat.completed:
		var actor_id := combat.active_actor_id()
		var monster := combat.monster_by_id(actor_id)
		if monster == null:
			var charmed_actor := state.party.character_by_id(actor_id)
			if charmed_actor == null or not charmed_actor.traitor:
				if charmed_actor != null and charmed_actor.current_health > 0:
					_prepare_character_turn(combat, charmed_actor)
				break
			if charmed_actor.current_health > 0 and _process_charmed_character_turn(state, content, charmed_actor, rng, events):
				combat.advance_turn()
				return
			combat.advance_turn()
			if _finish_if_resolved(state, content, events):
				break
			guard -= 1
			continue
		if monster.current_health <= 0:
			combat.advance_turn()
			guard -= 1
			continue
		var definition := content.monster_by_id(monster.definition_id)
		if definition == null:
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": "unavailable_definition"}))
			combat.advance_turn()
			guard -= 1
			continue
		var active_turn := combat.begin_active_turn()
		if active_turn.action.is_empty():
			active_turn.action = _rules.monsters.choose_action(monster, definition, rng)
		var attack_result := MONSTER_ATTACK_COMPLETED
		if active_turn.action == &"advance":
			while active_turn.attack_index < _monster_attack_limit(definition):
				attack_result = _resolve_monster_attack_row(state, content, monster, definition, active_turn.attack_index, active_turn, rng, events)
				if attack_result != MONSTER_ATTACK_COMPLETED:
					return
		elif active_turn.action == &"missile":
			attack_result = _resolve_monster_attack_row(state, content, monster, definition, 0, active_turn, rng, events)
			if attack_result != MONSTER_ATTACK_COMPLETED:
				return
		else:
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": String(active_turn.action)}))
		combat.advance_turn()
		if _finish_if_resolved(state, content, events):
			break
		guard -= 1


func _resolve_monster_attack_row(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, attack_index: int, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	if not _monster_target_is_available(state, monster, active_turn.target_id):
		active_turn.target_id = _select_monster_target(state, monster, rng)
	if active_turn.target_id.is_empty():
		active_turn.attack_index = _monster_attack_limit(definition)
		return MONSTER_ATTACK_COMPLETED
	active_turn.attack_index += 1
	var character_target := state.party.character_by_id(active_turn.target_id)
	if character_target != null:
		var race := content.race_by_id(character_target.race_id)
		var caste := content.caste_by_id(character_target.caste_id)
		var charm_bonus := 50 if state.party.conditions.is_active(ConditionRules.PARTY_CHARM_RESISTANCE) else 0
		var defender_equipment := _rules.inventory.combat_equipment(character_target, content.item_definitions())
		var defender_luck := defender_equipment.effective_luck if defender_equipment.valid else character_target.luck
		var weapon := content.item_by_id(monster.weapon_id) if not monster.weapon_id.is_empty() else null
		var defender_armor := defender_equipment.effective_armor if defender_equipment.valid else character_target.armor
		var attack_context := MonsterAttackContext.new(weapon, state.clock.day(), false, defender_luck, state.party.conditions.is_active(ConditionRules.PARTY_DRAGON_HIDE), defender_armor)
		var resolution := _rules.combat.resolve_monster_attack(monster, definition, attack_index, character_target, race, caste, rng, charm_bonus, attack_context)
		var age_update_requested := false
		if resolution.special_handled:
			_append_monster_special_events(events, monster.id, character_target.id, &"character", resolution)
			if resolution.aging != null and resolution.aging.changed_group():
				events.append(DomainEvent.new(&"character_age_changed", resolution.aging.event_payload(character_target, race)))
				age_update_requested = true
		if age_update_requested:
			combat.pending_monster_attack = PendingMonsterAttack.new(monster.id, character_target.id, active_turn.action, resolution.damage, resolution.chance, resolution.roll, resolution.weapon_condition_index, resolution.weapon_condition_before, resolution.weapon_condition_after, resolution.physical_feedback_sound_id)
			return MONSTER_ATTACK_WAITING
		_append_monster_physical_feedback(events, resolution.physical_feedback_sound_id)
		events.append(DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": character_target.id, "action": String(active_turn.action), "attackIndex": attack_index, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll}))
		if resolution.killed:
			active_turn.target_id = ""
		return MONSTER_ATTACK_COMPLETED
	var monster_target := combat.monster_by_id(active_turn.target_id)
	if monster_target == null:
		active_turn.target_id = ""
		return MONSTER_ATTACK_COMPLETED
	var target_definition := content.monster_by_id(monster_target.definition_id)
	var weapon := content.item_by_id(monster.weapon_id) if not monster.weapon_id.is_empty() else null
	var attack_context := MonsterAttackContext.new(weapon, state.clock.day())
	var resolution := _rules.combat.resolve_monster_attack_monster(monster, definition, attack_index, monster_target, target_definition, rng, attack_context)
	if resolution.special_handled:
		_append_monster_special_events(events, monster.id, monster_target.id, &"monster", resolution)
	events.append(DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": monster_target.id, "action": String(active_turn.action), "attackIndex": attack_index, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll}))
	if resolution.killed:
		active_turn.target_id = ""
		if _request_monster_death_macro(monster_target, target_definition, events):
			if active_turn.attack_index >= _monster_attack_limit(definition):
				combat.advance_turn()
			return MONSTER_ATTACK_DEATH_MACRO
	return MONSTER_ATTACK_COMPLETED


func _select_monster_target(state: GameState, monster: MonsterState, rng: RealmzRng) -> String:
	var target_ids: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor != monster.traitor:
			target_ids.append(character.id)
	for candidate: MonsterState in state.combat.monsters():
		if candidate.id != monster.id and candidate.current_health > 0 and candidate.traitor != monster.traitor:
			target_ids.append(candidate.id)
	if target_ids.is_empty():
		return ""
	return target_ids[rng.draw_between(0, target_ids.size() - 1, &"combat.monster-target")]


func _monster_target_is_available(state: GameState, monster: MonsterState, target_id: String) -> bool:
	if target_id.is_empty():
		return false
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.current_health > 0 and character.traitor != monster.traitor
	var candidate := state.combat.monster_by_id(target_id)
	return candidate != null and candidate.id != monster.id and candidate.current_health > 0 and candidate.traitor != monster.traitor


static func _monster_attack_limit(definition: MonsterDefinition) -> int:
	return mini(maxi(0, definition.attack_count), definition.attacks().size())


func _process_charmed_character_turn(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> bool:
	var character_targets: Array[CharacterState] = []
	for candidate: CharacterState in state.party.characters():
		if candidate.id != actor.id and candidate.current_health > 0 and candidate.traitor != actor.traitor:
			character_targets.append(candidate)
	var monster_targets: Array[MonsterState] = []
	for candidate: MonsterState in state.combat.monsters():
		if candidate.current_health > 0 and candidate.traitor != actor.traitor:
			monster_targets.append(candidate)
	var target_count := character_targets.size() + monster_targets.size()
	if target_count == 0:
		return false
	var target_index := rng.draw_between(0, target_count - 1, &"combat.charmed-target")
	var equipment := _rules.inventory.combat_equipment(actor, content.item_definitions())
	if not equipment.valid:
		events.append(DomainEvent.new(&"combat_attack_blocked", {"actorId": actor.id, "reason": String(equipment.error_code), "message": equipment.error_message}))
		return false
	if target_index < character_targets.size():
		var character_target := character_targets[target_index]
		var target_equipment := _rules.inventory.combat_equipment(character_target, content.item_definitions())
		if not target_equipment.valid:
			events.append(DomainEvent.new(&"combat_attack_blocked", {"actorId": actor.id, "targetId": character_target.id, "reason": String(target_equipment.error_code), "message": target_equipment.error_message}))
			return false
		var resolution := _rules.combat.resolve_character_attack_character(actor, equipment, character_target, target_equipment, rng)
		var event := _character_attack_event(actor.id, character_target.id, &"character", resolution)
		event.payload["automatic"] = true
		events.append(event)
		return false
	var monster_target := monster_targets[target_index - character_targets.size()]
	var target_definition := content.monster_by_id(monster_target.definition_id)
	var resolution := _rules.combat.resolve_character_attack(actor, equipment, monster_target, target_definition, rng, state.clock.day())
	var event := _character_attack_event(actor.id, monster_target.id, &"monster", resolution)
	event.payload["automatic"] = true
	events.append(event)
	return resolution.killed and _request_monster_death_macro(monster_target, target_definition, events)


static func _character_attack_event(actor_id: String, target_id: String, target_kind: StringName, resolution: AttackResolution) -> DomainEvent:
	return DomainEvent.new(&"combat_attack_resolved", {
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
		"weaponEffects": resolution.weapon_effects.duplicate(true),
		"weaponConditionIndex": resolution.weapon_condition_index,
		"weaponConditionBefore": resolution.weapon_condition_before,
		"weaponConditionAfter": resolution.weapon_condition_after,
		"criticalRolls": resolution.critical_rolls.duplicate(),
	})


func _append_monster_special_events(events: Array[DomainEvent], actor_id: String, target_id: String, target_kind: StringName, resolution: AttackResolution) -> void:
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


static func _append_monster_physical_feedback(events: Array[DomainEvent], sound_id: int) -> void:
	if sound_id > 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": false, "source": "classic-party-dragon-hide"}))


func _request_monster_death_macro(monster: MonsterState, definition: MonsterDefinition, events: Array[DomainEvent]) -> bool:
	if monster == null or definition == null or definition.death_macro <= 0:
		return false
	events.append(DomainEvent.new(&"monster_death_macro_requested", {
		"combatantId": monster.id,
		"definitionId": monster.definition_id,
		"classicMonsterId": definition.classic_id,
		"programId": "xap:%d" % definition.death_macro,
		"macroId": definition.death_macro,
		"traitor": monster.traitor,
	}))
	return true


func _finish_if_resolved(state: GameState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	var combat := state.combat
	var enemies_alive := false
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor:
			enemies_alive = true
			break
	for monster: MonsterState in combat.monsters():
		if monster.current_health > 0 and monster.traitor:
			enemies_alive = true
			break
	var party_alive := false
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and not character.traitor:
			party_alive = true
			break
	if enemies_alive and party_alive:
		return false
	combat.completed = true
	combat.outcome = &"victory" if party_alive else &"defeat"
	combat.clear_active_turn()
	state.last_battle_outcome = combat.outcome
	_restore_party_allegiance(state, events)
	if combat.outcome == &"victory":
		var experience := 0
		for monster: MonsterState in combat.monsters():
			var definition := content.monster_by_id(monster.definition_id)
			if definition != null and monster.traitor:
				experience += maxi(0, definition.experience)
		var experience_by_character: Dictionary = {}
		for character: CharacterState in state.party.characters():
			if character.current_health > 0:
				var race := content.race_by_id(character.race_id)
				var awarded := _rules.characters.battle_experience(character, race, experience)
				character.experience += awarded
				experience_by_character[character.id] = awarded
		events.append(DomainEvent.new(&"battle_rewards_granted", {"experiencePerSurvivor": experience, "experienceByCharacter": experience_by_character}))
	events.append(DomainEvent.new(&"battle_completed", {"battleId": combat.battle_id, "outcome": String(combat.outcome)}))
	return true


func _restore_party_allegiance(state: GameState, events: Array[DomainEvent]) -> void:
	var restored_ids: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.traitor:
			character.traitor = false
			restored_ids.append(character.id)
	if not restored_ids.is_empty():
		events.append(DomainEvent.new(&"combat_allegiance_restored", {"characterIds": restored_ids}))
