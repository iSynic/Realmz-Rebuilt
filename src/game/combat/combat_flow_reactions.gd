## Implements deterministic combat flow reactions rules without presentation dependencies.

class_name CombatFlowReactions
extends RefCounted


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

var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context

func probe_character_retreat(combat: CombatState, characters: Array[CharacterState], actor_id: String):
	if combat == null or combat.completed or combat.battlefield == null or combat.turns.active_actor_id() != actor_id or not combat.battlefield.actors.has_actor(actor_id):
		return CombatRetreatProbe.blocked(&"invalid_combat_actor", "The active character is unavailable.")
	var actor: CharacterState = null
	for character: CharacterState in characters:
		if character.id == actor_id:
			actor = character
			break
	if actor == null or actor.current_health <= 0 or actor.traitor:
		return CombatRetreatProbe.blocked(&"invalid_combat_actor", "Only a living loyal character can retreat.")
	var nearest_range := 127
	var origin := combat.battlefield.actors.actor_position(actor_id)
	for character: CharacterState in characters:
		if character.id != actor_id and character.current_health > 0 and character.traitor != actor.traitor and combat.battlefield.actors.has_actor(character.id):
			nearest_range = mini(nearest_range, floori(Vector2(combat.battlefield.actors.actor_position(character.id) - origin).length()))
	for monster: MonsterState in combat.roster.monsters():
		if monster.current_health > 0 and monster.traitor != actor.traitor and combat.battlefield.actors.has_actor(monster.id):
			nearest_range = mini(nearest_range, floori(Vector2(combat.battlefield.actors.actor_position(monster.id) - origin).length()))
	if nearest_range < 10:
		return CombatRetreatProbe.blocked(&"enemy_too_close", "Classic Escape requires every enemy to be at least 10 battlefield cells away.", nearest_range)
	for condition: int in [ConditionRules.HELPLESS, ConditionRules.CONFUSED, ConditionRules.TANGLED, ConditionRules.SLOW]:
		if actor.conditions.is_active(condition):
			return CombatRetreatProbe.blocked(&"retreat_condition_blocked", "This character's current condition prevents Escape.", nearest_range)
	return CombatRetreatProbe.permitted(nearest_range)


func character_projectile_profile(character: CharacterState, content: RealmzContent, equipment: CharacterCombatEquipment = null, combat: CombatState = null) -> ProjectileAttackProfile:
	if character == null or content == null:
		return ProjectileAttackProfile.blocked(&"invalid_combat_actor", "A projectile requires an available character and content package.")
	var resolved_equipment := equipment if equipment != null else _context.equipment.combat_equipment(character, content.items.definitions())
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
	var spell := content.magic.spell_by_classic_id(absi(projectile_item.special_2))
	if spell == null:
		return ProjectileAttackProfile.blocked(&"projectile_spell_unavailable", "Projectile item '%s' references unavailable Classic spell %d." % [projectile_item.id, absi(projectile_item.special_2)])
	var unsupported = _context.actions().projectile_spell_unavailable_reason(spell)
	if not unsupported.is_empty():
		return ProjectileAttackProfile.blocked(&"unsupported_projectile_spell", unsupported)
	var power := absi(projectile_item.special_1)
	if power == 8:
		power = combat.turns.staged_random_item_power(character.id, instance_id) if combat != null else 0
		if power == 0:
			var staged := ProjectileAttackProfile.blocked(&"projectile_power_roll_required", "Roll this projectile's power before choosing its target.")
			staged.item = projectile_item
			staged.item_instance_id = instance_id
			staged.spell = spell
			for possible_power: int in range(1, 8):
				staged.maximum_range = maxi(staged.maximum_range, absi(spell.range_min + spell.range_max * possible_power))
			return staged
	return ProjectileAttackProfile.permitted(projectile_item, instance_id, spell, power, absi(spell.range_min + spell.range_max * power))


func projectile_target_is_valid(combat: CombatState, content: RealmzContent, actor_id: String, target_id: String, maximum_range: int, require_line_of_sight: bool = true) -> bool:
	if combat == null or content == null or combat.battlefield == null:
		return false
	var terrain_set = _context.automation().monster_actions().battle_terrain_set(content, combat.battlefield)
	return terrain_set != null and _context.battlefield.projectile_target_is_valid(combat.battlefield, terrain_set, actor_id, target_id, maximum_range, require_line_of_sight)


func probe_edge_retreat(combat: CombatState, actor_id: String, destination: Vector2i):
	if combat == null or combat.completed or combat.battlefield == null or combat.turns.active_actor_id() != actor_id or not combat.battlefield.actors.has_actor(actor_id):
		return CombatRetreatProbe.blocked(&"invalid_combat_actor", "The active character is unavailable.")
	var origin := combat.battlefield.actors.actor_position(actor_id)
	var direction := destination - origin
	if direction == Vector2i.ZERO or absi(direction.x) > 1 or absi(direction.y) > 1:
		return CombatRetreatProbe.blocked(&"invalid_direction", "Battlefield-edge retreat requires one adjacent movement direction.")
	if destination.x >= 2 and destination.y >= 2 and destination.x <= 87 and destination.y <= 87:
		return CombatRetreatProbe.blocked(&"not_battlefield_edge", "This movement does not enter Castle's retreat band.")
	var forced := origin.x < 1 or origin.y < 1 or origin.x > 88 or origin.y > 88
	return CombatRetreatProbe.permitted(127, forced)


func retreat_character(state: GameState, content: RealmzContent, actor_id: String, mode: StringName, destination: Vector2i, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or combat.turns.active_actor_id() != actor_id:
		return CombatFlowResult.failed(&"invalid_combat_actor", "The active character cannot retreat.")
	var actor := state.party.character_by_id(actor_id)
	if actor == null:
		return CombatFlowResult.failed(&"invalid_combat_actor", "The active character cannot retreat.")
	var probe: Variant = probe_character_retreat(combat, state.party.characters(), actor_id) if mode == &"explicit" else probe_edge_retreat(combat, actor_id, destination) if mode == &"edge" else null
	if probe == null:
		return CombatFlowResult.failed(&"invalid_retreat_mode", "The retreat route is unavailable.")
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	if not combat.actor_statuses.mark_character_retreated(actor.id):
		return CombatFlowResult.failed(&"invalid_retreat_state", "The active character's Escape state could not be recorded.")
	combat.battlefield.actors.remove_character(actor.id)
	combat.actor_statuses.set_guarding(actor.id, false)
	combat.turns.clear_active_turn()
	actor.attacks_remaining = 0
	actor.movement = 0
	actor.prestige_penalty = _context.arithmetic.signed_32(actor.prestige_penalty + 200)
	var events: Array[DomainEvent] = [DomainEvent.new(&"combatant_retreated", {"actorId": actor.id, "mode": String(mode), "forced": probe.forced, "prestigePenalty": 200, "nearestEnemyRange": probe.nearest_enemy_range, "source": "classic"})]
	if not _context.rounds().has_loyal_battlefield_character(state):
		_context.rounds().complete_battle(state, content, &"retreated", events)
		return CombatFlowResult.succeeded(events, true)
	_context.rounds().advance_turn(state, content, rng, events)
	return _context.automation().process_monster_turns(state, content, rng, events)


func move_character(state: GameState, content: RealmzContent, actor_id: String, destination: Vector2i, rng: RealmzRng, auto_switch_to_melee: bool = false, friendly_collision_action: StringName = &"") -> CombatFlowResult:
	var combat := state.combat
	if combat == null or combat.completed or rng == null:
		return CombatFlowResult.failed(&"no_active_battle", "No Realmz battle is accepting tactical movement.")
	if combat.pending_reaction != null or combat.pending_monster_attack != null:
		if combat.pending_monster_attack == null and not friendly_collision_action.is_empty() and combat.pending_reaction.awaits_friendly_collision_choice() and combat.pending_reaction.mover_id == actor_id and combat.pending_reaction.destination == destination:
			return _resolve_friendly_collision(state, content, friendly_collision_action, rng)
		return CombatFlowResult.failed(&"combat_reaction_pending", "The previous Classic combat reaction must finish before another movement command.")
	if combat.turns.active_actor_id() != actor_id:
		return CombatFlowResult.failed(&"wrong_combat_actor", "Combat movement actor '%s' does not own the current turn." % actor_id)
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0 or actor.traitor or combat.battlefield == null:
		return CombatFlowResult.failed(&"invalid_combat_actor", "The current combat actor or battlefield is unavailable.")
	var terrain_set = _context.automation().monster_actions().battle_terrain_set(content, combat.battlefield)
	if terrain_set == null:
		return CombatFlowResult.failed(&"missing_battle_terrain", "The active battlefield has no validated Classic terrain catalog.")
	var origin := combat.battlefield.actors.actor_position(actor_id)
	var direction := destination - origin
	var available_movement := actor.maximum_movement if combat.turns.active_turn == null else actor.movement
	var probe := _context.battlefield.probe_step(combat.battlefield, terrain_set, actor_id, direction, available_movement)
	var contact_target_id = _context.automation().hostile_contact_target_id(state, actor.id, probe.occupant_id) if probe.reason == &"occupied" else ""
	var friendly_target_id := friendly_collision_target_id(state, actor.id, destination) if probe.reason == &"occupied" else ""
	var automatic_actor = _context.processing_auto or actor.traitor or actor.conditions.is_active(ConditionRules.ANIMATED)
	if not friendly_target_id.is_empty() and friendly_collision_action.is_empty():
		if automatic_actor:
			friendly_collision_action = &"swap"
	if not friendly_collision_action.is_empty() and (friendly_collision_action not in [&"swap", &"attack"] or friendly_target_id.is_empty()):
		return CombatFlowResult.failed(&"invalid_friendly_collision", "The selected Classic friendly-collision action is no longer available.")
	if friendly_collision_action == &"attack" and combat.actor_statuses.character_weapon_mode(actor.id) != &"melee":
		return CombatFlowResult.failed(&"melee_weapon_mode_required", "Switch to the melee weapon before attacking an adjacent ally.")
	var should_auto_switch := false
	if not contact_target_id.is_empty() and combat.actor_statuses.character_weapon_mode(actor.id) != &"melee":
		if not auto_switch_to_melee or automatic_actor or not classic_projectile_uses_point_blank_auto_switch(actor, content):
			return CombatFlowResult.failed(&"melee_weapon_mode_required", "Switch to the melee weapon before attacking an occupied hostile footprint.")
		should_auto_switch = true
	if not probe.allowed and contact_target_id.is_empty() and friendly_target_id.is_empty() and probe.reason == &"invalid_direction":
		return CombatFlowResult.failed(probe.reason, _movement_failure_message(probe))
	if not contact_target_id.is_empty() or friendly_collision_action == &"attack":
		var equipment := _context.equipment.combat_equipment(actor, content.items.definitions())
		if not equipment.valid:
			return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
	_context.actions().prepare_character_turn(combat, actor)
	var movement_cost := 5 if friendly_collision_action == &"swap" else 3 if not contact_target_id.is_empty() or friendly_collision_action == &"attack" else probe.movement_cost
	combat.pending_reaction = CombatReactionState.new(CombatReactionState.CHARACTER_MOVE, actor.id, origin, destination, movement_cost)
	combat.pending_reaction.auto_switch_to_melee = should_auto_switch
	combat.pending_reaction.friendly_collision_action = friendly_collision_action
	combat.pending_reaction.friendly_collision_target_id = friendly_target_id
	var origin_hostiles = _context.automation().hostile_adjacent_ids(state, actor.id)
	combat.pending_reaction.set_origin_hostiles(origin_hostiles)
	combat.pending_reaction.set_phase(CombatReactionState.GUARD_BEFORE, guarding_actor_ids(state, origin_hostiles))
	var events: Array[DomainEvent] = []
	var reaction_result := continue_pending_reaction(state, content, rng, events)
	if reaction_result == REACTION_MOVER_DEFEATED:
		if combat.turns.active_actor_id() == actor.id:
			_context.rounds().advance_turn(state, content, rng, events)
		if _context.rounds().finish_if_resolved(state, content, events):
			return CombatFlowResult.succeeded(events, true)
		return _context.automation().process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func _resolve_friendly_collision(state: GameState, content: RealmzContent, action: StringName, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat if state != null else null
	var reaction := combat.pending_reaction if combat != null else null
	if reaction == null or not reaction.awaits_friendly_collision_choice() or rng == null:
		return CombatFlowResult.failed(&"invalid_friendly_collision", "No guarded friendly-collision choice is pending.")
	if friendly_collision_target_id(state, reaction.mover_id, reaction.destination) != reaction.friendly_collision_target_id:
		return CombatFlowResult.failed(&"invalid_friendly_collision", "The adjacent ally is no longer available.")
	if action == &"cancel":
		combat.pending_reaction = null
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_friendly_collision_cancelled", {"actorId": reaction.mover_id, "targetId": reaction.friendly_collision_target_id, "destination": [reaction.destination.x, reaction.destination.y], "source": "classic"})], false)
	if action == &"attack" and combat.actor_statuses.character_weapon_mode(reaction.mover_id) != &"melee":
		return CombatFlowResult.failed(&"melee_weapon_mode_required", "Switch to the melee weapon before attacking an adjacent ally.")
	if action == &"attack":
		var actor := state.party.character_by_id(reaction.mover_id)
		var equipment := _context.equipment.combat_equipment(actor, content.items.definitions())
		if not equipment.valid:
			return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
	if not reaction.select_friendly_collision_action(action):
		return CombatFlowResult.failed(&"invalid_friendly_collision", "The guarded friendly-collision choice could not be applied.")
	var events: Array[DomainEvent] = []
	var mover_id := reaction.mover_id
	var reaction_result := continue_pending_reaction(state, content, rng, events)
	if reaction_result == REACTION_MOVER_DEFEATED and combat.turns.active_actor_id() == mover_id:
		_context.rounds().advance_turn(state, content, rng, events)
	if _context.rounds().finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	if reaction_result == REACTION_MOVER_DEFEATED:
		return _context.automation().process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func friendly_collision_target_id(state: GameState, actor_id: String, destination: Vector2i) -> String:
	var combat := state.combat if state != null else null
	var actor := state.party.character_by_id(actor_id) if state != null else null
	if combat == null or combat.completed or combat.battlefield == null or actor == null or actor.current_health <= 0 or actor.traitor or combat.turns.active_actor_id() != actor_id:
		return ""
	var origin := combat.battlefield.actors.actor_position(actor_id)
	var direction := destination - origin
	var movement := actor.maximum_movement if combat.turns.active_turn == null else actor.movement
	if direction == Vector2i.ZERO or absi(direction.x) > 1 or absi(direction.y) > 1 or movement <= 4:
		return ""
	var target_id := combat.battlefield.actors.actor_at(destination, actor_id)
	if target_id.is_empty() or combat.battlefield.actors.actor_size(target_id) != 0:
		return ""
	var target_character := state.party.character_by_id(target_id)
	if target_character != null:
		return target_id if target_character.current_health > 0 and target_character.traitor == actor.traitor else ""
	var target_monster := combat.roster.monster_by_id(target_id)
	return target_id if target_monster != null and target_monster.current_health > 0 and target_monster.traitor == actor.traitor else ""


func classic_projectile_uses_point_blank_auto_switch(actor: CharacterState, content: RealmzContent) -> bool:
	var equipment := _context.equipment.combat_equipment(actor, content.items.definitions())
	if not equipment.valid or equipment.missile_weapon == null:
		return false
	var projectile_item := equipment.missile_weapon
	if projectile_item.special_2 <= 1100:
		return false
	var spell := content.magic.spell_by_classic_id(absi(projectile_item.special_2))
	return spell != null and spell.spell_class == 9 and spell.damage_type == 9


func continue_pending_reaction(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var operation_guard := 256
	while combat != null and combat.pending_reaction != null and operation_guard > 0:
		var reaction := combat.pending_reaction
		if reaction.mover_killed or not combatant_is_alive(state, reaction.mover_id):
			reaction.mover_killed = true
			combat.pending_reaction = null
			return REACTION_MOVER_DEFEATED
		if reaction.has_next_attacker():
			var attacker_id := reaction.take_next_attacker()
			var attack_result := resolve_reaction_attack(state, content, attacker_id, reaction, rng, events)
			if attack_result != REACTION_COMPLETED:
				if attack_result == REACTION_MOVER_DEFEATED:
					combat.pending_reaction = null
				return attack_result
			operation_guard -= 1
			continue
		match reaction.phase:
			CombatReactionState.GUARD_BEFORE:
				var guard_result := _continue_guard_before(state, content, reaction, rng, events)
				if guard_result != REACTION_COMPLETED or combat.pending_reaction == null:
					if guard_result == REACTION_MOVER_DEFEATED:
						combat.pending_reaction = null
					return guard_result
			CombatReactionState.WITHDRAWAL:
				var move_result := commit_reaction_move(state, content, reaction, rng, events)
				if move_result != REACTION_COMPLETED:
					if move_result == REACTION_MOVER_DEFEATED:
						combat.pending_reaction = null
					return move_result
			CombatReactionState.GUARD_AFTER:
				combat.pending_reaction = null
				return REACTION_COMPLETED
		operation_guard -= 1
	if operation_guard == 0:
		events.append(DomainEvent.new(&"combat_reaction_failed", {"reason": "reaction-budget-exhausted"}))
		if combat != null:
			combat.pending_reaction = null
	return REACTION_COMPLETED


func _continue_guard_before(state: GameState, content: RealmzContent, reaction: CombatReactionState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	if reaction.kind != CombatReactionState.CHARACTER_MOVE:
		return commit_reaction_move(state, content, reaction, rng, events)
	if reaction.awaits_friendly_collision_choice():
		return REACTION_WAITING
	if reaction.friendly_collision_action == &"attack":
		return _submit_friendly_contact_attack(state, content, reaction, rng, events)
	if reaction.friendly_collision_action == &"swap":
		return commit_reaction_move(state, content, reaction, rng, events)
	var contact_target_id = _context.automation().hostile_contact_target_id(state, reaction.mover_id, reaction.destination)
	if not contact_target_id.is_empty():
		return _submit_hostile_contact_attack(state, content, reaction, contact_target_id, rng, events)
	reaction.auto_switch_to_melee = false
	var terrain_set: BattleTerrainSetDefinition = _context.automation().monster_actions().battle_terrain_set(content, state.combat.battlefield)
	var actor := state.party.character_by_id(reaction.mover_id)
	var probe := _context.battlefield.probe_step(state.combat.battlefield, terrain_set, reaction.mover_id, reaction.destination - reaction.origin, actor.movement)
	if not probe.allowed and probe.reason != &"insufficient_movement":
		return commit_reaction_move(state, content, reaction, rng, events)
	reaction.set_phase(CombatReactionState.WITHDRAWAL, withdrawal_hostiles(state, reaction))
	return REACTION_COMPLETED


func _submit_friendly_contact_attack(state: GameState, content: RealmzContent, reaction: CombatReactionState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var target_monster := combat.roster.monster_by_id(reaction.friendly_collision_target_id)
	var previous_traitor := false
	if target_monster != null:
		previous_traitor = target_monster.traitor
		target_monster.traitor = not state.party.character_by_id(reaction.mover_id).traitor
	combat.pending_reaction = null
	var friendly_attack: CombatFlowResult = _context.actions().submit_action(state, content, reaction.mover_id, &"attack", reaction.friendly_collision_target_id, rng, true)
	if not friendly_attack.ok:
		if target_monster != null:
			target_monster.traitor = previous_traitor
		events.append(DomainEvent.new(&"combat_contact_attack_failed", {"actorId": reaction.mover_id, "targetId": reaction.friendly_collision_target_id, "reason": String(friendly_attack.error_code)}))
		return REACTION_COMPLETED
	events.append_array(friendly_attack.events)
	return REACTION_COMPLETED


func _submit_hostile_contact_attack(state: GameState, content: RealmzContent, reaction: CombatReactionState, target_id: String, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	if reaction.auto_switch_to_melee and combat.actor_statuses.character_weapon_mode(reaction.mover_id) != &"melee":
		if not combat.actor_statuses.set_character_weapon_mode(reaction.mover_id, &"melee"):
			combat.pending_reaction = null
			events.append(DomainEvent.new(&"combat_contact_attack_failed", {"actorId": reaction.mover_id, "targetId": target_id, "reason": "invalid_weapon_mode"}))
			return REACTION_COMPLETED
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-auto-weapon-switch"}))
		events.append(DomainEvent.new(&"combat_weapon_mode_changed", {"actorId": reaction.mover_id, "mode": "melee", "source": "classic-auto-weapon-switch"}))
	combat.pending_reaction = null
	var contact_result = _context.actions().submit_action(state, content, reaction.mover_id, &"attack", target_id, rng)
	if not contact_result.ok:
		events.append(DomainEvent.new(&"combat_contact_attack_failed", {"actorId": reaction.mover_id, "targetId": target_id, "reason": String(contact_result.error_code)}))
		return REACTION_COMPLETED
	events.append_array(contact_result.events)
	return REACTION_COMPLETED


func commit_reaction_move(state: GameState, content: RealmzContent, reaction: CombatReactionState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	if combat == null or combat.battlefield == null or not combatant_is_alive(state, reaction.mover_id) or combat.battlefield.actors.actor_position(reaction.mover_id) != reaction.origin:
		return REACTION_MOVER_DEFEATED
	var movement_remaining := 0
	if reaction.kind == CombatReactionState.CHARACTER_MOVE:
		if state.party.character_by_id(reaction.mover_id) == null:
			return REACTION_MOVER_DEFEATED
	else:
		if combat.turns.active_turn == null or combat.turns.active_turn.actor_id != reaction.mover_id:
			return REACTION_MOVER_DEFEATED
	if reaction.friendly_collision_action == &"swap":
		if combat.battlefield.actors.actor_at(reaction.destination, reaction.mover_id) != reaction.friendly_collision_target_id or not combat.battlefield.actors.swap_size_zero_actors(reaction.mover_id, reaction.friendly_collision_target_id):
			return REACTION_MOVER_DEFEATED
		var character := state.party.character_by_id(reaction.mover_id)
		character.movement = maxi(0, character.movement - 5)
		combat.turns.invalidate_undo()
		events.append(DomainEvent.new(&"combatants_swapped", {"actorId": reaction.mover_id, "targetId": reaction.friendly_collision_target_id, "from": [reaction.origin.x, reaction.origin.y], "to": [reaction.destination.x, reaction.destination.y], "cost": 5, "movementRemaining": character.movement, "automatic": _context.processing_auto, "source": "classic"}))
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 654, "waitForCompletion": false, "source": "classic-friendly-swap"}))
		combat.pending_reaction = null
		return REACTION_COMPLETED
	var terrain_set: BattleTerrainSetDefinition = _context.automation().monster_actions().battle_terrain_set(content, combat.battlefield)
	var movement_available := state.party.character_by_id(reaction.mover_id).movement if reaction.kind == CombatReactionState.CHARACTER_MOVE else combat.turns.active_turn.movement_remaining
	var probe := _context.battlefield.probe_step(combat.battlefield, terrain_set, reaction.mover_id, reaction.destination - reaction.origin, movement_available)
	if not probe.allowed:
		events.append(DomainEvent.new(&"combat_movement_blocked", {"actorId": reaction.mover_id, "destination": [reaction.destination.x, reaction.destination.y], "reason": String(probe.reason), "source": "classic-after-guard"}))
		reaction.set_phase(CombatReactionState.GUARD_AFTER, guarding_hostiles(state, reaction.mover_id))
		return REACTION_COMPLETED
	if not combat.battlefield.actors.move_actor(reaction.mover_id, reaction.destination):
		return REACTION_MOVER_DEFEATED
	if reaction.kind == CombatReactionState.CHARACTER_MOVE:
		var character := state.party.character_by_id(reaction.mover_id)
		character.movement = maxi(0, character.movement - reaction.movement_cost)
		movement_remaining = character.movement
	else:
		combat.turns.active_turn.movement_remaining = maxi(0, combat.turns.active_turn.movement_remaining - reaction.movement_cost)
		movement_remaining = combat.turns.active_turn.movement_remaining
	events.append(DomainEvent.new(&"combatant_moved", {
		"actorId": reaction.mover_id,
		"from": [reaction.origin.x, reaction.origin.y],
		"to": [reaction.destination.x, reaction.destination.y],
		"cost": reaction.movement_cost,
		"movementRemaining": movement_remaining,
		"automatic": reaction.kind != CombatReactionState.CHARACTER_MOVE or _context.processing_auto,
	}))
	var terrain: BattleTerrainTileDefinition = terrain_set.tile_by_id(combat.battlefield.terrain.tile_at(reaction.destination)) if terrain_set != null else null
	if terrain != null and terrain.sound != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": terrain.sound, "waitForCompletion": terrain.sound < 0, "source": "classic-battle-movement"}))
	var collision_result: int = _context.fields().resolve_actor_collisions(state, content, reaction.mover_id, rng, events)
	if collision_result == CombatFlowFields.COLLISION_DEATH_MACRO:
		return REACTION_DEATH_MACRO
	if collision_result == CombatFlowFields.COLLISION_INVALID:
		events.append(DomainEvent.new(&"combat_persistent_field_collision_failed", {"actorId": reaction.mover_id, "reason": "invalid-runtime-state"}))
	if collision_result == CombatFlowFields.COLLISION_DEFEATED:
		return REACTION_MOVER_DEFEATED
	if reaction.kind == CombatReactionState.MONSTER_RETREAT and _context.automation().retreating_monster_reached_edge(state, content, reaction.mover_id, reaction.destination, events):
		reaction.set_phase(CombatReactionState.GUARD_AFTER, [])
		return REACTION_COMPLETED
	reaction.set_phase(CombatReactionState.GUARD_AFTER, guarding_hostiles(state, reaction.mover_id))
	return REACTION_COMPLETED


func resolve_reaction_attack(state: GameState, content: RealmzContent, attacker_id: String, reaction: CombatReactionState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	if not combatant_is_alive(state, attacker_id) or combatant_is_helpless(state, attacker_id):
		return REACTION_COMPLETED
	combat.actor_statuses.set_guarding(attacker_id, false)
	var action: StringName = &"withdrawal" if reaction.phase == CombatReactionState.WITHDRAWAL else &"guard"
	var behind := reaction.phase == CombatReactionState.WITHDRAWAL
	var character_attacker := state.party.character_by_id(attacker_id)
	if character_attacker != null:
		return resolve_character_reaction(state, content, character_attacker, reaction.mover_id, action, behind, rng, events)
	var monster_attacker := combat.roster.monster_by_id(attacker_id)
	if monster_attacker == null:
		return REACTION_COMPLETED
	return resolve_monster_reaction(state, content, monster_attacker, reaction.mover_id, action, behind, rng, events)


func resolve_character_reaction(state: GameState, content: RealmzContent, attacker: CharacterState, target_id: String, action: StringName, behind: bool, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	combat.turns.invalidate_undo()
	var equipment := _context.equipment.combat_equipment(attacker, content.items.definitions())
	if not equipment.valid:
		events.append(DomainEvent.new(&"combat_reaction_failed", {"actorId": attacker.id, "targetId": target_id, "reason": String(equipment.error_code)}))
		return REACTION_COMPLETED
	var monster_target := combat.roster.monster_by_id(target_id)
	if monster_target != null:
		var definition := content.combat.monster_by_id(monster_target.definition_id)
		var reaction_resolution := _context.combat.resolve_character_attack(attacker, equipment, monster_target, definition, rng, state.clock.day(), behind, true, combat.dropped_items.can_queue())
		if reaction_resolution.total_damage() > 0:
			combat.actor_statuses.mark_attacked(monster_target.id)
		if reaction_resolution.fumbled and not _context.actions().events().commit_character_fumble(state, content, attacker, equipment, events):
			events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": attacker.id, "reason": "invalid-fumble-state"}))
		_context.actions().events().append_character_attack_audio(events, attacker, equipment, reaction_resolution, &"monster")
		var reaction_event = _context.actions().events().character_attack_event(attacker.id, monster_target.id, &"monster", reaction_resolution, equipment.melee_weapon != null)
		append_reaction_identity(reaction_event, action, behind)
		events.append(reaction_event)
		if reaction_resolution.killed:
			combat.pending_reaction.mover_killed = true
			var death_macro_requested = _context.actions().events().request_monster_death_macro(monster_target, definition, events)
			_context.automation().remove_defeated_position(combat, monster_target.id, not death_macro_requested)
			return REACTION_DEATH_MACRO if death_macro_requested else REACTION_MOVER_DEFEATED
		return REACTION_COMPLETED
	var character_target := state.party.character_by_id(target_id)
	if character_target == null:
		return REACTION_COMPLETED
	var target_equipment := _context.equipment.combat_equipment(character_target, content.items.definitions())
	if not target_equipment.valid:
		events.append(DomainEvent.new(&"combat_reaction_failed", {"actorId": attacker.id, "targetId": target_id, "reason": String(target_equipment.error_code)}))
		return REACTION_COMPLETED
	var resolution := _context.combat.resolve_character_attack_character(attacker, equipment, character_target, target_equipment, rng, behind, true, combat.dropped_items.can_queue())
	if resolution.total_damage() > 0:
		combat.actor_statuses.mark_attacked(character_target.id)
	if resolution.fumbled and not _context.actions().events().commit_character_fumble(state, content, attacker, equipment, events):
		events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": attacker.id, "reason": "invalid-fumble-state"}))
	_context.actions().events().append_character_attack_audio(events, attacker, equipment, resolution, &"character")
	var event = _context.actions().events().character_attack_event(attacker.id, character_target.id, &"character", resolution, equipment.melee_weapon != null)
	append_reaction_identity(event, action, behind)
	events.append(event)
	if resolution.killed:
		combat.pending_reaction.mover_killed = true
		_context.actions().mark_character_bleeding(state, character_target, true)
		_context.automation().remove_defeated_position(combat, character_target.id, true)
		return REACTION_MOVER_DEFEATED
	return REACTION_COMPLETED


func resolve_monster_reaction(state: GameState, content: RealmzContent, attacker: MonsterState, target_id: String, action: StringName, behind: bool, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	combat.turns.invalidate_undo()
	var definition := content.combat.monster_by_id(attacker.definition_id)
	if definition == null:
		return REACTION_COMPLETED
	_context.automation().monster_actions().prepare_melee_weapon(attacker, definition, content)
	var weapon := content.items.item_by_id(attacker.weapon_id) if not attacker.weapon_id.is_empty() else null
	var character_target := state.party.character_by_id(target_id)
	if character_target != null:
		return _resolve_monster_character_reaction(state, content, attacker, definition, weapon, character_target, action, behind, rng, events)
	var monster_target := combat.roster.monster_by_id(target_id)
	if monster_target == null:
		return REACTION_COMPLETED
	return _resolve_monster_monster_reaction(state, content, attacker, definition, weapon, monster_target, action, behind, rng, events)


func _resolve_monster_character_reaction(state: GameState, content: RealmzContent, attacker: MonsterState, definition: MonsterDefinition, weapon: ItemDefinition, target: CharacterState, action: StringName, behind: bool, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var race := content.characters.race_by_id(target.race_id)
	var caste := content.characters.caste_by_id(target.caste_id)
	var charm_bonus := 50 if state.party.conditions.is_active(ConditionRules.PARTY_CHARM_RESISTANCE) else 0
	var defender_equipment := _context.equipment.combat_equipment(target, content.items.definitions())
	var defender_luck := defender_equipment.effective_luck if defender_equipment.valid else target.luck
	var defender_armor := defender_equipment.effective_armor if defender_equipment.valid else target.armor
	var reaction_context := MonsterAttackContext.new(weapon, state.clock.day(), behind, defender_luck, state.party.conditions.is_active(ConditionRules.PARTY_DRAGON_HIDE), defender_armor)
	var resolution := _context.combat.resolve_monster_attack(attacker, definition, 0, target, race, caste, rng, charm_bonus, reaction_context, true)
	if resolution.total_damage() > 0:
		combat.actor_statuses.mark_attacked(target.id)
	if resolution.fumbled:
		_context.actions().events().commit_monster_fumble(attacker, events)
	if resolution.special_handled:
		_context.actions().events().append_monster_special_events(events, attacker.id, target.id, &"character", resolution)
		if resolution.aging != null and resolution.aging.changed_group():
			events.append(DomainEvent.new(&"character_age_changed", resolution.aging.event_payload(target, race)))
			combat.pending_monster_attack = PendingMonsterAttack.new(attacker.id, target.id, action, resolution.damage, resolution.chance, resolution.roll, resolution.weapon_condition_index, resolution.weapon_condition_before, resolution.weapon_condition_after, resolution.physical_feedback_sound_id)
			return REACTION_WAITING
	_context.actions().events().append_monster_physical_feedback(events, resolution.physical_feedback_sound_id)
	_context.actions().events().append_monster_attack_audio(events, attacker, definition, 0, weapon, resolution, rng)
	var event := DomainEvent.new(&"combat_attack_resolved", {"actorId": attacker.id, "targetId": target.id, "targetKind": "character", "action": String(action), "attackIndex": 0, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll})
	_context.actions().events().append_physical_result_effect(event, resolution.hit, weapon != null)
	append_reaction_identity(event, action, behind)
	events.append(event)
	if not resolution.killed:
		return REACTION_COMPLETED
	combat.pending_reaction.mover_killed = true
	_context.actions().mark_character_bleeding(state, target, true)
	_context.automation().remove_defeated_position(combat, target.id, true)
	return REACTION_MOVER_DEFEATED


func _resolve_monster_monster_reaction(state: GameState, content: RealmzContent, attacker: MonsterState, definition: MonsterDefinition, weapon: ItemDefinition, target: MonsterState, action: StringName, behind: bool, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var target_definition := content.combat.monster_by_id(target.definition_id)
	var context := MonsterAttackContext.new(weapon, state.clock.day(), behind)
	var resolution := _context.combat.resolve_monster_attack_monster(attacker, definition, 0, target, target_definition, rng, context, true)
	if resolution.total_damage() > 0:
		combat.actor_statuses.mark_attacked(target.id)
	if resolution.fumbled:
		_context.actions().events().commit_monster_fumble(attacker, events)
	if resolution.special_handled:
		_context.actions().events().append_monster_special_events(events, attacker.id, target.id, &"monster", resolution)
	_context.actions().events().append_monster_attack_audio(events, attacker, definition, 0, weapon, resolution, rng)
	var event := DomainEvent.new(&"combat_attack_resolved", {"actorId": attacker.id, "targetId": target.id, "targetKind": "monster", "action": String(action), "attackIndex": 0, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll})
	_context.actions().events().append_physical_result_effect(event, resolution.hit, weapon != null)
	append_reaction_identity(event, action, behind)
	events.append(event)
	if resolution.killed:
		combat.pending_reaction.mover_killed = true
		var death_macro_requested = _context.actions().events().request_monster_death_macro(target, target_definition, events)
		_context.automation().remove_defeated_position(combat, target.id, not death_macro_requested)
		return REACTION_DEATH_MACRO if death_macro_requested else REACTION_MOVER_DEFEATED
	return REACTION_COMPLETED


static func append_reaction_identity(event: DomainEvent, action: StringName, behind: bool) -> void:
	event.payload["action"] = String(action)
	event.payload["reaction"] = true
	event.payload["behind"] = behind
	event.payload["automatic"] = true


func guarding_hostiles(state: GameState, mover_id: String, anchor_override: Vector2i = Vector2i(-1, -1)) -> Array[String]:
	var result: Array[String] = []
	for attacker_id: String in _context.automation().hostile_adjacent_ids(state, mover_id, anchor_override):
		if state.combat.actor_statuses.is_guarding(attacker_id) and not combatant_is_helpless(state, attacker_id):
			result.append(attacker_id)
	return result


func withdrawal_hostiles(state: GameState, reaction: CombatReactionState) -> Array[String]:
	var result: Array[String] = []
	if combatant_is_invisible(state, reaction.mover_id):
		return result
	var after := _context.battlefield.adjacent_actor_ids(state.combat.battlefield, reaction.mover_id, reaction.destination)
	for attacker_id: String in reaction.origin_hostiles():
		if not after.has(attacker_id) and not combatant_is_helpless(state, attacker_id):
			result.append(attacker_id)
	return result


func guarding_actor_ids(state: GameState, actor_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for actor_id: String in actor_ids:
		if state.combat.actor_statuses.is_guarding(actor_id) and not combatant_is_helpless(state, actor_id):
			result.append(actor_id)
	return result


func combatant_is_alive(state: GameState, actor_id: String) -> bool:
	var character := state.party.character_by_id(actor_id)
	if character != null:
		return character.current_health > 0
	var monster := state.combat.roster.monster_by_id(actor_id) if state.combat != null else null
	return monster != null and monster.current_health > 0


func combatant_is_helpless(state: GameState, actor_id: String) -> bool:
	var character := state.party.character_by_id(actor_id)
	if character != null:
		return character.conditions.is_active(ConditionRules.HELPLESS)
	var monster := state.combat.roster.monster_by_id(actor_id) if state.combat != null else null
	return monster != null and monster.conditions.is_active(ConditionRules.HELPLESS)


func combatant_is_invisible(state: GameState, actor_id: String) -> bool:
	var character := state.party.character_by_id(actor_id)
	if character != null:
		return character.conditions.is_active(ConditionRules.INVISIBLE)
	var monster := state.combat.roster.monster_by_id(actor_id) if state.combat != null else null
	return monster != null and monster.conditions.is_active(ConditionRules.INVISIBLE)


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
