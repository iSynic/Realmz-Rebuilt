class_name CombatFlow
extends RefCounted

const MONSTER_ATTACK_COMPLETED := 0
const MONSTER_ATTACK_WAITING := 1
const MONSTER_ATTACK_DEATH_MACRO := 2
const REACTION_COMPLETED := 0
const REACTION_WAITING := 1
const REACTION_DEATH_MACRO := 2
const REACTION_MOVER_DEFEATED := 3
const MAX_MONSTERS: int = 100
const CHARACTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 10123, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": false},
]
const MONSTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": true},
]

var _rules: RealmzRules


func _init(rules: RealmzRules) -> void:
	_rules = rules


func start_battle(state: GameState, content: RealmzContent, battle: BattleDefinition, rng: RealmzRng, surprise: int = 0) -> CombatFlowResult:
	if state == null or content == null or battle == null or rng == null:
		return CombatFlowResult.failed(&"invalid_battle", "Battle setup requires validated state, content, and randomness.")
	if state.combat != null and not state.combat.completed:
		return CombatFlowResult.failed(&"battle_already_active", "A Realmz battle is already active.")
	var map := content.world.map_by_id(state.party.map_id)
	if map == null or map.topology.width != 90 or map.topology.height != 90:
		return CombatFlowResult.failed(&"invalid_battle_map", "Battle '%s' requires the party's validated 90 by 90 Classic map." % battle.id)
	var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id)
	if terrain_set == null:
		return CombatFlowResult.failed(&"missing_battle_terrain", "Map '%s' has no validated Classic battle-terrain catalog." % map.id)
	var initial_weapon_modes: Dictionary = {}
	for character: CharacterState in state.party.characters():
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
		var definition := content.monster_by_id(slot.monster_id)
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
	var party_characters := state.party.characters()
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
		var pending_monster := _rules.monsters.build_battle_monster(definition, pending_id, slot.invert_traitor, 0, state.clock.day(), rng)
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
	combat.set_turn_order(_rules.combat.initiative_order(state.party.characters(), monsters, surprise, rng))
	for character: CharacterState in state.party.characters():
		if character.current_health <= 0:
			continue
		var initial_mode := StringName(initial_weapon_modes.get(character.id, &"melee"))
		if not combat.set_character_weapon_mode(character.id, initial_mode):
			return _battle_setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"invalid_weapon_mode", "Battle '%s' could not initialize '%s' weapon mode." % [battle.id, character.id])
	for ally: MonsterState in consumed_ally_states:
		ally.traitor = false
	if not state.allies_suspended:
		state.party.set_allies([])
	for character: CharacterState in state.party.characters():
		character.traitor = false
		character.attacks_remaining = 0
		character.movement = character.maximum_movement
	state.combat = combat
	var events: Array[DomainEvent] = [DomainEvent.new(&"battle_started", {"battleId": battle.id, "classicId": battle.classic_id, "distance": battle.distance, "rolledDistance": battlefield.rolled_distance, "direction": battlefield.direction_degrees, "mapId": battlefield.map_id, "surprise": surprise, "turnOrder": combat.turn_order(), "consumedAllyIds": consumed_allies})]
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func _battle_setup_failure(state: GameState, instance_checkpoint: int, rng: RealmzRng, checkpoint: Dictionary, code: StringName, message: String) -> CombatFlowResult:
	if state == null or not state.rollback_instance_ids(instance_checkpoint) or not rng.rollback(checkpoint):
		return CombatFlowResult.failed(&"battle_setup_rollback_failed", "Battle setup failed and could not restore the deterministic RNG boundary.")
	return CombatFlowResult.failed(code, message)


func submit_action(state: GameState, content: RealmzContent, actor_id: String, action: StringName, target_id: String, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	if combat == null or combat.completed:
		return CombatFlowResult.failed(&"no_active_battle", "No Realmz battle is accepting combat actions.")
	if combat.active_actor_id() != actor_id:
		return CombatFlowResult.failed(&"wrong_combat_actor", "Combat action actor '%s' does not own the current turn." % actor_id)
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0 or actor.traitor:
		return CombatFlowResult.failed(&"invalid_combat_actor", "The current combat actor is unavailable.")
	var events: Array[DomainEvent] = []
	var monster_death_macro_requested := false
	match action:
		&"attack":
			var equipment := _rules.inventory.combat_equipment(actor, content.item_definitions())
			if not equipment.valid:
				return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
			if combat.character_weapon_mode(actor.id) == &"missile":
				return CombatFlowResult.failed(&"missile_attack_unavailable", "Missile range, line of sight, and projectile resolution are not implemented yet. Switch to melee to continue.")
			if combat.battlefield == null:
				return CombatFlowResult.failed(&"missing_battlefield", "Melee requires the session-owned Classic battlefield.")
			if not _rules.battlefield.are_adjacent(combat.battlefield, actor.id, target_id):
				return CombatFlowResult.failed(&"combat_target_not_adjacent", "Classic melee can target only an enemy in an adjacent battlefield footprint.")
			_prepare_character_turn(combat, actor)
			var monster_target := combat.monster_by_id(target_id)
			if monster_target != null and monster_target.current_health > 0 and monster_target.traitor != actor.traitor:
				combat.active_turn.physical_action_committed = true
				var definition := content.monster_by_id(monster_target.definition_id)
				var resolution := _rules.combat.resolve_character_attack(actor, equipment, monster_target, definition, rng, state.clock.day(), false, true, combat.can_queue_fumbled_item())
				if resolution.fumbled and not _commit_character_fumble(state, actor, equipment, events):
					return CombatFlowResult.failed(&"invalid_fumble_state", "The fumbled melee weapon could not enter the battle recovery queue.")
				events.append(_character_attack_event(actor.id, monster_target.id, &"monster", resolution))
				monster_death_macro_requested = resolution.killed and _request_monster_death_macro(monster_target, definition, events)
				_remove_defeated_position(combat, monster_target.id, resolution.killed and not monster_death_macro_requested)
			else:
				var character_target := state.party.character_by_id(target_id)
				if character_target == null or character_target.id == actor.id or character_target.current_health <= 0 or character_target.traitor == actor.traitor:
					return CombatFlowResult.failed(&"invalid_combat_target", "The selected combatant is unavailable to this allegiance.")
				combat.active_turn.physical_action_committed = true
				var target_equipment := _rules.inventory.combat_equipment(character_target, content.item_definitions())
				if not target_equipment.valid:
					return CombatFlowResult.failed(target_equipment.error_code, target_equipment.error_message)
				var resolution := _rules.combat.resolve_character_attack_character(actor, equipment, character_target, target_equipment, rng, false, true, combat.can_queue_fumbled_item())
				if resolution.fumbled and not _commit_character_fumble(state, actor, equipment, events):
					return CombatFlowResult.failed(&"invalid_fumble_state", "The fumbled melee weapon could not enter the battle recovery queue.")
				events.append(_character_attack_event(actor.id, character_target.id, &"character", resolution))
				_remove_defeated_position(combat, character_target.id, resolution.killed)
			_consume_character_attack(actor)
			if not _character_can_continue(actor):
				combat.advance_turn()
			if monster_death_macro_requested:
				return CombatFlowResult.succeeded(events)
		&"switch_weapon":
			var equipment := _rules.inventory.combat_equipment(actor, content.item_definitions())
			if not equipment.valid:
				return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
			var current_mode := combat.character_weapon_mode(actor.id)
			var next_mode: StringName = &"melee" if current_mode == &"missile" else &"missile"
			if next_mode == &"missile" and equipment.missile_weapon == null:
				return CombatFlowResult.failed(&"missile_weapon_unavailable", "The active character has no equipped Classic type-15 missile weapon.")
			_prepare_character_turn(combat, actor)
			if not combat.set_character_weapon_mode(actor.id, next_mode):
				return CombatFlowResult.failed(&"invalid_weapon_mode", "The active character's battle weapon mode could not be changed.")
			events.append(DomainEvent.new(&"combat_weapon_mode_changed", {"actorId": actor.id, "mode": String(next_mode)}))
		&"defend":
			_prepare_character_turn(combat, actor)
			var guard_roll := rng.draw(100, &"combat.guard-sound")
			var guard_sound := 10121 if guard_roll < 50 else 10123
			combat.set_guarding(actor.id, true)
			events.append(DomainEvent.new(&"sound_requested", {"soundId": guard_sound, "waitForCompletion": false, "source": "classic-combat-guard"}))
			events.append(DomainEvent.new(&"combatant_guarded", {"actorId": actor.id, "roll": guard_roll, "soundId": guard_sound, "source": "classic"}))
			combat.advance_turn()
		&"finish", &"pass":
			_prepare_character_turn(combat, actor)
			actor.movement = 0
			combat.set_guarding(actor.id, false)
			events.append(DomainEvent.new(&"combat_turn_passed", {"actorId": actor.id, "action": String(action)}))
			combat.advance_turn()
		&"retreat":
			_prepare_character_turn(combat, actor)
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


func move_character(state: GameState, content: RealmzContent, actor_id: String, destination: Vector2i, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	if combat == null or combat.completed or rng == null:
		return CombatFlowResult.failed(&"no_active_battle", "No Realmz battle is accepting tactical movement.")
	if combat.pending_reaction != null or combat.pending_monster_attack != null:
		return CombatFlowResult.failed(&"combat_reaction_pending", "The previous Classic combat reaction must finish before another movement command.")
	if combat.active_actor_id() != actor_id:
		return CombatFlowResult.failed(&"wrong_combat_actor", "Combat movement actor '%s' does not own the current turn." % actor_id)
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0 or actor.traitor or combat.battlefield == null:
		return CombatFlowResult.failed(&"invalid_combat_actor", "The current combat actor or battlefield is unavailable.")
	var terrain_set := _battle_terrain_set(content, combat.battlefield)
	if terrain_set == null:
		return CombatFlowResult.failed(&"missing_battle_terrain", "The active battlefield has no validated Classic terrain catalog.")
	var origin := combat.battlefield.actor_position(actor_id)
	var direction := destination - origin
	var available_movement := actor.maximum_movement if combat.active_turn == null else actor.movement
	var probe := _rules.battlefield.probe_step(combat.battlefield, terrain_set, actor_id, direction, available_movement)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, _movement_failure_message(probe))
	_prepare_character_turn(combat, actor)
	combat.pending_reaction = CombatReactionState.new(CombatReactionState.CHARACTER_MOVE, actor.id, origin, destination, probe.movement_cost)
	var origin_hostiles := _hostile_adjacent_ids(state, actor.id)
	combat.pending_reaction.set_origin_hostiles(origin_hostiles)
	combat.pending_reaction.set_phase(CombatReactionState.GUARD_BEFORE, _guarding_actor_ids(state, origin_hostiles))
	var events: Array[DomainEvent] = []
	var reaction_result := _continue_pending_reaction(state, content, rng, events)
	if reaction_result == REACTION_MOVER_DEFEATED:
		if combat.active_actor_id() == actor.id:
			combat.advance_turn()
		if _finish_if_resolved(state, content, events):
			return CombatFlowResult.succeeded(events, true)
		_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func _continue_pending_reaction(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var operation_guard := 256
	while combat != null and combat.pending_reaction != null and operation_guard > 0:
		var reaction := combat.pending_reaction
		if reaction.mover_killed or not _combatant_is_alive(state, reaction.mover_id):
			reaction.mover_killed = true
			combat.pending_reaction = null
			return REACTION_MOVER_DEFEATED
		if reaction.has_next_attacker():
			var attacker_id := reaction.take_next_attacker()
			var attack_result := _resolve_reaction_attack(state, content, attacker_id, reaction, rng, events)
			if attack_result != REACTION_COMPLETED:
				if attack_result == REACTION_MOVER_DEFEATED:
					combat.pending_reaction = null
				return attack_result
			operation_guard -= 1
			continue
		match reaction.phase:
			CombatReactionState.GUARD_BEFORE:
				if reaction.kind == CombatReactionState.CHARACTER_MOVE:
					reaction.set_phase(CombatReactionState.WITHDRAWAL, _withdrawal_hostiles(state, reaction))
				else:
					if not _commit_reaction_move(state, content, reaction, events):
						combat.pending_reaction = null
						return REACTION_MOVER_DEFEATED
			CombatReactionState.WITHDRAWAL:
				if not _commit_reaction_move(state, content, reaction, events):
					combat.pending_reaction = null
					return REACTION_MOVER_DEFEATED
			CombatReactionState.GUARD_AFTER:
				combat.pending_reaction = null
				return REACTION_COMPLETED
		operation_guard -= 1
	if operation_guard == 0:
		events.append(DomainEvent.new(&"combat_reaction_failed", {"reason": "reaction-budget-exhausted"}))
		if combat != null:
			combat.pending_reaction = null
	return REACTION_COMPLETED


func _commit_reaction_move(state: GameState, content: RealmzContent, reaction: CombatReactionState, events: Array[DomainEvent]) -> bool:
	var combat := state.combat
	if combat == null or combat.battlefield == null or not _combatant_is_alive(state, reaction.mover_id) or combat.battlefield.actor_position(reaction.mover_id) != reaction.origin:
		return false
	var movement_remaining := 0
	if reaction.kind == CombatReactionState.CHARACTER_MOVE:
		if state.party.character_by_id(reaction.mover_id) == null:
			return false
	else:
		if combat.active_turn == null or combat.active_turn.actor_id != reaction.mover_id:
			return false
	if not combat.battlefield.move_actor(reaction.mover_id, reaction.destination):
		return false
	if reaction.kind == CombatReactionState.CHARACTER_MOVE:
		var character := state.party.character_by_id(reaction.mover_id)
		character.movement = maxi(0, character.movement - reaction.movement_cost)
		movement_remaining = character.movement
	else:
		combat.active_turn.movement_remaining = maxi(0, combat.active_turn.movement_remaining - reaction.movement_cost)
		movement_remaining = combat.active_turn.movement_remaining
	events.append(DomainEvent.new(&"combatant_moved", {
		"actorId": reaction.mover_id,
		"from": [reaction.origin.x, reaction.origin.y],
		"to": [reaction.destination.x, reaction.destination.y],
		"cost": reaction.movement_cost,
		"movementRemaining": movement_remaining,
		"automatic": reaction.kind == CombatReactionState.MONSTER_MOVE,
	}))
	var terrain_set := _battle_terrain_set(content, combat.battlefield)
	var terrain := terrain_set.tile_by_id(combat.battlefield.terrain_at(reaction.destination)) if terrain_set != null else null
	if terrain != null and terrain.sound != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": terrain.sound, "waitForCompletion": terrain.sound < 0, "source": "classic-battle-movement"}))
	reaction.set_phase(CombatReactionState.GUARD_AFTER, _guarding_hostiles(state, reaction.mover_id))
	return true


func _resolve_reaction_attack(state: GameState, content: RealmzContent, attacker_id: String, reaction: CombatReactionState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	if not _combatant_is_alive(state, attacker_id) or _combatant_is_helpless(state, attacker_id):
		return REACTION_COMPLETED
	combat.set_guarding(attacker_id, false)
	var action: StringName = &"withdrawal" if reaction.phase == CombatReactionState.WITHDRAWAL else &"guard"
	var behind := reaction.phase == CombatReactionState.WITHDRAWAL
	var character_attacker := state.party.character_by_id(attacker_id)
	if character_attacker != null:
		return _resolve_character_reaction(state, content, character_attacker, reaction.mover_id, action, behind, rng, events)
	var monster_attacker := combat.monster_by_id(attacker_id)
	if monster_attacker == null:
		return REACTION_COMPLETED
	return _resolve_monster_reaction(state, content, monster_attacker, reaction.mover_id, action, behind, rng, events)


func _resolve_character_reaction(state: GameState, content: RealmzContent, attacker: CharacterState, target_id: String, action: StringName, behind: bool, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var equipment := _rules.inventory.combat_equipment(attacker, content.item_definitions())
	if not equipment.valid:
		events.append(DomainEvent.new(&"combat_reaction_failed", {"actorId": attacker.id, "targetId": target_id, "reason": String(equipment.error_code)}))
		return REACTION_COMPLETED
	var monster_target := combat.monster_by_id(target_id)
	if monster_target != null:
		var definition := content.monster_by_id(monster_target.definition_id)
		var resolution := _rules.combat.resolve_character_attack(attacker, equipment, monster_target, definition, rng, state.clock.day(), behind, true, combat.can_queue_fumbled_item())
		if resolution.fumbled and not _commit_character_fumble(state, attacker, equipment, events):
			events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": attacker.id, "reason": "invalid-fumble-state"}))
		var event := _character_attack_event(attacker.id, monster_target.id, &"monster", resolution)
		_append_reaction_identity(event, action, behind)
		events.append(event)
		if resolution.killed:
			combat.pending_reaction.mover_killed = true
			var death_macro_requested := _request_monster_death_macro(monster_target, definition, events)
			_remove_defeated_position(combat, monster_target.id, not death_macro_requested)
			return REACTION_DEATH_MACRO if death_macro_requested else REACTION_MOVER_DEFEATED
		return REACTION_COMPLETED
	var character_target := state.party.character_by_id(target_id)
	if character_target == null:
		return REACTION_COMPLETED
	var target_equipment := _rules.inventory.combat_equipment(character_target, content.item_definitions())
	if not target_equipment.valid:
		events.append(DomainEvent.new(&"combat_reaction_failed", {"actorId": attacker.id, "targetId": target_id, "reason": String(target_equipment.error_code)}))
		return REACTION_COMPLETED
	var resolution := _rules.combat.resolve_character_attack_character(attacker, equipment, character_target, target_equipment, rng, behind, true, combat.can_queue_fumbled_item())
	if resolution.fumbled and not _commit_character_fumble(state, attacker, equipment, events):
		events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": attacker.id, "reason": "invalid-fumble-state"}))
	var event := _character_attack_event(attacker.id, character_target.id, &"character", resolution)
	_append_reaction_identity(event, action, behind)
	events.append(event)
	if resolution.killed:
		combat.pending_reaction.mover_killed = true
		_remove_defeated_position(combat, character_target.id, true)
		return REACTION_MOVER_DEFEATED
	return REACTION_COMPLETED


func _resolve_monster_reaction(state: GameState, content: RealmzContent, attacker: MonsterState, target_id: String, action: StringName, behind: bool, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var definition := content.monster_by_id(attacker.definition_id)
	if definition == null:
		return REACTION_COMPLETED
	var weapon := content.item_by_id(attacker.weapon_id) if not attacker.weapon_id.is_empty() else null
	var character_target := state.party.character_by_id(target_id)
	if character_target != null:
		var race := content.race_by_id(character_target.race_id)
		var caste := content.caste_by_id(character_target.caste_id)
		var charm_bonus := 50 if state.party.conditions.is_active(ConditionRules.PARTY_CHARM_RESISTANCE) else 0
		var defender_equipment := _rules.inventory.combat_equipment(character_target, content.item_definitions())
		var defender_luck := defender_equipment.effective_luck if defender_equipment.valid else character_target.luck
		var defender_armor := defender_equipment.effective_armor if defender_equipment.valid else character_target.armor
		var context := MonsterAttackContext.new(weapon, state.clock.day(), behind, defender_luck, state.party.conditions.is_active(ConditionRules.PARTY_DRAGON_HIDE), defender_armor)
		var resolution := _rules.combat.resolve_monster_attack(attacker, definition, 0, character_target, race, caste, rng, charm_bonus, context, true)
		if resolution.fumbled:
			_commit_monster_fumble(attacker, events)
		if resolution.special_handled:
			_append_monster_special_events(events, attacker.id, character_target.id, &"character", resolution)
			if resolution.aging != null and resolution.aging.changed_group():
				events.append(DomainEvent.new(&"character_age_changed", resolution.aging.event_payload(character_target, race)))
				combat.pending_monster_attack = PendingMonsterAttack.new(attacker.id, character_target.id, action, resolution.damage, resolution.chance, resolution.roll, resolution.weapon_condition_index, resolution.weapon_condition_before, resolution.weapon_condition_after, resolution.physical_feedback_sound_id)
				return REACTION_WAITING
		_append_monster_physical_feedback(events, resolution.physical_feedback_sound_id)
		var event := DomainEvent.new(&"combat_attack_resolved", {"actorId": attacker.id, "targetId": character_target.id, "targetKind": "character", "action": String(action), "attackIndex": 0, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll})
		_append_reaction_identity(event, action, behind)
		events.append(event)
		if resolution.killed:
			combat.pending_reaction.mover_killed = true
			_remove_defeated_position(combat, character_target.id, true)
			return REACTION_MOVER_DEFEATED
		return REACTION_COMPLETED
	var monster_target := combat.monster_by_id(target_id)
	if monster_target == null:
		return REACTION_COMPLETED
	var target_definition := content.monster_by_id(monster_target.definition_id)
	var context := MonsterAttackContext.new(weapon, state.clock.day(), behind)
	var resolution := _rules.combat.resolve_monster_attack_monster(attacker, definition, 0, monster_target, target_definition, rng, context, true)
	if resolution.fumbled:
		_commit_monster_fumble(attacker, events)
	if resolution.special_handled:
		_append_monster_special_events(events, attacker.id, monster_target.id, &"monster", resolution)
	var event := DomainEvent.new(&"combat_attack_resolved", {"actorId": attacker.id, "targetId": monster_target.id, "targetKind": "monster", "action": String(action), "attackIndex": 0, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll})
	_append_reaction_identity(event, action, behind)
	events.append(event)
	if resolution.killed:
		combat.pending_reaction.mover_killed = true
		var death_macro_requested := _request_monster_death_macro(monster_target, target_definition, events)
		_remove_defeated_position(combat, monster_target.id, not death_macro_requested)
		return REACTION_DEATH_MACRO if death_macro_requested else REACTION_MOVER_DEFEATED
	return REACTION_COMPLETED


static func _append_reaction_identity(event: DomainEvent, action: StringName, behind: bool) -> void:
	event.payload["action"] = String(action)
	event.payload["reaction"] = true
	event.payload["behind"] = behind
	event.payload["automatic"] = true


func _guarding_hostiles(state: GameState, mover_id: String, anchor_override: Vector2i = Vector2i(-1, -1)) -> Array[String]:
	var result: Array[String] = []
	for attacker_id: String in _hostile_adjacent_ids(state, mover_id, anchor_override):
		if state.combat.is_guarding(attacker_id) and not _combatant_is_helpless(state, attacker_id):
			result.append(attacker_id)
	return result


func _withdrawal_hostiles(state: GameState, reaction: CombatReactionState) -> Array[String]:
	var result: Array[String] = []
	if _combatant_is_invisible(state, reaction.mover_id):
		return result
	var after := _rules.battlefield.adjacent_actor_ids(state.combat.battlefield, reaction.mover_id, reaction.destination)
	for attacker_id: String in reaction.origin_hostiles():
		if not after.has(attacker_id) and not _combatant_is_helpless(state, attacker_id):
			result.append(attacker_id)
	return result


func _guarding_actor_ids(state: GameState, actor_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for actor_id: String in actor_ids:
		if state.combat.is_guarding(actor_id) and not _combatant_is_helpless(state, actor_id):
			result.append(actor_id)
	return result


func _combatant_is_alive(state: GameState, actor_id: String) -> bool:
	var character := state.party.character_by_id(actor_id)
	if character != null:
		return character.current_health > 0
	var monster := state.combat.monster_by_id(actor_id) if state.combat != null else null
	return monster != null and monster.current_health > 0


func _combatant_is_helpless(state: GameState, actor_id: String) -> bool:
	var character := state.party.character_by_id(actor_id)
	if character != null:
		return character.conditions.is_active(ConditionRules.HELPLESS)
	var monster := state.combat.monster_by_id(actor_id) if state.combat != null else null
	return monster != null and monster.conditions.is_active(ConditionRules.HELPLESS)


func _combatant_is_invisible(state: GameState, actor_id: String) -> bool:
	var character := state.party.character_by_id(actor_id)
	if character != null:
		return character.conditions.is_active(ConditionRules.INVISIBLE)
	var monster := state.combat.monster_by_id(actor_id) if state.combat != null else null
	return monster != null and monster.conditions.is_active(ConditionRules.INVISIBLE)


func cause_active_fumble(state: GameState, content: RealmzContent, actor_id: String) -> CombatFlowResult:
	if state == null or content == null or state.combat == null or state.combat.completed:
		return CombatFlowResult.failed(&"no_active_battle", "No Realmz battle can receive a fumble operation.")
	if actor_id.is_empty():
		actor_id = state.combat.active_actor_id()
	if actor_id != state.combat.active_actor_id():
		return CombatFlowResult.failed(&"invalid_fumble_actor", "Classic opcode 122 can affect only the active physical combatant.")
	if state.combat.active_turn == null or not state.combat.active_turn.physical_action_committed:
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_fumble_skipped", {"combatantId": actor_id, "reason": "no-physical-action", "source": "classic"})])
	var events: Array[DomainEvent] = []
	var character := state.party.character_by_id(actor_id)
	# Castle's outer q[up] < 10 guard excludes monster initiative IDs (10+).
	# The monster branch nested below that guard is therefore unreachable.
	if character == null:
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_fumble_skipped", {"combatantId": actor_id, "reason": "not-party-actor", "source": "classic"})])
	var equipment := _rules.inventory.combat_equipment(character, content.item_definitions())
	if not equipment.valid:
		return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
	if not equipment.is_armed():
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_fumble_skipped", {"combatantId": actor_id, "reason": "unarmed", "source": "classic"})])
	if not equipment.melee_weapon.cursed_item_id.is_empty():
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_fumble_skipped", {"combatantId": actor_id, "reason": "cursed-weapon", "source": "classic"})])
	if not state.combat.can_queue_fumbled_item():
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_fumble_skipped", {"combatantId": actor_id, "reason": "queue-full", "source": "classic"})])
	if not _commit_character_fumble(state, character, equipment, events):
		return CombatFlowResult.failed(&"invalid_fumble_state", "The active character's melee weapon could not enter the recovery queue.")
	return CombatFlowResult.succeeded(events)


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
	var death_macro_requested := resolution.target_defeated and _request_monster_death_macro(target, target_definition, events)
	_remove_defeated_position(combat, target.id, resolution.target_defeated and not death_macro_requested)
	if death_macro_requested:
		return CombatFlowResult.succeeded(events)
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func continue_after_monster_death_macro(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null:
		return CombatFlowResult.failed(&"invalid_death_macro_continuation", "Monster death-macro continuation requires an active battle.")
	var events: Array[DomainEvent] = []
	_remove_all_defeated_positions(state)
	if state.combat.pending_reaction != null:
		var reaction := state.combat.pending_reaction
		var mover_id := reaction.mover_id
		if _combatant_is_alive(state, mover_id):
			reaction.mover_killed = false
			var reaction_result := _continue_pending_reaction(state, content, rng, events)
			if reaction_result == REACTION_WAITING or reaction_result == REACTION_DEATH_MACRO:
				return CombatFlowResult.succeeded(events)
			if reaction_result == REACTION_COMPLETED:
				_process_monster_turns(state, content, rng, events)
				return CombatFlowResult.succeeded(events, state.combat.completed)
		else:
			state.combat.pending_reaction = null
		if state.combat.active_actor_id() == mover_id:
			state.combat.advance_turn()
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
	_remove_defeated_position(combat, target.id, defeated)
	var pending_attack_index := maxi(0, combat.active_turn.attack_index - 1) if combat.active_turn != null and combat.pending_reaction == null else 0
	var attack_event := DomainEvent.new(&"combat_attack_resolved", {"actorId": pending.actor_id, "targetId": pending.target_id, "action": String(pending.action), "attackIndex": pending_attack_index, "hit": true, "damage": pending.damage, "defeated": defeated, "chance": pending.chance, "roll": pending.roll})
	if combat.pending_reaction != null:
		_append_reaction_identity(attack_event, pending.action, pending.action == &"withdrawal")
	events.append(attack_event)
	combat.pending_monster_attack = null
	if combat.pending_reaction != null:
		var reaction_kind := combat.pending_reaction.kind
		var mover_id := combat.pending_reaction.mover_id
		if defeated:
			combat.pending_reaction.mover_killed = true
		var reaction_result := _continue_pending_reaction(state, content, rng, events)
		if reaction_result == REACTION_WAITING or reaction_result == REACTION_DEATH_MACRO:
			return CombatFlowResult.succeeded(events)
		if reaction_result == REACTION_MOVER_DEFEATED:
			if combat.active_actor_id() == mover_id:
				combat.advance_turn()
			if _finish_if_resolved(state, content, events):
				return CombatFlowResult.succeeded(events, true)
			_process_monster_turns(state, content, rng, events)
			return CombatFlowResult.succeeded(events, combat.completed)
		if reaction_kind == CombatReactionState.CHARACTER_MOVE:
			return CombatFlowResult.succeeded(events)
		_process_monster_turns(state, content, rng, events)
		return CombatFlowResult.succeeded(events, combat.completed)
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
		},
		"characters": candidates,
		"remaining": queued.size(),
	}


func apply_fumble_recovery(state: GameState, content: RealmzContent, response_payload: Variant) -> CombatFlowResult:
	var request_payload := fumble_recovery_payload(state, content)
	if request_payload.is_empty() or not response_payload is Dictionary:
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "Fumbled-weapon recovery is unavailable.")
	if not response_payload.get("action") is String or not response_payload.get("instanceId") is String or response_payload["instanceId"] != request_payload["item"]["instanceId"]:
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "Fumbled-weapon recovery must identify the pending item and action.")
	var action: String = response_payload["action"]
	var instance_id: String = response_payload["instanceId"]
	if action == "discard":
		var discarded := state.combat.remove_fumbled_item(instance_id)
		if discarded == null:
			return CombatFlowResult.failed(&"invalid_fumble_recovery", "The pending fumbled weapon is unavailable.")
		return CombatFlowResult.succeeded([DomainEvent.new(&"fumbled_item_left_behind", {"battleId": state.combat.battle_id, "instanceId": discarded.id, "itemId": discarded.definition_id})])
	if action != "assign" or not response_payload.get("characterId") is String:
		return CombatFlowResult.failed(&"invalid_fumble_recovery", "Fumbled-weapon recovery requires an available character or discard action.")
	var character_id: String = response_payload["characterId"]
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
		if combat.active_turn == null:
			combat.set_guarding(monster.id, true)
		if monster.conditions.is_active(ConditionRules.HELPLESS):
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": "incapacitated"}))
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
		if active_turn.movement_remaining < 0:
			active_turn.movement_remaining = _monster_movement_allowance(monster, definition)
		if active_turn.target_id.is_empty() and active_turn.attack_index == 0:
			active_turn.target_id = monster.target_id
		if active_turn.action.is_empty():
			active_turn.action = _rules.monsters.choose_action(monster, definition, rng, not _hostile_adjacent_ids(state, monster.id).is_empty())
		var attack_result := MONSTER_ATTACK_COMPLETED
		if active_turn.action == &"advance":
			if monster.conditions.is_active(ConditionRules.SPEEDY):
				events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "monster-speedy-cadence-unresolved"}))
			elif monster.conditions.value(ConditionRules.TANGLED) < 0:
				events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "permanent-tangle-movement-unresolved"}))
			else:
				attack_result = _process_monster_advance(state, content, monster, definition, active_turn, rng, events)
				if attack_result != MONSTER_ATTACK_COMPLETED:
					return
		elif active_turn.action == &"missile":
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "missile", "reason": "tactical-position-unavailable"}))
		elif active_turn.action == &"cast":
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "reason": "monster-spell-resolution-not-implemented"}))
		elif active_turn.action == &"retreat":
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": "monster-retreat-not-implemented"}))
		else:
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": String(active_turn.action)}))
		combat.advance_turn()
		if _finish_if_resolved(state, content, events):
			break
		guard -= 1


func _process_monster_advance(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var terrain_set := _battle_terrain_set(content, combat.battlefield)
	if terrain_set == null:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "missing-battle-terrain"}))
		active_turn.movement_remaining = 0
		return MONSTER_ATTACK_COMPLETED
	var contact_origin := combat.battlefield.actor_position(monster.id)
	combat.pending_reaction = CombatReactionState.new(CombatReactionState.MONSTER_CONTACT, monster.id, contact_origin, contact_origin, 0)
	combat.pending_reaction.set_phase(CombatReactionState.GUARD_AFTER, _guarding_hostiles(state, monster.id))
	var contact_result := _continue_pending_reaction(state, content, rng, events)
	if contact_result == REACTION_WAITING:
		return MONSTER_ATTACK_WAITING
	if contact_result == REACTION_DEATH_MACRO:
		return MONSTER_ATTACK_DEATH_MACRO
	if contact_result == REACTION_MOVER_DEFEATED:
		return MONSTER_ATTACK_COMPLETED
	var operation_guard := 512
	while operation_guard > 0 and active_turn.attack_index < _monster_attack_limit(definition):
		var adjacent_ids := _hostile_adjacent_ids(state, monster.id)
		if not adjacent_ids.is_empty():
			if (active_turn.attack_index == 0 and not active_turn.physical_action_committed) or not adjacent_ids.has(active_turn.target_id):
				active_turn.target_id = _select_adjacent_monster_target(state, monster, rng)
				monster.target_id = active_turn.target_id
			while active_turn.attack_index < _monster_attack_limit(definition):
				var attack_result := _resolve_monster_attack_row(state, content, monster, definition, active_turn.attack_index, active_turn, rng, events)
				if attack_result != MONSTER_ATTACK_COMPLETED:
					return attack_result
			return MONSTER_ATTACK_COMPLETED
		if active_turn.movement_remaining <= 0:
			return MONSTER_ATTACK_COMPLETED
		if _monster_target_is_available(state, monster, active_turn.target_id) and not _rules.battlefield.has_line_of_sight(combat.battlefield, terrain_set, monster.id, active_turn.target_id):
			active_turn.target_id = _scan_visible_monster_target(state, monster, terrain_set)
			monster.target_id = active_turn.target_id
		elif not _monster_target_is_available(state, monster, active_turn.target_id):
			active_turn.target_id = _select_visible_monster_target(state, monster, terrain_set, rng)
			monster.target_id = active_turn.target_id
		if active_turn.target_id.is_empty():
			active_turn.movement_remaining = 0
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "no-visible-target"}))
			return MONSTER_ATTACK_COMPLETED
		var target_coordinate := combat.battlefield.actor_position(active_turn.target_id)
		var origin := combat.battlefield.actor_position(monster.id)
		var probe := _rules.battlefield.probe_monster_step_toward(combat.battlefield, terrain_set, monster.id, target_coordinate, active_turn.movement_remaining, rng)
		if not probe.allowed:
			active_turn.target_id = ""
			monster.target_id = ""
			active_turn.movement_remaining = 0
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": String(probe.reason)}))
			return MONSTER_ATTACK_COMPLETED
		combat.pending_reaction = CombatReactionState.new(CombatReactionState.MONSTER_MOVE, monster.id, origin, probe.destination, probe.movement_cost)
		combat.pending_reaction.set_phase(CombatReactionState.WITHDRAWAL, [])
		var movement_result := _continue_pending_reaction(state, content, rng, events)
		if movement_result == REACTION_WAITING:
			return MONSTER_ATTACK_WAITING
		if movement_result == REACTION_DEATH_MACRO:
			return MONSTER_ATTACK_DEATH_MACRO
		if movement_result == REACTION_MOVER_DEFEATED:
			return MONSTER_ATTACK_COMPLETED
		operation_guard -= 1
	if operation_guard == 0:
		active_turn.movement_remaining = 0
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "monster-movement-budget-exhausted"}))
	return MONSTER_ATTACK_COMPLETED


func _resolve_monster_attack_row(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, attack_index: int, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	if not _monster_target_is_available(state, monster, active_turn.target_id) or not _rules.battlefield.are_adjacent(combat.battlefield, monster.id, active_turn.target_id):
		active_turn.target_id = _select_adjacent_monster_target(state, monster, rng)
		monster.target_id = active_turn.target_id
	if active_turn.target_id.is_empty():
		active_turn.attack_index = _monster_attack_limit(definition)
		return MONSTER_ATTACK_COMPLETED
	active_turn.attack_index += 1
	active_turn.physical_action_committed = true
	combat.set_guarding(monster.id, false)
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
		var resolution := _rules.combat.resolve_monster_attack(monster, definition, attack_index, character_target, race, caste, rng, charm_bonus, attack_context, true)
		if resolution.fumbled:
			_commit_monster_fumble(monster, events)
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
		_remove_defeated_position(combat, character_target.id, resolution.killed)
		if resolution.killed:
			active_turn.target_id = ""
			monster.target_id = ""
		return MONSTER_ATTACK_COMPLETED
	var monster_target := combat.monster_by_id(active_turn.target_id)
	if monster_target == null:
		active_turn.target_id = ""
		return MONSTER_ATTACK_COMPLETED
	var target_definition := content.monster_by_id(monster_target.definition_id)
	var weapon := content.item_by_id(monster.weapon_id) if not monster.weapon_id.is_empty() else null
	var attack_context := MonsterAttackContext.new(weapon, state.clock.day())
	var resolution := _rules.combat.resolve_monster_attack_monster(monster, definition, attack_index, monster_target, target_definition, rng, attack_context, true)
	if resolution.fumbled:
		_commit_monster_fumble(monster, events)
	if resolution.special_handled:
		_append_monster_special_events(events, monster.id, monster_target.id, &"monster", resolution)
	events.append(DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": monster_target.id, "action": String(active_turn.action), "attackIndex": attack_index, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll}))
	if resolution.killed:
		active_turn.target_id = ""
		monster.target_id = ""
		var death_macro_requested := _request_monster_death_macro(monster_target, target_definition, events)
		_remove_defeated_position(combat, monster_target.id, not death_macro_requested)
		if death_macro_requested:
			if active_turn.attack_index >= _monster_attack_limit(definition):
				combat.advance_turn()
			return MONSTER_ATTACK_DEATH_MACRO
	return MONSTER_ATTACK_COMPLETED


func _select_adjacent_monster_target(state: GameState, monster: MonsterState, rng: RealmzRng) -> String:
	var target_ids: Array[String] = []
	var adjacent_ids := _rules.battlefield.adjacent_actor_ids(state.combat.battlefield, monster.id)
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor != monster.traitor and adjacent_ids.has(character.id):
			target_ids.append(character.id)
	for candidate: MonsterState in state.combat.monsters():
		if candidate.id != monster.id and candidate.current_health > 0 and candidate.traitor != monster.traitor and adjacent_ids.has(candidate.id):
			target_ids.append(candidate.id)
	if target_ids.is_empty():
		return ""
	return target_ids[rng.draw_between(0, target_ids.size() - 1, &"combat.monster-target")]


func _select_visible_monster_target(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition, rng: RealmzRng) -> String:
	var slot_count := 10 + state.combat.monsters().size()
	if not _has_available_monster_target(state, monster):
		return ""
	for _attempt: int in 4096:
		var slot := rng.draw_between(0, slot_count - 1, &"combat.monster-target-slot")
		var candidate_id := _monster_target_id_for_slot(state, monster, slot)
		if candidate_id.is_empty():
			continue
		if _rules.battlefield.has_line_of_sight(state.combat.battlefield, terrain_set, monster.id, candidate_id):
			return candidate_id
		break
	# Castle switches from random selection to ascending combat slots after its
	# first unseen valid target. Bound the scan to real typed slots instead of
	# reading uninitialized native monster entries through its 110 sentinel.
	return _scan_visible_monster_target(state, monster, terrain_set)


func _scan_visible_monster_target(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition) -> String:
	var slot_count := 10 + state.combat.monsters().size()
	for slot: int in slot_count:
		var candidate_id := _monster_target_id_for_slot(state, monster, slot)
		if not candidate_id.is_empty() and _rules.battlefield.has_line_of_sight(state.combat.battlefield, terrain_set, monster.id, candidate_id):
			return candidate_id
	return ""


func _monster_target_id_for_slot(state: GameState, monster: MonsterState, slot: int) -> String:
	if slot >= 0 and slot < 9:
		var characters := state.party.characters()
		if slot >= characters.size():
			return ""
		var character: CharacterState = characters[slot]
		return character.id if _monster_target_is_available(state, monster, character.id) else ""
	if slot < 10:
		return ""
	var monsters := state.combat.monsters()
	var monster_index := slot - 10
	if monster_index < 0 or monster_index >= monsters.size():
		return ""
	var candidate: MonsterState = monsters[monster_index]
	return candidate.id if _monster_target_is_available(state, monster, candidate.id) else ""


func _has_available_monster_target(state: GameState, monster: MonsterState) -> bool:
	for character: CharacterState in state.party.characters():
		if _monster_target_is_available(state, monster, character.id):
			return true
	for candidate: MonsterState in state.combat.monsters():
		if _monster_target_is_available(state, monster, candidate.id):
			return true
	return false


func _monster_target_is_available(state: GameState, monster: MonsterState, target_id: String) -> bool:
	if target_id.is_empty():
		return false
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.current_health > 0 and character.traitor != monster.traitor and state.combat.battlefield.has_actor(character.id)
	var candidate := state.combat.monster_by_id(target_id)
	return candidate != null and candidate.id != monster.id and candidate.current_health > 0 and candidate.traitor != monster.traitor and state.combat.battlefield.has_actor(candidate.id)


static func _monster_movement_allowance(monster: MonsterState, definition: MonsterDefinition) -> int:
	var movement := definition.movement_max
	var tangled := monster.conditions.value(ConditionRules.TANGLED)
	if tangled > 0:
		movement -= tangled
	if monster.conditions.is_active(ConditionRules.SLOW):
		movement = int(float(movement) / 2.0)
	if monster.conditions.is_active(ConditionRules.SPEEDY):
		movement *= 2
	return maxi(0, movement)


static func _monster_attack_limit(definition: MonsterDefinition) -> int:
	return mini(maxi(0, definition.attack_count), definition.attacks().size())


func _process_charmed_character_turn(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> bool:
	var adjacent_ids := _rules.battlefield.adjacent_actor_ids(state.combat.battlefield, actor.id)
	var character_targets: Array[CharacterState] = []
	for candidate: CharacterState in state.party.characters():
		if candidate.id != actor.id and candidate.current_health > 0 and candidate.traitor != actor.traitor and adjacent_ids.has(candidate.id):
			character_targets.append(candidate)
	var monster_targets: Array[MonsterState] = []
	for candidate: MonsterState in state.combat.monsters():
		if candidate.current_health > 0 and candidate.traitor != actor.traitor and adjacent_ids.has(candidate.id):
			monster_targets.append(candidate)
	var target_count := character_targets.size() + monster_targets.size()
	if target_count == 0:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": actor.id, "action": "advance", "reason": "tactical-movement-not-implemented"}))
		return false
	var target_index := rng.draw_between(0, target_count - 1, &"combat.charmed-target")
	var equipment := _rules.inventory.combat_equipment(actor, content.item_definitions())
	if not equipment.valid:
		events.append(DomainEvent.new(&"combat_attack_blocked", {"actorId": actor.id, "reason": String(equipment.error_code), "message": equipment.error_message}))
		return false
	var active_turn := state.combat.begin_active_turn()
	if active_turn == null:
		return false
	if target_index < character_targets.size():
		var character_target := character_targets[target_index]
		var target_equipment := _rules.inventory.combat_equipment(character_target, content.item_definitions())
		if not target_equipment.valid:
			events.append(DomainEvent.new(&"combat_attack_blocked", {"actorId": actor.id, "targetId": character_target.id, "reason": String(target_equipment.error_code), "message": target_equipment.error_message}))
			return false
		active_turn.physical_action_committed = true
		var resolution := _rules.combat.resolve_character_attack_character(actor, equipment, character_target, target_equipment, rng, false, true, state.combat.can_queue_fumbled_item())
		if resolution.fumbled and not _commit_character_fumble(state, actor, equipment, events):
			events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": actor.id, "reason": "invalid-fumble-state"}))
			return false
		var event := _character_attack_event(actor.id, character_target.id, &"character", resolution)
		event.payload["automatic"] = true
		events.append(event)
		_remove_defeated_position(state.combat, character_target.id, resolution.killed)
		return false
	var monster_target := monster_targets[target_index - character_targets.size()]
	var target_definition := content.monster_by_id(monster_target.definition_id)
	active_turn.physical_action_committed = true
	var resolution := _rules.combat.resolve_character_attack(actor, equipment, monster_target, target_definition, rng, state.clock.day(), false, true, state.combat.can_queue_fumbled_item())
	if resolution.fumbled and not _commit_character_fumble(state, actor, equipment, events):
		events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": actor.id, "reason": "invalid-fumble-state"}))
		return false
	var event := _character_attack_event(actor.id, monster_target.id, &"monster", resolution)
	event.payload["automatic"] = true
	events.append(event)
	var death_macro_requested := resolution.killed and _request_monster_death_macro(monster_target, target_definition, events)
	_remove_defeated_position(state.combat, monster_target.id, resolution.killed and not death_macro_requested)
	return death_macro_requested


func _hostile_adjacent_ids(state: GameState, actor_id: String, anchor_override: Vector2i = Vector2i(-1, -1)) -> Array[String]:
	var result: Array[String] = []
	if state == null or state.combat == null or state.combat.battlefield == null:
		return result
	var actor_traitor := false
	var character := state.party.character_by_id(actor_id)
	if character != null:
		actor_traitor = character.traitor
	else:
		var monster := state.combat.monster_by_id(actor_id)
		if monster == null:
			return result
		actor_traitor = monster.traitor
	var adjacent_ids := _rules.battlefield.adjacent_actor_ids(state.combat.battlefield, actor_id, anchor_override)
	# Castle scans numeric combat slots: party members first, then monsters in
	# authored runtime order. Stable IDs must not accidentally redefine reactions.
	for candidate_character: CharacterState in state.party.characters():
		if adjacent_ids.has(candidate_character.id) and candidate_character.current_health > 0 and candidate_character.traitor != actor_traitor:
			result.append(candidate_character.id)
	for candidate_monster: MonsterState in state.combat.monsters():
		if adjacent_ids.has(candidate_monster.id) and candidate_monster.current_health > 0 and candidate_monster.traitor != actor_traitor:
			result.append(candidate_monster.id)
	return result


static func _remove_defeated_position(combat: CombatState, actor_id: String, defeated: bool) -> void:
	if not defeated or combat == null or combat.battlefield == null:
		return
	if combat.monster_by_id(actor_id) != null:
		combat.battlefield.remove_monster(actor_id)
	else:
		combat.battlefield.remove_character(actor_id)


static func _remove_all_defeated_positions(state: GameState) -> void:
	if state == null or state.combat == null or state.combat.battlefield == null:
		return
	for monster: MonsterState in state.combat.monsters():
		_remove_defeated_position(state.combat, monster.id, monster.current_health <= 0)
	for character: CharacterState in state.party.characters():
		_remove_defeated_position(state.combat, character.id, character.current_health <= 0)


static func _battle_terrain_set(content: RealmzContent, battlefield: BattlefieldState) -> BattleTerrainSetDefinition:
	var map := content.world.map_by_id(battlefield.map_id)
	return null if map == null else content.world.battle_terrain_set_by_id(map.battle_terrain_set_id)


static func _movement_failure_message(result: BattlefieldStepResult) -> String:
	match result.reason:
		&"invalid_direction":
			return "Tactical movement accepts one adjacent eight-direction step."
		&"outside_battlefield":
			return "The destination is outside the Classic battlefield."
		&"occupied":
			return "The destination footprint is occupied by '%s'." % result.occupant_id
		&"solid_terrain":
			return "The destination terrain blocks this combatant."
		&"insufficient_movement":
			return "The step costs %d movement points." % result.movement_cost
		_:
			return "The tactical step is unavailable: %s." % String(result.reason)


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
		"fumbled": resolution.fumbled,
		"fumbleRoll": resolution.fumble_roll,
		"fumbleBlockReason": String(resolution.fumble_block_reason),
		"weaponEffects": resolution.weapon_effects.duplicate(true),
		"weaponConditionIndex": resolution.weapon_condition_index,
		"weaponConditionBefore": resolution.weapon_condition_before,
		"weaponConditionAfter": resolution.weapon_condition_after,
		"criticalRolls": resolution.critical_rolls.duplicate(),
	})


func _commit_character_fumble(state: GameState, character: CharacterState, equipment: CharacterCombatEquipment, events: Array[DomainEvent]) -> bool:
	if state.combat == null or equipment == null or equipment.melee_weapon == null or equipment.melee_weapon_instance_id.is_empty() or not state.combat.can_queue_fumbled_item():
		return false
	var instance: ItemInstance = null
	for carried: ItemInstance in character.inventory():
		if carried.id == equipment.melee_weapon_instance_id and carried.definition_id == equipment.melee_weapon.id and carried.equipped:
			instance = carried
			break
	if instance == null or not state.combat.queue_fumbled_item(instance):
		return false
	var removed := _rules.inventory.remove_item(character, instance.id, equipment.melee_weapon)
	if removed == null:
		state.combat.remove_fumbled_item(instance.id)
		instance.equipped = true
		return false
	# FD-COMBAT-005 preserves the exact runtime item and its remaining charges.
	# Castle's short-only queue reconstructs the item from its definition at booty.
	removed.identified = true
	_append_fumble_feedback(events, character.id, removed, true)
	return true


static func _commit_monster_fumble(monster: MonsterState, events: Array[DomainEvent]) -> void:
	var weapon_id := monster.weapon_id
	monster.weapon_id = ""
	_append_fumble_feedback(events, monster.id, null, false, weapon_id)


static func _append_fumble_feedback(events: Array[DomainEvent], actor_id: String, item: ItemInstance, player_weapon: bool, monster_weapon_id: String = "") -> void:
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
