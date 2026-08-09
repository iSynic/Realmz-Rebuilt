class_name CombatFlow
extends RefCounted

var _rules: RealmzRules


func _init(rules: RealmzRules) -> void:
	_rules = rules


func start_battle(state: GameState, content: RealmzContent, battle: BattleDefinition, rng: RealmzRng, surprise: int = 0) -> CombatFlowResult:
	if state == null or content == null or battle == null or rng == null:
		return CombatFlowResult.failed(&"invalid_battle", "Battle setup requires validated state, content, and randomness.")
	if state.combat != null and not state.combat.completed:
		return CombatFlowResult.failed(&"battle_already_active", "A Realmz battle is already active.")
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
	if actor == null or actor.current_health <= 0:
		return CombatFlowResult.failed(&"invalid_combat_actor", "The current combat actor is unavailable.")
	var events: Array[DomainEvent] = []
	match action:
		&"attack":
			var target := combat.monster_by_id(target_id)
			if target == null or target.current_health <= 0 or not target.traitor:
				return CombatFlowResult.failed(&"invalid_combat_target", "The selected monster is unavailable.")
			var definition := content.monster_by_id(target.definition_id)
			var damage_bonus := _rules.inventory.equipped_damage_bonus(actor, content.item_definitions())
			var resolution := _rules.combat.resolve_character_attack(actor, target, definition, damage_bonus, rng, state.clock.day())
			events.append(DomainEvent.new(&"combat_attack_resolved", {"actorId": actor.id, "targetId": target.id, "hit": resolution.hit, "damage": resolution.damage, "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll}))
			if resolution.killed and _request_monster_death_macro(target, definition, events):
				combat.advance_turn()
				return CombatFlowResult.succeeded(events)
		&"defend", &"pass":
			events.append(DomainEvent.new(&"combat_turn_passed", {"actorId": actor.id, "action": String(action)}))
		&"retreat":
			combat.completed = true
			combat.outcome = &"retreated"
			state.last_battle_outcome = combat.outcome
			events.append(DomainEvent.new(&"battle_completed", {"battleId": combat.battle_id, "outcome": String(combat.outcome)}))
			return CombatFlowResult.succeeded(events, true)
		_:
			return CombatFlowResult.failed(&"unknown_combat_action", "Combat action '%s' is not available." % action)
	combat.advance_turn()
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
	if caster == null or target == null or target.current_health <= 0 or not target.traitor or spell == null or power_level < 1:
		return CombatFlowResult.failed(&"invalid_spell_target", "The spell, caster, power, or target is unavailable.")
	if not caster.known_spells().has(spell.id):
		return CombatFlowResult.failed(&"spell_not_known", "The caster does not know '%s'." % spell.id)
	var target_definition := content.monster_by_id(target.definition_id)
	var resolution := _rules.magic.resolve_character_spell(caster, target, target_definition, spell, power_level, caster.level, rng)
	if resolution == null or not resolution.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The spell could not be cast with the available spell points.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_spell_resolved", {"actorId": caster.id, "targetId": target.id, "spellId": spell.id, "power": power_level, "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "duration": resolution.duration, "defeated": resolution.target_defeated})]
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
	target.current_health -= pending.damage
	var defeated := target.current_health <= 0
	events.append(DomainEvent.new(&"combat_attack_resolved", {"actorId": pending.actor_id, "targetId": pending.target_id, "action": String(pending.action), "hit": true, "damage": pending.damage, "defeated": defeated, "chance": pending.chance, "roll": pending.roll}))
	combat.pending_monster_attack = null
	combat.advance_turn()
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
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


func _process_monster_turns(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	var guard := combat.turn_order().size()
	while guard > 0 and not combat.completed:
		var actor_id := combat.active_actor_id()
		var monster := combat.monster_by_id(actor_id)
		if monster == null:
			break
		if monster.current_health > 0:
			var definition := content.monster_by_id(monster.definition_id)
			var character_targets: Array[CharacterState] = []
			if monster.traitor:
				for character: CharacterState in state.party.characters():
					if character.current_health > 0:
						character_targets.append(character)
			var monster_targets: Array[MonsterState] = []
			for candidate: MonsterState in combat.monsters():
				if candidate.id != monster.id and candidate.current_health > 0 and candidate.traitor != monster.traitor:
					monster_targets.append(candidate)
			var target_count := character_targets.size() + monster_targets.size()
			if target_count == 0:
				_finish_if_resolved(state, content, events)
				break
			var target_index := rng.draw_between(0, target_count - 1, &"combat.monster-target")
			var choice := _rules.monsters.choose_action(monster, definition, rng)
			if choice in [&"advance", &"missile"]:
				if target_index < character_targets.size():
					var character_target := character_targets[target_index]
					var race := content.race_by_id(character_target.race_id)
					var caste := content.caste_by_id(character_target.caste_id)
					var character_resolution := _rules.combat.resolve_monster_attack(monster, definition, 0, character_target, race, caste, rng)
					var age_update_requested := false
					if character_resolution.special_code == 17:
						events.append(DomainEvent.new(&"combat_monster_special_resolved", {"actorId": monster.id, "targetId": character_target.id, "specialCode": character_resolution.special_code, "potency": character_resolution.special_potency, "saveChance": character_resolution.special_save_chance, "saveRoll": character_resolution.special_save_roll, "saved": character_resolution.special_saved, "applied": character_resolution.special_applied, "ageDays": character_resolution.special_age_days, "source": "classic"}))
						if character_resolution.aging != null and character_resolution.aging.changed_group():
							events.append(DomainEvent.new(&"character_age_changed", character_resolution.aging.event_payload(character_target, race)))
							age_update_requested = true
					if age_update_requested:
						combat.pending_monster_attack = PendingMonsterAttack.new(monster.id, character_target.id, choice, character_resolution.damage, character_resolution.chance, character_resolution.roll)
						return
					events.append(DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": character_target.id, "action": String(choice), "hit": character_resolution.hit, "damage": character_resolution.damage, "defeated": character_resolution.killed, "chance": character_resolution.chance, "roll": character_resolution.roll}))
				else:
					var monster_target := monster_targets[target_index - character_targets.size()]
					var monster_resolution := _rules.combat.resolve_monster_attack_monster(monster, definition, 0, monster_target, rng)
					events.append(DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": monster_target.id, "action": String(choice), "hit": monster_resolution.hit, "damage": monster_resolution.damage, "defeated": monster_resolution.killed, "chance": monster_resolution.chance, "roll": monster_resolution.roll}))
					if monster_resolution.killed:
						var target_definition := content.monster_by_id(monster_target.definition_id)
						if _request_monster_death_macro(monster_target, target_definition, events):
							combat.advance_turn()
							return
			else:
				events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": String(choice)}))
		combat.advance_turn()
		if _finish_if_resolved(state, content, events):
			break
		guard -= 1


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
	for monster: MonsterState in combat.monsters():
		if monster.current_health > 0 and monster.traitor:
			enemies_alive = true
			break
	var party_alive := false
	for character: CharacterState in state.party.characters():
		if character.current_health > 0:
			party_alive = true
			break
	if enemies_alive and party_alive:
		return false
	combat.completed = true
	combat.outcome = &"victory" if party_alive else &"defeat"
	state.last_battle_outcome = combat.outcome
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
