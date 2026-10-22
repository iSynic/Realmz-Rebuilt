## Executes getup.c's ordered round work, advancing the saved cursor before a wait.
class_name CombatRoundBoundary
extends RefCounted

var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context


func begin(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	state.combat.round_cursor = CombatRoundCursor.new()
	var prior_death := CombatActionEvents.death_macro_request(events)
	if not prior_death.is_empty():
		state.combat.round_cursor.phase = &"prior-death-macro"
		state.combat.round_cursor.waiting_monster_id = prior_death["combatantId"]
	elif state.combat.macro_id < 0:
		state.combat.round_cursor.phase = &"battle-macro"
	else:
		resume(state, content, rng, events)


func resume(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	while combat.round_cursor != null and not combat.completed:
		var cursor := combat.round_cursor
		if cursor.phase == &"battle-macro" or not cursor.waiting_monster_id.is_empty() or not combat.spell_runtime.pending_death_macro_id().is_empty():
			return
		match cursor.phase:
			&"party":
				_process_party(state, events)
				cursor.phase = &"character-fields"
			&"character-fields":
				if cursor.actor_index >= state.party.characters().size():
					cursor.actor_index = 0
					cursor.phase = &"monster-decay"
				else:
					var character := state.party.characters()[cursor.actor_index]
					cursor.actor_index += 1
					_collide(state, content, character.id, character.current_health, rng, events)
					process_character_bleeding(state, character, rng, events)
			&"warning":
				append_bleeding_warning(state, rng, events)
				combat.round_cursor = null
			_:
				if cursor.actor_index >= combat.roster.monsters().size():
					cursor.phase = &"warning"
				else:
					_process_monster(state, content, combat.roster.monsters()[cursor.actor_index], rng, events)


func _process_party(state: GameState, events: Array[DomainEvent]) -> void:
	events.append_array(_context.conditions.tick_party_conditions(state.party))
	for character: CharacterState in state.party.characters():
		var alive := character.current_health > 0
		events.append_array(_context.conditions.tick_character(character, true, _context.arithmetic))
		if alive and character.current_health <= 0:
			_context.actions().mark_character_bleeding(state, character, true)
			_context.automation().remove_defeated_position(state.combat, character.id, true)
			CombatActionEvents.append_defeat_audio(events, character.id)


func _process_monster(state: GameState, content: RealmzContent, monster: MonsterState, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var cursor := state.combat.round_cursor
	match cursor.phase:
		&"monster-decay":
			for index: int in monster.conditions.decay_positive():
				var payload := {"monsterId": monster.id, "condition": index}
				if index == ConditionRules.HELPLESS:
					payload.merge({"helplessBefore": true, "helplessAfter": false})
				events.append(DomainEvent.new(&"condition_expired", payload))
			cursor.phase = &"monster-regeneration"
		&"monster-regeneration":
			cursor.phase = &"monster-disease"
			if monster.conditions.is_active(ConditionRules.REGENERATING) and monster.current_health > 0 and monster.current_health < monster.maximum_health:
				var amount := absi(monster.conditions.value(ConditionRules.REGENERATING))
				monster.current_health = mini(monster.maximum_health, _context.arithmetic.signed_16(monster.current_health + amount))
				# getup.c reports the original magnitude even when its stamina cap applies.
				_append_monster_effect(events, monster, ConditionRules.REGENERATING, amount, true)
		&"monster-disease", &"monster-poison":
			var index := ConditionRules.DISEASED if cursor.phase == &"monster-disease" else ConditionRules.POISONED
			cursor.phase = &"monster-poison" if index == ConditionRules.DISEASED else &"monster-energy"
			_damage_monster(state, content, monster, index, events)
		&"monster-energy":
			cursor.phase = &"monster-field"
			var drain := monster.conditions.value(ConditionRules.ENERGY_DRAIN)
			if drain != 0:
				monster.spell_points = maxi(0, _context.arithmetic.signed_16(monster.spell_points - drain))
			var definition := content.combat.monster_by_id(monster.definition_id)
			# getup.c reads signed ENERGY_DRAIN again for absorption,
			# including dead monsters, and does not cap the result at maximum SP.
			if monster.conditions.is_active(ConditionRules.ABSORBING_ENERGY) and definition != null and definition.type_flag(0):
				monster.spell_points = _context.arithmetic.signed_16(monster.spell_points + drain)
		&"monster-field":
			cursor.phase = &"monster-decay"
			cursor.actor_index += 1
			_collide(state, content, monster.id, monster.current_health, rng, events)


func _damage_monster(state: GameState, content: RealmzContent, monster: MonsterState, index: int, events: Array[DomainEvent]) -> void:
	if not monster.conditions.is_active(index) or monster.conditions.is_active(ConditionRules.ANIMATED) or monster.current_health <= 0:
		return
	var amount := absi(monster.conditions.value(index))
	monster.current_health = _context.arithmetic.signed_16(monster.current_health - amount)
	_append_monster_effect(events, monster, index, amount, false)
	if monster.current_health > 0:
		return
	CombatActionEvents.append_defeat_audio(events, monster.id)
	var definition := content.combat.monster_by_id(monster.definition_id)
	var requested := CombatActionEvents.request_monster_death_macro(monster, definition, events)
	if requested:
		state.combat.round_cursor.waiting_monster_id = monster.id
	_context.automation().remove_defeated_position(state.combat, monster.id, not requested)


func _collide(state: GameState, content: RealmzContent, actor_id: String, health: int, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	if health <= 0 or state.combat.battlefield == null:
		return
	var result := _context.fields().resolve_actor_collisions(state, content, actor_id, rng, events, false)
	var character := state.party.character_by_id(actor_id)
	if character != null and character.current_health <= 0:
		_context.actions().mark_character_bleeding(state, character, true)
	if result == CombatFlowFields.COLLISION_INVALID:
		events.append(DomainEvent.new(&"combat_persistent_field_collision_failed", {"actorId": actor_id, "reason": "invalid-runtime-state"}))


static func _append_monster_effect(events: Array[DomainEvent], monster: MonsterState, index: int, amount: int, healed: bool) -> void:
	events.append(DomainEvent.new(&"condition_healed" if healed else &"condition_damaged", {"monsterId": monster.id, "condition": index, "amount": amount, "health": monster.current_health, "combat": true}))


func process_character_bleeding(state: GameState, character: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	if not combat.actor_statuses.is_character_bleeding(character.id):
		return
	if character.current_health <= -10:
		combat.actor_statuses.set_character_bleeding(character.id, false)
		state.set_combat_auto(character.id, false)
		return
	character.current_health = _context.arithmetic.signed_16(character.current_health - 1)
	if character.current_health < -9:
		character.lifetime_record.record_death(true)
		combat.actor_statuses.set_character_bleeding(character.id, false)
		state.set_combat_auto(character.id, false)
		_context.automation().remove_defeated_position(combat, character.id, true)
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 132, "waitForCompletion": false, "source": "classic-combat-bleeding"}))
		events.append(DomainEvent.new(&"combatant_bled_to_death", {"characterId": character.id, "health": character.current_health, "source": "classic"}))
		return
	var roll := rng.draw(100, StringName("combat.bleeding.%s" % character.id))
	var sound_id := 10121 if roll < 50 else 10123
	events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": false, "source": "classic-combat-bleeding"}))
	events.append(DomainEvent.new(&"combatant_bleeding_progressed", {"characterId": character.id, "health": character.current_health, "roll": roll, "soundId": sound_id, "source": "classic"}))


func append_bleeding_warning(state: GameState, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	if not _context.actions().bandage_candidate_ids(state).is_empty():
		# getup.c performs a second, party-wide warning draw after every
		# individual bleeding result when the Classic warning preference is on.
		# Realmz Rebuilt currently preserves that default; exposing the preference
		# itself remains owned by the settings workflow.
		var warning_roll := rng.draw(100, &"combat.bleeding.warning-sound")
		var warning_sound_id := 10121 if warning_roll < 50 else 10123
		events.append(DomainEvent.new(&"sound_requested", {"soundId": warning_sound_id, "waitForCompletion": false, "source": "classic-combat-bleeding-warning"}))
		events.append(DomainEvent.new(&"combat_bleeding_warning", {"roll": warning_roll, "soundId": warning_sound_id, "source": "classic-default"}))
