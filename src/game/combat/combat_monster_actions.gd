## Owns monster target selection and source-backed projectile actions.
class_name CombatMonsterActions
extends RefCounted

const MONSTER_ATTACK_COMPLETED := 0
const MONSTER_ATTACK_FALLBACK := 3

var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context


func process_projectile(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var projectile_item_id := definition.item_id_at(1)
	var projectile_item := content.items.item_by_id(projectile_item_id) if not projectile_item_id.is_empty() else null
	var projectile_spell := content.magic.spell_by_classic_id(absi(projectile_item.special_2)) if projectile_item != null else null
	var unavailable := "Monster missile slot 1 is empty or references an unavailable item."
	if projectile_item != null and projectile_spell == null:
		unavailable = "Monster missile item '%s' references an unavailable Classic spell." % projectile_item.id
	elif projectile_spell != null:
		unavailable = _context.actions().projectile_spell_unavailable_reason(projectile_spell)
	if projectile_item == null or projectile_spell == null or not unavailable.is_empty():
		active_turn.movement_remaining = 0
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "missile", "reason": unavailable, "source": "classic"}))
		return MONSTER_ATTACK_COMPLETED
	var terrain_set := battle_terrain_set(content, combat.battlefield)
	if terrain_set == null:
		active_turn.movement_remaining = 0
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "missile", "reason": "missing-battle-terrain", "source": "classic"}))
		return MONSTER_ATTACK_COMPLETED
	var range_power := rng.draw(7, StringName("combat.monster-projectile.%s.power" % monster.id))
	var maximum_range := absi(projectile_spell.range_min + projectile_spell.range_max * range_power)
	var target_ids := projectile_target_ids(state, monster, terrain_set, maximum_range)
	if target_ids.is_empty():
		events.append(DomainEvent.new(&"combat_monster_projectile_skipped", {"actorId": monster.id, "reason": "no-character-target-in-range", "range": maximum_range, "source": "classic"}))
		return MONSTER_ATTACK_FALLBACK
	var cost_power := range_power
	while cost_power > 0 and monster.spell_points < absi(projectile_spell.cost * cost_power): cost_power -= 1
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
	combat.actor_statuses.set_guarding(monster.id, false)
	var resolution := _context.magic.resolve_monster_projectile(monster, projectile_item, target, projectile_spell, 1, rng)
	if resolution == null:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "missile", "reason": "projectile-resolution-failed", "source": "classic"}))
		return MONSTER_ATTACK_COMPLETED
	target.lifetime_record.add_projectile_damage_taken(resolution.total_damage, resolution.hit_count, resolution.miss_count)
	if resolution.total_damage > 0: combat.actor_statuses.mark_attacked(target.id)
	events.append(DomainEvent.new(&"combat_projectile_resolved", {
		"actorId": monster.id, "targetId": target.id, "targetKind": "character",
		"itemId": projectile_item.id, "spellId": projectile_spell.id,
		"rangePower": range_power, "costPower": cost_power, "resolutionPower": 1,
		"range": _context.battlefield.classic_range(combat.battlefield, monster.id, target.id),
		"hitCount": resolution.hit_count, "missCount": resolution.miss_count,
		"damage": resolution.total_damage, "defeated": resolution.target_defeated,
		"source": "classic-monster",
	}))
	_context.actions().mark_character_bleeding(state, target, resolution.target_defeated)
	if resolution.target_defeated: combat.battlefield.remove_actor(target.id)
	return MONSTER_ATTACK_COMPLETED


func select_adjacent_target(state: GameState, monster: MonsterState, rng: RealmzRng) -> String:
	var target_ids: Array[String] = []
	var adjacent_ids := _context.battlefield.adjacent_actor_ids(state.combat.battlefield, monster.id)
	for character: CharacterState in state.party.characters():
		if target_is_available(state, monster, character.id) and adjacent_ids.has(character.id): target_ids.append(character.id)
	for candidate: MonsterState in state.combat.roster.monsters():
		if target_is_available(state, monster, candidate.id) and adjacent_ids.has(candidate.id): target_ids.append(candidate.id)
	if target_ids.is_empty(): return ""
	return target_ids[rng.draw_between(0, target_ids.size() - 1, &"combat.monster-target")]


func projectile_target_ids(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition, maximum_range: int) -> Array[String]:
	var candidates: Array[String] = []
	for character: CharacterState in state.party.characters():
		if target_is_available(state, monster, character.id) and _context.battlefield.projectile_target_is_valid(state.combat.battlefield, terrain_set, monster.id, character.id, maximum_range, true): candidates.append(character.id)
	return candidates


static func prepare_melee_weapon(monster: MonsterState, definition: MonsterDefinition, content: RealmzContent) -> void:
	if monster == null or definition == null or content == null or monster.weapon_id.is_empty(): return
	var active_item := content.items.item_by_id(monster.weapon_id)
	var active_spell := content.magic.spell_by_classic_id(absi(active_item.special_2)) if active_item != null and active_item.special_2 != 0 else null
	if active_spell != null and active_spell.damage_type == 9:
		# FD-COMBAT-010 applies Castle's intended slot-zero replacement to the actor.
		monster.weapon_id = definition.item_id_at(0)


func select_visible_target(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition, rng: RealmzRng) -> String:
	var characters := state.party.characters()
	var monsters := state.combat.roster.monsters()
	var slot_count := 10 + monsters.size()
	if not _has_available_target(state, monster, characters, monsters): return ""
	for _attempt: int in 4096:
		var slot := rng.draw_between(0, slot_count - 1, &"combat.monster-target-slot")
		var candidate_id := _target_id_for_slot(state, monster, slot, characters, monsters)
		if candidate_id.is_empty(): continue
		if _context.battlefield.has_line_of_sight(state.combat.battlefield, terrain_set, monster.id, candidate_id): return candidate_id
		break
	return scan_visible_target(state, monster, terrain_set)


func scan_visible_target(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition) -> String:
	var characters := state.party.characters()
	var monsters := state.combat.roster.monsters()
	for slot: int in 10 + monsters.size():
		var candidate_id := _target_id_for_slot(state, monster, slot, characters, monsters)
		if not candidate_id.is_empty() and _context.battlefield.has_line_of_sight(state.combat.battlefield, terrain_set, monster.id, candidate_id): return candidate_id
	return ""


func _target_id_for_slot(state: GameState, monster: MonsterState, slot: int, characters: Array[CharacterState], monsters: Array[MonsterState]) -> String:
	if slot >= 0 and slot < 9:
		if slot >= characters.size(): return ""
		return characters[slot].id if target_is_available(state, monster, characters[slot].id) else ""
	if slot < 10: return ""
	var monster_index := slot - 10
	if monster_index < 0 or monster_index >= monsters.size(): return ""
	return monsters[monster_index].id if target_is_available(state, monster, monsters[monster_index].id) else ""


func has_available_target(state: GameState, monster: MonsterState) -> bool:
	return _has_available_target(state, monster, state.party.characters(), state.combat.roster.monsters())


func _has_available_target(state: GameState, monster: MonsterState, characters: Array[CharacterState], monsters: Array[MonsterState]) -> bool:
	for character: CharacterState in characters:
		if target_is_available(state, monster, character.id): return true
	for candidate: MonsterState in monsters:
		if target_is_available(state, monster, candidate.id): return true
	return false


static func target_is_available(state: GameState, monster: MonsterState, target_id: String) -> bool:
	if target_id.is_empty(): return false
	var character := state.party.character_by_id(target_id)
	if character != null: return character.current_health > 0 and character.traitor != monster.traitor and state.combat.battlefield.actors.has_actor(character.id)
	var candidate := state.combat.roster.monster_by_id(target_id)
	return candidate != null and candidate.id != monster.id and candidate.current_health > 0 and candidate.traitor != monster.traitor and state.combat.battlefield.actors.has_actor(candidate.id)


static func battle_terrain_set(content: RealmzContent, battlefield: BattlefieldState) -> BattleTerrainSetDefinition:
	var map := content.world.map_by_id(battlefield.map_id)
	return null if map == null else content.world.battle_terrain_set_by_id(map.battle_terrain_set_id)


static func movement_allowance(monster: MonsterState, definition: MonsterDefinition) -> int:
	var movement := definition.movement_max
	var tangled := monster.conditions.value(ConditionRules.TANGLED)
	if tangled > 0: movement -= tangled
	if monster.conditions.is_active(ConditionRules.SLOW): movement = int(float(movement) / 2.0)
	if monster.conditions.is_active(ConditionRules.SPEEDY): movement *= 2
	return maxi(0, movement)


static func attack_limit(definition: MonsterDefinition) -> int:
	return mini(maxi(0, definition.attack_count), definition.attacks().size())


static func retreat_reached_edge(state: GameState, content: RealmzContent, monster_id: String, destination: Vector2i, events: Array[DomainEvent]) -> bool:
	if destination.x >= 2 and destination.y >= 2 and destination.x <= 87 and destination.y <= 87: return false
	var monster := state.combat.roster.monster_by_id(monster_id)
	var definition := content.combat.monster_by_id(monster.definition_id) if monster != null else null
	if monster == null or definition == null: return false
	state.combat.actor_statuses.set_guarding(monster.id, false)
	state.combat.turns.active_turn.movement_remaining = 0
	if definition.can_summon < 0:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": "mandatory-ally-edge-retreat-unresolved"}))
		return false
	monster.current_health = 0
	state.combat.battlefield.actors.remove_monster(monster.id)
	events.append(DomainEvent.new(&"combatant_retreated", {"actorId": monster.id, "mode": "battlefield-edge", "forced": true, "source": "classic-monster"}))
	return true
