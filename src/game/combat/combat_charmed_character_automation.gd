## Resolves movement and automatic attacks for animated party actors: charmed, confused and frightened.

class_name CombatCharmedCharacterAutomation
extends RefCounted

const ATTACKED := 0
const NO_TARGET := 1
const DEATH_MACRO := 2
## A spell death-macro sequence owns the rest of the activation and advances the turn when it completes.
const MACRO_SEQUENCE := 3
## Castle actor-slot layout used by the animated missile target loop (variables.h maxloopminus and maxmon).
const CLASSIC_PARTY_SLOT_COUNT := 6
const CLASSIC_FIRST_MONSTER_SLOT := 10
const CLASSIC_LAST_ACTOR_SLOT := 109
const CLASSIC_MONSTER_SLOT_COUNT := 100
## Bounds the redraw loop; getrange already guarantees a reachable target, so Castle never needs this many draws.
const CLASSIC_TARGET_LOOP_LIMIT := 100_000
## Castle loopposs guards once its pass counter, starting at -1, exceeds twenty.
const CLASSIC_JUKE_PASSES := 20
const APPROACH_CONTACT := 10
const APPROACH_STEPPED := 11
const APPROACH_GUARDED := 12
const APPROACH_NO_TARGET := 13
## The character waits for the player's Embrace Cowardice or Stay and Fight answer.
const APPROACH_FLEE_QUESTION := 14
## The character left the battle from the outermost battlefield cells.
const APPROACH_FLED := 15
const DUTY_NONE := 0
const DUTY_BANDAGED := 1
const DUTY_TURNED := 2
const EDGE_NONE := 0
const EDGE_QUESTION := 1
const EDGE_FORCED := 2
## Castle's large battle view (screensize 1) keeps an actor in its window only at field cells 1-87.
const CLASSIC_WINDOW_FIRST_CELL := 1
const CLASSIC_WINDOW_LAST_CELL := 87

var _context: CombatContext
var _monster_actions: CombatMonsterActions
var _occupancy: CombatOccupancyRules
var failure_result: CombatFlowResult
## Opponent selected for melee by the last APPROACH_CONTACT result.
var contact_target_id: String = ""


func _init(context: CombatContext, monster_actions: CombatMonsterActions) -> void:
	_context = context
	_monster_actions = monster_actions
	_occupancy = CombatOccupancyRules.new(context)


## Castle forcemove (combatinfo-combatchoice.c:1497-1866) for one combatchoice of an animated character; a
## fleeing one reverses its step. Returns APPROACH_CONTACT with contact_target_id set when it strikes an opposed
## actor; APPROACH_STEPPED after a step, swap or zero juke, so the next combatchoice decides again; APPROACH_GUARDED
## when juke passes or movement run out; APPROACH_NO_TARGET without an opponent; APPROACH_FLEE_QUESTION or
## APPROACH_FLED at the battlefield edge; otherwise the result of a suspended reaction.
func advance_charmed_character(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent], fleeing: bool = false) -> int:
	var combat := state.combat
	contact_target_id = ""
	failure_result = null
	_context.actions().prepare_character_turn(combat, actor)
	var resumed := combat.pending_reaction != null
	if resumed:
		var continuation: int = _context.reactions().continue_pending_reaction(state, content, rng, events)
		if continuation != 0:
			return continuation
	if combat.turns.active_turn.juke_step_cost > 0:
		return _resume_juke(state, content, actor, rng, events)
	if resumed:
		return APPROACH_STEPPED
	var origin := combat.battlefield.actors.actor_position(actor.id)
	var edge := classic_window_edge(origin)
	if edge == EDGE_FORCED:
		return _flee_battle(state, content, actor, origin, rng, events)
	if edge == EDGE_QUESTION:
		combat.turns.active_turn.action = CombatActivationConditions.FLEE_QUESTION_ACTION
		events.append(DomainEvent.new(&"combat_flee_question_requested", {"actorId": actor.id, "source": "classic"}))
		return APPROACH_FLEE_QUESTION
	var adjacent := _first_adjacent_opponent(state, actor)
	if not fleeing and not adjacent.is_empty():
		var toward := combat.battlefield.actors.actor_position(adjacent) - origin
		var guards := _guard_strikes(state, content, actor, origin + Vector2i(signi(toward.x), signi(toward.y)), rng, events)
		return guards if guards != APPROACH_CONTACT else _contact(state, actor, adjacent)
	var target_id := adjacent
	if adjacent.is_empty():
		target_id = _approach_target(state, actor, rng)
	else:
		combat.turns.set_character_target(actor.id, adjacent)
		combat.turns.active_turn.target_id = adjacent
	if target_id.is_empty():
		return APPROACH_NO_TARGET
	var goal := combat.battlefield.actors.actor_position(target_id)
	var direction := Vector2i(signi(goal.x - origin.x), signi(goal.y - origin.y))
	if fleeing:
		direction = -direction
		# moveforward's checkforenemy(0) lets guarding neighbors strike before the fleeing step.
		var guards := _guard_strikes(state, content, actor, origin + direction, rng, events)
		if guards != APPROACH_CONTACT:
			return guards
	return _step_or_juke(state, content, actor, direction, rng, events)


## Castle forcemove's window check on the large battle view (inwindow, centerfield, canflee). The camera keeps
## the acting character inside cells 1-87 whenever it can, so only the outermost cells leave it outside: cell 0
## or 89 forces flight, and cell 88 asks Embrace Cowardice or Stay and Fight.
static func classic_window_edge(position: Vector2i) -> int:
	if position.x >= CLASSIC_WINDOW_FIRST_CELL and position.x <= CLASSIC_WINDOW_LAST_CELL and position.y >= CLASSIC_WINDOW_FIRST_CELL and position.y <= CLASSIC_WINDOW_LAST_CELL:
		return EDGE_NONE
	if position.x < 1 or position.y < 1 or position.x > 88 or position.y > 88:
		return EDGE_FORCED
	return EDGE_QUESTION


## An animated character's flight from its own cell (destination == origin): Castle forcemove's canflee forces it
## from cells 0 and 89, and the Embrace Cowardice answer releases it from cell 88.
static func probe_edge_flight(combat: CombatState, origin: Vector2i, direction: Vector2i) -> CombatRetreatProbe:
	var turn := combat.turns.active_turn if direction == Vector2i.ZERO else null
	var edge := classic_window_edge(origin)
	if turn != null and edge == EDGE_FORCED and turn.action in [CombatActivationConditions.ANIMATED_ACTION, CombatActivationConditions.FLEEING_ACTION]:
		return CombatRetreatProbe.permitted(127, true)
	if turn != null and edge == EDGE_QUESTION and turn.action == CombatActivationConditions.FLEE_QUESTION_ACTION:
		return CombatRetreatProbe.permitted(127, false)
	return CombatRetreatProbe.blocked(&"invalid_direction", "Battlefield-edge retreat requires one adjacent movement direction.")


## Castle combatinfo-combatchoice.c:205-275: an animated loyal character that is not fleeing first bandages the
## first bleeding party member, which ends its activation, then turns undead once when it can.
func process_loyal_duties(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	failure_result = null
	var combat := state.combat
	var bleeding := _context.actions().bandage_candidate_ids(state)
	if not bleeding.is_empty():
		_context.actions().prepare_character_turn(combat, actor)
		if not combat.actor_statuses.set_character_bleeding(bleeding[0], false):
			failure_result = CombatFlowResult.failed(&"invalid_bandage_target", "The bleeding state could not be cleared.")
			return DUTY_NONE
		var roll := rng.draw(100, StringName("combat.animated.%s.bandage-sound" % actor.id))
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 10105, "waitForCompletion": false, "source": "classic-combat-bandage"}))
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 10121 if roll < 50 else 10123, "waitForCompletion": false, "source": "classic-combat-auto-bandage"}))
		events.append(DomainEvent.new(&"combatant_bandaged", {"actorId": actor.id, "targetId": bleeding[0], "automatic": true, "source": "classic"}))
		actor.attacks_remaining = 0
		return DUTY_BANDAGED
	if not _context.actions().probe_turn_undead(state, content, actor.id).allowed:
		return DUTY_NONE
	var turned := _context.actions().turn_undead(state, content, actor, rng)
	if not turned.ok:
		failure_result = turned
		return DUTY_NONE
	events.append_array(turned.events)
	return DUTY_TURNED


func _flee_battle(state: GameState, content: RealmzContent, actor: CharacterState, origin: Vector2i, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var fled := _context.reactions().retreat_character(state, content, actor.id, &"edge", origin, rng, false)
	if not fled.ok:
		failure_result = fled
		return APPROACH_GUARDED
	events.append(DomainEvent.new(&"classic_notification_requested", {"text": "Sorry...This PCs position forces him to flee from battle.", "soundId": 6000, "source": "classic-forced-flee"}))
	events.append_array(fled.events)
	return APPROACH_FLED


## Castle checkforenemy(1) scans the surrounding cells row by row; enemy[0] is the first opposed actor found.
func _first_adjacent_opponent(state: GameState, actor: CharacterState) -> String:
	var actors := state.combat.battlefield.actors
	var origin := actors.actor_position(actor.id)
	for dy: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			var id := actors.actor_at(origin + Vector2i(dx, dy), actor.id)
			if not id.is_empty() and _is_present_opponent(state, actor, id):
				return id
	return ""


## Castle treats an opposed party member still in battle, or an opposed monster with stamina, as an enemy.
func _is_present_opponent(state: GameState, actor: CharacterState, id: String) -> bool:
	if CombatAiTargetFacts.character_is_friendly(state, actor, id) or not state.combat.battlefield.actors.has_actor(id):
		return false
	return state.party.character_by_id(id) != null or CombatAiTargetFacts.health(state, id) > 0


## Castle moveforward runs checkforenemy(0) before the blow or fleeing step: each guarding adjacent opponent
## strikes first and stops guarding. Returns APPROACH_CONTACT when the choice may go on, otherwise the suspended
## reaction result.
func _guard_strikes(state: GameState, content: RealmzContent, actor: CharacterState, destination: Vector2i, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var guards := _context.reactions().guarding_hostiles(state, actor.id)
	if guards.is_empty():
		return APPROACH_CONTACT
	var origin := state.combat.battlefield.actors.actor_position(actor.id)
	var reaction := CombatReactionState.new(CombatReactionState.CHARACTER_MOVE, actor.id, origin, destination, 0)
	reaction.set_origin_hostiles(_context.automation().hostile_adjacent_ids(state, actor.id))
	reaction.set_phase(CombatReactionState.GUARD_AFTER, guards)
	state.combat.pending_reaction = reaction
	var result: int = _context.reactions().continue_pending_reaction(state, content, rng, events)
	if result != 0:
		return result
	return APPROACH_CONTACT if actor.current_health > 0 else CombatActivationConditions.REACTION_MOVER_DEFEATED


func _contact(state: GameState, actor: CharacterState, target_id: String) -> int:
	state.combat.turns.set_character_target(actor.id, target_id)
	state.combat.turns.active_turn.target_id = target_id
	contact_target_id = target_id
	return APPROACH_CONTACT


## Castle combatinfo-combatchoice.c:1527-1557 keeps c[].target while it is a living opponent in battle, otherwise
## redraws randrange(0, maxloopminus) until a party or monster slot holds one.
func _approach_target(state: GameState, actor: CharacterState, rng: RealmzRng) -> String:
	var retained := state.combat.turns.character_target(actor.id)
	if not retained.is_empty() and _is_present_opponent(state, actor, retained) and CombatAiTargetFacts.health(state, retained) > 0:
		state.combat.turns.active_turn.target_id = retained
		return retained
	# Castle ends the battle before another combatchoice once no opponent stands; never redraw for nobody.
	if not state.combat.battlefield.actors.actor_ids().any(func(id: String) -> bool: return _is_present_opponent(state, actor, id) and CombatAiTargetFacts.health(state, id) > 0):
		return ""
	for _guard: int in CLASSIC_TARGET_LOOP_LIMIT:
		var id := _slot_actor(state, rng.draw_between(0, CLASSIC_LAST_ACTOR_SLOT, &"combat.charmed_approach.target"))
		if not id.is_empty() and _is_present_opponent(state, actor, id) and CombatAiTargetFacts.health(state, id) > 0:
			state.combat.turns.set_character_target(actor.id, id)
			state.combat.turns.active_turn.target_id = id
			return id
	return ""


## Castle moveforward/loopposs: try the step; when blocked, juke by -2 + Rand(3) on each axis, and guard
## after more than twenty passes or once movement is spent. A blocking friend swaps places for five movement.
func _step_or_juke(state: GameState, content: RealmzContent, actor: CharacterState, direction: Vector2i, rng: RealmzRng, events: Array[DomainEvent], passes: int = -1, juking: bool = false) -> int:
	var combat := state.combat
	var terrain := _monster_actions.battle_terrain_set(content, combat.battlefield)
	for _guard: int in CLASSIC_TARGET_LOOP_LIMIT:
		if juking:
			var previous := passes
			passes += 1
			if previous > CLASSIC_JUKE_PASSES or actor.movement < 1:
				return _guard_activation(state, actor)
			var juke_x := rng.draw(3, &"combat.charmed_approach.juke_x") - 2
			direction = Vector2i(juke_x, rng.draw(3, &"combat.charmed_approach.juke_y") - 2)
		juking = true
		if direction == Vector2i.ZERO:
			return APPROACH_STEPPED
		var origin := combat.battlefield.actors.actor_position(actor.id)
		var probe := _context.battlefield.probe_step(combat.battlefield, terrain, actor.id, direction, actor.movement)
		if probe.reason == &"occupied":
			if _is_present_opponent(state, actor, probe.occupant_id):
				return _contact(state, actor, probe.occupant_id)
			if _can_swap(state, actor, probe.occupant_id):
				return _begin_step(state, content, actor, origin, probe.destination, 5, probe.occupant_id, rng, events)
			continue
		if not probe.allowed:
			continue
		var result := _begin_step(state, content, actor, origin, probe.destination, probe.movement_cost, "", rng, events)
		if combat.pending_reaction != null and actor.current_health > 0:
			# The step waits on a reaction; its resumption continues this loop (_resume_juke).
			combat.turns.active_turn.juke_passes = passes
			combat.turns.active_turn.juke_step_cost = probe.movement_cost
		# Castle juke-checks again when the movement left cannot pay for the step just taken.
		if result != APPROACH_STEPPED or actor.current_health <= 0 or actor.movement >= probe.movement_cost:
			return result
	return _guard_activation(state, actor)


## Continues the juke loop of a step that waited on a reaction, once that step has finished.
func _resume_juke(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var turn := state.combat.turns.active_turn
	var cost := turn.juke_step_cost
	turn.juke_step_cost = 0
	if actor.current_health <= 0 or not state.combat.battlefield.actors.has_actor(actor.id) or actor.movement >= cost:
		return APPROACH_STEPPED
	return _step_or_juke(state, content, actor, Vector2i.ZERO, rng, events, turn.juke_passes, true)


## Castle swaps an animated character with a blocking friend when it has more than four movement and the friend
## is a party member or a single-square monster.
func _can_swap(state: GameState, actor: CharacterState, occupant_id: String) -> bool:
	if actor.movement <= 4 or not CombatAiTargetFacts.character_is_friendly(state, actor, occupant_id):
		return false
	return state.party.character_by_id(occupant_id) != null or state.combat.battlefield.actors.actor_size(occupant_id) == 0


func _begin_step(state: GameState, content: RealmzContent, actor: CharacterState, origin: Vector2i, destination: Vector2i, cost: int, swap_id: String, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var reaction := CombatReactionState.new(CombatReactionState.CHARACTER_MOVE, actor.id, origin, destination, cost)
	reaction.set_origin_hostiles(_context.automation().hostile_adjacent_ids(state, actor.id))
	if not swap_id.is_empty():
		reaction.friendly_collision_target_id = swap_id
		reaction.friendly_collision_action = &"swap"
	# Castle's checkforenemy(0) for this combatchoice already ran (_guard_strikes) or had no adjacent opponent.
	reaction.set_phase(CombatReactionState.GUARD_BEFORE, [])
	combat.pending_reaction = reaction
	var continuation: int = _context.reactions().continue_pending_reaction(state, content, rng, events)
	return continuation if continuation != 0 else APPROACH_STEPPED


func _guard_activation(state: GameState, actor: CharacterState) -> int:
	state.combat.actor_statuses.set_guarding(actor.id, true)
	return APPROACH_GUARDED


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
	if not profile.available or CombatFlowSummoning.is_summon_spell(profile.spell):
		return NO_TARGET
	var target_id := _missile_target(state, content, actor, profile, rng)
	if target_id.is_empty():
		return NO_TARGET
	combat.turns.active_turn.target_id = target_id
	# Castle sets toggle on an animated shot, so the character stays in missile mode afterwards.
	combat.actor_statuses.set_character_weapon_mode(actor.id, &"missile")
	var monster := combat.roster.monster_by_id(target_id)
	if monster != null and profile.spell.target_type == 1 and ClassicSpellSourceRules.is_supported_projectile_item_profile(profile.spell):
		return _fire_physical_missile(state, content, actor, profile, monster, rng, events)
	return _fire_item_missile(state, content, actor, profile, target_id, rng, events)


## Castle combatinfo-combatchoice.c:396-475: with any opposed actor in range and sight (getrange), keep the
## retained target while it is in range, otherwise redraw randrange(0, maxloopminus) over party slots 0-5
## and monster slots 10-109. After twenty opposed out-of-range picks it sweeps upward from
## randrange(0, maxmon); after fifty more it gives up and the activation moves to melee.
func _missile_target(state: GameState, content: RealmzContent, actor: CharacterState, profile: ProjectileAttackProfile, rng: RealmzRng) -> String:
	var combat := state.combat
	var needs_sight := profile.spell.range_min + profile.spell.range_max > 0
	var in_range := func(id: String) -> bool:
		return CombatAiTargetFacts.health(state, id) > 0 and _context.reactions().projectile_target_is_valid(combat, content, actor.id, id, profile.maximum_range, needs_sight)
	var any_in_range := false
	for id: String in combat.battlefield.actors.actor_ids():
		if not CombatAiTargetFacts.character_is_friendly(state, actor, id) and in_range.call(id):
			any_in_range = true
			break
	if not any_in_range:
		return ""
	var slot := _classic_slot(state, combat.turns.character_target(actor.id))
	var tries := 0
	var cycle := false
	for _guard: int in CLASSIC_TARGET_LOOP_LIMIT:
		var id := _slot_actor(state, slot)
		if not id.is_empty() and not CombatAiTargetFacts.character_is_friendly(state, actor, id):
			combat.turns.set_character_target(actor.id, id)
			combat.turns.active_turn.target_id = id
			tries += 1
			if tries > 51 and cycle:
				return ""
			if tries > 20 and not cycle:
				tries = 0
				cycle = true
				slot = rng.draw_between(0, CLASSIC_MONSTER_SLOT_COUNT, &"combat.charmed_missile.cycle_start")
			elif in_range.call(id):
				return id
		if cycle:
			slot = 0 if slot >= CLASSIC_LAST_ACTOR_SLOT else slot + 1
		else:
			slot = rng.draw_between(0, CLASSIC_LAST_ACTOR_SLOT, &"combat.charmed_missile.target")
	return ""


## Field square Castle tomissle hands cast() for an actor (combatinfo-combatchoice.c:430-438): its slot as x and
## 1 for a party member or 2 for a monster as y. Spells above type 1 land on this square, not on the actor.
static func classic_target_square(state: GameState, actor_id: String) -> Vector2i:
	var slot := _classic_slot(state, actor_id)
	return Vector2i(slot, 1 if slot < CLASSIC_FIRST_MONSTER_SLOT else 2)


## Castle actor slot for a party member (0-5) or roster monster (10 + index); -1 when absent.
static func _classic_slot(state: GameState, actor_id: String) -> int:
	if actor_id.is_empty():
		return -1
	var characters := state.party.characters()
	for index: int in characters.size():
		if characters[index].id == actor_id:
			return index
	var monsters := state.combat.roster.monsters()
	for index: int in monsters.size():
		if monsters[index].id == actor_id:
			return CLASSIC_FIRST_MONSTER_SLOT + index
	return -1


## Actor in a Castle slot that its missile loop treats as present: a party member still in battle or a living monster.
static func _slot_actor(state: GameState, slot: int) -> String:
	if slot < 0:
		return ""
	if slot < CLASSIC_FIRST_MONSTER_SLOT:
		var characters := state.party.characters()
		if slot >= mini(characters.size(), CLASSIC_PARTY_SLOT_COUNT) or not state.combat.battlefield.actors.has_actor(characters[slot].id):
			return ""
		return characters[slot].id
	var monsters := state.combat.roster.monsters()
	var index := slot - CLASSIC_FIRST_MONSTER_SLOT
	return monsters[index].id if index < monsters.size() and monsters[index].current_health > 0 else ""


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
	combat.classic_blank_rounds = 0
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
	var result := _context.magic_flow().fire_item_missile(state, content, actor, profile.item_instance_id, target_id, profile.power_level, rng)
	if not result.ok:
		failure_result = result
		return NO_TARGET
	events.append_array(result.events)
	return MACRO_SEQUENCE if not state.combat.death_macros.actor_id().is_empty() else ATTACKED


## Resolves one automatic melee attack and reports ATTACKED, NO_TARGET or DEATH_MACRO.
## Strikes the adjacent opponent chosen by the approach (Castle attack(charup, hit)).
func process_charmed_character_turn(state: GameState, content: RealmzContent, actor: CharacterState, target_id: String, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	failure_result = null
	if not _is_present_opponent(state, actor, target_id) or not _context.battlefield.are_adjacent(state.combat.battlefield, actor.id, target_id):
		return NO_TARGET
	var character_target := state.party.character_by_id(target_id)
	var monster_target := state.combat.roster.monster_by_id(target_id)
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
	if character_target != null:
		return _resolve_charmed_attack_character(state, content, actor, equipment, character_target, active_turn, rng, events)
	var target_definition := content.combat.monster_by_id(monster_target.definition_id)
	if target_definition == null:
		failure_result = CombatFlowResult.failed(&"missing_monster_definition", "Charmed target '%s' has no monster definition." % monster_target.id)
		return NO_TARGET
	active_turn.physical_action_committed = true
	active_turn.classic_physical_active = true
	state.combat.classic_blank_rounds = 0
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
	state.combat.classic_blank_rounds = 0
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
