class_name CombatFlow
extends RefCounted

const CombatRetreatProbeType = preload("res://src/core/rules/combat_retreat_probe.gd")
const CombatCommandProbeType = preload("res://src/core/rules/combat_command_probe.gd")

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

class RuleDependencies:
	extends RefCounted

	var arithmetic: RealmzArithmetic
	var inventory: InventoryRules
	var combat: CombatRules
	var magic: MagicRules
	var monsters: MonsterRules
	var battlefield: BattlefieldRules
	var spell_areas: SpellAreaRules

	func _init(
		arithmetic_rules: RealmzArithmetic,
		inventory_rules: InventoryRules,
		combat_rules: CombatRules,
		magic_rules: MagicRules,
		monster_rules: MonsterRules,
		battlefield_rules: BattlefieldRules,
		area_rules: SpellAreaRules,
	) -> void:
		arithmetic = arithmetic_rules
		inventory = inventory_rules
		combat = combat_rules
		magic = magic_rules
		monsters = monster_rules
		battlefield = battlefield_rules
		spell_areas = area_rules


var _rules: RuleDependencies
var _processing_auto: bool = false


func _init(rules: RealmzRules) -> void:
	# Retain the stateless modules CombatFlow uses without owning its parent aggregate.
	_rules = RuleDependencies.new(
		rules.arithmetic,
		rules.inventory,
		rules.combat,
		rules.magic,
		rules.monsters,
		rules.battlefield,
		rules.spell_areas,
	)


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
	if actor == null or actor.current_health <= 0 or actor.traitor or combat.battlefield == null or not combat.battlefield.has_actor(actor.id):
		return CombatFlowResult.failed(&"invalid_combat_actor", "The current combat actor is unavailable.")
	var events: Array[DomainEvent] = []
	var monster_death_macro_requested := false
	match action:
		&"attack":
			var equipment := _rules.inventory.combat_equipment(actor, content.item_definitions())
			if not equipment.valid:
				return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
			if combat.character_weapon_mode(actor.id) == &"missile":
				return _fire_character_projectile(state, content, actor, equipment, target_id, rng)
			if combat.battlefield == null:
				return CombatFlowResult.failed(&"missing_battlefield", "Melee requires the session-owned Classic battlefield.")
			if not _rules.battlefield.are_adjacent(combat.battlefield, actor.id, target_id):
				return CombatFlowResult.failed(&"combat_target_not_adjacent", "Classic melee can target only an enemy in an adjacent battlefield footprint.")
			var monster_target := combat.monster_by_id(target_id)
			if monster_target != null and monster_target.current_health > 0 and monster_target.traitor != actor.traitor:
				var definition := content.monster_by_id(monster_target.definition_id)
				if definition == null:
					return CombatFlowResult.failed(&"unknown_monster_definition", "The selected monster has no immutable definition.")
				_prepare_character_turn(combat, actor)
				combat.invalidate_undo()
				combat.active_turn.physical_action_committed = true
				var resolution := _rules.combat.resolve_character_attack(actor, equipment, monster_target, definition, rng, state.clock.day(), false, true, combat.can_queue_fumbled_item())
				if resolution.total_damage() > 0:
					combat.mark_attacked(monster_target.id)
				if resolution.fumbled and not _commit_character_fumble(state, actor, equipment, events):
					return CombatFlowResult.failed(&"invalid_fumble_state", "The fumbled melee weapon could not enter the battle recovery queue.")
				_append_character_attack_audio(events, actor, equipment, resolution, &"monster")
				events.append(_character_attack_event(actor.id, monster_target.id, &"monster", resolution, equipment.melee_weapon != null))
				monster_death_macro_requested = resolution.killed and _request_monster_death_macro(monster_target, definition, events)
				_remove_defeated_position(combat, monster_target.id, resolution.killed and not monster_death_macro_requested)
			else:
				var character_target := state.party.character_by_id(target_id)
				if character_target == null or character_target.id == actor.id or character_target.current_health <= 0 or character_target.traitor == actor.traitor:
					return CombatFlowResult.failed(&"invalid_combat_target", "The selected combatant is unavailable to this allegiance.")
				var target_equipment := _rules.inventory.combat_equipment(character_target, content.item_definitions())
				if not target_equipment.valid:
					return CombatFlowResult.failed(target_equipment.error_code, target_equipment.error_message)
				_prepare_character_turn(combat, actor)
				combat.invalidate_undo()
				combat.active_turn.physical_action_committed = true
				var resolution := _rules.combat.resolve_character_attack_character(actor, equipment, character_target, target_equipment, rng, false, true, combat.can_queue_fumbled_item())
				if resolution.total_damage() > 0:
					combat.mark_attacked(character_target.id)
				if resolution.fumbled and not _commit_character_fumble(state, actor, equipment, events):
					return CombatFlowResult.failed(&"invalid_fumble_state", "The fumbled melee weapon could not enter the battle recovery queue.")
				_append_character_attack_audio(events, actor, equipment, resolution, &"character")
				events.append(_character_attack_event(actor.id, character_target.id, &"character", resolution, equipment.melee_weapon != null))
				_mark_character_bleeding(state, character_target, resolution.killed)
				_remove_defeated_position(combat, character_target.id, resolution.killed)
			_consume_character_attack(actor)
			if not _character_can_continue(actor):
				_advance_turn(state, rng, events)
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
			_advance_turn(state, rng, events)
		&"delay":
			var delay_probe := probe_delay(state, actor.id)
			if not delay_probe.allowed:
				return CombatFlowResult.failed(&"combat_delay_unavailable", delay_probe.reason_text)
			_prepare_character_turn(combat, actor)
			actor.attacks_remaining = _rules.arithmetic.signed_16(actor.attacks_remaining - actor.normal_attacks - actor.attack_bonus)
			var round_advanced := combat.delay_active_actor()
			if round_advanced:
				_process_bleeding_round(state, rng, events)
			events.append(DomainEvent.new(&"combat_turn_delayed", {"actorId": actor.id, "roundAdvanced": round_advanced, "source": "classic-corrected", "fidelityDecision": "FD-COMBAT-012"}))
		&"bandage":
			var bandage_probe := probe_bandage(state, actor.id, target_id)
			if not bandage_probe.allowed:
				return CombatFlowResult.failed(&"combat_bandage_unavailable", bandage_probe.reason_text)
			_prepare_character_turn(combat, actor)
			if not combat.set_character_bleeding(target_id, false):
				return CombatFlowResult.failed(&"invalid_bandage_target", "The selected bleeding state could not be cleared.")
			actor.attacks_remaining = 0
			actor.movement = 0
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10105, "waitForCompletion": false, "source": "classic-combat-bandage"}))
			if _processing_auto:
				var bandage_roll := rng.draw(100, StringName("combat.auto.%s.bandage-sound" % actor.id))
				var bandage_sound := 10121 if bandage_roll < 50 else 10123
				events.append(DomainEvent.new(&"sound_requested", {"soundId": bandage_sound, "waitForCompletion": false, "source": "classic-combat-auto-bandage"}))
			events.append(DomainEvent.new(&"combatant_bandaged", {"actorId": actor.id, "targetId": target_id, "source": "classic-corrected", "fidelityDecision": "FD-COMBAT-013"}))
			_advance_turn(state, rng, events)
		&"turn_undead":
			var turn_result := _turn_undead(state, content, actor, rng)
			if not turn_result.ok:
				return turn_result
			events.append_array(turn_result.events)
			if not combat.pending_spell_death_macro_id().is_empty():
				return CombatFlowResult.succeeded(events)
		&"undo":
			var undo_probe := probe_undo(state, actor.id)
			if not undo_probe.allowed:
				return CombatFlowResult.failed(&"combat_undo_unavailable", undo_probe.reason_text)
			var from_position := combat.battlefield.actor_position(actor.id)
			var start_position := combat.undo_state.start_position
			if from_position != start_position and not combat.battlefield.move_actor(actor.id, start_position):
				return CombatFlowResult.failed(&"combat_undo_position_blocked", "The activation-start position is no longer available.")
			actor.attacks_remaining = _rules.arithmetic.signed_16(actor.attacks_remaining - actor.normal_attacks - actor.attack_bonus)
			combat.restart_active_turn_after_undo()
			_prepare_character_turn(combat, actor)
			combat.invalidate_undo()
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 664, "waitForCompletion": false, "source": "classic-combat-undo"}))
			if not actor.conditions.is_active(ConditionRules.ANIMATED):
				events.append(DomainEvent.new(&"sound_requested", {"soundId": 138, "waitForCompletion": false, "source": "classic-combat-activation"}))
			events.append(DomainEvent.new(&"combat_turn_undone", {"actorId": actor.id, "from": [from_position.x, from_position.y], "to": [start_position.x, start_position.y], "attacksRemaining": actor.attacks_remaining, "movementRemaining": actor.movement, "source": "classic"}))
		&"auto":
			var auto_state_checkpoint := state.to_data()
			var auto_rng_checkpoint := rng.checkpoint()
			var auto_result := run_auto_turn(state, content, actor.id, rng)
			if not auto_result.ok or auto_result.completed or state.combat == null or state.combat.pending_monster_attack != null or _events_include(auto_result.events, &"monster_death_macro_requested"):
				if auto_result.ok:
					auto_result.events.push_front(DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-combat-auto-button"}))
				return auto_result
			var persistent_result := run_persistent_auto_characters(state, content, rng)
			if not persistent_result.ok:
				if not state.restore_from_data(auto_state_checkpoint) or not rng.rollback(auto_rng_checkpoint):
					return CombatFlowResult.failed(&"combat_auto_rollback_failed", "Auto Turn failed and could not restore its deterministic transaction boundary.")
				return persistent_result
			auto_result.events.append_array(persistent_result.events)
			auto_result.events.push_front(DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-combat-auto-button"}))
			auto_result.completed = persistent_result.completed
			return auto_result
		&"finish", &"pass":
			_prepare_character_turn(combat, actor)
			actor.movement = 0
			combat.set_guarding(actor.id, false)
			events.append(DomainEvent.new(&"combat_turn_passed", {"actorId": actor.id, "action": String(action)}))
			_advance_turn(state, rng, events)
		&"retreat":
			return retreat_character(state, content, actor_id, &"explicit", Vector2i(-100_000, -100_000), rng)
		_:
			return CombatFlowResult.failed(&"unknown_combat_action", "Combat action '%s' is not available." % action)
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func probe_delay(state: GameState, actor_id: String) -> CombatCommandProbeType:
	var actor := state.party.character_by_id(actor_id) if state != null else null
	var combat := state.combat if state != null else null
	if actor == null or combat == null or combat.completed or combat.active_actor_id() != actor_id or actor.current_health <= 0 or actor.traitor:
		return CombatCommandProbeType.new(false, "Only the active loyal character can Delay.")
	if not _is_fresh_character_activation(combat, actor):
		return CombatCommandProbeType.new(false, "Delay is available only before moving, attacking, or casting this activation.")
	return CombatCommandProbeType.new(true)


func probe_undo(state: GameState, actor_id: String) -> CombatCommandProbeType:
	var actor := state.party.character_by_id(actor_id) if state != null else null
	var combat := state.combat if state != null else null
	if actor == null or combat == null or combat.completed or combat.active_actor_id() != actor_id or actor.current_health <= 0:
		return CombatCommandProbeType.new(false, "Only the active living character can Undo.")
	if actor.traitor or actor.conditions.is_active(ConditionRules.HELPLESS) or actor.conditions.is_active(ConditionRules.CONFUSED):
		return CombatCommandProbeType.new(false, "This character's current combat state prevents Undo.")
	if combat.pending_reaction != null or combat.pending_monster_attack != null:
		return CombatCommandProbeType.new(false, "Resolve the current combat result before using Undo.")
	var undo := combat.undo_state
	if combat.active_turn == null or undo == null or not undo.available or undo.actor_id != actor_id or undo.round_number != combat.round_number or undo.turn_index != combat.turn_index:
		return CombatCommandProbeType.new(false, "Undo is unavailable after a combat result.")
	if combat.battlefield == null or not combat.battlefield.has_actor(actor_id):
		return CombatCommandProbeType.new(false, "The active character has no battlefield position to restore.")
	var occupant := combat.battlefield.actor_at(undo.start_position, actor_id)
	if not occupant.is_empty():
		return CombatCommandProbeType.new(false, "The activation-start position is occupied.")
	return CombatCommandProbeType.new(true)


func bandage_candidate_ids(state: GameState) -> Array[String]:
	var result: Array[String] = []
	if state == null or state.combat == null:
		return result
	for character: CharacterState in state.party.characters():
		if state.combat.is_character_bleeding(character.id) and character.current_health > -10:
			result.append(character.id)
	return result


func probe_bandage(state: GameState, actor_id: String, target_id: String = "") -> CombatCommandProbeType:
	var actor := state.party.character_by_id(actor_id) if state != null else null
	var combat := state.combat if state != null else null
	if actor == null or combat == null or combat.completed or combat.active_actor_id() != actor_id or actor.current_health <= 0 or actor.traitor:
		return CombatCommandProbeType.new(false, "Only the active loyal character can Bandage.")
	if not _is_fresh_character_activation(combat, actor):
		return CombatCommandProbeType.new(false, "Bandage is available only before moving, attacking, or casting this activation.")
	var candidates := bandage_candidate_ids(state)
	if candidates.is_empty():
		return CombatCommandProbeType.new(false, "No party member is bleeding.")
	if not target_id.is_empty() and not candidates.has(target_id):
		return CombatCommandProbeType.new(false, "The selected party member is not a legal bleeding recipient.")
	return CombatCommandProbeType.new(true)


func turn_undead_target_ids(state: GameState, content: RealmzContent) -> Array[String]:
	var result: Array[String] = []
	if state == null or state.combat == null or content == null or state.combat.battlefield == null:
		return result
	for monster: MonsterState in state.combat.monsters():
		var definition := content.monster_by_id(monster.definition_id)
		# Providence normalizes Castle's unsigned byte sentinel 255 to signed -1.
		if monster.current_health > 0 and monster.traitor and state.combat.battlefield.has_actor(monster.id) and definition != null and definition.can_summon != -1 and (definition.type_flag(1) or definition.type_flag(2)):
			result.append(monster.id)
	return result


func probe_turn_undead(state: GameState, content: RealmzContent, actor_id: String) -> CombatCommandProbeType:
	var actor := state.party.character_by_id(actor_id) if state != null else null
	var combat := state.combat if state != null else null
	if actor == null or combat == null or combat.completed or combat.active_actor_id() != actor_id or actor.current_health <= 0 or actor.traitor:
		return CombatCommandProbeType.new(false, "Only the active loyal character can Turn Undead.")
	if not state.priest_turning_allowed:
		return CombatCommandProbeType.new(false, "This campaign location forbids priest turning.")
	if actor.ability_value(13) <= 0:
		return CombatCommandProbeType.new(false, "This character has no Turn Undead ability.")
	if combat.has_used_turn_undead(actor.id):
		return CombatCommandProbeType.new(false, "This character has already attempted Turn Undead in this battle.")
	if combat.active_turn != null and actor.attacks_remaining < 2:
		return CombatCommandProbeType.new(false, "Turn Undead requires one remaining attack.")
	if turn_undead_target_ids(state, content).is_empty():
		return CombatCommandProbeType.new(false, "No hostile undead or nether spawn can be turned.")
	return CombatCommandProbeType.new(true)


func _turn_undead(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> CombatFlowResult:
	_prepare_character_turn(state.combat, actor)
	var probe := probe_turn_undead(state, content, actor.id)
	if not probe.allowed:
		return CombatFlowResult.failed(&"combat_turn_undead_unavailable", probe.reason_text)
	var combat := state.combat
	combat.invalidate_undo()
	var target_ids := turn_undead_target_ids(state, content)
	var macro_count := 0
	for target_id: String in target_ids:
		var target := combat.monster_by_id(target_id)
		var definition := content.monster_by_id(target.definition_id) if target != null else null
		if definition != null and definition.death_macro > 0:
			macro_count += 1
	if macro_count > CombatState.MAX_SPELL_DEATH_MACROS - combat.spell_death_macro_queue().size():
		return CombatFlowResult.failed(&"combat_turn_undead_macro_limit", "Turn Undead would exceed the bounded death-macro queue.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 659, "waitForCompletion": false, "source": "classic-combat-turn-undead"})]
	combat.mark_turn_undead_used(actor.id)
	events.append(DomainEvent.new(&"combat_turn_undead_attempted", {"actorId": actor.id, "ability": actor.ability_value(13), "targetIds": target_ids.duplicate(), "source": "classic"}))
	for target_id: String in target_ids:
		var target := combat.monster_by_id(target_id)
		var definition := content.monster_by_id(target.definition_id)
		var threshold := maxi(25, 100 - actor.ability_value(13) + 5 * target.hit_dice) + target.magic_resistance
		var roll := rng.draw(100, StringName("combat.turn-undead.%s" % target.id))
		var margin := roll - threshold
		var result_kind := "resisted"
		var experience_award := 0
		if margin > 0 and margin < 30:
			result_kind = "destroyed"
			experience_award = 25 * target.hit_dice
			target.current_health = 0
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 132, "waitForCompletion": false, "source": "classic-combat-turn-undead"}))
			if not _queue_spell_death_macro(combat, target, definition):
				_remove_defeated_position(combat, target.id, true)
		elif margin >= 30:
			result_kind = "turned"
			experience_award = 50 * target.hit_dice
			target.traitor = actor.traitor
			target.target_id = ""
			combat.set_guarding(target.id, false)
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 630, "waitForCompletion": false, "source": "classic-combat-turn-undead"}))
		actor.experience = _rules.arithmetic.signed_32(actor.experience + experience_award)
		events.append(DomainEvent.new(&"combat_turn_undead_resolved", {
			"actorId": actor.id,
			"targetId": target.id,
			"result": result_kind,
			"threshold": threshold,
			"roll": roll,
			"margin": margin,
			"experience": experience_award,
			"effectResourceType": "CIcon" if result_kind == "turned" else "",
			"effectResourceId": 12056 if result_kind == "turned" else 0,
			"effectFrameCount": 8 if result_kind == "turned" else 0,
			"source": "classic",
		}))
	actor.attacks_remaining = _rules.arithmetic.signed_16(actor.attacks_remaining - 2)
	var advances_turn := not _character_can_continue(actor)
	if not combat.pending_spell_death_macro_id().is_empty():
		if not combat.begin_spell_death_macro_sequence(actor.id, advances_turn) or not _request_next_spell_death_macro(combat, content, events):
			return CombatFlowResult.failed(&"invalid_turn_undead_macro_queue", "Turn Undead could not begin its source-ordered death-macro continuation.")
		return CombatFlowResult.succeeded(events)
	if advances_turn:
		_advance_turn(state, rng, events)
	return CombatFlowResult.succeeded(events)


static func _is_fresh_character_activation(combat: CombatState, actor: CharacterState) -> bool:
	return combat.active_turn == null or (actor.movement == actor.maximum_movement and not combat.active_turn.physical_action_committed and combat.active_turn.spell_cast_count == 0)


static func _mark_character_bleeding(state: GameState, character: CharacterState, defeated: bool) -> void:
	if not defeated or state == null or state.combat == null or character == null:
		return
	# killbody.c clears doauto as soon as a party combatant is removed from the
	# battle, even when the body remains recoverable above -10 health.
	state.set_combat_auto(character.id, false)
	if character.current_health > -10:
		state.combat.set_character_bleeding(character.id, true)


func _advance_turn(state: GameState, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	if state == null or state.combat == null:
		return
	if state.combat.advance_turn():
		_process_bleeding_round(state, rng, events)


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
			combat.set_character_bleeding(character.id, false)
			state.set_combat_auto(character.id, false)
			_remove_defeated_position(combat, character.id, true)
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 132, "waitForCompletion": false, "source": "classic-combat-bleeding"}))
			events.append(DomainEvent.new(&"combatant_bled_to_death", {"characterId": character.id, "health": character.current_health, "source": "classic"}))
			continue
		var roll := rng.draw(100, StringName("combat.bleeding.%s" % character.id))
		var sound_id := 10121 if roll < 50 else 10123
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": false, "source": "classic-combat-bleeding"}))
		events.append(DomainEvent.new(&"combatant_bleeding_progressed", {"characterId": character.id, "health": character.current_health, "roll": roll, "soundId": sound_id, "source": "classic"}))
	if not bandage_candidate_ids(state).is_empty():
		# getup.c performs a second, party-wide warning draw after every
		# individual bleeding result when the Classic warning preference is on.
		# Realmz Rebuilt currently preserves that default; exposing the preference
		# itself remains owned by the settings workflow.
		var warning_roll := rng.draw(100, &"combat.bleeding.warning-sound")
		var warning_sound_id := 10121 if warning_roll < 50 else 10123
		events.append(DomainEvent.new(&"sound_requested", {"soundId": warning_sound_id, "waitForCompletion": false, "source": "classic-combat-bleeding-warning"}))
		events.append(DomainEvent.new(&"combat_bleeding_warning", {"roll": warning_roll, "soundId": warning_sound_id, "source": "classic-default"}))


func run_auto_turn(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null or state.combat.completed:
		return CombatFlowResult.failed(&"combat_auto_unavailable", "No active battle can resolve an automatic turn.")
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0 or actor.traitor or state.combat.active_actor_id() != actor_id:
		return CombatFlowResult.failed(&"combat_auto_unavailable", "Only the active loyal character can use Auto Turn.")
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_auto_started", {"actorId": actor.id, "persistent": state.combat_auto_enabled(actor.id), "source": "classic"})]
	var starting_round := state.combat.round_number
	var operation_count := 0
	var previous_processing := _processing_auto
	_processing_auto = true
	while operation_count < MAX_AUTO_OPERATIONS and state.combat != null and not state.combat.completed and state.combat.active_actor_id() == actor_id and state.combat.round_number == starting_round:
		operation_count += 1
		var result: CombatFlowResult = null
		var bandage_targets := bandage_candidate_ids(state)
		if probe_bandage(state, actor.id).allowed and not bandage_targets.is_empty():
			result = submit_action(state, content, actor.id, &"bandage", bandage_targets[0], rng)
		elif probe_turn_undead(state, content, actor.id).allowed:
			result = submit_action(state, content, actor.id, &"turn_undead", "", rng)
		else:
			var adjacent_ids := _hostile_adjacent_ids(state, actor.id)
			if not adjacent_ids.is_empty():
				if state.combat.character_weapon_mode(actor.id) == &"missile":
					result = submit_action(state, content, actor.id, &"switch_weapon", "", rng)
				else:
					result = submit_action(state, content, actor.id, &"attack", adjacent_ids[0], rng)
			else:
				result = _auto_projectile_or_move(state, content, actor, rng)
		if result == null or not result.ok:
			result = submit_action(state, content, actor.id, &"defend", "", rng)
		if result == null or not result.ok:
			_processing_auto = previous_processing
			if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
				return CombatFlowResult.failed(&"combat_auto_rollback_failed", "Automatic combat failed and could not restore its deterministic transaction boundary.")
			return CombatFlowResult.failed(&"combat_auto_failed", "Automatic combat could not choose a legal source-backed action.")
		events.append_array(result.events)
		if result.completed or _events_include(result.events, &"monster_death_macro_requested") or state.combat.pending_monster_attack != null:
			break
	_processing_auto = previous_processing
	if operation_count >= MAX_AUTO_OPERATIONS and state.combat != null and not state.combat.completed and state.combat.active_actor_id() == actor_id and state.combat.round_number == starting_round:
		if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
			return CombatFlowResult.failed(&"combat_auto_rollback_failed", "Automatic combat exhausted its operation limit and could not restore its deterministic transaction boundary.")
		return CombatFlowResult.failed(&"combat_auto_operation_limit", "Automatic combat exceeded its 256-operation safety limit without committing a partial activation.")
	events.append(DomainEvent.new(&"combat_auto_completed", {"actorId": actor.id, "operations": operation_count, "source": "classic"}))
	return CombatFlowResult.succeeded(events, state.combat == null or state.combat.completed)


func run_persistent_auto_characters(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null or state.combat.completed:
		return CombatFlowResult.succeeded([])
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	var events: Array[DomainEvent] = []
	var activation_count := 0
	var previous_processing := _processing_auto
	_processing_auto = true
	while activation_count < MAX_AUTO_OPERATIONS and state.combat != null and not state.combat.completed:
		var actor_id := state.combat.active_actor_id()
		var actor := state.party.character_by_id(actor_id)
		if actor == null or actor.traitor or not state.combat_auto_enabled(actor_id):
			break
		activation_count += 1
		var result := run_auto_turn(state, content, actor_id, rng)
		if not result.ok:
			_processing_auto = previous_processing
			if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
				return CombatFlowResult.failed(&"combat_auto_rollback_failed", "Persistent Auto failed and could not restore its deterministic transaction boundary.")
			return result
		events.append_array(result.events)
		if result.completed or state.combat.pending_monster_attack != null or _events_include(result.events, &"monster_death_macro_requested"):
			_processing_auto = previous_processing
			return CombatFlowResult.succeeded(events, result.completed)
	_processing_auto = previous_processing
	if activation_count >= MAX_AUTO_OPERATIONS and state.combat != null and not state.combat.completed and state.combat_auto_enabled(state.combat.active_actor_id()):
		if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
			return CombatFlowResult.failed(&"combat_auto_rollback_failed", "Persistent Auto exhausted its operation limit and could not restore its deterministic transaction boundary.")
		return CombatFlowResult.failed(&"combat_auto_operation_limit", "Persistent Auto exceeded its 256-activation safety limit without committing a partial chain.")
	return CombatFlowResult.succeeded(events, state.combat == null or state.combat.completed)


func _auto_projectile_or_move(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> CombatFlowResult:
	if state.combat.character_weapon_mode(actor.id) == &"missile":
		var equipment := _rules.inventory.combat_equipment(actor, content.item_definitions())
		var profile := character_projectile_profile(actor, content, equipment)
		if profile != null and profile.available:
			for character: CharacterState in state.party.characters():
				if character.id != actor.id and character.current_health > 0 and character.traitor != actor.traitor and projectile_target_is_valid(state.combat, content, actor.id, character.id, profile.maximum_range, profile.spell.range_min + profile.spell.range_max > 0):
					return submit_action(state, content, actor.id, &"attack", character.id, rng)
			for monster: MonsterState in state.combat.monsters():
				if monster.current_health > 0 and monster.traitor != actor.traitor and projectile_target_is_valid(state.combat, content, actor.id, monster.id, profile.maximum_range, profile.spell.range_min + profile.spell.range_max > 0):
					return submit_action(state, content, actor.id, &"attack", monster.id, rng)
		return submit_action(state, content, actor.id, &"switch_weapon", "", rng)
	return _auto_move_toward_target(state, content, actor, rng)


func _auto_move_toward_target(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	_prepare_character_turn(combat, actor)
	if actor.movement <= 0:
		return CombatFlowResult.failed(&"combat_auto_no_movement", "The automatic character cannot move toward a target.")
	var candidates: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.id != actor.id and character.current_health > 0 and character.traitor != actor.traitor and combat.battlefield.has_actor(character.id):
			candidates.append(character.id)
	for monster: MonsterState in combat.monsters():
		if monster.current_health > 0 and monster.traitor != actor.traitor and combat.battlefield.has_actor(monster.id):
			candidates.append(monster.id)
	if candidates.is_empty():
		return CombatFlowResult.failed(&"combat_auto_no_target", "No opposed battlefield combatant remains.")
	var target_id := combat.active_turn.target_id
	if not candidates.has(target_id):
		target_id = candidates[rng.draw_between(0, candidates.size() - 1, StringName("combat.auto.%s.target" % actor.id))]
		combat.active_turn.target_id = target_id
	var origin := combat.battlefield.actor_position(actor.id)
	var target := combat.battlefield.actor_position(target_id)
	var direction := Vector2i(signi(target.x - origin.x), signi(target.y - origin.y))
	if direction != Vector2i.ZERO:
		var direct := move_character(state, content, actor.id, origin + direction, rng)
		if direct.ok:
			return direct
	for retry: int in 20:
		var shifted := Vector2i(rng.draw(3, StringName("combat.auto.%s.shift.%d.x" % [actor.id, retry])) - 2, rng.draw(3, StringName("combat.auto.%s.shift.%d.y" % [actor.id, retry])) - 2)
		if shifted == Vector2i.ZERO:
			continue
		var shifted_result := move_character(state, content, actor.id, origin + shifted, rng)
		if shifted_result.ok:
			return shifted_result
	return CombatFlowResult.failed(&"combat_auto_blocked", "The automatic character exhausted Castle's bounded movement retries.")


static func _events_include(events: Array[DomainEvent], kind: StringName) -> bool:
	for event: DomainEvent in events:
		if event.kind == kind:
			return true
	return false


func probe_character_retreat(combat: CombatState, characters: Array[CharacterState], actor_id: String):
	if combat == null or combat.completed or combat.battlefield == null or combat.active_actor_id() != actor_id or not combat.battlefield.has_actor(actor_id):
		return CombatRetreatProbeType.blocked(&"invalid_combat_actor", "The active character is unavailable.")
	var actor: CharacterState = null
	for character: CharacterState in characters:
		if character.id == actor_id:
			actor = character
			break
	if actor == null or actor.current_health <= 0 or actor.traitor:
		return CombatRetreatProbeType.blocked(&"invalid_combat_actor", "Only a living loyal character can retreat.")
	var nearest_range := 127
	var origin := combat.battlefield.actor_position(actor_id)
	for character: CharacterState in characters:
		if character.id != actor_id and character.current_health > 0 and character.traitor != actor.traitor and combat.battlefield.has_actor(character.id):
			nearest_range = mini(nearest_range, floori(Vector2(combat.battlefield.actor_position(character.id) - origin).length()))
	for monster: MonsterState in combat.monsters():
		if monster.current_health > 0 and monster.traitor != actor.traitor and combat.battlefield.has_actor(monster.id):
			nearest_range = mini(nearest_range, floori(Vector2(combat.battlefield.actor_position(monster.id) - origin).length()))
	if nearest_range < 10:
		return CombatRetreatProbeType.blocked(&"enemy_too_close", "Classic Escape requires every enemy to be at least 10 battlefield cells away.", nearest_range)
	for condition: int in [ConditionRules.HELPLESS, ConditionRules.CONFUSED, ConditionRules.TANGLED, ConditionRules.SLOW]:
		if actor.conditions.is_active(condition):
			return CombatRetreatProbeType.blocked(&"retreat_condition_blocked", "This character's current condition prevents Escape.", nearest_range)
	return CombatRetreatProbeType.permitted(nearest_range)


func character_projectile_profile(character: CharacterState, content: RealmzContent, equipment: CharacterCombatEquipment = null) -> ProjectileAttackProfile:
	if character == null or content == null:
		return ProjectileAttackProfile.blocked(&"invalid_combat_actor", "A projectile requires an available character and content package.")
	var resolved_equipment := equipment if equipment != null else _rules.inventory.combat_equipment(character, content.item_definitions())
	if not resolved_equipment.valid:
		return ProjectileAttackProfile.blocked(resolved_equipment.error_code, resolved_equipment.error_message)
	if resolved_equipment.missile_weapon == null:
		return ProjectileAttackProfile.blocked(&"missile_weapon_unavailable", "The active character has no equipped Classic type-15 missile weapon.")
	var projectile_item := resolved_equipment.missile_weapon
	var instance_id := resolved_equipment.missile_weapon_instance_id
	if resolved_equipment.missile_ammunition != null and resolved_equipment.missile_ammunition.special_2 > 1100:
		projectile_item = resolved_equipment.missile_ammunition
		instance_id = resolved_equipment.missile_ammunition_instance_id
	var instance: ItemInstance = null
	for candidate: ItemInstance in character.inventory():
		if candidate.id == instance_id:
			instance = candidate
			break
	if instance == null or instance.charges == 0:
		return ProjectileAttackProfile.blocked(&"projectile_charge_unavailable", "The selected Classic projectile has no remaining charge.")
	var spell := content.spell_by_classic_id(absi(projectile_item.special_2))
	if spell == null:
		return ProjectileAttackProfile.blocked(&"projectile_spell_unavailable", "Projectile item '%s' references unavailable Classic spell %d." % [projectile_item.id, absi(projectile_item.special_2)])
	var unsupported := _projectile_spell_unavailable_reason(spell)
	if not unsupported.is_empty():
		return ProjectileAttackProfile.blocked(&"unsupported_projectile_spell", unsupported)
	var power := absi(projectile_item.special_1)
	if power == 8:
		return ProjectileAttackProfile.blocked(&"random_projectile_power_unresolved", "This projectile rolls power before Castle opens its target picker; that serializable targeting continuation is not implemented yet.")
	return ProjectileAttackProfile.permitted(projectile_item, instance_id, spell, power, absi(spell.range_min + spell.range_max * power))


func projectile_target_is_valid(combat: CombatState, content: RealmzContent, actor_id: String, target_id: String, maximum_range: int, require_line_of_sight: bool = true) -> bool:
	if combat == null or content == null or combat.battlefield == null:
		return false
	var terrain_set := _battle_terrain_set(content, combat.battlefield)
	return terrain_set != null and _rules.battlefield.projectile_target_is_valid(combat.battlefield, terrain_set, actor_id, target_id, maximum_range, require_line_of_sight)


func probe_edge_retreat(combat: CombatState, actor_id: String, destination: Vector2i):
	if combat == null or combat.completed or combat.battlefield == null or combat.active_actor_id() != actor_id or not combat.battlefield.has_actor(actor_id):
		return CombatRetreatProbeType.blocked(&"invalid_combat_actor", "The active character is unavailable.")
	var origin := combat.battlefield.actor_position(actor_id)
	var direction := destination - origin
	if direction == Vector2i.ZERO or absi(direction.x) > 1 or absi(direction.y) > 1:
		return CombatRetreatProbeType.blocked(&"invalid_direction", "Battlefield-edge retreat requires one adjacent movement direction.")
	if destination.x >= 2 and destination.y >= 2 and destination.x <= 87 and destination.y <= 87:
		return CombatRetreatProbeType.blocked(&"not_battlefield_edge", "This movement does not enter Castle's retreat band.")
	var forced := origin.x < 1 or origin.y < 1 or origin.x > 88 or origin.y > 88
	return CombatRetreatProbeType.permitted(127, forced)


func retreat_character(state: GameState, content: RealmzContent, actor_id: String, mode: StringName, destination: Vector2i, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or combat.active_actor_id() != actor_id:
		return CombatFlowResult.failed(&"invalid_combat_actor", "The active character cannot retreat.")
	var actor := state.party.character_by_id(actor_id)
	if actor == null:
		return CombatFlowResult.failed(&"invalid_combat_actor", "The active character cannot retreat.")
	var probe: Variant = probe_character_retreat(combat, state.party.characters(), actor_id) if mode == &"explicit" else probe_edge_retreat(combat, actor_id, destination) if mode == &"edge" else null
	if probe == null:
		return CombatFlowResult.failed(&"invalid_retreat_mode", "The retreat route is unavailable.")
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	if not combat.mark_character_retreated(actor.id):
		return CombatFlowResult.failed(&"invalid_retreat_state", "The active character's Escape state could not be recorded.")
	combat.battlefield.remove_character(actor.id)
	combat.set_guarding(actor.id, false)
	combat.clear_active_turn()
	actor.attacks_remaining = 0
	actor.movement = 0
	actor.prestige_penalty = _rules.arithmetic.signed_32(actor.prestige_penalty + 200)
	var events: Array[DomainEvent] = [DomainEvent.new(&"combatant_retreated", {"actorId": actor.id, "mode": String(mode), "forced": probe.forced, "prestigePenalty": 200, "nearestEnemyRange": probe.nearest_enemy_range, "source": "classic"})]
	if not _has_loyal_battlefield_character(state):
		_complete_battle(state, content, &"retreated", events)
		return CombatFlowResult.succeeded(events, true)
	_advance_turn(state, rng, events)
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
	var contact_target_id := _hostile_contact_target_id(state, actor.id, probe.occupant_id) if probe.reason == &"occupied" else ""
	if not contact_target_id.is_empty() and combat.character_weapon_mode(actor.id) != &"melee":
		return CombatFlowResult.failed(&"melee_weapon_mode_required", "Switch to the melee weapon before attacking an occupied hostile footprint.")
	if not probe.allowed and contact_target_id.is_empty():
		return CombatFlowResult.failed(probe.reason, _movement_failure_message(probe))
	if not contact_target_id.is_empty():
		var equipment := _rules.inventory.combat_equipment(actor, content.item_definitions())
		if not equipment.valid:
			return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
	_prepare_character_turn(combat, actor)
	combat.pending_reaction = CombatReactionState.new(CombatReactionState.CHARACTER_MOVE, actor.id, origin, destination, 3 if not contact_target_id.is_empty() else probe.movement_cost)
	var origin_hostiles := _hostile_adjacent_ids(state, actor.id)
	combat.pending_reaction.set_origin_hostiles(origin_hostiles)
	combat.pending_reaction.set_phase(CombatReactionState.GUARD_BEFORE, _guarding_actor_ids(state, origin_hostiles))
	var events: Array[DomainEvent] = []
	var reaction_result := _continue_pending_reaction(state, content, rng, events)
	if reaction_result == REACTION_MOVER_DEFEATED:
		if combat.active_actor_id() == actor.id:
			_advance_turn(state, rng, events)
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
					var contact_target_id := _hostile_contact_target_id(state, reaction.mover_id, reaction.destination)
					if not contact_target_id.is_empty():
						combat.pending_reaction = null
						var contact_result := submit_action(state, content, reaction.mover_id, &"attack", contact_target_id, rng)
						if not contact_result.ok:
							events.append(DomainEvent.new(&"combat_contact_attack_failed", {"actorId": reaction.mover_id, "targetId": contact_target_id, "reason": String(contact_result.error_code)}))
							return REACTION_COMPLETED
						events.append_array(contact_result.events)
						return REACTION_COMPLETED
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
		"automatic": reaction.kind != CombatReactionState.CHARACTER_MOVE,
	}))
	var terrain_set := _battle_terrain_set(content, combat.battlefield)
	var terrain := terrain_set.tile_by_id(combat.battlefield.terrain_at(reaction.destination)) if terrain_set != null else null
	if terrain != null and terrain.sound != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": terrain.sound, "waitForCompletion": terrain.sound < 0, "source": "classic-battle-movement"}))
	if reaction.kind == CombatReactionState.MONSTER_RETREAT and _retreating_monster_reached_edge(state, content, reaction.mover_id, reaction.destination, events):
		reaction.set_phase(CombatReactionState.GUARD_AFTER, [])
		return true
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
	combat.invalidate_undo()
	var equipment := _rules.inventory.combat_equipment(attacker, content.item_definitions())
	if not equipment.valid:
		events.append(DomainEvent.new(&"combat_reaction_failed", {"actorId": attacker.id, "targetId": target_id, "reason": String(equipment.error_code)}))
		return REACTION_COMPLETED
	var monster_target := combat.monster_by_id(target_id)
	if monster_target != null:
		var definition := content.monster_by_id(monster_target.definition_id)
		var reaction_resolution := _rules.combat.resolve_character_attack(attacker, equipment, monster_target, definition, rng, state.clock.day(), behind, true, combat.can_queue_fumbled_item())
		if reaction_resolution.total_damage() > 0:
			combat.mark_attacked(monster_target.id)
		if reaction_resolution.fumbled and not _commit_character_fumble(state, attacker, equipment, events):
			events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": attacker.id, "reason": "invalid-fumble-state"}))
		_append_character_attack_audio(events, attacker, equipment, reaction_resolution, &"monster")
		var reaction_event := _character_attack_event(attacker.id, monster_target.id, &"monster", reaction_resolution, equipment.melee_weapon != null)
		_append_reaction_identity(reaction_event, action, behind)
		events.append(reaction_event)
		if reaction_resolution.killed:
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
	if resolution.total_damage() > 0:
		combat.mark_attacked(character_target.id)
	if resolution.fumbled and not _commit_character_fumble(state, attacker, equipment, events):
		events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": attacker.id, "reason": "invalid-fumble-state"}))
	_append_character_attack_audio(events, attacker, equipment, resolution, &"character")
	var event := _character_attack_event(attacker.id, character_target.id, &"character", resolution, equipment.melee_weapon != null)
	_append_reaction_identity(event, action, behind)
	events.append(event)
	if resolution.killed:
		combat.pending_reaction.mover_killed = true
		_mark_character_bleeding(state, character_target, true)
		_remove_defeated_position(combat, character_target.id, true)
		return REACTION_MOVER_DEFEATED
	return REACTION_COMPLETED


func _resolve_monster_reaction(state: GameState, content: RealmzContent, attacker: MonsterState, target_id: String, action: StringName, behind: bool, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	combat.invalidate_undo()
	var definition := content.monster_by_id(attacker.definition_id)
	if definition == null:
		return REACTION_COMPLETED
	_prepare_monster_melee_weapon(attacker, definition, content)
	var weapon := content.item_by_id(attacker.weapon_id) if not attacker.weapon_id.is_empty() else null
	var character_target := state.party.character_by_id(target_id)
	if character_target != null:
		var race := content.race_by_id(character_target.race_id)
		var caste := content.caste_by_id(character_target.caste_id)
		var charm_bonus := 50 if state.party.conditions.is_active(ConditionRules.PARTY_CHARM_RESISTANCE) else 0
		var defender_equipment := _rules.inventory.combat_equipment(character_target, content.item_definitions())
		var defender_luck := defender_equipment.effective_luck if defender_equipment.valid else character_target.luck
		var defender_armor := defender_equipment.effective_armor if defender_equipment.valid else character_target.armor
		var reaction_context := MonsterAttackContext.new(weapon, state.clock.day(), behind, defender_luck, state.party.conditions.is_active(ConditionRules.PARTY_DRAGON_HIDE), defender_armor)
		var reaction_resolution := _rules.combat.resolve_monster_attack(attacker, definition, 0, character_target, race, caste, rng, charm_bonus, reaction_context, true)
		if reaction_resolution.total_damage() > 0:
			combat.mark_attacked(character_target.id)
		if reaction_resolution.fumbled:
			_commit_monster_fumble(attacker, events)
		if reaction_resolution.special_handled:
			_append_monster_special_events(events, attacker.id, character_target.id, &"character", reaction_resolution)
			if reaction_resolution.aging != null and reaction_resolution.aging.changed_group():
				events.append(DomainEvent.new(&"character_age_changed", reaction_resolution.aging.event_payload(character_target, race)))
				combat.pending_monster_attack = PendingMonsterAttack.new(attacker.id, character_target.id, action, reaction_resolution.damage, reaction_resolution.chance, reaction_resolution.roll, reaction_resolution.weapon_condition_index, reaction_resolution.weapon_condition_before, reaction_resolution.weapon_condition_after, reaction_resolution.physical_feedback_sound_id)
				return REACTION_WAITING
		_append_monster_physical_feedback(events, reaction_resolution.physical_feedback_sound_id)
		_append_monster_attack_audio(events, attacker, definition, 0, weapon, reaction_resolution, rng)
		var reaction_event := DomainEvent.new(&"combat_attack_resolved", {"actorId": attacker.id, "targetId": character_target.id, "targetKind": "character", "action": String(action), "attackIndex": 0, "hit": reaction_resolution.hit, "damage": reaction_resolution.total_damage(), "defeated": reaction_resolution.killed, "chance": reaction_resolution.chance, "roll": reaction_resolution.roll})
		_append_physical_result_effect(reaction_event, reaction_resolution.hit, weapon != null)
		_append_reaction_identity(reaction_event, action, behind)
		events.append(reaction_event)
		if reaction_resolution.killed:
			combat.pending_reaction.mover_killed = true
			_mark_character_bleeding(state, character_target, true)
			_remove_defeated_position(combat, character_target.id, true)
			return REACTION_MOVER_DEFEATED
		return REACTION_COMPLETED
	var monster_target := combat.monster_by_id(target_id)
	if monster_target == null:
		return REACTION_COMPLETED
	var target_definition := content.monster_by_id(monster_target.definition_id)
	var context := MonsterAttackContext.new(weapon, state.clock.day(), behind)
	var resolution := _rules.combat.resolve_monster_attack_monster(attacker, definition, 0, monster_target, target_definition, rng, context, true)
	if resolution.total_damage() > 0:
		combat.mark_attacked(monster_target.id)
	if resolution.fumbled:
		_commit_monster_fumble(attacker, events)
	if resolution.special_handled:
		_append_monster_special_events(events, attacker.id, monster_target.id, &"monster", resolution)
	_append_monster_attack_audio(events, attacker, definition, 0, weapon, resolution, rng)
	var event := DomainEvent.new(&"combat_attack_resolved", {"actorId": attacker.id, "targetId": monster_target.id, "targetKind": "monster", "action": String(action), "attackIndex": 0, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll})
	_append_physical_result_effect(event, resolution.hit, weapon != null)
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


func probe_character_item_spell(state: GameState, content: RealmzContent, caster_id: String, target_id: String, instance_id: String) -> CombatSpellCastProbe:
	if state == null or content == null:
		return CombatSpellCastProbe.blocked(&"invalid_item_turn", "Item use requires an active game session.")
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or combat.active_actor_id() != caster_id:
		return CombatSpellCastProbe.blocked(&"invalid_item_turn", "Only the active character may use an item in combat.")
	if not combat.pending_spell_death_macro_id().is_empty():
		return CombatSpellCastProbe.blocked(&"spell_death_macro_pending", "A spell-triggered monster death macro must complete before another combat action.")
	var caster := state.party.character_by_id(caster_id)
	var instance := _inventory_instance(caster, instance_id)
	var item: ItemDefinition = null if instance == null else content.item_by_id(instance.definition_id)
	var spell: SpellDefinition = null if item == null else content.spell_by_classic_id(item.special_2)
	var use_probe := _rules.inventory.classic_spell_item_probe(caster, instance, item, spell, content.race_by_id(caster.race_id) if caster != null else null, content.caste_by_id(caster.caste_id) if caster != null else null, true)
	if not use_probe.allowed:
		return CombatSpellCastProbe.blocked(_item_use_reason_code(instance, item, spell), use_probe.reason)
	var power_level := absi(item.special_1)
	if power_level == 8:
		return CombatSpellCastProbe.blocked(&"random_item_power_requires_staging", "A random-power item requires a source-backed staged targeting continuation.")
	if spell.target_type not in [1, 2, 5, 9, 10, 12]:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_item_targeting", "This item's Classic combat target shape is not implemented yet.")
	var healing_spell := _is_source_backed_combat_healing_spell(spell)
	var ordinary_spell := spell.special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 6 and absi(spell.spell_class) != 9
	if not ordinary_spell and not healing_spell:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_item_effect", "This item's Classic combat spell effect is not implemented yet.")
	if spell.queue_icon != 0:
		return CombatSpellCastProbe.blocked(&"queued_spell_field_unresolved", "This item creates a persistent battlefield field whose collision lifecycle is not implemented.")
	if spell.target_type in [9, 10, 12]:
		var group_target_count := 0
		for character: CharacterState in state.party.characters():
			if character.current_health > 0 and combat.battlefield.has_actor(character.id) and _group_target_matches(spell.target_type, character.traitor, caster.traitor):
				group_target_count += 1
		for monster: MonsterState in combat.monsters():
			if monster.current_health <= 0 or not combat.battlefield.has_actor(monster.id) or not _group_target_matches(spell.target_type, monster.traitor, caster.traitor):
				continue
			if content.monster_by_id(monster.definition_id) == null:
				return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "An item spell target has no immutable monster definition.")
			group_target_count += 1
		if group_target_count == 0:
			return CombatSpellCastProbe.blocked(&"invalid_item_target", "The item spell has no available group target.")
		return CombatSpellCastProbe.permitted()
	var effective_target_id := caster_id if spell.target_type == 5 else target_id
	if _spell_target_selection(state, content, effective_target_id) == null:
		return CombatSpellCastProbe.blocked(&"invalid_item_target", "The selected combatant is unavailable.")
	if not _spell_actor_target_is_valid(state, content, caster_id, effective_target_id, spell, power_level):
		return CombatSpellCastProbe.blocked(&"item_target_unavailable", "The target is outside the item's Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func use_spell_item(state: GameState, content: RealmzContent, caster_id: String, target_id: String, instance_id: String, rng: RealmzRng) -> CombatFlowResult:
	var probe := probe_character_item_spell(state, content, caster_id, target_id, instance_id)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	var caster := state.party.character_by_id(caster_id)
	var instance := _inventory_instance(caster, instance_id)
	var item := content.item_by_id(instance.definition_id)
	var spell := content.spell_by_classic_id(item.special_2)
	var power_level := absi(item.special_1)
	if not _rules.inventory.use_charge(caster, instance.id, item):
		return CombatFlowResult.failed(&"item_charge_commit_failed", "The validated item charge could not be committed.")
	_prepare_character_turn(state.combat, caster)
	state.combat.invalidate_undo()
	var cast_level := spell.classic_tier()
	var result: CombatFlowResult
	if spell.target_type in [9, 10, 12]:
		var character_targets: Array[CharacterState] = []
		var monster_targets: Array[MonsterState] = []
		var monster_definitions: Array[MonsterDefinition] = []
		for character: CharacterState in state.party.characters():
			if character.current_health > 0 and state.combat.battlefield.has_actor(character.id) and _group_target_matches(spell.target_type, character.traitor, caster.traitor):
				character_targets.append(character)
		for monster: MonsterState in state.combat.monsters():
			if monster.current_health <= 0 or not state.combat.battlefield.has_actor(monster.id) or not _group_target_matches(spell.target_type, monster.traitor, caster.traitor):
				continue
			var definition := content.monster_by_id(monster.definition_id)
			if definition == null:
				return CombatFlowResult.failed(&"spell_target_unavailable", "An item spell target has no immutable monster definition.")
			monster_targets.append(monster)
			monster_definitions.append(definition)
		var group := _rules.magic.resolve_character_group_spell(caster, character_targets, monster_targets, monster_definitions, spell, power_level, cast_level, rng, false, false)
		if group == null or not group.cast:
			return CombatFlowResult.failed(&"item_spell_failed", "The item spell could not be resolved.")
		result = _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, group, rng, INVALID_COORDINATE, 0, "classic-item", instance_id, false)
	else:
		var effective_target_id := caster_id if spell.target_type == 5 else target_id
		var selection := _spell_target_selection(state, content, effective_target_id)
		var targeted := _rules.magic.resolve_character_targeted_spell(caster, selection, spell, power_level, cast_level, rng, false)
		if targeted == null or not targeted.cast:
			return CombatFlowResult.failed(&"item_spell_failed", "The item spell could not be resolved.")
		result = _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, targeted, rng, INVALID_COORDINATE, 0, "classic-item", instance_id, false)
	if not result.ok:
		return result
	var events: Array[DomainEvent] = [_item_used_event(caster_id, instance_id, item, spell, power_level, caster)]
	var native_sound_id := item.sound_id + 600
	if item.sound_id != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(native_sound_id), "waitForCompletion": native_sound_id < 0, "source": "classic-item"}))
	events.append_array(result.events)
	result.events = events
	return result


func character_item_spell_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatItemOptionView]:
	var result: Array[CombatItemOptionView] = []
	if state == null or state.combat == null or state.combat.active_actor_id() != caster_id:
		return result
	var caster := state.party.character_by_id(caster_id)
	if caster == null:
		return result
	for instance: ItemInstance in caster.inventory():
		var item := content.item_by_id(instance.definition_id)
		var spell := content.spell_by_classic_id(item.special_2) if item != null else null
		if item == null or spell == null or absi(item.special_1) == 8:
			continue
		if spell.target_type in [9, 10, 12]:
			if probe_character_item_spell(state, content, caster_id, "", instance.id).allowed:
				result.append(CombatItemOptionView.new(instance, item, spell, absi(item.special_1), null, _group_spell_target_label(spell.target_type), &"automatic"))
			continue
		if spell.target_type == 5:
			if probe_character_item_spell(state, content, caster_id, caster_id, instance.id).allowed:
				result.append(CombatItemOptionView.new(instance, item, spell, absi(item.special_1), _spell_target_view(state, content, caster_id)))
			continue
		for target: CombatSpellTargetView in _character_actor_spell_candidates(state, content, caster, spell, absi(item.special_1)):
			if probe_character_item_spell(state, content, caster_id, target.id, instance.id).allowed:
				result.append(CombatItemOptionView.new(instance, item, spell, absi(item.special_1), target))
	return result


func character_item_spell_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	if state == null or state.combat == null or state.combat.active_actor_id() != caster_id:
		return "Only the active character may use an item."
	var caster := state.party.character_by_id(caster_id)
	if caster == null or caster.inventory().is_empty():
		return "The active character carries no items."
	for instance: ItemInstance in caster.inventory():
		var item := content.item_by_id(instance.definition_id)
		var spell := content.spell_by_classic_id(item.special_2) if item != null else null
		if item != null and spell != null:
			var probe := probe_character_item_spell(state, content, caster_id, caster_id if spell.target_type == 5 else "", instance.id)
			if not probe.allowed:
				return probe.reason_text
	return "No carried item has a supported Classic combat use."


static func _inventory_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null:
		return null
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


static func _item_use_reason_code(instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition) -> StringName:
	if instance == null or item == null:
		return &"unknown_item_instance"
	if instance.charges == 0:
		return &"item_has_no_charges"
	if item.special_2 <= 1100:
		return &"item_has_no_spell_effect"
	if spell == null:
		return &"unknown_item_spell"
	return &"item_cannot_be_used"


static func _item_used_event(caster_id: String, instance_id: String, item: ItemDefinition, spell: SpellDefinition, power_level: int, caster: CharacterState) -> DomainEvent:
	var remaining := -1
	var dropped := true
	for instance: ItemInstance in caster.inventory():
		if instance.id == instance_id:
			remaining = instance.charges
			dropped = false
			break
	return DomainEvent.new(&"item_used", {"characterId": caster_id, "instanceId": instance_id, "itemId": item.id, "spellId": spell.id, "power": power_level, "chargesRemaining": remaining, "droppedOnEmpty": dropped, "source": "classic"})


func cast_spell(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell_id: String, power_level: int, rng: RealmzRng, target_coordinate: Vector2i = Vector2i(-100_000, -100_000), rotation: int = 0, target_ids: Array[String] = []) -> CombatFlowResult:
	var probe := probe_character_spell_cast(state, content, caster_id, target_id, spell_id, power_level, target_coordinate, rotation, target_ids)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	var combat := state.combat
	var caster := state.party.character_by_id(caster_id)
	var spell := content.spell_by_id(spell_id)
	var cast_level := spell.classic_tier()
	if spell.target_type in [3, 4]:
		if target_coordinate == INVALID_COORDINATE:
			return CombatFlowResult.failed(&"area_target_required", "A fixed or power area spell requires a battlefield coordinate.")
		_prepare_character_turn(combat, caster)
		combat.invalidate_undo()
		return _cast_character_area_spell(state, content, caster, spell, power_level, cast_level, rng, target_coordinate, rotation)
	_prepare_character_turn(combat, caster)
	combat.invalidate_undo()
	if spell.target_type in [9, 10, 12]:
		return _cast_character_group_spell(state, content, caster, spell, power_level, cast_level, rng)
	if spell.target_type == 0:
		var selections: Array[SpellTargetSelection] = []
		for selected_id: String in target_ids:
			var repeated_selection := _spell_target_selection(state, content, selected_id)
			if repeated_selection == null:
				return CombatFlowResult.failed(&"spell_target_unavailable", "A selected repeated-spell target is unavailable.")
			selections.append(repeated_selection)
		var repeated := _rules.magic.resolve_character_repeated_spell(caster, selections, spell, power_level, cast_level, rng)
		if repeated == null or not repeated.cast:
			return CombatFlowResult.failed(&"spell_cast_failed", "The repeated-target spell could not be cast with the available spell points.")
		return _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, repeated, rng)
	var selection := _spell_target_selection(state, content, target_id)
	if selection == null:
		return CombatFlowResult.failed(&"spell_target_unavailable", "The selected combatant is unavailable.")
	var targeted := _rules.magic.resolve_character_targeted_spell(caster, selection, spell, power_level, cast_level, rng)
	if targeted == null or not targeted.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The spell could not be cast with the available spell points.")
	return _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, targeted, rng)


func _cast_character_group_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	var character_targets: Array[CharacterState] = []
	var monster_targets: Array[MonsterState] = []
	var monster_definitions: Array[MonsterDefinition] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and combat.battlefield.has_actor(character.id) and _group_target_matches(spell.target_type, character.traitor, caster.traitor):
			character_targets.append(character)
	for monster: MonsterState in combat.monsters():
		if monster.current_health <= 0 or not combat.battlefield.has_actor(monster.id):
			continue
		if not _group_target_matches(spell.target_type, monster.traitor, caster.traitor):
			continue
		var definition := content.monster_by_id(monster.definition_id)
		if definition == null:
			return CombatFlowResult.failed(&"spell_target_unavailable", "A group spell target has no immutable monster definition.")
		monster_targets.append(monster)
		monster_definitions.append(definition)
	var group := _rules.magic.resolve_character_group_spell(caster, character_targets, monster_targets, monster_definitions, spell, power_level, cast_level, rng)
	if group == null or not group.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The group spell could not be cast with the available spell points.")
	return _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, group, rng)


func _cast_character_area_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, center: Vector2i, rotation: int) -> CombatFlowResult:
	var combat := state.combat
	var shape := _rules.spell_areas.shape_for(spell, power_level, rotation)
	var selected_ids: Dictionary = {}
	for offset: Vector2i in _rules.spell_areas.pattern(shape):
		var actor_id := combat.battlefield.actor_at(center + offset)
		if not actor_id.is_empty():
			selected_ids[actor_id] = true
	var character_targets: Array[CharacterState] = []
	var monster_targets: Array[MonsterState] = []
	var monster_definitions: Array[MonsterDefinition] = []
	for character: CharacterState in state.party.characters():
		if not selected_ids.has(character.id) or character.current_health <= 0 or not combat.battlefield.has_actor(character.id):
			continue
		if character.conditions.is_active(ConditionRules.REFLECTING_SPELLS):
			return CombatFlowResult.failed(&"area_spell_reflection_unresolved", "This area intersects a spell-reflecting character; Classic reflection targeting remains unresolved.")
		character_targets.append(character)
	for monster: MonsterState in combat.monsters():
		if not selected_ids.has(monster.id) or monster.current_health <= 0 or not combat.battlefield.has_actor(monster.id):
			continue
		if monster.conditions.is_active(ConditionRules.REFLECTING_SPELLS):
			return CombatFlowResult.failed(&"area_spell_reflection_unresolved", "This area intersects a spell-reflecting monster; Classic reflection targeting remains unresolved.")
		# spelltargets.c removes over-100 magic resistance before resolvespell.
		if monster.magic_resistance > 100:
			continue
		var definition := content.monster_by_id(monster.definition_id)
		if definition == null:
			return CombatFlowResult.failed(&"spell_target_unavailable", "An area spell target has no immutable monster definition.")
		monster_targets.append(monster)
		monster_definitions.append(definition)
	_prepare_character_turn(combat, caster)
	var area := _rules.magic.resolve_character_group_spell(caster, character_targets, monster_targets, monster_definitions, spell, power_level, cast_level, rng, true)
	if area == null or not area.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The area spell could not be cast with the available spell points.")
	return _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, area, rng, center, shape)


func _commit_character_multi_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, group: GroupSpellResolution, rng: RealmzRng, center: Vector2i = Vector2i(-100_000, -100_000), shape: int = 0, event_source: String = "classic", item_instance_id: String = "", count_spell_cast: bool = true) -> CombatFlowResult:
	var combat := state.combat
	if count_spell_cast:
		combat.active_turn.spell_cast_count += 1
	caster.attacks_remaining = _rules.arithmetic.signed_16(caster.attacks_remaining - 2)
	caster.movement = maxi(0, caster.movement - 12)
	var events: Array[DomainEvent] = []
	_append_spell_sound(events, spell.sound_start, "classic-combat-spell-start")
	_append_spell_cast_event(events, caster.id, spell, group, center, shape, event_source)
	for index: int in group.resolutions.size():
		var resolution := group.resolutions[index]
		var resolved_target_id := group.target_ids[index]
		var selected_target_id := group.selected_target_ids[index]
		var target_kind := group.target_kinds[index]
		var reflected := group.reflected_targets[index]
		if resolution.damage > 0 or (resolution.damage < 0 and target_kind == &"monster"):
			combat.mark_attacked(resolved_target_id)
		_append_spell_projectile_event(events, caster.id, resolved_target_id, spell, event_source)
		_append_spell_sound(events, spell.sound_end, "classic-combat-spell-result")
		var payload := {"actorId": caster.id, "targetId": resolved_target_id, "selectedTargetId": selected_target_id, "targetKind": String(target_kind), "spellId": spell.id, "targetType": spell.target_type, "power": power_level, "classicTier": cast_level, "reflected": reflected, "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "healing": maxi(0, -resolution.damage), "duration": resolution.duration, "defeated": resolution.target_defeated, "source": event_source}
		_append_spell_presentation(payload, spell, index, group.resolutions.size(), resolution.target_defeated)
		if not item_instance_id.is_empty():
			payload["itemInstanceId"] = item_instance_id
		if shape > 0:
			payload["areaCenter"] = [center.x, center.y]
			payload["areaShape"] = shape
		events.append(DomainEvent.new(&"combat_spell_resolved", payload))
		if not resolution.target_defeated:
			continue
		if target_kind == &"character":
			_remove_defeated_position(combat, resolved_target_id, true)
		else:
			var defeated_monster := combat.monster_by_id(resolved_target_id)
			var defeated_definition := content.monster_by_id(defeated_monster.definition_id) if defeated_monster != null else null
			var queued := _queue_spell_death_macro(combat, defeated_monster, defeated_definition)
			_remove_defeated_position(combat, resolved_target_id, not queued)
	var advances_turn := not _character_can_continue(caster)
	if not combat.pending_spell_death_macro_id().is_empty():
		if not combat.begin_spell_death_macro_sequence(caster.id, advances_turn) or not _request_next_spell_death_macro(combat, content, events):
			return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The multi-target spell death-macro queue could not retain its caster and source order.")
		return CombatFlowResult.succeeded(events)
	if advances_turn:
		_advance_turn(state, rng, events)
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


static func _append_spell_sound(events: Array[DomainEvent], authored_sound_id: int, source: String) -> void:
	var native_sound_id := authored_sound_id + 600
	if native_sound_id == 0:
		return
	events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(native_sound_id), "waitForCompletion": native_sound_id < 0, "source": source}))


static func _append_spell_cast_event(events: Array[DomainEvent], actor_id: String, spell: SpellDefinition, resolutions: GroupSpellResolution, center: Vector2i, shape: int, source: String) -> void:
	var target_id := resolutions.target_ids[0] if not resolutions.target_ids.is_empty() else ""
	var payload := {"actorId": actor_id, "targetId": target_id, "spellId": spell.id, "classicEffectResourceId": 11_992 + spell.look_start * 8, "source": source}
	if shape > 0:
		payload["areaCenter"] = [center.x, center.y]
		payload["areaShape"] = shape
	events.append(DomainEvent.new(&"combat_spell_cast", payload))


static func _append_spell_projectile_event(events: Array[DomainEvent], actor_id: String, target_id: String, spell: SpellDefinition, source: String) -> void:
	if not spell.target_type in [0, 1, 2, 5, 6, 7, 8, 11]:
		return
	events.append(DomainEvent.new(&"combat_spell_projectile", {"actorId": actor_id, "targetId": target_id, "spellId": spell.id, "classicBattleTileId": 200 + spell.look_start, "source": source}))


static func _append_spell_presentation(payload: Dictionary, spell: SpellDefinition, sequence_index: int, sequence_count: int, target_defeated: bool) -> void:
	payload["castSequenceIndex"] = sequence_index
	payload["castSequenceCount"] = sequence_count
	# resolvespell.c bypasses the ordinary eight-frame resolution effect when the
	# target dies, and group-body flashes (9/10) use a separate path.
	if target_defeated or spell.target_type in [9, 10]:
		return
	var first_resource_id := 12_032 if spell.look_end == 0 else 11_992 + spell.look_end * 8
	var effect_ids: Array[int] = []
	for frame_offset: int in 8:
		effect_ids.append(first_resource_id + frame_offset)
	payload["classicResolutionEffectResourceIds"] = effect_ids


func probe_character_spell_cast(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell_id: String, power_level: int, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = []) -> CombatSpellCastProbe:
	if state == null or content == null:
		return CombatSpellCastProbe.blocked(&"invalid_spell_turn", "Spell casting requires an active game session.")
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or combat.active_actor_id() != caster_id:
		return CombatSpellCastProbe.blocked(&"invalid_spell_turn", "The caster does not own an active combat turn.")
	if not combat.pending_spell_death_macro_id().is_empty():
		return CombatSpellCastProbe.blocked(&"spell_death_macro_pending", "A spell-triggered monster death macro must complete before another combat action.")
	var caster := state.party.character_by_id(caster_id)
	var spell := content.spell_by_id(spell_id)
	if caster == null or caster.current_health <= 0 or caster.traitor or spell == null or power_level < 1 or power_level > 7:
		return CombatSpellCastProbe.blocked(&"invalid_spell_target", "The spell, caster, power, or target is unavailable.")
	var repeated_target := spell.target_type == 0
	var group_target := spell.target_type in [9, 10, 12]
	var area_target := spell.target_type in [3, 4]
	var actor_target := not repeated_target and not group_target and not area_target
	var actor_selection := _spell_target_selection(state, content, target_id) if actor_target else null
	if actor_target and actor_selection == null:
		return CombatSpellCastProbe.blocked(&"invalid_spell_target", "The spell, caster, power, or target is unavailable.")
	if not caster.known_spells().has(spell.id):
		return CombatSpellCastProbe.blocked(&"spell_not_known", "The caster does not know '%s'." % spell.id)
	if state.character_spellcasting_blocked:
		return CombatSpellCastProbe.blocked(&"character_spellcasting_blocked", "Classic scenario state currently blocks character spellcasting.")
	for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
		if caster.conditions.is_active(condition):
			return CombatSpellCastProbe.blocked(&"spellcasting_condition_blocked", "The caster's current Classic condition prevents spellcasting.")
	if combat.was_attacked(caster.id):
		return CombatSpellCastProbe.blocked(&"caster_attacked_this_round", "Castle prevents a character who has been attacked this combat round from casting.")
	var committed_casts := combat.active_turn.spell_cast_count if combat.active_turn != null else 0
	if caster.maximum_spell_attacks <= 0 or committed_casts >= caster.maximum_spell_attacks:
		return CombatSpellCastProbe.blocked(&"spell_attack_limit_reached", "The caster has reached the Classic per-activation spell limit.")
	if not spell.in_combat:
		return CombatSpellCastProbe.blocked(&"spell_not_available_in_combat", "The selected spell is not available in combat.")
	var healing_spell := _is_source_backed_combat_healing_spell(spell)
	var ordinary_spell := spell.special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 6 and absi(spell.spell_class) != 9
	if spell.target_type not in [0, 1, 3, 4, 9, 10, 12] or (not ordinary_spell and not healing_spell):
		return CombatSpellCastProbe.blocked(&"unsupported_combat_spell", "This pass supports source-backed ordinary combat spells and the strict special-57 single-target healing form.")
	if repeated_target and spell.size != 0:
		return CombatSpellCastProbe.blocked(&"repeated_open_space_spell_unresolved", "Classic target type 0 with nonzero size selects open-space footprints for summoning or special behavior, not ordinary actors.")
	if spell.queue_icon != 0:
		return CombatSpellCastProbe.blocked(&"queued_spell_field_unresolved", "This spell creates a persistent Classic battlefield field whose collision lifecycle is not implemented.")
	if area_target and spell.can_rotate:
		return CombatSpellCastProbe.blocked(&"rotatable_area_spell_unresolved", "Classic rotatable area masks require a separate orientation-selection contract.")
	if area_target and rotation != 0:
		return CombatSpellCastProbe.blocked(&"invalid_area_rotation", "This non-rotating Classic area spell requires rotation zero.")
	if not healing_spell and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_spell", "A zero-damage spell requires its source-backed special-effect path.")
	if spell.cost < 0 and power_level != 1:
		return CombatSpellCastProbe.blocked(&"fixed_power_spell", "Castle fixes negative-cost spells at power one.")
	var spell_cost := absi(spell.cost * power_level)
	if caster.spell_points < spell_cost:
		return CombatSpellCastProbe.blocked(&"insufficient_spell_points", "The caster lacks the spell points for this power level.")
	var cast_level := spell.classic_tier()
	if cast_level < 0 or cast_level > 6:
		return CombatSpellCastProbe.blocked(&"invalid_classic_spell_tier", "The spell ID does not encode a valid Classic tier.")
	if repeated_target:
		if target_ids.size() > power_level:
			return CombatSpellCastProbe.blocked(&"too_many_spell_targets", "A repeated-target spell may select at most one distinct actor per power level.")
		var seen: Dictionary = {}
		for selected_id: String in target_ids:
			if selected_id.is_empty() or seen.has(selected_id):
				return CombatSpellCastProbe.blocked(&"invalid_repeated_spell_targets", "Repeated spell targets must be nonempty and distinct.")
			seen[selected_id] = true
			var selection := _spell_target_selection(state, content, selected_id)
			if selection == null:
				return CombatSpellCastProbe.blocked(&"invalid_spell_target", "A selected repeated-spell actor is unavailable.")
			if not _spell_actor_target_is_valid(state, content, caster.id, selected_id, spell, power_level):
				return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "A selected repeated-spell actor is outside the Classic spell range or line of sight.")
		if target_ids.is_empty() and _character_actor_spell_candidates(state, content, caster, spell, power_level).is_empty():
			return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "No actor is available within this repeated spell's Classic range and line of sight.")
	elif area_target:
		var shape := _rules.spell_areas.shape_for(spell, power_level, rotation)
		if _rules.spell_areas.pattern(shape).is_empty():
			return CombatSpellCastProbe.blocked(&"invalid_spell_area_shape", "The spell references an unavailable Classic Data AD area mask.")
		if target_coordinate != INVALID_COORDINATE:
			if not _rules.spell_areas.pattern_fits(target_coordinate, shape):
				return CombatSpellCastProbe.blocked(&"spell_area_outside_battlefield", "The complete Classic area mask must remain inside the validated battlefield.")
			var map := content.world.map_by_id(combat.battlefield.map_id)
			var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null
			var maximum_range := absi(spell.range_min + spell.range_max * power_level)
			if terrain_set == null or not _rules.battlefield.coordinate_target_is_valid(combat.battlefield, terrain_set, caster.id, target_coordinate, maximum_range, spell.range_min + spell.range_max > 0):
				return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "The area center is outside the Classic spell range or line of sight.")
	elif not group_target:
		if not _spell_actor_target_is_valid(state, content, caster.id, target_id, spell, power_level):
			return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "The target is outside the Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func character_spell_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatSpellOptionView]:
	var result: Array[CombatSpellOptionView] = []
	if state == null or state.combat == null:
		return result
	var caster := state.party.character_by_id(caster_id)
	if caster == null:
		return result
	for spell_id: String in caster.known_spells():
		var spell := content.spell_by_id(spell_id)
		if spell == null:
			continue
		for power_level: int in range(1, 8):
			if spell.target_type == 0:
				if probe_character_spell_cast(state, content, caster_id, "", spell.id, power_level).allowed:
					var candidates := _character_actor_spell_candidates(state, content, caster, spell, power_level)
					result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose up to %d actors" % power_level, &"sequence", 0, INVALID_COORDINATE, [], power_level, candidates))
				continue
			if spell.target_type in [9, 10, 12]:
				if probe_character_spell_cast(state, content, caster_id, "", spell.id, power_level).allowed:
					result.append(CombatSpellOptionView.new(spell, power_level, null, _group_spell_target_label(spell.target_type), &"automatic"))
				continue
			if spell.target_type in [3, 4]:
				if probe_character_spell_cast(state, content, caster_id, "", spell.id, power_level).allowed:
					var shape := _rules.spell_areas.shape_for(spell, power_level)
					var offsets := _rules.spell_areas.pattern(shape)
					var legal_coordinates := _legal_area_spell_target_coordinates(state, content, caster_id, spell, power_level, shape)
					result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose battlefield point", &"area", shape, state.combat.battlefield.actor_position(caster_id), offsets, 1, [], legal_coordinates))
				continue
			for target: CombatSpellTargetView in _character_actor_spell_candidates(state, content, caster, spell, power_level):
				if probe_character_spell_cast(state, content, caster_id, target.id, spell.id, power_level).allowed:
					result.append(CombatSpellOptionView.new(spell, power_level, target))
	return result


func _legal_area_spell_target_coordinates(state: GameState, content: RealmzContent, caster_id: String, spell: SpellDefinition, power_level: int, shape: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if state == null or state.combat == null or state.combat.battlefield == null or content == null or spell == null:
		return result
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null
	if terrain_set == null:
		return result
	var origin := state.combat.battlefield.actor_position(caster_id)
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	var minimum := Vector2i(maxi(0, origin.x - maximum_range - 1), maxi(0, origin.y - maximum_range - 1))
	var maximum := Vector2i(mini(BattlefieldState.SIZE - 1, origin.x + maximum_range + 1), mini(BattlefieldState.SIZE - 1, origin.y + maximum_range + 1))
	var require_line_of_sight := spell.range_min + spell.range_max > 0
	for y: int in range(minimum.y, maximum.y + 1):
		for x: int in range(minimum.x, maximum.x + 1):
			var coordinate := Vector2i(x, y)
			if _rules.spell_areas.pattern_fits(coordinate, shape) and _rules.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster_id, coordinate, maximum_range, require_line_of_sight):
				result.append(coordinate)
	return result


func _character_actor_spell_candidates(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int) -> Array[CombatSpellTargetView]:
	var result: Array[CombatSpellTargetView] = []
	for character: CharacterState in state.party.characters():
		if character.current_health <= 0 or not state.combat.battlefield.has_actor(character.id):
			continue
		if _spell_actor_target_is_valid(state, content, caster.id, character.id, spell, power_level):
			result.append(CombatSpellTargetView.new(character.id, &"character", character.name, character.current_health, character.maximum_health))
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health <= 0 or not state.combat.battlefield.has_actor(monster.id):
			continue
		if _spell_actor_target_is_valid(state, content, caster.id, monster.id, spell, power_level):
			result.append(CombatSpellTargetView.new(monster.id, &"monster", monster.name, monster.current_health, monster.maximum_health))
	return result


static func _spell_target_view(state: GameState, content: RealmzContent, target_id: String) -> CombatSpellTargetView:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return CombatSpellTargetView.new(character.id, &"character", character.name, character.current_health, character.maximum_health)
	var monster := state.combat.monster_by_id(target_id) if state.combat != null else null
	if monster != null and content.monster_by_id(monster.definition_id) != null:
		return CombatSpellTargetView.new(monster.id, &"monster", monster.name, monster.current_health, monster.maximum_health)
	return null


func _spell_actor_target_is_valid(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell: SpellDefinition, power_level: int) -> bool:
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	if caster_id == target_id:
		var map := content.world.map_by_id(state.combat.battlefield.map_id)
		var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null
		return terrain_set != null and _rules.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster_id, state.combat.battlefield.actor_position(caster_id), maximum_range, spell.range_min + spell.range_max > 0)
	return projectile_target_is_valid(state.combat, content, caster_id, target_id, maximum_range, spell.range_min + spell.range_max > 0)


static func _spell_target_selection(state: GameState, content: RealmzContent, target_id: String) -> SpellTargetSelection:
	var character := state.party.character_by_id(target_id)
	if character != null and character.current_health > 0 and state.combat.battlefield.has_actor(character.id):
		return SpellTargetSelection.for_character(character)
	var monster := state.combat.monster_by_id(target_id)
	if monster == null or monster.current_health <= 0 or not state.combat.battlefield.has_actor(monster.id):
		return null
	var definition := content.monster_by_id(monster.definition_id)
	return SpellTargetSelection.for_monster(monster, definition) if definition != null else null


static func _group_spell_target_label(target_type: int) -> String:
	return {9: "All Friendly", 10: "All Enemies", 12: "Everybody"}.get(target_type, "Automatic Targets")


static func _group_target_matches(target_type: int, target_traitor: bool, caster_traitor: bool) -> bool:
	if target_type == 12:
		return true
	if target_type == 9:
		return target_traitor == caster_traitor
	return target_traitor != caster_traitor


func character_spell_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	if state == null or state.combat == null:
		return ""
	var caster := state.party.character_by_id(caster_id)
	if caster == null or caster.maximum_spell_attacks <= 0 or caster.known_spells().is_empty():
		return ""
	if not character_spell_options(state, content, caster_id).is_empty():
		return ""
	var spells := caster.known_spells()
	var first_spell := content.spell_by_id(spells[0])
	var targets := _character_actor_spell_candidates(state, content, caster, first_spell, 1) if first_spell != null else []
	if targets.is_empty():
		return "No live combatant is available for this spell."
	var probe := probe_character_spell_cast(state, content, caster_id, targets[0].id, spells[0], 1)
	return probe.reason_text


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
		_remove_defeated_position(state.combat, completed_combatant_id, completed_monster != null and completed_monster.current_health <= 0 and not same_subject_remains)
		if not state.combat.pending_spell_death_macro_id().is_empty():
			if not _request_next_spell_death_macro(state.combat, content, events):
				return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The next queued spell death macro references unavailable content.")
			return CombatFlowResult.succeeded(events)
		var spell_actor_id := state.combat.spell_macro_actor_id()
		var advances_turn := state.combat.spell_macro_advances_turn()
		if advances_turn:
			if state.combat.active_actor_id() != spell_actor_id:
				return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The active caster changed before the queued spell action completed.")
		state.combat.clear_spell_death_macro_sequence()
		if advances_turn:
			_advance_turn(state, rng, events)
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
			_advance_turn(state, rng, events)
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
	if pending.damage > 0:
		combat.mark_attacked(target.id)
	var defeated := target.current_health <= 0
	_mark_character_bleeding(state, target, defeated)
	_remove_defeated_position(combat, target.id, defeated)
	var pending_attack_index := maxi(0, combat.active_turn.attack_index - 1) if combat.active_turn != null and combat.pending_reaction == null else 0
	var pending_attacker := combat.monster_by_id(pending.actor_id)
	var pending_definition := content.monster_by_id(pending_attacker.definition_id) if pending_attacker != null else null
	var pending_weapon := content.item_by_id(pending_attacker.weapon_id) if pending_attacker != null and not pending_attacker.weapon_id.is_empty() else null
	var pending_resolution := AttackResolution.new(true, defeated, pending.chance, pending.roll, pending.damage)
	_append_monster_attack_audio(events, pending_attacker, pending_definition, pending_attack_index, pending_weapon, pending_resolution, rng)
	var attack_event := DomainEvent.new(&"combat_attack_resolved", {"actorId": pending.actor_id, "targetId": pending.target_id, "action": String(pending.action), "attackIndex": pending_attack_index, "hit": true, "damage": pending.damage, "defeated": defeated, "chance": pending.chance, "roll": pending.roll})
	_append_physical_result_effect(attack_event, true, pending_weapon != null)
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
				_advance_turn(state, rng, events)
			if _finish_if_resolved(state, content, events):
				return CombatFlowResult.succeeded(events, true)
			_process_monster_turns(state, content, rng, events)
			return CombatFlowResult.succeeded(events, state.combat.completed)
		if reaction_kind == CombatReactionState.CHARACTER_MOVE:
			return CombatFlowResult.succeeded(events)
		_process_monster_turns(state, content, rng, events)
		return CombatFlowResult.succeeded(events, state.combat.completed)
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	var monster := combat.monster_by_id(pending.actor_id)
	var definition := content.monster_by_id(monster.definition_id) if monster != null else null
	if combat.active_turn == null or combat.active_turn.actor_id != pending.actor_id or pending.action != &"advance" or definition == null or combat.active_turn.attack_index >= _monster_attack_limit(definition):
		_advance_turn(state, rng, events)
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


func _fire_character_projectile(state: GameState, content: RealmzContent, actor: CharacterState, equipment: CharacterCombatEquipment, target_id: String, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	var profile := character_projectile_profile(actor, content, equipment)
	if not profile.available:
		return CombatFlowResult.failed(profile.error_code, profile.error_message)
	var target := combat.monster_by_id(target_id)
	if target == null or target.current_health <= 0 or target.traitor == actor.traitor:
		return CombatFlowResult.failed(&"invalid_projectile_target", "This source-backed projectile slice can target only a living hostile monster.")
	if not projectile_target_is_valid(combat, content, actor.id, target.id, profile.maximum_range, profile.spell.range_min + profile.spell.range_max > 0):
		return CombatFlowResult.failed(&"projectile_target_unavailable", "The target is outside the Classic projectile range or line of sight.")
	var definition := content.monster_by_id(target.definition_id)
	var caste := content.caste_by_id(actor.caste_id)
	if definition == null or caste == null:
		return CombatFlowResult.failed(&"projectile_target_unavailable", "Projectile resolution requires the target monster and caster caste definitions.")
	_prepare_character_turn(combat, actor)
	if not _rules.inventory.use_charge(actor, profile.item_instance_id, profile.item):
		return CombatFlowResult.failed(&"projectile_charge_unavailable", "The selected projectile charge could not be consumed atomically.")
	combat.invalidate_undo()
	var resolution := _rules.magic.resolve_character_projectile(actor, caste, profile.item, target, profile.spell, profile.power_level, rng)
	if resolution == null:
		return CombatFlowResult.failed(&"unsupported_projectile_spell", "The selected projectile cannot be resolved by the source-backed missile rules.")
	if resolution.total_damage > 0:
		combat.mark_attacked(target.id)
	combat.active_turn.physical_action_committed = true
	actor.attacks_remaining = _rules.arithmetic.signed_16(actor.attacks_remaining - 2)
	actor.movement = maxi(0, actor.movement - 12)
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_projectile_resolved", {
		"actorId": actor.id,
		"targetId": target.id,
		"targetKind": "monster",
		"itemId": profile.item.id,
		"spellId": profile.spell.id,
		"powerLevel": profile.power_level,
		"range": _rules.battlefield.classic_range(combat.battlefield, actor.id, target.id),
		"hitCount": resolution.hit_count,
		"missCount": resolution.miss_count,
		"damage": resolution.total_damage,
		"defeated": resolution.target_defeated,
		"source": "classic",
	})]
	var death_macro_requested := resolution.target_defeated and _request_monster_death_macro(target, definition, events)
	_remove_defeated_position(combat, target.id, resolution.target_defeated and not death_macro_requested)
	if not _character_can_continue(actor):
		_advance_turn(state, rng, events)
	if death_macro_requested:
		return CombatFlowResult.succeeded(events)
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


static func _projectile_spell_unavailable_reason(spell: SpellDefinition) -> String:
	if spell.target_type != 1:
		return "Classic projectile spell '%s' does not use a single-target picker." % spell.id
	if absi(spell.spell_class) != 9:
		return "Classic projectile spell '%s' is not missile class 9." % spell.id
	if absi(spell.damage_type) != 9:
		return "Elemental projectile spell '%s' requires its source-backed save and special-effect path." % spell.id
	if spell.special != 0:
		return "Projectile spell '%s' uses unresolved Classic special %d." % [spell.id, spell.special]
	return ""


func _prepare_character_turn(combat: CombatState, character: CharacterState) -> void:
	if combat.active_turn != null:
		return
	combat.begin_active_turn()
	combat.begin_character_undo(character.id)
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
			if charmed_actor != null and (combat.battlefield == null or not combat.battlefield.has_actor(charmed_actor.id)):
				_advance_turn(state, rng, events)
				guard -= 1
				continue
			if charmed_actor == null or not charmed_actor.traitor:
				if charmed_actor != null and charmed_actor.current_health > 0:
					_prepare_character_turn(combat, charmed_actor)
					if state.combat_auto_enabled(charmed_actor.id) and not _processing_auto:
						var auto_result := run_persistent_auto_characters(state, content, rng)
						if not auto_result.ok:
							events.append(DomainEvent.new(&"combat_auto_failed", {"actorId": charmed_actor.id, "code": String(auto_result.error_code), "message": auto_result.error_message, "rolledBack": true}))
							return
						events.append_array(auto_result.events)
						return
				break
			if charmed_actor.current_health > 0 and _process_charmed_character_turn(state, content, charmed_actor, rng, events):
				_advance_turn(state, rng, events)
				return
			_advance_turn(state, rng, events)
			if _finish_if_resolved(state, content, events):
				break
			guard -= 1
			continue
		if monster.current_health <= 0:
			_advance_turn(state, rng, events)
			guard -= 1
			continue
		if combat.active_turn == null:
			combat.set_guarding(monster.id, true)
		if monster.conditions.is_active(ConditionRules.HELPLESS):
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": "incapacitated"}))
			_advance_turn(state, rng, events)
			guard -= 1
			continue
		var definition := content.monster_by_id(monster.definition_id)
		if definition == null:
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": "unavailable_definition"}))
			_advance_turn(state, rng, events)
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
				if _monster_can_retry_cast(state, monster, definition, active_turn):
					attack_result = _process_monster_cast(state, content, monster, definition, active_turn, rng, events)
		elif active_turn.action == &"missile":
			attack_result = _process_monster_projectile(state, content, monster, definition, active_turn, rng, events)
			if attack_result == MONSTER_ATTACK_FALLBACK:
				active_turn.action = _rules.monsters.choose_action_after_missile(monster, definition, rng)
				if active_turn.action == &"cast":
					attack_result = _process_monster_cast(state, content, monster, definition, active_turn, rng, events)
					if attack_result == MONSTER_ATTACK_FALLBACK:
						active_turn.action = &"advance"
						attack_result = _process_monster_advance(state, content, monster, definition, active_turn, rng, events)
						if attack_result == MONSTER_ATTACK_COMPLETED and _monster_can_retry_cast(state, monster, definition, active_turn):
							attack_result = _process_monster_cast(state, content, monster, definition, active_turn, rng, events)
				else:
					attack_result = _process_monster_advance(state, content, monster, definition, active_turn, rng, events)
					if attack_result == MONSTER_ATTACK_COMPLETED and _monster_can_retry_cast(state, monster, definition, active_turn):
						attack_result = _process_monster_cast(state, content, monster, definition, active_turn, rng, events)
			if attack_result != MONSTER_ATTACK_COMPLETED:
				return
		elif active_turn.action == &"cast":
			attack_result = _process_monster_cast(state, content, monster, definition, active_turn, rng, events)
			if attack_result == MONSTER_ATTACK_FALLBACK:
				active_turn.action = &"advance"
				attack_result = _process_monster_advance(state, content, monster, definition, active_turn, rng, events)
				if attack_result == MONSTER_ATTACK_COMPLETED and _monster_can_retry_cast(state, monster, definition, active_turn):
					attack_result = _process_monster_cast(state, content, monster, definition, active_turn, rng, events)
			if attack_result != MONSTER_ATTACK_COMPLETED:
				return
		elif active_turn.action == &"retreat":
			attack_result = _process_monster_retreat(state, content, monster, definition, active_turn, rng, events)
			if attack_result != MONSTER_ATTACK_COMPLETED:
				return
		else:
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": String(active_turn.action)}))
		_advance_turn(state, rng, events)
		if _finish_if_resolved(state, content, events):
			break
		guard -= 1


func _process_monster_cast(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	active_turn.monster_cast_attempt_count += 1
	if state.monster_spellcasting_blocked or state.combat.was_attacked(monster.id) or definition.magic_attack_count <= 0:
		return MONSTER_ATTACK_FALLBACK
	for condition: int in [ConditionRules.STUPID, ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS]:
		if monster.conditions.is_active(condition):
			return MONSTER_ATTACK_FALLBACK
	var did_cast := active_turn.spell_cast_count > 0
	while active_turn.spell_cast_count < definition.magic_attack_count:
		var spell: SpellDefinition = null
		var sampled_slot := -1
		var sampled_id := ""
		for draw_index: int in 30:
			sampled_slot = rng.draw_between(0, 9, StringName("monster.spell.slot.%d.%d" % [active_turn.spell_cast_count, draw_index]))
			sampled_id = definition.spell_id_at(sampled_slot)
			if not sampled_id.is_empty():
				spell = content.spell_by_id(sampled_id)
				break
		if not sampled_id.is_empty() and spell == null:
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "spellId": sampled_id, "spellSlot": sampled_slot, "reason": "unknown-monster-spell-definition"}))
			if did_cast:
				break
			return MONSTER_ATTACK_COMPLETED
		if spell == null:
			if did_cast:
				break
			return MONSTER_ATTACK_FALLBACK
		var unavailable := _monster_spell_unavailable_reason(spell)
		if not unavailable.is_empty():
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "spellId": spell.id, "spellSlot": sampled_slot, "reason": unavailable}))
			if did_cast:
				break
			return MONSTER_ATTACK_COMPLETED
		var range_power := rng.draw(7, StringName("monster.spell.range-power.%d" % active_turn.spell_cast_count))
		var eligible_targets: Dictionary = {}
		var targets_friendly := spell.cannot == 4
		var party := state.party.characters()
		for party_index: int in party.size():
			var character := party[party_index]
			if character.current_health > 0 and (character.traitor == monster.traitor) == targets_friendly and state.combat.battlefield.has_actor(character.id) and _spell_actor_target_is_valid(state, content, monster.id, character.id, spell, range_power):
				eligible_targets[party_index] = SpellTargetSelection.for_character(character)
		var battle_monsters := state.combat.monsters()
		for monster_index: int in battle_monsters.size():
			var candidate := battle_monsters[monster_index]
			if candidate.current_health > 0 and (candidate.traitor == monster.traitor) == targets_friendly and state.combat.battlefield.has_actor(candidate.id) and _spell_actor_target_is_valid(state, content, monster.id, candidate.id, spell, range_power):
				var target_definition := content.monster_by_id(candidate.definition_id)
				if target_definition == null:
					events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "spellId": spell.id, "targetId": candidate.id, "reason": "unknown-monster-target-definition"}))
					return MONSTER_ATTACK_COMPLETED
				eligible_targets[10 + monster_index] = SpellTargetSelection.for_monster(candidate, target_definition)
		if eligible_targets.is_empty():
			if did_cast:
				break
			return MONSTER_ATTACK_FALLBACK
		var cost_power := rng.draw(eligible_targets.size(), StringName("monster.spell.target-power.%d" % active_turn.spell_cast_count)) if spell.target_type == 0 else range_power
		cost_power = mini(7, cost_power)
		while cost_power > 0 and spell.cost * cost_power > monster.spell_points:
			cost_power -= 1
		if cost_power <= 0:
			if did_cast:
				break
			return MONSTER_ATTACK_FALLBACK
		var selected_targets: Array[SpellTargetSelection] = []
		var selected_target_ids: Dictionary = {}
		var native_target_count := 10 + battle_monsters.size()
		var target_draw := 0
		var target_attempts := 0
		while selected_targets.size() < (cost_power if spell.target_type == 0 else 1):
			target_attempts += 1
			if target_attempts > 100:
				break
			var native_target := rng.draw(native_target_count, StringName("monster.spell.target.%d.%d" % [active_turn.spell_cast_count, target_draw])) - 1
			target_draw += 1
			var candidate := eligible_targets.get(native_target) as SpellTargetSelection
			if candidate == null or selected_target_ids.has(candidate.id):
				continue
			selected_targets.append(candidate)
			selected_target_ids[candidate.id] = true
		if selected_targets.is_empty():
			if did_cast:
				break
			return MONSTER_ATTACK_FALLBACK
		var cast_level := spell.classic_tier()
		if cast_level < 0 or cast_level > 6:
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "spellId": spell.id, "reason": "invalid-classic-spell-tier"}))
			if did_cast:
				break
			return MONSTER_ATTACK_COMPLETED
		state.combat.set_guarding(monster.id, false)
		active_turn.movement_remaining = 0
		var resolutions: GroupSpellResolution
		if spell.target_type == 0:
			resolutions = _rules.magic.resolve_monster_repeated_spell(monster, definition, selected_targets, spell, cost_power, cast_level, rng)
		else:
			resolutions = _rules.magic.resolve_monster_targeted_spell(monster, definition, selected_targets[0], spell, cost_power, cast_level, rng)
		if resolutions == null or not resolutions.cast:
			if did_cast:
				break
			return MONSTER_ATTACK_FALLBACK
		active_turn.spell_cast_count += 1
		did_cast = true
		_append_spell_sound(events, spell.sound_start, "classic-monster-spell-start")
		_append_spell_cast_event(events, monster.id, spell, resolutions, INVALID_COORDINATE, 0, "classic-monster")
		for index: int in resolutions.resolutions.size():
			var resolution := resolutions.resolutions[index]
			var resolved_target_id := resolutions.target_ids[index]
			var selected_target_id := resolutions.selected_target_ids[index]
			var target_kind := resolutions.target_kinds[index]
			var reflected := resolutions.reflected_targets[index]
			if resolution.damage > 0 or (resolution.damage < 0 and target_kind == &"monster"):
				state.combat.mark_attacked(resolved_target_id)
			_append_spell_projectile_event(events, monster.id, resolved_target_id, spell, "classic-monster")
			_append_spell_sound(events, spell.sound_end, "classic-monster-spell-result")
			var payload := {"actorId": monster.id, "targetId": resolved_target_id, "selectedTargetId": selected_target_id, "targetKind": String(target_kind), "spellId": spell.id, "targetType": spell.target_type, "power": cost_power, "rangePower": range_power, "classicTier": cast_level, "reflected": reflected, "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "healing": maxi(0, -resolution.damage), "duration": resolution.duration, "defeated": resolution.target_defeated, "source": "classic-monster"}
			_append_spell_presentation(payload, spell, index, resolutions.resolutions.size(), resolution.target_defeated)
			events.append(DomainEvent.new(&"combat_spell_resolved", payload))
			if not resolution.target_defeated:
				continue
			if target_kind == &"character":
				_mark_character_bleeding(state, state.party.character_by_id(resolved_target_id), true)
				_remove_defeated_position(state.combat, resolved_target_id, true)
			else:
				var defeated_monster := state.combat.monster_by_id(resolved_target_id)
				var defeated_definition := content.monster_by_id(defeated_monster.definition_id) if defeated_monster != null else null
				var queued := _queue_spell_death_macro(state.combat, defeated_monster, defeated_definition)
				if not queued and defeated_definition != null and defeated_definition.death_macro > 0:
					events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "targetId": resolved_target_id, "reason": "spell-death-macro-queue-limit"}))
				# Castle's noofmagattacks loop continues after reflection kills the caster;
				# retain its anchor until the complete spell sequence and queued macros finish.
				_remove_defeated_position(state.combat, resolved_target_id, not queued and resolved_target_id != monster.id)
	if not state.combat.pending_spell_death_macro_id().is_empty():
		if not state.combat.begin_spell_death_macro_sequence(monster.id, true) or not _request_next_spell_death_macro(state.combat, content, events):
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "reason": "invalid-spell-death-macro-queue"}))
			return MONSTER_ATTACK_COMPLETED
		return MONSTER_ATTACK_DEATH_MACRO
	if monster.current_health <= 0:
		_remove_defeated_position(state.combat, monster.id, true)
	return MONSTER_ATTACK_COMPLETED if did_cast else MONSTER_ATTACK_FALLBACK


static func _monster_can_retry_cast(state: GameState, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState) -> bool:
	return definition.cast_percent != 0 and not active_turn.physical_action_committed and active_turn.spell_cast_count == 0 and active_turn.monster_cast_attempt_count < 2 and monster.current_health > 0 and not state.combat.was_attacked(monster.id) and not state.monster_spellcasting_blocked


static func _monster_spell_unavailable_reason(spell: SpellDefinition) -> String:
	if spell.queue_icon != 0:
		return "monster-queued-spell-field-unresolved"
	if spell.target_type in [9, 10, 12]:
		return "monster-group-spell-power-resource-anomaly"
	if spell.target_type == 0 and spell.size != 0:
		return "monster-repeated-open-space-spell-unresolved"
	if spell.target_type not in [0, 1]:
		return "monster-spell-target-shape-unresolved"
	var healing_spell := _is_source_backed_combat_healing_spell(spell)
	if spell.special != 0 and not healing_spell:
		return "monster-spell-special-unresolved"
	if not healing_spell and (absi(spell.damage_type) < 1 or absi(spell.damage_type) > 6 or absi(spell.spell_class) == 9):
		return "monster-spell-damage-class-unresolved"
	if not healing_spell and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0:
		return "monster-spell-zero-damage-effect-unresolved"
	if spell.cost <= 0:
		return "monster-spell-nonpositive-cost-anomaly"
	if spell.cannot == 4 and not healing_spell:
		return "monster-spell-friendly-target-unresolved"
	return ""


static func _is_source_backed_combat_healing_spell(spell: SpellDefinition) -> bool:
	if spell == null or absi(spell.special) != 57 or not spell.in_combat or spell.queue_icon != 0 or spell.target_type != 1 or spell.cannot != 4 or spell.cost <= 0:
		return false
	if absi(spell.spell_class) != 8 or absi(spell.damage_type) != 8:
		return false
	if spell.duration_min != 0 or spell.duration_max != 0 or spell.power_duration_min != 0 or spell.power_duration_max != 0:
		return false
	if spell.damage_min < 0 or spell.damage_max < 0 or spell.power_damage_min < 0 or spell.power_damage_max < 0:
		return false
	return spell.damage_min > 0 or spell.damage_max > 0 or spell.power_damage_min > 0 or spell.power_damage_max > 0


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


func _process_monster_projectile(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var projectile_item_id := definition.item_id_at(1)
	var projectile_item := content.item_by_id(projectile_item_id) if not projectile_item_id.is_empty() else null
	var projectile_spell := content.spell_by_classic_id(absi(projectile_item.special_2)) if projectile_item != null else null
	var unavailable := "Monster missile slot 1 is empty or references an unavailable item."
	if projectile_item != null and projectile_spell == null:
		unavailable = "Monster missile item '%s' references an unavailable Classic spell." % projectile_item.id
	elif projectile_spell != null:
		unavailable = _projectile_spell_unavailable_reason(projectile_spell)
	if projectile_item == null or projectile_spell == null or not unavailable.is_empty():
		active_turn.movement_remaining = 0
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "missile", "reason": unavailable, "source": "classic"}))
		return MONSTER_ATTACK_COMPLETED
	var terrain_set := _battle_terrain_set(content, combat.battlefield)
	if terrain_set == null:
		active_turn.movement_remaining = 0
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "missile", "reason": "missing-battle-terrain", "source": "classic"}))
		return MONSTER_ATTACK_COMPLETED
	# combat.c rolls power for range and spell-point cost, then forces power 1
	# immediately before resolving the actual missile effect.
	var range_power := rng.draw(7, StringName("combat.monster-projectile.%s.power" % monster.id))
	var maximum_range := absi(projectile_spell.range_min + projectile_spell.range_max * range_power)
	var target_ids := _monster_projectile_target_ids(state, monster, terrain_set, maximum_range)
	if target_ids.is_empty():
		events.append(DomainEvent.new(&"combat_monster_projectile_skipped", {"actorId": monster.id, "reason": "no-character-target-in-range", "range": maximum_range, "source": "classic"}))
		return MONSTER_ATTACK_FALLBACK
	var cost_power := range_power
	while cost_power > 0 and monster.spell_points < absi(projectile_spell.cost * cost_power):
		cost_power -= 1
	if cost_power <= 0:
		events.append(DomainEvent.new(&"combat_monster_projectile_skipped", {"actorId": monster.id, "reason": "insufficient-spell-points", "source": "classic"}))
		return MONSTER_ATTACK_FALLBACK
	var spell_cost := absi(projectile_spell.cost * cost_power)
	var target_id := target_ids[rng.draw_between(0, target_ids.size() - 1, StringName("combat.monster-projectile.%s.target" % monster.id))]
	var target := state.party.character_by_id(target_id)
	monster.weapon_id = projectile_item.id
	monster.target_id = target.id
	monster.spell_points -= spell_cost
	active_turn.target_id = target.id
	active_turn.movement_remaining = 0
	active_turn.physical_action_committed = true
	combat.set_guarding(monster.id, false)
	var resolution := _rules.magic.resolve_monster_projectile(monster, projectile_item, target, projectile_spell, 1, rng)
	if resolution == null:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "missile", "reason": "projectile-resolution-failed", "source": "classic"}))
		return MONSTER_ATTACK_COMPLETED
	if resolution.total_damage > 0:
		combat.mark_attacked(target.id)
	events.append(DomainEvent.new(&"combat_projectile_resolved", {
		"actorId": monster.id,
		"targetId": target.id,
		"targetKind": "character",
		"itemId": projectile_item.id,
		"spellId": projectile_spell.id,
		"rangePower": range_power,
		"costPower": cost_power,
		"resolutionPower": 1,
		"range": _rules.battlefield.classic_range(combat.battlefield, monster.id, target.id),
		"hitCount": resolution.hit_count,
		"missCount": resolution.miss_count,
		"damage": resolution.total_damage,
		"defeated": resolution.target_defeated,
		"source": "classic-monster",
	}))
	_mark_character_bleeding(state, target, resolution.target_defeated)
	_remove_defeated_position(combat, target.id, resolution.target_defeated)
	return MONSTER_ATTACK_COMPLETED


func _process_monster_retreat(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var terrain_set := _battle_terrain_set(content, combat.battlefield)
	if terrain_set == null:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": "missing-battle-terrain"}))
		active_turn.movement_remaining = 0
		return MONSTER_ATTACK_COMPLETED
	if not _monster_target_is_available(state, monster, active_turn.target_id):
		# movemonster.c reads pos[-1] when a routed monster has no retained target.
		# Keep that unsafe source path explicit instead of inventing a threat target.
		active_turn.movement_remaining = 0
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": "retreat-target-unresolved"}))
		return MONSTER_ATTACK_COMPLETED
	var operation_guard := 512
	while operation_guard > 0 and active_turn.movement_remaining > 0 and monster.current_health > 0:
		var origin := combat.battlefield.actor_position(monster.id)
		var target_coordinate := combat.battlefield.actor_position(active_turn.target_id)
		var probe := _rules.battlefield.probe_monster_step_away(combat.battlefield, terrain_set, monster.id, target_coordinate, active_turn.movement_remaining, rng)
		if not probe.allowed:
			active_turn.movement_remaining = 0
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": String(probe.reason)}))
			return MONSTER_ATTACK_COMPLETED
		combat.pending_reaction = CombatReactionState.new(CombatReactionState.MONSTER_RETREAT, monster.id, origin, probe.destination, probe.movement_cost)
		combat.pending_reaction.set_origin_hostiles(_hostile_adjacent_ids(state, monster.id))
		combat.pending_reaction.set_phase(CombatReactionState.WITHDRAWAL, _withdrawal_hostiles(state, combat.pending_reaction))
		var reaction_result := _continue_pending_reaction(state, content, rng, events)
		if reaction_result == REACTION_WAITING:
			return MONSTER_ATTACK_WAITING
		if reaction_result == REACTION_DEATH_MACRO:
			return MONSTER_ATTACK_DEATH_MACRO
		if reaction_result == REACTION_MOVER_DEFEATED:
			return MONSTER_ATTACK_COMPLETED
		operation_guard -= 1
	if operation_guard == 0:
		active_turn.movement_remaining = 0
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": "monster-movement-budget-exhausted"}))
	return MONSTER_ATTACK_COMPLETED


func _retreating_monster_reached_edge(state: GameState, content: RealmzContent, monster_id: String, destination: Vector2i, events: Array[DomainEvent]) -> bool:
	if destination.x >= 2 and destination.y >= 2 and destination.x <= 87 and destination.y <= 87:
		return false
	var monster := state.combat.monster_by_id(monster_id)
	var definition := content.monster_by_id(monster.definition_id) if monster != null else null
	if monster == null or definition == null:
		return false
	state.combat.set_guarding(monster.id, false)
	state.combat.active_turn.movement_remaining = 0
	if definition.can_summon < 0:
		# Castle says mandatory allies cannot leave, but flips deltas only after
		# committing the edge step. Stop safely at that observed boundary.
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": "mandatory-ally-edge-retreat-unresolved"}))
		return false
	monster.current_health = 0
	state.combat.battlefield.remove_monster(monster.id)
	events.append(DomainEvent.new(&"combatant_retreated", {"actorId": monster.id, "mode": "battlefield-edge", "forced": true, "source": "classic-monster"}))
	return true


func _resolve_monster_attack_row(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, attack_index: int, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	_prepare_monster_melee_weapon(monster, definition, content)
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
		var attack_weapon := content.item_by_id(monster.weapon_id) if not monster.weapon_id.is_empty() else null
		var defender_armor := defender_equipment.effective_armor if defender_equipment.valid else character_target.armor
		var monster_attack_context := MonsterAttackContext.new(attack_weapon, state.clock.day(), false, defender_luck, state.party.conditions.is_active(ConditionRules.PARTY_DRAGON_HIDE), defender_armor)
		var monster_resolution := _rules.combat.resolve_monster_attack(monster, definition, attack_index, character_target, race, caste, rng, charm_bonus, monster_attack_context, true)
		if monster_resolution.total_damage() > 0:
			combat.mark_attacked(character_target.id)
		if monster_resolution.fumbled:
			_commit_monster_fumble(monster, events)
		var age_update_requested := false
		if monster_resolution.special_handled:
			_append_monster_special_events(events, monster.id, character_target.id, &"character", monster_resolution)
			if monster_resolution.aging != null and monster_resolution.aging.changed_group():
				events.append(DomainEvent.new(&"character_age_changed", monster_resolution.aging.event_payload(character_target, race)))
				age_update_requested = true
		if age_update_requested:
			combat.pending_monster_attack = PendingMonsterAttack.new(monster.id, character_target.id, active_turn.action, monster_resolution.damage, monster_resolution.chance, monster_resolution.roll, monster_resolution.weapon_condition_index, monster_resolution.weapon_condition_before, monster_resolution.weapon_condition_after, monster_resolution.physical_feedback_sound_id)
			return MONSTER_ATTACK_WAITING
		_append_monster_physical_feedback(events, monster_resolution.physical_feedback_sound_id)
		_append_monster_attack_audio(events, monster, definition, attack_index, attack_weapon, monster_resolution, rng)
		var character_attack_event := DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": character_target.id, "action": String(active_turn.action), "attackIndex": attack_index, "hit": monster_resolution.hit, "damage": monster_resolution.total_damage(), "defeated": monster_resolution.killed, "chance": monster_resolution.chance, "roll": monster_resolution.roll})
		_append_physical_result_effect(character_attack_event, monster_resolution.hit, attack_weapon != null)
		events.append(character_attack_event)
		_mark_character_bleeding(state, character_target, monster_resolution.killed)
		_remove_defeated_position(combat, character_target.id, monster_resolution.killed)
		if monster_resolution.killed:
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
	if resolution.total_damage() > 0:
		combat.mark_attacked(monster_target.id)
	if resolution.fumbled:
		_commit_monster_fumble(monster, events)
	if resolution.special_handled:
		_append_monster_special_events(events, monster.id, monster_target.id, &"monster", resolution)
	_append_monster_attack_audio(events, monster, definition, attack_index, weapon, resolution, rng)
	var monster_attack_event := DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": monster_target.id, "action": String(active_turn.action), "attackIndex": attack_index, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll})
	_append_physical_result_effect(monster_attack_event, resolution.hit, weapon != null)
	events.append(monster_attack_event)
	if resolution.killed:
		active_turn.target_id = ""
		monster.target_id = ""
		var death_macro_requested := _request_monster_death_macro(monster_target, target_definition, events)
		_remove_defeated_position(combat, monster_target.id, not death_macro_requested)
		if death_macro_requested:
			if active_turn.attack_index >= _monster_attack_limit(definition):
				_advance_turn(state, rng, events)
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


func _monster_projectile_target_ids(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition, maximum_range: int) -> Array[String]:
	var candidates: Array[String] = []
	for character: CharacterState in state.party.characters():
		if _monster_target_is_available(state, monster, character.id) and _rules.battlefield.projectile_target_is_valid(state.combat.battlefield, terrain_set, monster.id, character.id, maximum_range, true):
			candidates.append(character.id)
	# Hostile monsters normally target party slots. Castle's monster-on-monster
	# projectile formula reads the stale global player missile statistic, so that
	# ally/traitor branch remains explicitly disabled pending an oracle decision.
	return candidates


func _prepare_monster_melee_weapon(monster: MonsterState, definition: MonsterDefinition, content: RealmzContent) -> void:
	if monster == null or definition == null or content == null or monster.weapon_id.is_empty():
		return
	var active_item := content.item_by_id(monster.weapon_id)
	var active_spell := content.spell_by_classic_id(absi(active_item.special_2)) if active_item != null and active_item.special_2 != 0 else null
	if active_spell == null or active_spell.damage_type != 9:
		return
	# attack2 writes this replacement through Castle's global monsterup instead
	# of its mon argument. Apply the intended slot-0 replacement to the actual
	# attacker so reactions cannot mutate an unrelated monster.
	monster.weapon_id = definition.item_id_at(0)


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
		var character_resolution := _rules.combat.resolve_character_attack_character(actor, equipment, character_target, target_equipment, rng, false, true, state.combat.can_queue_fumbled_item())
		if character_resolution.total_damage() > 0:
			state.combat.mark_attacked(character_target.id)
		if character_resolution.fumbled and not _commit_character_fumble(state, actor, equipment, events):
			events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": actor.id, "reason": "invalid-fumble-state"}))
			return false
		var character_event := _character_attack_event(actor.id, character_target.id, &"character", character_resolution, equipment.melee_weapon != null)
		_append_character_attack_audio(events, actor, equipment, character_resolution, &"character")
		character_event.payload["automatic"] = true
		events.append(character_event)
		_mark_character_bleeding(state, character_target, character_resolution.killed)
		_remove_defeated_position(state.combat, character_target.id, character_resolution.killed)
		return false
	var monster_target := monster_targets[target_index - character_targets.size()]
	var target_definition := content.monster_by_id(monster_target.definition_id)
	active_turn.physical_action_committed = true
	var resolution := _rules.combat.resolve_character_attack(actor, equipment, monster_target, target_definition, rng, state.clock.day(), false, true, state.combat.can_queue_fumbled_item())
	if resolution.total_damage() > 0:
		state.combat.mark_attacked(monster_target.id)
	if resolution.fumbled and not _commit_character_fumble(state, actor, equipment, events):
		events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": actor.id, "reason": "invalid-fumble-state"}))
		return false
	var event := _character_attack_event(actor.id, monster_target.id, &"monster", resolution, equipment.melee_weapon != null)
	_append_character_attack_audio(events, actor, equipment, resolution, &"monster")
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


func _hostile_contact_target_id(state: GameState, actor_id: String, destination_or_target: Variant) -> String:
	if state == null or state.combat == null or state.combat.battlefield == null:
		return ""
	var candidate_id := ""
	if destination_or_target is String:
		candidate_id = destination_or_target
	elif destination_or_target is Vector2i:
		candidate_id = state.combat.battlefield.actor_at(destination_or_target, actor_id)
	if candidate_id.is_empty():
		return ""
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0:
		return ""
	var monster := state.combat.monster_by_id(candidate_id)
	if monster != null:
		return candidate_id if monster.current_health > 0 and monster.traitor != actor.traitor else ""
	var character := state.party.character_by_id(candidate_id)
	return candidate_id if character != null and character.current_health > 0 and character.traitor != actor.traitor else ""


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


static func _character_attack_event(actor_id: String, target_id: String, target_kind: StringName, resolution: AttackResolution, armed: bool) -> DomainEvent:
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
	_append_physical_result_effect(event, resolution.hit, armed)
	return event


static func _append_physical_result_effect(event: DomainEvent, hit: bool, armed: bool) -> void:
	if event == null or not hit:
		return
	event.payload["classicResultEffectResourceId"] = 160 if armed else 161


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
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": true, "source": "classic-party-dragon-hide"}))


static func _append_character_attack_audio(events: Array[DomainEvent], attacker: CharacterState, equipment: CharacterCombatEquipment, resolution: AttackResolution, target_kind: StringName) -> void:
	if attacker == null or equipment == null or resolution == null:
		return
	if resolution.blocked:
		_append_attack_sound(events, _weapon_requirement_sound(resolution.block_reason))
		return
	if not resolution.hit:
		_append_attack_sound(events, 650)
		return
	var sound_id := 600 + (equipment.melee_weapon.sound_id if equipment.melee_weapon != null else 30 + attacker.gender * 8)
	if resolution.killed and target_kind == &"character":
		_append_attack_sound(events, 132)
	_append_attack_sound(events, sound_id)
	if resolution.killed and target_kind != &"character":
		_append_attack_sound(events, 132)


static func _append_monster_attack_audio(events: Array[DomainEvent], attacker: MonsterState, definition: MonsterDefinition, attack_index: int, weapon: ItemDefinition, resolution: AttackResolution, rng: RealmzRng) -> void:
	if attacker == null or definition == null or resolution == null or rng == null:
		return
	if resolution.blocked:
		_append_attack_sound(events, _weapon_requirement_sound(resolution.block_reason))
		return
	if not resolution.hit:
		_append_attack_sound(events, 650)
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
	_append_attack_sound(events, sound_id)
	if resolution.killed:
		_append_attack_sound(events, 132)


static func _weapon_requirement_sound(reason: StringName) -> int:
	match reason:
		&"classic_blunt_weapon_required":
			return 621
		&"classic_sharp_weapon_required":
			return 639
		&"classic_magic_weapon_required", &"classic_specific_weapon_required":
			return 698
	return 0


static func _append_attack_sound(events: Array[DomainEvent], native_sound_id: int) -> void:
	if native_sound_id == 0:
		return
	events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(native_sound_id), "waitForCompletion": native_sound_id < 0, "source": "classic-combat-attack"}))


func _request_monster_death_macro(monster: MonsterState, definition: MonsterDefinition, events: Array[DomainEvent]) -> bool:
	if monster == null or definition == null or definition.death_macro <= 0:
		return false
	_append_monster_death_macro_request(monster, definition, events, false)
	return true


func _queue_spell_death_macro(combat: CombatState, monster: MonsterState, definition: MonsterDefinition) -> bool:
	return combat != null and monster != null and definition != null and definition.death_macro > 0 and combat.queue_spell_death_macro(monster.id)


func _request_next_spell_death_macro(combat: CombatState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	var combatant_id := combat.pending_spell_death_macro_id() if combat != null else ""
	var monster := combat.monster_by_id(combatant_id) if combat != null else null
	var definition := content.monster_by_id(monster.definition_id) if monster != null and content != null else null
	if monster == null or definition == null or definition.death_macro <= 0:
		return false
	_append_monster_death_macro_request(monster, definition, events, true)
	return true


static func _append_monster_death_macro_request(monster: MonsterState, definition: MonsterDefinition, events: Array[DomainEvent], queued_by_spell: bool) -> void:
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


func _finish_if_resolved(state: GameState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	state.prune_combat_auto_characters()
	var combat := state.combat
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
