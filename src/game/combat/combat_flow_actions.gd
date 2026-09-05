## Implements deterministic combat flow actions rules without presentation dependencies.

class_name CombatFlowActions
extends RefCounted

## Resolves direct character combat commands and their deterministic turn effects.


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
var _context: CombatContext
var _events: CombatActionEvents


func _init(context: CombatContext) -> void:
	_context = context
	_events = CombatActionEvents.new(context)


func events() -> CombatActionEvents:
	return _events

func submit_action(state: GameState, content: RealmzContent, actor_id: String, action: StringName, target_id: String, rng: RealmzRng, allow_friendly_contact: bool = false) -> CombatFlowResult:
	var combat := state.combat
	if combat == null or combat.completed:
		return CombatFlowResult.failed(&"no_active_battle", "No Realmz battle is accepting combat actions.")
	if combat.turns.active_actor_id() != actor_id:
		return CombatFlowResult.failed(&"wrong_combat_actor", "Combat action actor '%s' does not own the current turn." % actor_id)
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0 or actor.traitor or combat.battlefield == null or not combat.battlefield.actors.has_actor(actor.id):
		return CombatFlowResult.failed(&"invalid_combat_actor", "The current combat actor is unavailable.")
	if action == &"auto":
		return _submit_auto(state, content, actor, rng)
	if action == &"retreat":
		return _context.reactions().retreat_character(state, content, actor_id, &"explicit", INVALID_COORDINATE, rng)
	var action_result := _submit_standard_action(state, content, actor, action, target_id, rng, allow_friendly_contact)
	if not action_result.ok or _action_waits_for_continuation(combat, action, action_result.events):
		return action_result
	var events := action_result.events
	if _context.rounds().finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_context.automation().process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func _submit_standard_action(state: GameState, content: RealmzContent, actor: CharacterState, action: StringName, target_id: String, rng: RealmzRng, allow_friendly_contact: bool) -> CombatFlowResult:
	match action:
		&"attack":
			return _submit_character_attack(state, content, actor, target_id, rng, allow_friendly_contact)
		&"switch_weapon":
			return _switch_character_weapon(state.combat, content, actor)
		&"defend":
			return _submit_guard(state, content, actor, rng)
		&"delay":
			return _submit_delay(state, content, actor, rng)
		&"bandage":
			return _submit_bandage(state, content, actor, target_id, rng)
		&"turn_undead":
			return turn_undead(state, content, actor, rng)
		&"undo":
			return _submit_undo(state, actor)
		&"finish", &"pass":
			return _submit_pass(state, content, actor, action, rng)
		_:
			return CombatFlowResult.failed(&"unknown_combat_action", "Combat action '%s' is not available." % action)


func _submit_guard(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> CombatFlowResult:
	prepare_character_turn(state.combat, actor)
	var guard_roll := rng.draw(100, &"combat.guard-sound")
	var guard_sound := 10121 if guard_roll < 50 else 10123
	state.combat.actor_statuses.set_guarding(actor.id, true)
	var events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": guard_sound, "waitForCompletion": false, "source": "classic-combat-guard"}), DomainEvent.new(&"combatant_guarded", {"actorId": actor.id, "roll": guard_roll, "soundId": guard_sound, "source": "classic"})]
	_context.rounds().advance_turn(state, content, rng, events)
	return CombatFlowResult.succeeded(events)


func _submit_delay(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> CombatFlowResult:
	var probe := probe_delay(state, actor.id)
	if not probe.allowed:
		return CombatFlowResult.failed(&"combat_delay_unavailable", probe.reason_text)
	prepare_character_turn(state.combat, actor)
	actor.attacks_remaining = _context.arithmetic.signed_16(actor.attacks_remaining - actor.normal_attacks - actor.attack_bonus)
	var round_advanced := state.combat.delay_active_actor()
	var events: Array[DomainEvent] = []
	if round_advanced:
		_context.rounds().process_bleeding_round(state, rng, events)
	events.append(DomainEvent.new(&"combat_turn_delayed", {"actorId": actor.id, "roundAdvanced": round_advanced, "source": "classic-corrected", "fidelityDecision": "FD-COMBAT-012"}))
	return CombatFlowResult.succeeded(events)


func _submit_bandage(state: GameState, content: RealmzContent, actor: CharacterState, target_id: String, rng: RealmzRng) -> CombatFlowResult:
	var probe := probe_bandage(state, actor.id, target_id)
	if not probe.allowed:
		return CombatFlowResult.failed(&"combat_bandage_unavailable", probe.reason_text)
	prepare_character_turn(state.combat, actor)
	if not state.combat.actor_statuses.set_character_bleeding(target_id, false):
		return CombatFlowResult.failed(&"invalid_bandage_target", "The selected bleeding state could not be cleared.")
	actor.attacks_remaining = 0
	actor.movement = 0
	var events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 10105, "waitForCompletion": false, "source": "classic-combat-bandage"})]
	if _context.processing_auto:
		var bandage_roll := rng.draw(100, StringName("combat.auto.%s.bandage-sound" % actor.id))
		var bandage_sound := 10121 if bandage_roll < 50 else 10123
		events.append(DomainEvent.new(&"sound_requested", {"soundId": bandage_sound, "waitForCompletion": false, "source": "classic-combat-auto-bandage"}))
	events.append(DomainEvent.new(&"combatant_bandaged", {"actorId": actor.id, "targetId": target_id, "source": "classic-corrected", "fidelityDecision": "FD-COMBAT-013"}))
	_context.rounds().advance_turn(state, content, rng, events)
	return CombatFlowResult.succeeded(events)


func _submit_undo(state: GameState, actor: CharacterState) -> CombatFlowResult:
	var probe := probe_undo(state, actor.id)
	if not probe.allowed:
		return CombatFlowResult.failed(&"combat_undo_unavailable", probe.reason_text)
	var combat := state.combat
	var from_position := combat.battlefield.actors.actor_position(actor.id)
	var start_position := combat.turns.undo_state.start_position
	if from_position != start_position and not combat.battlefield.actors.move_actor(actor.id, start_position):
		return CombatFlowResult.failed(&"combat_undo_position_blocked", "The activation-start position is no longer available.")
	actor.attacks_remaining = _context.arithmetic.signed_16(actor.attacks_remaining - actor.normal_attacks - actor.attack_bonus)
	combat.turns.restart_active_turn_after_undo()
	prepare_character_turn(combat, actor)
	var events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 664, "waitForCompletion": false, "source": "classic-combat-undo"})]
	if not actor.conditions.is_active(ConditionRules.ANIMATED):
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 138, "waitForCompletion": false, "source": "classic-combat-activation"}))
	events.append(DomainEvent.new(&"combat_turn_undone", {"actorId": actor.id, "from": [from_position.x, from_position.y], "to": [start_position.x, start_position.y], "attacksRemaining": actor.attacks_remaining, "movementRemaining": actor.movement, "source": "classic"}))
	return CombatFlowResult.succeeded(events)


func _submit_pass(state: GameState, content: RealmzContent, actor: CharacterState, action: StringName, rng: RealmzRng) -> CombatFlowResult:
	prepare_character_turn(state.combat, actor)
	actor.movement = 0
	state.combat.actor_statuses.set_guarding(actor.id, false)
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_turn_passed", {"actorId": actor.id, "action": String(action)})]
	_context.rounds().advance_turn(state, content, rng, events)
	return CombatFlowResult.succeeded(events)


func _submit_auto(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> CombatFlowResult:
	var result: CombatFlowResult = _context.automation().run_auto_activation_chain(state, content, actor.id, rng)
	if result.ok:
		result.events.push_front(DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-combat-auto-button"}))
	return result


func _action_waits_for_continuation(combat: CombatState, action: StringName, events: Array[DomainEvent]) -> bool:
	return action == &"attack" and _events_include(events, &"monster_death_macro_requested") or action == &"turn_undead" and not combat.spell_runtime.pending_death_macro_id().is_empty()


func _switch_character_weapon(combat: CombatState, content: RealmzContent, actor: CharacterState) -> CombatFlowResult:
	var equipment := _context.equipment.combat_equipment(actor, content.items.definitions())
	if not equipment.valid:
		return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
	var current_mode := combat.actor_statuses.character_weapon_mode(actor.id)
	var next_mode: StringName = &"melee" if current_mode == &"missile" else &"missile"
	if next_mode == &"missile" and equipment.missile_weapon == null:
		return CombatFlowResult.failed(&"missile_weapon_unavailable", "The active character has no equipped Classic type-15 missile weapon.")
	prepare_character_turn(combat, actor)
	if not combat.actor_statuses.set_character_weapon_mode(actor.id, next_mode):
		return CombatFlowResult.failed(&"invalid_weapon_mode", "The active character's battle weapon mode could not be changed.")
	return CombatFlowResult.succeeded([DomainEvent.new(&"combat_weapon_mode_changed", {"actorId": actor.id, "mode": String(next_mode)})])


func _submit_character_attack(state: GameState, content: RealmzContent, actor: CharacterState, target_id: String, rng: RealmzRng, allow_friendly_contact: bool = false) -> CombatFlowResult:
	var combat := state.combat
	var events: Array[DomainEvent] = []
	var equipment := _context.equipment.combat_equipment(actor, content.items.definitions())
	if not equipment.valid: return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
	if combat.actor_statuses.character_weapon_mode(actor.id) == &"missile": return fire_character_projectile(state, content, actor, equipment, target_id, rng)
	if combat.battlefield == null: return CombatFlowResult.failed(&"missing_battlefield", "Melee requires the session-owned Classic battlefield.")
	if not _context.battlefield.are_adjacent(combat.battlefield, actor.id, target_id): return CombatFlowResult.failed(&"combat_target_not_adjacent", "Classic melee can target only an enemy in an adjacent battlefield footprint.")
	var monster_target := combat.roster.monster_by_id(target_id)
	if monster_target != null and monster_target.current_health > 0 and (monster_target.traitor != actor.traitor or allow_friendly_contact):
		var definition := content.combat.monster_by_id(monster_target.definition_id)
		if definition == null: return CombatFlowResult.failed(&"unknown_monster_definition", "The selected monster has no immutable definition.")
		prepare_character_turn(combat, actor)
		combat.turns.invalidate_undo()
		combat.turns.active_turn.physical_action_committed = true
		var resolution := _context.combat.resolve_character_attack(actor, equipment, monster_target, definition, rng, state.clock.day(), false, true, combat.dropped_items.can_queue())
		if resolution.total_damage() > 0: combat.actor_statuses.mark_attacked(monster_target.id)
		if resolution.fumbled and not _events.commit_character_fumble(state, actor, equipment, events): return CombatFlowResult.failed(&"invalid_fumble_state", "The fumbled melee weapon could not enter the battle recovery queue.")
		_events.append_character_attack_audio(events, actor, equipment, resolution, &"monster")
		events.append(_events.character_attack_event(actor.id, monster_target.id, &"monster", resolution, equipment.melee_weapon != null))
		var macro_requested := resolution.killed and _events.request_monster_death_macro(monster_target, definition, events)
		_context.automation().remove_defeated_position(combat, monster_target.id, resolution.killed and not macro_requested)
	else:
		var character_target := state.party.character_by_id(target_id)
		if character_target == null or character_target.id == actor.id or character_target.current_health <= 0 or (character_target.traitor == actor.traitor and not allow_friendly_contact): return CombatFlowResult.failed(&"invalid_combat_target", "The selected combatant is unavailable to this allegiance.")
		var target_equipment := _context.equipment.combat_equipment(character_target, content.items.definitions())
		if not target_equipment.valid: return CombatFlowResult.failed(target_equipment.error_code, target_equipment.error_message)
		prepare_character_turn(combat, actor)
		combat.turns.invalidate_undo()
		combat.turns.active_turn.physical_action_committed = true
		var resolution := _context.combat.resolve_character_attack_character(actor, equipment, character_target, target_equipment, rng, false, true, combat.dropped_items.can_queue())
		if resolution.total_damage() > 0: combat.actor_statuses.mark_attacked(character_target.id)
		if resolution.fumbled and not _events.commit_character_fumble(state, actor, equipment, events): return CombatFlowResult.failed(&"invalid_fumble_state", "The fumbled melee weapon could not enter the battle recovery queue.")
		_events.append_character_attack_audio(events, actor, equipment, resolution, &"character")
		events.append(_events.character_attack_event(actor.id, character_target.id, &"character", resolution, equipment.melee_weapon != null))
		mark_character_bleeding(state, character_target, resolution.killed)
		_context.automation().remove_defeated_position(combat, character_target.id, resolution.killed)
	consume_character_attack(actor)
	if not character_can_continue(actor): _context.rounds().advance_turn(state, content, rng, events)
	return CombatFlowResult.succeeded(events)


func probe_delay(state: GameState, actor_id: String) -> CombatCommandProbe:
	var actor := state.party.character_by_id(actor_id) if state != null else null
	var combat := state.combat if state != null else null
	if actor == null or combat == null or combat.completed or combat.turns.active_actor_id() != actor_id or actor.current_health <= 0 or actor.traitor:
		return CombatCommandProbe.new(false, "Only the active loyal character can Delay.")
	if not is_fresh_character_activation(combat, actor):
		return CombatCommandProbe.new(false, "Delay is available only before moving, attacking, or casting this activation.")
	return CombatCommandProbe.new(true)


func probe_undo(state: GameState, actor_id: String) -> CombatCommandProbe:
	var actor := state.party.character_by_id(actor_id) if state != null else null
	var combat := state.combat if state != null else null
	if actor == null or combat == null or combat.completed or combat.turns.active_actor_id() != actor_id or actor.current_health <= 0:
		return CombatCommandProbe.new(false, "Only the active living character can Undo.")
	if actor.traitor or actor.conditions.is_active(ConditionRules.HELPLESS) or actor.conditions.is_active(ConditionRules.CONFUSED):
		return CombatCommandProbe.new(false, "This character's current combat state prevents Undo.")
	if combat.pending_reaction != null or combat.pending_monster_attack != null:
		return CombatCommandProbe.new(false, "Resolve the current combat result before using Undo.")
	var undo := combat.turns.undo_state
	if combat.turns.active_turn == null or undo == null or not undo.available or undo.actor_id != actor_id or undo.round_number != combat.turns.round_number or undo.turn_index != combat.turns.turn_index:
		return CombatCommandProbe.new(false, "Undo is unavailable after a combat result.")
	if combat.battlefield == null or not combat.battlefield.actors.has_actor(actor_id):
		return CombatCommandProbe.new(false, "The active character has no battlefield position to restore.")
	var occupant := combat.battlefield.actors.actor_at(undo.start_position, actor_id)
	if not occupant.is_empty():
		return CombatCommandProbe.new(false, "The activation-start position is occupied.")
	return CombatCommandProbe.new(true)


func bandage_candidate_ids(state: GameState) -> Array[String]:
	var result: Array[String] = []
	if state == null or state.combat == null:
		return result
	for character: CharacterState in state.party.characters():
		if state.combat.actor_statuses.is_character_bleeding(character.id) and character.current_health > -10:
			result.append(character.id)
	return result


func probe_bandage(state: GameState, actor_id: String, target_id: String = "") -> CombatCommandProbe:
	var actor := state.party.character_by_id(actor_id) if state != null else null
	var combat := state.combat if state != null else null
	if actor == null or combat == null or combat.completed or combat.turns.active_actor_id() != actor_id or actor.current_health <= 0 or actor.traitor:
		return CombatCommandProbe.new(false, "Only the active loyal character can Bandage.")
	if not is_fresh_character_activation(combat, actor):
		return CombatCommandProbe.new(false, "Bandage is available only before moving, attacking, or casting this activation.")
	var candidates := bandage_candidate_ids(state)
	if candidates.is_empty():
		return CombatCommandProbe.new(false, "No party member is bleeding.")
	if not target_id.is_empty() and not candidates.has(target_id):
		return CombatCommandProbe.new(false, "The selected party member is not a legal bleeding recipient.")
	return CombatCommandProbe.new(true)


func turn_undead_target_ids(state: GameState, content: RealmzContent) -> Array[String]:
	var result: Array[String] = []
	if state == null or state.combat == null or content == null or state.combat.battlefield == null:
		return result
	for monster: MonsterState in state.combat.roster.monsters():
		var definition := content.combat.monster_by_id(monster.definition_id)
		# Providence normalizes Castle's unsigned byte sentinel 255 to signed -1.
		if monster.current_health > 0 and monster.traitor and state.combat.battlefield.actors.has_actor(monster.id) and definition != null and definition.can_summon != -1 and (definition.type_flag(1) or definition.type_flag(2)):
			result.append(monster.id)
	return result


func probe_turn_undead(state: GameState, content: RealmzContent, actor_id: String) -> CombatCommandProbe:
	var actor := state.party.character_by_id(actor_id) if state != null else null
	var combat := state.combat if state != null else null
	if actor == null or combat == null or combat.completed or combat.turns.active_actor_id() != actor_id or actor.current_health <= 0 or actor.traitor:
		return CombatCommandProbe.new(false, "Only the active loyal character can Turn Undead.")
	if not state.priest_turning_allowed:
		return CombatCommandProbe.new(false, "This campaign location forbids priest turning.")
	if actor.ability_value(13) <= 0:
		return CombatCommandProbe.new(false, "This character has no Turn Undead ability.")
	if combat.actor_statuses.has_used_turn_undead(actor.id):
		return CombatCommandProbe.new(false, "This character has already attempted Turn Undead in this battle.")
	if combat.turns.active_turn != null and actor.attacks_remaining < 2:
		return CombatCommandProbe.new(false, "Turn Undead requires one remaining attack.")
	if turn_undead_target_ids(state, content).is_empty():
		return CombatCommandProbe.new(false, "No hostile undead or nether spawn can be turned.")
	return CombatCommandProbe.new(true)


func turn_undead(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> CombatFlowResult:
	prepare_character_turn(state.combat, actor)
	var probe := probe_turn_undead(state, content, actor.id)
	if not probe.allowed:
		return CombatFlowResult.failed(&"combat_turn_undead_unavailable", probe.reason_text)
	var combat := state.combat
	combat.turns.invalidate_undo()
	var target_ids := turn_undead_target_ids(state, content)
	var macro_count := _turn_undead_macro_count(combat, content, target_ids)
	if macro_count > CombatSpellRuntimeState.MAX_DEATH_MACROS - combat.spell_runtime.death_macro_queue().size():
		return CombatFlowResult.failed(&"combat_turn_undead_macro_limit", "Turn Undead would exceed the bounded death-macro queue.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 659, "waitForCompletion": false, "source": "classic-combat-turn-undead"})]
	combat.actor_statuses.mark_turn_undead_used(actor.id)
	events.append(DomainEvent.new(&"combat_turn_undead_attempted", {"actorId": actor.id, "ability": actor.ability_value(13), "targetIds": target_ids.duplicate(), "source": "classic"}))
	for target_id: String in target_ids:
		_resolve_turn_undead_target(combat, content, actor, target_id, rng, events)
	actor.attacks_remaining = _context.arithmetic.signed_16(actor.attacks_remaining - 2)
	return _finish_turn_undead(state, content, actor, rng, events)


func _turn_undead_macro_count(combat: CombatState, content: RealmzContent, target_ids: Array[String]) -> int:
	var result := 0
	for target_id: String in target_ids:
		var target := combat.roster.monster_by_id(target_id)
		var definition := content.combat.monster_by_id(target.definition_id) if target != null else null
		if definition != null and definition.death_macro > 0:
			result += 1
	return result


func _resolve_turn_undead_target(combat: CombatState, content: RealmzContent, actor: CharacterState, target_id: String, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var target := combat.roster.monster_by_id(target_id)
	var definition := content.combat.monster_by_id(target.definition_id)
	var threshold := maxi(25, 100 - actor.ability_value(13) + 5 * target.hit_dice) + target.magic_resistance
	var roll := rng.draw(100, StringName("combat.turn-undead.%s" % target.id))
	var margin := roll - threshold
	var result_kind := "resisted"
	var experience_award := 0
	if margin > 0 and margin < 30:
		result_kind = "destroyed"
		actor.lifetime_record.record_turn_undead(true)
		experience_award = 25 * target.hit_dice
		target.current_health = 0
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 132, "waitForCompletion": false, "source": "classic-combat-turn-undead"}))
		if not _events.queue_spell_death_macro(combat, target, definition):
			_context.automation().remove_defeated_position(combat, target.id, true)
	elif margin >= 30:
		result_kind = "turned"
		actor.lifetime_record.record_turn_undead(false)
		experience_award = 50 * target.hit_dice
		target.traitor = actor.traitor
		target.target_id = ""
		combat.actor_statuses.set_guarding(target.id, false)
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 630, "waitForCompletion": false, "source": "classic-combat-turn-undead"}))
	actor.experience = _context.arithmetic.signed_32(actor.experience + experience_award)
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


func _finish_turn_undead(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> CombatFlowResult:
	var combat := state.combat
	var advances_turn := not character_can_continue(actor)
	if not combat.spell_runtime.pending_death_macro_id().is_empty():
		if not combat.spell_runtime.begin_death_macro_sequence(actor.id, advances_turn) or not _events.request_next_spell_death_macro(combat, content, events):
			return CombatFlowResult.failed(&"invalid_turn_undead_macro_queue", "Turn Undead could not begin its source-ordered death-macro continuation.")
		return CombatFlowResult.succeeded(events)
	if advances_turn:
		_context.rounds().advance_turn(state, content, rng, events)
	return CombatFlowResult.succeeded(events)


static func is_fresh_character_activation(combat: CombatState, actor: CharacterState) -> bool:
	return combat.turns.active_turn == null or (actor.movement == actor.maximum_movement and not combat.turns.active_turn.physical_action_committed and combat.turns.active_turn.spell_cast_count == 0)


static func mark_character_bleeding(state: GameState, character: CharacterState, defeated: bool) -> void:
	if not defeated or state == null or state.combat == null or character == null:
		return
	# killbody.c clears doauto as soon as a party combatant is removed from the
	# battle, even when the body remains recoverable above -10 health.
	state.set_combat_auto(character.id, false)
	if character.current_health > -10:
		character.lifetime_record.record_knockout()
		state.combat.actor_statuses.set_character_bleeding(character.id, true)
	else:
		character.lifetime_record.record_death()


func cause_active_fumble(state: GameState, content: RealmzContent, actor_id: String) -> CombatFlowResult:
	if state == null or content == null or state.combat == null or state.combat.completed:
		return CombatFlowResult.failed(&"no_active_battle", "No Realmz battle can receive a fumble operation.")
	if actor_id.is_empty():
		actor_id = state.combat.turns.active_actor_id()
	if actor_id != state.combat.turns.active_actor_id():
		return CombatFlowResult.failed(&"invalid_fumble_actor", "Classic opcode 122 can affect only the active physical combatant.")
	if state.combat.turns.active_turn == null or not state.combat.turns.active_turn.physical_action_committed:
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_fumble_skipped", {"combatantId": actor_id, "reason": "no-physical-action", "source": "classic"})])
	var events: Array[DomainEvent] = []
	var character := state.party.character_by_id(actor_id)
	# Castle's outer q[up] < 10 guard excludes monster initiative IDs (10+).
	# The monster branch nested below that guard is therefore unreachable.
	if character == null:
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_fumble_skipped", {"combatantId": actor_id, "reason": "not-party-actor", "source": "classic"})])
	var equipment := _context.equipment.combat_equipment(character, content.items.definitions())
	if not equipment.valid:
		return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
	if not equipment.is_armed():
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_fumble_skipped", {"combatantId": actor_id, "reason": "unarmed", "source": "classic"})])
	if not equipment.melee_weapon.cursed_item_id.is_empty():
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_fumble_skipped", {"combatantId": actor_id, "reason": "cursed-weapon", "source": "classic"})])
	if not state.combat.dropped_items.can_queue():
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_fumble_skipped", {"combatantId": actor_id, "reason": "queue-full", "source": "classic"})])
	if not _events.commit_character_fumble(state, character, equipment, events):
		return CombatFlowResult.failed(&"invalid_fumble_state", "The active character's melee weapon could not enter the recovery queue.")
	return CombatFlowResult.succeeded(events)


func fire_character_projectile(state: GameState, content: RealmzContent, actor: CharacterState, equipment: CharacterCombatEquipment, target_id: String, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	var profile = _context.reactions().character_projectile_profile(actor, content, equipment)
	if not profile.available:
		return CombatFlowResult.failed(profile.error_code, profile.error_message)
	var target := combat.roster.monster_by_id(target_id)
	if target == null or target.current_health <= 0 or target.traitor == actor.traitor:
		return CombatFlowResult.failed(&"invalid_projectile_target", "This source-backed projectile slice can target only a living hostile monster.")
	if not _context.reactions().projectile_target_is_valid(combat, content, actor.id, target.id, profile.maximum_range, profile.spell.range_min + profile.spell.range_max > 0):
		return CombatFlowResult.failed(&"projectile_target_unavailable", "The target is outside the Classic projectile range or line of sight.")
	var definition := content.combat.monster_by_id(target.definition_id)
	var caste := content.characters.caste_by_id(actor.caste_id)
	if definition == null or caste == null:
		return CombatFlowResult.failed(&"projectile_target_unavailable", "Projectile resolution requires the target monster and caster caste definitions.")
	prepare_character_turn(combat, actor)
	if not _context.inventory.use_charge(actor, profile.item_instance_id, profile.item):
		return CombatFlowResult.failed(&"projectile_charge_unavailable", "The selected projectile charge could not be consumed atomically.")
	combat.turns.invalidate_undo()
	var resolution := _context.magic.resolve_character_projectile(actor, caste, profile.item, target, profile.spell, profile.power_level, rng)
	if resolution == null:
		return CombatFlowResult.failed(&"unsupported_projectile_spell", "The selected projectile cannot be resolved by the source-backed missile rules.")
	actor.lifetime_record.add_projectile_damage_given(resolution.total_damage, resolution.hit_count, resolution.miss_count, resolution.target_defeated)
	if resolution.total_damage > 0:
		combat.actor_statuses.mark_attacked(target.id)
	combat.turns.active_turn.physical_action_committed = true
	actor.attacks_remaining = _context.arithmetic.signed_16(actor.attacks_remaining - 2)
	actor.movement = maxi(0, actor.movement - 12)
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_projectile_resolved", {
		"actorId": actor.id,
		"targetId": target.id,
		"targetKind": "monster",
		"itemId": profile.item.id,
		"spellId": profile.spell.id,
		"powerLevel": profile.power_level,
		"range": _context.battlefield.classic_range(combat.battlefield, actor.id, target.id),
		"hitCount": resolution.hit_count,
		"missCount": resolution.miss_count,
		"damage": resolution.total_damage,
		"defeated": resolution.target_defeated,
		"source": "classic",
	})]
	var death_macro_requested := resolution.target_defeated and _events.request_monster_death_macro(target, definition, events)
	_context.automation().remove_defeated_position(combat, target.id, resolution.target_defeated and not death_macro_requested)
	if not character_can_continue(actor):
		_context.rounds().advance_turn(state, content, rng, events)
	if death_macro_requested:
		return CombatFlowResult.succeeded(events)
	if _context.rounds().finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_context.automation().process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


static func projectile_spell_unavailable_reason(spell: SpellDefinition) -> String:
	if spell.target_type != 1:
		return "Classic projectile spell '%s' does not use a single-target picker." % spell.id
	if absi(spell.spell_class) != 9:
		return "Classic projectile spell '%s' is not missile class 9." % spell.id
	if absi(spell.damage_type) != 9:
		return "Elemental projectile spell '%s' requires its source-backed save and special-effect path." % spell.id
	if spell.special != 0:
		return "Projectile spell '%s' uses unresolved Classic special %d." % [spell.id, spell.special]
	return ""


func prepare_character_turn(combat: CombatState, character: CharacterState) -> void:
	if combat.turns.active_turn != null:
		return
	combat.turns.begin_active_turn()
	combat.turns.begin_character_undo(character.id, combat.battlefield)
	var movement := character.maximum_movement
	var tangled := character.conditions.value(ConditionRules.TANGLED)
	if tangled > 0:
		movement -= tangled
	if character.conditions.is_active(ConditionRules.SLOW):
		movement /= 2
	var helpless := character.conditions.is_active(ConditionRules.HELPLESS)
	if helpless:
		movement = 0
	character.movement = maxi(0, movement)
	var carried_half_attack := 1 if character.attacks_remaining > 0 else 0
	var haste_half_attacks := 4 if character.conditions.is_active(ConditionRules.SPEEDY) else 0
	character.attacks_remaining = 0 if helpless else _context.arithmetic.signed_16(carried_half_attack + character.normal_attacks + character.attack_bonus + haste_half_attacks)


func consume_character_attack(character: CharacterState) -> void:
	character.attacks_remaining = _context.arithmetic.signed_16(character.attacks_remaining - 2)
	character.movement = maxi(0, character.movement - 3)


static func character_can_continue(character: CharacterState) -> bool:
	return character.current_health > 0 and character.attacks_remaining >= 2


static func _events_include(events: Array[DomainEvent], kind: StringName) -> bool:
	return events.any(func(event: DomainEvent) -> bool: return event.kind == kind)
