## Resolves movement and automatic attacks for animated party actors.

class_name CombatCharmedCharacterAutomation
extends RefCounted

const ATTACKED := 0
const NO_TARGET := 1
const DEATH_MACRO := 2
## A spell death-macro sequence owns the rest of the activation and advances the turn when it completes.
const MACRO_SEQUENCE := 3

var _context: CombatContext
var _monster_actions: CombatMonsterActions
var _occupancy: CombatOccupancyRules
var failure_result: CombatFlowResult


func _init(context: CombatContext, monster_actions: CombatMonsterActions) -> void:
	_context = context
	_monster_actions = monster_actions
	_occupancy = CombatOccupancyRules.new(context)


func advance_charmed_character(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	_context.actions().prepare_character_turn(combat, actor)
	if combat.pending_reaction == null and not _occupancy.hostile_adjacent_ids(state, actor.id).is_empty(): return 0
	var terrain := _monster_actions.battle_terrain_set(content, combat.battlefield)
	var targets: Array[String] = []
	for id: String in combat.battlefield.actors.actor_ids():
		if id != actor.id and not CombatAiTargetFacts.character_is_friendly(state, actor, id) and CombatAiTargetFacts.health(state, id) > 0:
			targets.append(id)
	var visited: Array[Vector2i] = []
	while actor.movement > 0 and actor.current_health > 0:
		if combat.pending_reaction != null:
			var continuation: int = _context.reactions().continue_pending_reaction(state, content, rng, events)
			if continuation != 0: return continuation
		if not _occupancy.hostile_adjacent_ids(state, actor.id).is_empty(): return 0
		var origin := combat.battlefield.actors.actor_position(actor.id)
		visited.append(origin)
		var retained := combat.turns.active_turn.target_id
		var candidates: Array[String] = targets.duplicate()
		if targets.has(retained): candidates.assign([retained])
		var step: BattlefieldStepResult = null
		for target_id: String in candidates:
			step = _context.battlefield.probe_path_step_toward_actors(combat.battlefield, terrain, actor.id, [target_id], actor.movement, [], visited)
			if step.allowed:
				combat.turns.active_turn.target_id = target_id
				break
		if step == null or not step.allowed: return 0
		combat.pending_reaction = CombatReactionState.new(CombatReactionState.CHARACTER_MOVE, actor.id, origin, step.destination, step.movement_cost)
		combat.pending_reaction.set_origin_hostiles([])
		combat.pending_reaction.set_phase(CombatReactionState.GUARD_BEFORE, [])
	return 0


## Fires one automatic missile, or reports NO_TARGET so the activation moves and strikes in melee.
## Castle tomissle (tomissle-weap.c) shoots only with no adjacent enemy and a single-target missile
## weapon; combatinfo-combatchoice.c:393-466 then fires at an opposed actor within spell range.
func process_charmed_missile(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	failure_result = null
	var combat := state.combat
	if combat.pending_reaction != null or not _occupancy.hostile_adjacent_ids(state, actor.id).is_empty():
		return NO_TARGET
	var equipment := _context.equipment.combat_equipment(actor, content.items.definitions())
	if not equipment.valid:
		failure_result = CombatFlowResult.failed(equipment.error_code, equipment.error_message)
		return NO_TARGET
	if equipment.missile_weapon == null:
		return NO_TARGET
	var weapon_spell := content.magic.spell_by_classic_id(absi(equipment.missile_weapon.special_2))
	if weapon_spell == null or weapon_spell.target_type != 1:
		return NO_TARGET
	_context.actions().prepare_character_turn(combat, actor)
	var profile := _context.reactions().character_projectile_profile(actor, content, equipment, state)
	if profile.error_code == &"projectile_power_roll_required":
		# Castle rolls Rand(7) for a power-eight missile before choosing its target.
		var power := rng.draw(7, StringName("combat.projectile.%s.power" % profile.item_instance_id))
		if not combat.turns.stage_random_item_power(actor.id, profile.item_instance_id, power, profile.item.id if state.adventure_rules.free_targeting_cancellation else ""):
			failure_result = CombatFlowResult.failed(&"projectile_power_roll_unavailable", "The animated missile power could not be staged.")
			return NO_TARGET
		profile = _context.reactions().character_projectile_profile(actor, content, equipment, state)
	# Area and ray ammunition keep melee: Rebuilt does not invent an actor-centered area for them.
	if not profile.available or profile.spell.target_type != 1:
		return NO_TARGET
	var target_id := _missile_target(state, content, actor, profile)
	if target_id.is_empty():
		return NO_TARGET
	combat.turns.active_turn.target_id = target_id
	# Castle sets toggle on an animated shot, so the character stays in missile mode afterwards.
	combat.actor_statuses.set_character_weapon_mode(actor.id, &"missile")
	var monster := combat.roster.monster_by_id(target_id)
	if monster != null and ClassicSpellSourceRules.is_supported_projectile_item_profile(profile.spell):
		return _fire_physical_missile(state, content, actor, profile, monster, rng, events)
	return _fire_item_missile(state, content, actor, profile, target_id, rng, events)


## Keeps the retained opponent when it is still a legal shot, otherwise takes the first in stable actor order.
## Castle redraws a random target until one is in range; Rebuilt picks deterministically and requires LOS.
func _missile_target(state: GameState, content: RealmzContent, actor: CharacterState, profile: ProjectileAttackProfile) -> String:
	var combat := state.combat
	var needs_sight := profile.spell.range_min + profile.spell.range_max > 0
	var candidates: Array[String] = []
	var retained := combat.turns.active_turn.target_id
	if not retained.is_empty():
		candidates.append(retained)
	candidates.append_array(combat.battlefield.actors.actor_ids())
	for id: String in candidates:
		if id == actor.id or CombatAiTargetFacts.character_is_friendly(state, actor, id) or CombatAiTargetFacts.health(state, id) <= 0:
			continue
		if _context.reactions().projectile_target_is_valid(combat, content, actor.id, id, profile.maximum_range, needs_sight):
			return id
	return ""


func _fire_physical_missile(state: GameState, content: RealmzContent, actor: CharacterState, profile: ProjectileAttackProfile, target: MonsterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var definition := content.combat.monster_by_id(target.definition_id)
	var caste := content.characters.caste_by_id(actor.caste_id)
	if definition == null or caste == null:
		failure_result = CombatFlowResult.failed(&"projectile_target_unavailable", "Animated missile resolution requires the target monster and caster caste definitions.")
		return NO_TARGET
	if not _context.inventory.use_charge(actor, profile.item_instance_id, profile.item):
		failure_result = CombatFlowResult.failed(&"projectile_charge_unavailable", "The animated missile charge could not be consumed atomically.")
		return NO_TARGET
	combat.turns.invalidate_undo()
	var resolution := _context.magic.resolve_character_projectile(actor, caste, profile.item, target, profile.spell, profile.power_level, rng)
	if resolution == null:
		failure_result = CombatFlowResult.failed(&"unsupported_projectile_spell", "The animated missile cannot be resolved by the source-backed missile rules.")
		return NO_TARGET
	actor.lifetime_record.add_projectile_damage_given(resolution.total_damage, resolution.hit_count, resolution.miss_count, resolution.target_defeated)
	if resolution.total_damage > 0:
		combat.actor_statuses.mark_attacked(target.id)
	combat.turns.active_turn.commit_physical_action()
	combat.turns.consume_random_item_power(profile.item_instance_id)
	# Castle combatinfo-combatchoice.c:458 spends two half-attacks and no movement on an animated shot.
	actor.attacks_remaining = _context.arithmetic.signed_16(actor.attacks_remaining - 2)
	CombatSpellEventBuilder.append_weapon_projectile(events, actor.id, target.id, profile.spell, resolution, "classic-combat-projectile")
	events.append(DomainEvent.new(&"combat_projectile_resolved", {
		"actorId": actor.id,
		"targetId": target.id,
		"targetKind": "monster",
		"itemId": profile.item.id,
		"spellId": profile.spell.id,
		"special": absi(profile.spell.special),
		"powerLevel": profile.power_level,
		"range": _context.battlefield.classic_range(combat.battlefield, actor.id, target.id),
		"hitCount": resolution.hit_count,
		"missCount": resolution.miss_count,
		"damage": resolution.total_damage,
		"defeated": resolution.target_defeated,
		"automatic": true,
		"source": "classic",
	}))
	var death_macro_requested := resolution.target_defeated and CombatDeathMacroOperations.request_immediate(combat, target, definition, events)
	CombatOccupancyRules.remove_defeated_position(combat, target.id, resolution.target_defeated and not death_macro_requested)
	return DEATH_MACRO if death_macro_requested else ATTACKED


func _fire_item_missile(state: GameState, content: RealmzContent, actor: CharacterState, profile: ProjectileAttackProfile, target_id: String, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var result := _context.magic_flow().fire_animated_item_missile(state, content, actor, profile.item_instance_id, target_id, profile.power_level, rng)
	if not result.ok:
		failure_result = result
		return NO_TARGET
	events.append_array(result.events)
	return MACRO_SEQUENCE if not state.combat.death_macros.actor_id().is_empty() else ATTACKED


## Resolves one automatic melee attack and reports ATTACKED, NO_TARGET or DEATH_MACRO.
func process_charmed_character_turn(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	failure_result = null
	var adjacent_ids := _context.battlefield.adjacent_actor_ids(state.combat.battlefield, actor.id)
	var character_targets: Array[CharacterState] = []
	for candidate: CharacterState in state.party.characters():
		if candidate.id != actor.id and candidate.current_health > 0 and candidate.classic_traitor != actor.classic_traitor and adjacent_ids.has(candidate.id):
			character_targets.append(candidate)
	var monster_targets: Array[MonsterState] = []
	for candidate: MonsterState in state.combat.roster.monsters():
		if candidate.current_health > 0 and candidate.classic_traitor != actor.classic_traitor and adjacent_ids.has(candidate.id):
			monster_targets.append(candidate)
	var target_count := character_targets.size() + monster_targets.size()
	if target_count == 0:
		return NO_TARGET
	var target_index := 0
	var equipment := _context.equipment.combat_equipment(actor, content.items.definitions())
	if not equipment.valid:
		failure_result = CombatFlowResult.failed(equipment.error_code, equipment.error_message)
		return NO_TARGET
	var active_turn := state.combat.turns.begin_active_turn()
	if active_turn == null:
		failure_result = CombatFlowResult.failed(&"invalid_combat_turn", "Charmed actor '%s' has no active turn." % actor.id)
		return NO_TARGET
	# Castle combatinfo-combatchoice.c:1700-1701 spends movement and two half-attacks before attack().
	_context.actions().consume_character_attack(actor)
	if target_index < character_targets.size():
		return _resolve_charmed_attack_character(state, content, actor, equipment, character_targets[target_index], active_turn, rng, events)
	var monster_target := monster_targets[target_index - character_targets.size()]
	var target_definition := content.combat.monster_by_id(monster_target.definition_id)
	if target_definition == null:
		failure_result = CombatFlowResult.failed(&"missing_monster_definition", "Charmed target '%s' has no monster definition." % monster_target.id)
		return NO_TARGET
	active_turn.physical_action_committed = true
	active_turn.classic_physical_active = true
	var resolution := _context.combat.resolve_character_attack(actor, equipment, monster_target, target_definition, rng, state.clock.day(), false, true, state.combat.dropped_items.can_queue())
	if resolution.total_damage() > 0:
		state.combat.actor_statuses.mark_attacked(monster_target.id)
	if resolution.fumbled and not _context.actions().events().commit_character_fumble(state, content, actor, equipment, events):
		failure_result = CombatFlowResult.failed(&"invalid_fumble_state", "Charmed actor '%s' could not commit its fumble." % actor.id)
		return NO_TARGET
	var event := _context.actions().events().character_attack_event(actor.id, monster_target.id, &"monster", resolution, equipment.melee_weapon != null)
	_context.actions().events().append_character_attack_audio(events, actor, equipment, resolution, &"monster", monster_target.id)
	event.payload["automatic"] = true
	events.append(event)
	if resolution.reflected:
		_context.actions().mark_character_bleeding(state, actor, resolution.killed)
		CombatOccupancyRules.remove_defeated_position(state.combat, actor.id, resolution.killed)
		return ATTACKED
	var death_macro_requested := resolution.killed and CombatDeathMacroOperations.request_immediate(state.combat, monster_target, target_definition, events)
	CombatOccupancyRules.remove_defeated_position(state.combat, monster_target.id, resolution.killed and not death_macro_requested)
	return DEATH_MACRO if death_macro_requested else ATTACKED


func _resolve_charmed_attack_character(state: GameState, content: RealmzContent, actor: CharacterState, equipment: CharacterCombatEquipment, target: CharacterState, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var target_equipment := _context.equipment.combat_equipment(target, content.items.definitions())
	if not target_equipment.valid:
		failure_result = CombatFlowResult.failed(target_equipment.error_code, target_equipment.error_message)
		return NO_TARGET
	active_turn.physical_action_committed = true
	active_turn.classic_physical_active = true
	var resolution := _context.combat.resolve_character_attack_character(actor, equipment, target, target_equipment, rng, false, true, state.combat.dropped_items.can_queue())
	if resolution.total_damage() > 0:
		state.combat.actor_statuses.mark_attacked(target.id)
	if resolution.fumbled and not _context.actions().events().commit_character_fumble(state, content, actor, equipment, events):
		failure_result = CombatFlowResult.failed(&"invalid_fumble_state", "Charmed actor '%s' could not commit its fumble." % actor.id)
		return NO_TARGET
	var character_event := _context.actions().events().character_attack_event(actor.id, target.id, &"character", resolution, equipment.melee_weapon != null)
	_context.actions().events().append_character_attack_audio(events, actor, equipment, resolution, &"character", target.id)
	character_event.payload["automatic"] = true
	events.append(character_event)
	var victim: CharacterState = actor if resolution.reflected else target
	_context.actions().mark_character_bleeding(state, victim, resolution.killed)
	CombatOccupancyRules.remove_defeated_position(state.combat, victim.id, resolution.killed)
	return ATTACKED
