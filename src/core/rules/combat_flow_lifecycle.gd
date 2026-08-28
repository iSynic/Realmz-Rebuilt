class_name CombatFlowLifecycle
extends RefCounted

const ContextType = preload("res://src/core/rules/combat_flow_context.gd")
const CombatRetreatProbeType = preload("res://src/core/rules/combat_retreat_probe.gd")
const CombatCommandProbeType = preload("res://src/core/rules/combat_command_probe.gd")
const CombatScrollOptionViewType = preload("res://src/core/view/combat_scroll_option_view.gd")
const FieldsType = preload("res://src/core/rules/combat_flow_fields.gd")

const MONSTER_ATTACK_COMPLETED := 0
const MONSTER_ATTACK_WAITING := 1
const MONSTER_ATTACK_DEATH_MACRO := 2
const MONSTER_ATTACK_FALLBACK := 3
const REACTION_COMPLETED := 0
const REACTION_WAITING := 1
const REACTION_DEATH_MACRO := 2
const REACTION_MOVER_DEFEATED := 3
const MAX_MONSTERS: int = 100
const MAX_AUTO_OPERATIONS: int = 256
const INVALID_COORDINATE := Vector2i(-100_000, -100_000)
const CHARACTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 10123, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": false},
]
const MONSTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": true},
]

var _flow_ref: WeakRef
var _rules: ContextType


func _init(flow: RefCounted, rules: ContextType) -> void:
	_flow_ref = weakref(flow)
	_rules = rules


func _flow() -> RefCounted:
	return _flow_ref.get_ref() if _flow_ref != null else null

func start_battle(state: GameState, content: RealmzContent, battle: BattleDefinition, rng: RealmzRng, surprise: int = 0, participant_character_ids: Array[String] = []) -> CombatFlowResult:
	if state == null or content == null or battle == null or rng == null:
		return CombatFlowResult.failed(&"invalid_battle", "Battle setup requires validated state, content, and randomness.")
	if state.combat != null and not state.combat.completed:
		return CombatFlowResult.failed(&"battle_already_active", "A Realmz battle is already active.")
	var map := content.world.map_by_id(state.party.map_id)
	if map == null or map.topology.width != 90 or map.topology.height != 90:
		return CombatFlowResult.failed(&"invalid_battle_map", "Battle '%s' requires the party's validated 90 by 90 Classic map." % battle.id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world)
	if terrain_set == null:
		return CombatFlowResult.failed(&"missing_battle_terrain", "Map '%s' has no validated Classic battle-terrain catalog." % map.id)
	var party_characters := state.party.characters()
	if not participant_character_ids.is_empty():
		var participant_set: Dictionary = {}
		for character_id: String in participant_character_ids:
			if participant_set.has(character_id) or state.party.character_by_id(character_id) == null:
				return CombatFlowResult.failed(&"invalid_battle_participants", "Battle participants must be unique members of the current party.")
			participant_set[character_id] = true
		party_characters = party_characters.filter(func(character: CharacterState) -> bool: return participant_set.has(character.id))
		if party_characters.is_empty():
			return CombatFlowResult.failed(&"invalid_battle_participants", "A selective battle requires at least one party participant.")
	var initial_weapon_modes: Dictionary = {}
	for character: CharacterState in party_characters:
		if character.current_health <= 0:
			continue
		var equipment := _rules.inventory.combat_equipment(character, content.item_definitions())
		if not equipment.valid:
			return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
		initial_weapon_modes[character.id] = &"missile" if equipment.melee_weapon == null and equipment.missile_weapon != null else &"melee"
	var ally_definitions: Dictionary = {}
	if not state.allies_suspended:
		for ally: MonsterState in state.party.allies():
			if ally.current_health <= 0:
				continue
			var ally_definition := content.monster_by_id(ally.definition_id)
			if ally_definition == null:
				return CombatFlowResult.failed(&"unknown_ally", "Held-over ally '%s' references unavailable monster '%s'." % [ally.id, ally.definition_id])
			ally_definitions[ally.id] = ally_definition
	var authored_slots := battle.monster_slots()
	if authored_slots.is_empty():
		return CombatFlowResult.failed(&"empty_battle", "Battle '%s' has no viable monsters." % battle.id)
	authored_slots.sort_custom(func(left: BattleMonsterSlotDefinition, right: BattleMonsterSlotDefinition) -> bool:
		return left.coordinate.y < right.coordinate.y or left.coordinate.y == right.coordinate.y and left.coordinate.x < right.coordinate.x
	)
	var authored_definitions: Dictionary = {}
	for slot: BattleMonsterSlotDefinition in authored_slots:
		var definition := content.monster_by_id_for_set(slot.monster_id, state.monster_set)
		if definition == null:
			return CombatFlowResult.failed(&"unknown_monster", "Battle '%s' references unavailable monster '%s'." % [battle.id, slot.monster_id])
		authored_definitions[slot.monster_id] = definition

	var rng_checkpoint := rng.checkpoint()
	var instance_checkpoint := state.instance_id_checkpoint()
	var battlefield_builder := BattlefieldBuilder.new()
	var terrain_result := battlefield_builder.build_terrain(map, state.world, terrain_set, state.party.coordinate, rng)
	if not terrain_result.is_ok():
		return _battle_setup_failure(state, instance_checkpoint, rng, rng_checkpoint, terrain_result.error_code, terrain_result.error_message)
	var battlefield := terrain_result.battlefield
	var formation := battlefield_builder.roll_formation(battlefield, battle, rng)
	if formation.is_empty():
		return _battle_setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"invalid_battle_formation", "Battle '%s' could not derive Castle's opening formation." % battle.id)
	for party_index: int in party_characters.size():
		var character := party_characters[party_index]
		if not battlefield_builder.place_character(battlefield, terrain_set, character.id, party_index, formation):
			return _battle_setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"character_placement_failed", "Battle '%s' has no legal battlefield cell for '%s'." % [battle.id, character.id])

	var monsters: Array[MonsterState] = []
	var consumed_allies: Array[String] = []
	var consumed_ally_states: Array[MonsterState] = []
	if not state.allies_suspended:
		for ally: MonsterState in state.party.allies():
			if ally.current_health <= 0 or monsters.size() >= MAX_MONSTERS:
				continue
			var ally_definition: MonsterDefinition = ally_definitions[ally.id]
			if not battlefield_builder.place_monster(battlefield, terrain_set, ally.id, Vector2i.ZERO, ally_definition.size):
				return _battle_setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"ally_placement_failed", "Battle '%s' has no legal battlefield footprint for ally '%s'." % [battle.id, ally.id])
			monsters.append(ally)
			consumed_allies.append(ally.id)
			consumed_ally_states.append(ally)
	var pending_authored: Array[Dictionary] = []
	var monster_origin: Vector2i = formation["monsterOrigin"]
	for slot_index: int in authored_slots.size():
		if monsters.size() + pending_authored.size() >= MAX_MONSTERS:
			break
		var slot: BattleMonsterSlotDefinition = authored_slots[slot_index]
		var definition: MonsterDefinition = authored_definitions[slot.monster_id]
		var pending_id := "pending.authored.%d" % slot_index
		if not battlefield_builder.place_monster(battlefield, terrain_set, pending_id, monster_origin + slot.coordinate, definition.size):
			return _battle_setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"monster_placement_failed", "Battle '%s' has no legal battlefield footprint for authored monster at %s." % [battle.id, slot.coordinate])
		var pending_monster := _rules.monsters.build_battle_monster(definition, pending_id, slot.invert_traitor, state.difficulty, state.clock.day(), rng)
		if pending_monster == null:
			return _battle_setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"invalid_monster", "Battle '%s' could not construct monster '%s'." % [battle.id, slot.monster_id])
		pending_authored.append({"placeholderId": pending_id, "monster": pending_monster})
	for character: CharacterState in party_characters:
		if character.current_health <= 0:
			battlefield.remove_character(character.id)
	for pending: Dictionary in pending_authored:
		var monster: MonsterState = pending["monster"]
		var instance_id := state.next_instance_id("combat.monster")
		if not battlefield.replace_monster_id(pending["placeholderId"], instance_id):
			return _battle_setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"invalid_battlefield_identity", "Battle '%s' could not commit a stable monster identity." % battle.id)
		monster.id = instance_id
		monsters.append(monster)
	var combat := CombatState.new(battle.id, monsters, battle.macro_id, battlefield)
	combat.set_turn_order(_rules.combat.initiative_order(party_characters, monsters, surprise, rng))
	for character: CharacterState in party_characters:
		if character.current_health <= 0:
			continue
		var initial_mode := StringName(initial_weapon_modes.get(character.id, &"melee"))
		if not combat.set_character_weapon_mode(character.id, initial_mode):
			return _battle_setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"invalid_weapon_mode", "Battle '%s' could not initialize '%s' weapon mode." % [battle.id, character.id])
	for ally: MonsterState in consumed_ally_states:
		ally.traitor = false
	if not state.allies_suspended:
		state.party.set_allies([])
	for character: CharacterState in party_characters:
		character.traitor = false
		character.attacks_remaining = 0
		character.movement = character.maximum_movement
	state.combat = combat
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"sound_requested", {"soundId": 10049, "waitForCompletion": false, "source": "classic-battle-entry"}),
		DomainEvent.new(&"battle_started", {"battleId": battle.id, "classicId": battle.classic_id, "distance": battle.distance, "rolledDistance": battlefield.rolled_distance, "direction": battlefield.direction_degrees, "mapId": battlefield.map_id, "surprise": surprise, "turnOrder": combat.turn_order(), "participantCharacterIds": party_characters.map(func(character: CharacterState) -> String: return character.id), "consumedAllyIds": consumed_allies}),
	]
	_flow()._process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func _battle_setup_failure(state: GameState, instance_checkpoint: int, rng: RealmzRng, checkpoint: Dictionary, code: StringName, message: String) -> CombatFlowResult:
	if state == null or not state.rollback_instance_ids(instance_checkpoint) or not rng.rollback(checkpoint):
		return CombatFlowResult.failed(&"battle_setup_rollback_failed", "Battle setup failed and could not restore the deterministic RNG boundary.")
	return CombatFlowResult.failed(code, message)


func _advance_turn(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	if state == null or state.combat == null:
		return
	var round_advanced := state.combat.advance_turn()
	for field: RefCounted in state.combat.decay_persistent_fields_for_phase(state.combat.turn_index):
		events.append(DomainEvent.new(&"combat_persistent_field_expired", {"slot": field.slot, "spellId": field.spell_id, "center": [field.center.x, field.center.y], "shape": field.shape, "queueIcon": field.queue_icon, "source": "classic"}))
	if round_advanced:
		_process_persistent_field_round_collisions(state, content, rng, events)
		_process_bleeding_round(state, rng, events)


func _process_persistent_field_round_collisions(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	if combat == null or combat.battlefield == null or combat.persistent_fields().is_empty():
		return
	var actor_ids: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and combat.battlefield.has_actor(character.id):
			actor_ids.append(character.id)
	for monster: MonsterState in combat.monsters():
		if monster.current_health > 0 and combat.battlefield.has_actor(monster.id):
			actor_ids.append(monster.id)
	for actor_id: String in actor_ids:
		var result: int = _flow()._resolve_persistent_field_collisions(state, content, actor_id, rng, events, false, false)
		if result == FieldsType.COLLISION_INVALID:
			events.append(DomainEvent.new(&"combat_persistent_field_collision_failed", {"actorId": actor_id, "reason": "invalid-runtime-state"}))
	if not combat.pending_spell_death_macro_id().is_empty() and not _flow()._begin_persistent_field_death_macros(combat, content, events):
		events.append(DomainEvent.new(&"combat_persistent_field_collision_failed", {"actorId": combat.active_actor_id(), "reason": "invalid-death-macro-queue"}))


func _process_bleeding_round(state: GameState, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	for character: CharacterState in state.party.characters():
		if not combat.is_character_bleeding(character.id):
			continue
		if character.current_health <= -10:
			combat.set_character_bleeding(character.id, false)
			state.set_combat_auto(character.id, false)
			continue
		character.current_health = _rules.arithmetic.signed_16(character.current_health - 1)
		if character.current_health < -9:
			character.lifetime_record.record_death(true)
			combat.set_character_bleeding(character.id, false)
			state.set_combat_auto(character.id, false)
			_flow()._remove_defeated_position(combat, character.id, true)
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 132, "waitForCompletion": false, "source": "classic-combat-bleeding"}))
			events.append(DomainEvent.new(&"combatant_bled_to_death", {"characterId": character.id, "health": character.current_health, "source": "classic"}))
			continue
		var roll := rng.draw(100, StringName("combat.bleeding.%s" % character.id))
		var sound_id := 10121 if roll < 50 else 10123
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": false, "source": "classic-combat-bleeding"}))
		events.append(DomainEvent.new(&"combatant_bleeding_progressed", {"characterId": character.id, "health": character.current_health, "roll": roll, "soundId": sound_id, "source": "classic"}))
	if not _flow().bandage_candidate_ids(state).is_empty():
		# getup.c performs a second, party-wide warning draw after every
		# individual bleeding result when the Classic warning preference is on.
		# Realmz Rebuilt currently preserves that default; exposing the preference
		# itself remains owned by the settings workflow.
		var warning_roll := rng.draw(100, &"combat.bleeding.warning-sound")
		var warning_sound_id := 10121 if warning_roll < 50 else 10123
		events.append(DomainEvent.new(&"sound_requested", {"soundId": warning_sound_id, "waitForCompletion": false, "source": "classic-combat-bleeding-warning"}))
		events.append(DomainEvent.new(&"combat_bleeding_warning", {"roll": warning_roll, "soundId": warning_sound_id, "source": "classic-default"}))


func continue_after_monster_death_macro(state: GameState, content: RealmzContent, rng: RealmzRng, completed_combatant_id: String = "") -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null:
		return CombatFlowResult.failed(&"invalid_death_macro_continuation", "Monster death-macro continuation requires an active battle.")
	var events: Array[DomainEvent] = []
	if not state.combat.pending_spell_death_macro_id().is_empty():
		var expected_id := state.combat.pending_spell_death_macro_id()
		if completed_combatant_id.is_empty():
			completed_combatant_id = expected_id
		if not state.combat.complete_spell_death_macro(completed_combatant_id):
			return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The completed spell death macro does not match the saved queue cursor.")
		var completed_monster := state.combat.monster_by_id(completed_combatant_id)
		var same_subject_remains := state.combat.spell_death_macro_queue().has(completed_combatant_id)
		_flow()._remove_defeated_position(state.combat, completed_combatant_id, completed_monster != null and completed_monster.current_health <= 0 and not same_subject_remains)
		if not state.combat.pending_spell_death_macro_id().is_empty():
			if not _flow()._request_next_spell_death_macro(state.combat, content, events):
				return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The next queued spell death macro references unavailable content.")
			return CombatFlowResult.succeeded(events)
		var spell_actor_id := state.combat.spell_macro_actor_id()
		var advances_turn := state.combat.spell_macro_advances_turn()
		if advances_turn:
			if state.combat.active_actor_id() != spell_actor_id:
				return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The active caster changed before the queued spell action completed.")
		state.combat.clear_spell_death_macro_sequence()
		if advances_turn:
			_advance_turn(state, content, rng, events)
	_flow()._remove_all_defeated_positions(state)
	if state.combat.pending_reaction != null:
		var reaction := state.combat.pending_reaction
		var mover_id := reaction.mover_id
		if _flow()._combatant_is_alive(state, mover_id):
			reaction.mover_killed = false
			var reaction_result = _flow()._continue_pending_reaction(state, content, rng, events)
			if reaction_result == REACTION_WAITING or reaction_result == REACTION_DEATH_MACRO:
				return CombatFlowResult.succeeded(events)
			if reaction_result == REACTION_COMPLETED:
				_flow()._process_monster_turns(state, content, rng, events)
				return CombatFlowResult.succeeded(events, state.combat.completed)
		else:
			state.combat.pending_reaction = null
		if state.combat.active_actor_id() == mover_id:
			_advance_turn(state, content, rng, events)
	if state.combat.completed or _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_flow()._process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func finalize_scenario_monster_destruction(state: GameState, content: RealmzContent) -> CombatFlowResult:
	if state == null or content == null or state.combat == null:
		return CombatFlowResult.failed(&"no_active_battle", "Classic monster destruction requires an active battle.")
	var events: Array[DomainEvent] = []
	_flow()._remove_all_defeated_positions(state)
	if not state.combat.completed:
		_finish_if_resolved(state, content, events)
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
	_flow()._append_monster_physical_feedback(events, pending.physical_feedback_sound_id)
	target.current_health -= pending.damage
	if pending.damage > 0:
		combat.mark_attacked(target.id)
	var defeated := target.current_health <= 0
	_flow()._mark_character_bleeding(state, target, defeated)
	_flow()._remove_defeated_position(combat, target.id, defeated)
	var pending_attack_index := maxi(0, combat.active_turn.attack_index - 1) if combat.active_turn != null and combat.pending_reaction == null else 0
	var pending_attacker := combat.monster_by_id(pending.actor_id)
	var pending_definition := content.monster_by_id(pending_attacker.definition_id) if pending_attacker != null else null
	var pending_weapon := content.item_by_id(pending_attacker.weapon_id) if pending_attacker != null and not pending_attacker.weapon_id.is_empty() else null
	var pending_resolution := AttackResolution.new(true, defeated, pending.chance, pending.roll, pending.damage)
	_flow()._append_monster_attack_audio(events, pending_attacker, pending_definition, pending_attack_index, pending_weapon, pending_resolution, rng)
	var attack_event := DomainEvent.new(&"combat_attack_resolved", {"actorId": pending.actor_id, "targetId": pending.target_id, "action": String(pending.action), "attackIndex": pending_attack_index, "hit": true, "damage": pending.damage, "defeated": defeated, "chance": pending.chance, "roll": pending.roll})
	_flow()._append_physical_result_effect(attack_event, true, pending_weapon != null)
	if combat.pending_reaction != null:
		_flow()._append_reaction_identity(attack_event, pending.action, pending.action == &"withdrawal")
	events.append(attack_event)
	combat.pending_monster_attack = null
	if combat.pending_reaction != null:
		var reaction_kind := combat.pending_reaction.kind
		var mover_id := combat.pending_reaction.mover_id
		if defeated:
			combat.pending_reaction.mover_killed = true
		var reaction_result = _flow()._continue_pending_reaction(state, content, rng, events)
		if reaction_result == REACTION_WAITING or reaction_result == REACTION_DEATH_MACRO:
			return CombatFlowResult.succeeded(events)
		if reaction_result == REACTION_MOVER_DEFEATED:
			if combat.active_actor_id() == mover_id:
				_advance_turn(state, content, rng, events)
			if _finish_if_resolved(state, content, events):
				return CombatFlowResult.succeeded(events, true)
			_flow()._process_monster_turns(state, content, rng, events)
			return CombatFlowResult.succeeded(events, state.combat.completed)
		if reaction_kind == CombatReactionState.CHARACTER_MOVE:
			return CombatFlowResult.succeeded(events)
		_flow()._process_monster_turns(state, content, rng, events)
		return CombatFlowResult.succeeded(events, state.combat.completed)
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	var monster := combat.monster_by_id(pending.actor_id)
	var definition := content.monster_by_id(monster.definition_id) if monster != null else null
	if combat.active_turn == null or combat.active_turn.actor_id != pending.actor_id or pending.action != &"advance" or definition == null or combat.active_turn.attack_index >= _flow()._monster_attack_limit(definition):
		_advance_turn(state, content, rng, events)
	elif defeated:
		combat.active_turn.target_id = ""
	_flow()._process_monster_turns(state, content, rng, events)
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
	# Castle bodycount.c returns before creating Dialog 173 when count is zero.
	# An empty choice is not an interaction boundary and must not stall battle return.
	if candidates.is_empty():
		return {}
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


func fumble_recovery_payload(state: GameState, content: RealmzContent) -> Dictionary:
	if state == null or content == null or state.combat == null or not state.combat.completed:
		return {}
	var queued := state.combat.fumbled_items()
	if queued.is_empty():
		return {}
	var item: ItemInstance = queued[0]
	var definition := content.item_by_id(item.definition_id)
	if definition == null:
		return {}
	var candidates: Array[Dictionary] = []
	for character: CharacterState in state.party.characters():
		var enabled := _rules.inventory.can_restore_item(character, item, definition)
		var reason := ""
		if character.inventory().size() >= InventoryRules.MAX_ITEMS:
			reason = "Inventory is full."
		elif character.carried_load + definition.instance_weight(item.charges) > character.maximum_load:
			reason = "The item would exceed maximum load."
		elif not enabled:
			reason = "This character cannot receive the item."
		candidates.append({
			"id": character.id,
			"name": character.name,
			"currentHealth": character.current_health,
			"maximumHealth": character.maximum_health,
			"enabled": enabled,
			"reason": reason,
		})
	return {
		"mode": "fumbled-item-recovery",
		"prompt": "Recover the fumbled weapon or leave it behind.",
		"battleId": state.combat.battle_id,
		"item": {
			"instanceId": item.id,
			"definitionId": item.definition_id,
			"name": definition.name,
			"charges": item.charges,
			"identified": true,
			"description": definition.description,
			"facts": _fumbled_item_facts(item, definition),
		},
		"characters": candidates,
		"remaining": queued.size(),
	}


static func _fumbled_item_facts(item: ItemInstance, definition: ItemDefinition) -> Array[Dictionary]:
	var facts: Array[Dictionary] = [{"label": "Weight", "value": str(definition.instance_weight(item.charges))}]
	if definition.hands != 0:
		facts.append({"label": "Hands", "value": str(definition.hands)})
	if definition.vs_small != 0:
		facts.append({"label": "Damage", "value": "%d–%d" % [1 + definition.damage_bonus, definition.damage_bonus + definition.vs_small]})
	if definition.vs_large != 0:
		facts.append({"label": "Large damage", "value": "%d–%d" % [1 + definition.damage_bonus, definition.damage_bonus + definition.vs_large]})
	if definition.armor_bonus != 0:
		facts.append({"label": "Armor", "value": "%+d" % definition.armor_bonus})
	_append_nonzero_fumble_fact(facts, "Damage bonus", definition.damage_bonus)
	_append_nonzero_fumble_fact(facts, "Strength", definition.strength_bonus)
	_append_nonzero_fumble_fact(facts, "Luck", definition.luck_bonus)
	_append_nonzero_fumble_fact(facts, "Movement", definition.movement_bonus)
	_append_nonzero_fumble_fact(facts, "Magic resistance", definition.magic_resistance_bonus)
	_append_nonzero_fumble_fact(facts, "Spell points", definition.spell_point_bonus)
	_append_nonzero_fumble_fact(facts, "Heat damage", definition.heat)
	_append_nonzero_fumble_fact(facts, "Cold damage", definition.cold)
	_append_nonzero_fumble_fact(facts, "Electrical damage", definition.electric)
	_append_nonzero_fumble_fact(facts, "Versus undead", definition.vs_undead)
	_append_nonzero_fumble_fact(facts, "Versus demons/devils", definition.vs_demon_devil)
	_append_nonzero_fumble_fact(facts, "Versus evil", definition.vs_evil)
	if item.charges > 0:
		facts.append({"label": "Charges", "value": str(item.charges)})
	return facts


static func _append_nonzero_fumble_fact(facts: Array[Dictionary], label: String, value: int) -> void:
	if value != 0:
		facts.append({"label": label, "value": "%+d" % value})


func apply_fumble_recovery(state: GameState, content: RealmzContent, action: StringName, instance_id: String, character_id: String = "") -> CombatFlowResult:
	var request_payload := fumble_recovery_payload(state, content)
	if request_payload.is_empty():
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "Fumbled-weapon recovery is unavailable.")
	if instance_id != request_payload["item"]["instanceId"]:
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "Fumbled-weapon recovery must identify the pending item and action.")
	if action == &"discard":
		var discarded := state.combat.remove_fumbled_item(instance_id)
		if discarded == null:
			return CombatFlowResult.failed(&"invalid_fumble_recovery", "The pending fumbled weapon is unavailable.")
		return CombatFlowResult.succeeded([DomainEvent.new(&"fumbled_item_left_behind", {"battleId": state.combat.battle_id, "instanceId": discarded.id, "itemId": discarded.definition_id})])
	if action != &"assign" or character_id.is_empty():
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "Fumbled-weapon recovery requires an available character or discard action.")
	var candidate: Dictionary = {}
	for entry: Dictionary in request_payload["characters"]:
		if entry["id"] == character_id:
			candidate = entry
			break
	if candidate.is_empty() or not candidate["enabled"]:
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "The selected character cannot receive the fumbled weapon.")
	var character := state.party.character_by_id(character_id)
	var queued: ItemInstance = state.combat.fumbled_items()[0]
	var definition := content.item_by_id(queued.definition_id)
	if character == null or definition == null or not _rules.inventory.can_restore_item(character, queued, definition):
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "The selected character can no longer receive the fumbled weapon.")
	var recovered := state.combat.remove_fumbled_item(instance_id)
	if recovered == null or not _rules.inventory.restore_item(character, recovered, definition):
		if recovered != null:
			state.combat.requeue_fumbled_item_first(recovered)
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "The fumbled weapon could not be restored atomically.")
	return CombatFlowResult.succeeded([DomainEvent.new(&"fumbled_item_recovered", {"battleId": state.combat.battle_id, "instanceId": recovered.id, "itemId": recovered.definition_id, "characterId": character.id})])


func _finish_if_resolved(state: GameState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	state.prune_combat_auto_characters()
	var combat := state.combat
	if not combat.pending_spell_death_macro_id().is_empty() or not combat.spell_macro_actor_id().is_empty():
		return false
	var enemies_alive := false
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor and combat.battlefield != null and combat.battlefield.has_actor(character.id):
			enemies_alive = true
			break
	for monster: MonsterState in combat.monsters():
		if monster.current_health > 0 and monster.traitor and combat.battlefield != null and combat.battlefield.has_actor(monster.id):
			enemies_alive = true
			break
	var party_alive := _has_loyal_battlefield_character(state)
	if enemies_alive and party_alive:
		return false
	var outcome: StringName = &"victory" if party_alive else &"retreated" if _has_living_retreated_character(state) else &"defeat"
	_complete_battle(state, content, outcome, events)
	return true


func finish_classic_macro_victory(state: GameState, content: RealmzContent) -> CombatFlowResult:
	if state == null or content == null or state.combat == null or state.combat.completed:
		return CombatFlowResult.failed(&"no_active_battle", "Classic opcode 100 requires an active battle macro.")
	var defeated: Array[String] = []
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health > 0 and monster.traitor:
			monster.current_health = 0
			state.combat.battlefield.remove_monster(monster.id)
			defeated.append(monster.id)
	state.combat.classic_post_battle_sentinel = 8
	var events: Array[DomainEvent] = [DomainEvent.new(&"classic_battle_forced_victory", {"battleId": state.combat.battle_id, "monsterIds": defeated, "rewardMode": 5, "postBattleSentinel": 8})]
	_complete_battle(state, content, &"victory", events)
	return CombatFlowResult.succeeded(events, true)


func _complete_battle(state: GameState, _content: RealmzContent, outcome: StringName, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	combat.completed = true
	combat.outcome = outcome
	combat.clear_active_turn()
	state.last_battle_outcome = combat.outcome
	_restore_party_allegiance(state, events)
	events.append(DomainEvent.new(&"battle_completed", {"battleId": combat.battle_id, "outcome": String(combat.outcome)}))


static func _has_loyal_battlefield_character(state: GameState) -> bool:
	if state.combat == null or state.combat.battlefield == null:
		return false
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and not character.traitor and state.combat.battlefield.has_actor(character.id):
			return true
	return false


static func _has_living_retreated_character(state: GameState) -> bool:
	if state.combat == null or state.combat.battlefield == null:
		return false
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and not character.traitor and state.combat.has_character_retreated(character.id):
			return true
	return false


func _restore_party_allegiance(state: GameState, events: Array[DomainEvent]) -> void:
	var restored_ids: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.traitor:
			character.traitor = false
			restored_ids.append(character.id)
	if not restored_ids.is_empty():
		events.append(DomainEvent.new(&"combat_allegiance_restored", {"characterIds": restored_ids}))
