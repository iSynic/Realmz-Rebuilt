class_name CombatFlowActions
extends RefCounted

const ContextType = preload("res://src/core/rules/combat_flow_context.gd")
const CombatRetreatProbeType = preload("res://src/core/rules/combat_retreat_probe.gd")
const CombatCommandProbeType = preload("res://src/core/rules/combat_command_probe.gd")
const CombatScrollOptionViewType = preload("res://src/core/view/combat_scroll_option_view.gd")

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

func submit_action(state: GameState, content: RealmzContent, actor_id: String, action: StringName, target_id: String, rng: RealmzRng, allow_friendly_contact: bool = false) -> CombatFlowResult:
	var combat := state.combat
	if combat == null or combat.completed:
		return CombatFlowResult.failed(&"no_active_battle", "No Realmz battle is accepting combat actions.")
	if combat.active_actor_id() != actor_id:
		return CombatFlowResult.failed(&"wrong_combat_actor", "Combat action actor '%s' does not own the current turn." % actor_id)
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0 or actor.traitor or combat.battlefield == null or not combat.battlefield.has_actor(actor.id):
		return CombatFlowResult.failed(&"invalid_combat_actor", "The current combat actor is unavailable.")
	var events: Array[DomainEvent] = []
	match action:
		&"attack":
			var attack_result := _submit_character_attack(state, content, actor, target_id, rng, allow_friendly_contact)
			if not attack_result.ok: return attack_result
			events.append_array(attack_result.events)
			if _flow()._events_include(events, &"monster_death_macro_requested"):
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
			_flow()._advance_turn(state, content, rng, events)
		&"delay":
			var delay_probe := probe_delay(state, actor.id)
			if not delay_probe.allowed:
				return CombatFlowResult.failed(&"combat_delay_unavailable", delay_probe.reason_text)
			_prepare_character_turn(combat, actor)
			actor.attacks_remaining = _rules.arithmetic.signed_16(actor.attacks_remaining - actor.normal_attacks - actor.attack_bonus)
			var round_advanced := combat.delay_active_actor()
			if round_advanced:
				_flow()._process_bleeding_round(state, rng, events)
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
			if _flow().is_processing_auto():
				var bandage_roll := rng.draw(100, StringName("combat.auto.%s.bandage-sound" % actor.id))
				var bandage_sound := 10121 if bandage_roll < 50 else 10123
				events.append(DomainEvent.new(&"sound_requested", {"soundId": bandage_sound, "waitForCompletion": false, "source": "classic-combat-auto-bandage"}))
			events.append(DomainEvent.new(&"combatant_bandaged", {"actorId": actor.id, "targetId": target_id, "source": "classic-corrected", "fidelityDecision": "FD-COMBAT-013"}))
			_flow()._advance_turn(state, content, rng, events)
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
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 664, "waitForCompletion": false, "source": "classic-combat-undo"}))
			if not actor.conditions.is_active(ConditionRules.ANIMATED):
				events.append(DomainEvent.new(&"sound_requested", {"soundId": 138, "waitForCompletion": false, "source": "classic-combat-activation"}))
			events.append(DomainEvent.new(&"combat_turn_undone", {"actorId": actor.id, "from": [from_position.x, from_position.y], "to": [start_position.x, start_position.y], "attacksRemaining": actor.attacks_remaining, "movementRemaining": actor.movement, "source": "classic"}))
		&"auto":
			var auto_result = _flow().run_auto_activation_chain(state, content, actor.id, rng)
			if not auto_result.ok:
				return auto_result
			auto_result.events.push_front(DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-combat-auto-button"}))
			return auto_result
		&"finish", &"pass":
			_prepare_character_turn(combat, actor)
			actor.movement = 0
			combat.set_guarding(actor.id, false)
			events.append(DomainEvent.new(&"combat_turn_passed", {"actorId": actor.id, "action": String(action)}))
			_flow()._advance_turn(state, content, rng, events)
		&"retreat":
			return _flow().retreat_character(state, content, actor_id, &"explicit", Vector2i(-100_000, -100_000), rng)
		_:
			return CombatFlowResult.failed(&"unknown_combat_action", "Combat action '%s' is not available." % action)
	if _flow()._finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_flow()._process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func _submit_character_attack(state: GameState, content: RealmzContent, actor: CharacterState, target_id: String, rng: RealmzRng, allow_friendly_contact: bool = false) -> CombatFlowResult:
	var combat := state.combat
	var events: Array[DomainEvent] = []
	var equipment := _rules.inventory.combat_equipment(actor, content.item_definitions())
	if not equipment.valid: return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
	if combat.character_weapon_mode(actor.id) == &"missile": return _fire_character_projectile(state, content, actor, equipment, target_id, rng)
	if combat.battlefield == null: return CombatFlowResult.failed(&"missing_battlefield", "Melee requires the session-owned Classic battlefield.")
	if not _rules.battlefield.are_adjacent(combat.battlefield, actor.id, target_id): return CombatFlowResult.failed(&"combat_target_not_adjacent", "Classic melee can target only an enemy in an adjacent battlefield footprint.")
	var monster_target := combat.monster_by_id(target_id)
	if monster_target != null and monster_target.current_health > 0 and (monster_target.traitor != actor.traitor or allow_friendly_contact):
		var definition := content.monster_by_id(monster_target.definition_id)
		if definition == null: return CombatFlowResult.failed(&"unknown_monster_definition", "The selected monster has no immutable definition.")
		_prepare_character_turn(combat, actor)
		combat.invalidate_undo()
		combat.active_turn.physical_action_committed = true
		var resolution := _rules.combat.resolve_character_attack(actor, equipment, monster_target, definition, rng, state.clock.day(), false, true, combat.can_queue_fumbled_item())
		if resolution.total_damage() > 0: combat.mark_attacked(monster_target.id)
		if resolution.fumbled and not _commit_character_fumble(state, actor, equipment, events): return CombatFlowResult.failed(&"invalid_fumble_state", "The fumbled melee weapon could not enter the battle recovery queue.")
		_append_character_attack_audio(events, actor, equipment, resolution, &"monster")
		events.append(_character_attack_event(actor.id, monster_target.id, &"monster", resolution, equipment.melee_weapon != null))
		var macro_requested := resolution.killed and _request_monster_death_macro(monster_target, definition, events)
		_flow()._remove_defeated_position(combat, monster_target.id, resolution.killed and not macro_requested)
	else:
		var character_target := state.party.character_by_id(target_id)
		if character_target == null or character_target.id == actor.id or character_target.current_health <= 0 or (character_target.traitor == actor.traitor and not allow_friendly_contact): return CombatFlowResult.failed(&"invalid_combat_target", "The selected combatant is unavailable to this allegiance.")
		var target_equipment := _rules.inventory.combat_equipment(character_target, content.item_definitions())
		if not target_equipment.valid: return CombatFlowResult.failed(target_equipment.error_code, target_equipment.error_message)
		_prepare_character_turn(combat, actor)
		combat.invalidate_undo()
		combat.active_turn.physical_action_committed = true
		var resolution := _rules.combat.resolve_character_attack_character(actor, equipment, character_target, target_equipment, rng, false, true, combat.can_queue_fumbled_item())
		if resolution.total_damage() > 0: combat.mark_attacked(character_target.id)
		if resolution.fumbled and not _commit_character_fumble(state, actor, equipment, events): return CombatFlowResult.failed(&"invalid_fumble_state", "The fumbled melee weapon could not enter the battle recovery queue.")
		_append_character_attack_audio(events, actor, equipment, resolution, &"character")
		events.append(_character_attack_event(actor.id, character_target.id, &"character", resolution, equipment.melee_weapon != null))
		_mark_character_bleeding(state, character_target, resolution.killed)
		_flow()._remove_defeated_position(combat, character_target.id, resolution.killed)
	_consume_character_attack(actor)
	if not _character_can_continue(actor): _flow()._advance_turn(state, content, rng, events)
	return CombatFlowResult.succeeded(events)


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
			actor.lifetime_record.record_turn_undead(true)
			experience_award = 25 * target.hit_dice
			target.current_health = 0
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 132, "waitForCompletion": false, "source": "classic-combat-turn-undead"}))
			if not _queue_spell_death_macro(combat, target, definition):
				_flow()._remove_defeated_position(combat, target.id, true)
		elif margin >= 30:
			result_kind = "turned"
			actor.lifetime_record.record_turn_undead(false)
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
		_flow()._advance_turn(state, content, rng, events)
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
		character.lifetime_record.record_knockout()
		state.combat.set_character_bleeding(character.id, true)
	else:
		character.lifetime_record.record_death()


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


func _fire_character_projectile(state: GameState, content: RealmzContent, actor: CharacterState, equipment: CharacterCombatEquipment, target_id: String, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	var profile = _flow().character_projectile_profile(actor, content, equipment)
	if not profile.available:
		return CombatFlowResult.failed(profile.error_code, profile.error_message)
	var target := combat.monster_by_id(target_id)
	if target == null or target.current_health <= 0 or target.traitor == actor.traitor:
		return CombatFlowResult.failed(&"invalid_projectile_target", "This source-backed projectile slice can target only a living hostile monster.")
	if not _flow().projectile_target_is_valid(combat, content, actor.id, target.id, profile.maximum_range, profile.spell.range_min + profile.spell.range_max > 0):
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
	actor.lifetime_record.add_projectile_damage_given(resolution.total_damage, resolution.hit_count, resolution.miss_count, resolution.target_defeated)
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
	_flow()._remove_defeated_position(combat, target.id, resolution.target_defeated and not death_macro_requested)
	if not _character_can_continue(actor):
		_flow()._advance_turn(state, content, rng, events)
	if death_macro_requested:
		return CombatFlowResult.succeeded(events)
	if _flow()._finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_flow()._process_monster_turns(state, content, rng, events)
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
	character.attacks_remaining = 0 if helpless else _rules.arithmetic.signed_16(carried_half_attack + character.normal_attacks + character.attack_bonus + haste_half_attacks)


func _consume_character_attack(character: CharacterState) -> void:
	character.attacks_remaining = _rules.arithmetic.signed_16(character.attacks_remaining - 2)
	character.movement = maxi(0, character.movement - 3)


static func _character_can_continue(character: CharacterState) -> bool:
	return character.current_health > 0 and character.attacks_remaining >= 2


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
