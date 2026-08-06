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
	var monsters: Array[MonsterState] = []
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
		monsters.append(monster)
	if monsters.is_empty():
		return CombatFlowResult.failed(&"empty_battle", "Battle '%s' has no viable monsters." % battle.id)
	var combat := CombatState.new(battle.id, monsters)
	combat.set_turn_order(_rules.combat.initiative_order(state.party.characters(), monsters, surprise, rng))
	state.combat = combat
	var events: Array[DomainEvent] = [DomainEvent.new(&"battle_started", {"battleId": battle.id, "classicId": battle.classic_id, "distance": battle.distance, "surprise": surprise, "turnOrder": combat.turn_order()})]
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
			if target == null or target.current_health <= 0:
				return CombatFlowResult.failed(&"invalid_combat_target", "The selected monster is unavailable.")
			var definition := content.monster_by_id(target.definition_id)
			var damage_bonus := _rules.inventory.equipped_damage_bonus(actor, content.item_definitions())
			var resolution := _rules.combat.resolve_character_attack(actor, target, definition, damage_bonus, rng, state.clock.day())
			events.append(DomainEvent.new(&"combat_attack_resolved", {"actorId": actor.id, "targetId": target.id, "hit": resolution.hit, "damage": resolution.damage, "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll}))
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
	if caster == null or target == null or target.current_health <= 0 or spell == null or power_level < 1:
		return CombatFlowResult.failed(&"invalid_spell_target", "The spell, caster, power, or target is unavailable.")
	if not caster.known_spells().has(spell.id):
		return CombatFlowResult.failed(&"spell_not_known", "The caster does not know '%s'." % spell.id)
	var target_definition := content.monster_by_id(target.definition_id)
	var resolution := _rules.magic.resolve_character_spell(caster, target, target_definition, spell, power_level, caster.level, rng)
	if resolution == null or not resolution.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The spell could not be cast with the available spell points.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_spell_resolved", {"actorId": caster.id, "targetId": target.id, "spellId": spell.id, "power": power_level, "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "duration": resolution.duration, "defeated": resolution.target_defeated})]
	combat.advance_turn()
	if _finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


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
			var targets: Array[CharacterState] = []
			for character: CharacterState in state.party.characters():
				if character.current_health > 0:
					targets.append(character)
			if targets.is_empty():
				_finish_if_resolved(state, content, events)
				break
			var target := targets[rng.draw_between(0, targets.size() - 1, &"combat.monster-target")]
			var choice := _rules.monsters.choose_action(monster, definition, rng)
			if choice in [&"advance", &"missile"]:
				var resolution := _rules.combat.resolve_monster_attack(monster, definition, 0, target, rng)
				events.append(DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": target.id, "action": String(choice), "hit": resolution.hit, "damage": resolution.damage, "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll}))
			else:
				events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": String(choice)}))
		combat.advance_turn()
		if _finish_if_resolved(state, content, events):
			break
		guard -= 1


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
			if definition != null:
				experience += maxi(0, definition.experience)
		for character: CharacterState in state.party.characters():
			if character.current_health > 0:
				character.experience += experience
		events.append(DomainEvent.new(&"battle_rewards_granted", {"experiencePerSurvivor": experience}))
	events.append(DomainEvent.new(&"battle_completed", {"battleId": combat.battle_id, "outcome": String(combat.outcome)}))
	return true
