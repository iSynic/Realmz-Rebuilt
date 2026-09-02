class_name CombatFlowSummoning
extends RefCounted

const ContextType = preload("res://src/core/rules/combat_flow_context.gd")
const INVALID_COORDINATE := Vector2i(-100_000, -100_000)
const MAX_MONSTERS: int = 100
const MAX_CLASSIC_SELECTION_ATTEMPTS: int = 400

var _flow_ref: WeakRef
var _rules: ContextType


func _init(flow: RefCounted, rules: ContextType) -> void:
	_flow_ref = weakref(flow)
	_rules = rules


func _flow() -> RefCounted:
	return _flow_ref.get_ref() if _flow_ref != null else null


static func is_summon_spell(spell: SpellDefinition) -> bool:
	return ClassicSpellCapabilityCatalog.is_combat_summon_spell(spell)


func probe_choice(state: GameState, content: RealmzContent, caster_id: String, spell: SpellDefinition, power_level: int) -> CombatSpellCastProbe:
	if state == null or content == null or spell == null or state.combat == null or state.combat.battlefield == null:
		return CombatSpellCastProbe.blocked(&"summon_unavailable", "Combat summoning requires an active battlefield.")
	if power_level < 1 or power_level > 7:
		return CombatSpellCastProbe.blocked(&"invalid_summon_power", "A summon spell requires power 1 through 7.")
	if state.combat.monsters().size() >= MAX_MONSTERS:
		return CombatSpellCastProbe.blocked(&"summon_capacity_reached", "The Classic battlefield already contains its maximum 100 monster instances.")
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	if terrain_set == null or not state.combat.battlefield.has_actor(caster_id):
		return CombatSpellCastProbe.blocked(&"summon_battlefield_unavailable", "The summon battlefield has no validated terrain or caster position.")
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	var require_line_of_sight := spell.range_min + spell.range_max > 0
	var bounds := _candidate_bounds(state.combat.battlefield, caster_id, maximum_range)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var coordinate := Vector2i(x, y)
			if _rules.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster_id, coordinate, maximum_range, require_line_of_sight) and _rules.battlefield.monster_footprint_is_open(state.combat.battlefield, terrain_set, coordinate, 0):
				return CombatSpellCastProbe.permitted()
	return CombatSpellCastProbe.blocked(&"summon_target_unavailable", "No in-range open space can hold every Classic summon footprint.")


func probe_coordinates(state: GameState, content: RealmzContent, caster_id: String, spell: SpellDefinition, power_level: int, target_coordinates: Array[Vector2i]) -> CombatSpellCastProbe:
	var choice := probe_choice(state, content, caster_id, spell, power_level)
	if not choice.allowed:
		return choice
	if target_coordinates.is_empty():
		return CombatSpellCastProbe.blocked(&"summon_target_required", "Choose at least one open battlefield space for the summon.")
	if target_coordinates.size() > power_level or state.combat.monsters().size() + target_coordinates.size() > MAX_MONSTERS:
		return CombatSpellCastProbe.blocked(&"too_many_summon_targets", "A summon spell may choose at most one space per power level without exceeding 100 monster instances.")
	var seen: Dictionary = {}
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	var require_line_of_sight := spell.range_min + spell.range_max > 0
	for coordinate: Vector2i in target_coordinates:
		if coordinate == INVALID_COORDINATE or seen.has(coordinate):
			return CombatSpellCastProbe.blocked(&"invalid_summon_targets", "Summon spaces must be distinct battlefield coordinates.")
		seen[coordinate] = true
		if not _rules.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster_id, coordinate, maximum_range, require_line_of_sight):
			return CombatSpellCastProbe.blocked(&"summon_target_unavailable", "A summon space is outside the Classic spell range or line of sight.")
		if not _rules.battlefield.monster_footprint_is_open(state.combat.battlefield, terrain_set, coordinate, 0):
			return CombatSpellCastProbe.blocked(&"summon_target_unavailable", "A summon anchor is already occupied or blocked by terrain.")
	return CombatSpellCastProbe.permitted()


func cast_character_summon(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, rng: RealmzRng, target_coordinates: Array[Vector2i], event_source: String = "classic", spend_spell_points: bool = true, count_spell_cast: bool = true) -> CombatFlowResult:
	if state == null or content == null or caster == null or spell == null or rng == null:
		return CombatFlowResult.failed(&"summon_unavailable", "The summon transaction is incomplete.")
	var probe := probe_coordinates(state, content, caster.id, spell, power_level, target_coordinates)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	var definition := _select_classic_summon_definition(state, content, spell, rng)
	if definition == null:
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_summon_denied", {"actorId": caster.id, "spellId": spell.id, "power": power_level, "reason": "no-eligible-classic-monster", "source": event_source})])
	var battlefield := state.combat.battlefield
	var map := content.world.map_by_id(battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	var planned_cells: Dictionary = {}
	for coordinate: Vector2i in target_coordinates:
		if not _rules.battlefield.monster_footprint_is_open(battlefield, terrain_set, coordinate, definition.size, planned_cells):
			return _rollback_failed_summon(state, rng, state_checkpoint, rng_checkpoint, &"summon_footprint_unavailable", "The selected space cannot hold the source-selected summon footprint.")
		for cell: Vector2i in BattlefieldState.footprint_cells(coordinate, definition.size):
			planned_cells[cell] = true
	_flow()._prepare_character_turn(state.combat, caster)
	state.combat.invalidate_undo()
	if spend_spell_points:
		var cost := absi(spell.cost * power_level)
		if caster.spell_points < cost:
			return _rollback_failed_summon(state, rng, state_checkpoint, rng_checkpoint, &"insufficient_spell_points", "The caster no longer has enough spell points for this summon.")
		caster.spell_points -= cost
	if count_spell_cast:
		state.combat.active_turn.spell_cast_count += 1
		caster.lifetime_record.record_spell_cast()
	caster.attacks_remaining = _rules.arithmetic.signed_16(caster.attacks_remaining - 2)
	caster.movement = maxi(0, caster.movement - 12)
	var events: Array[DomainEvent] = []
	_flow()._append_spell_sound(events, spell.sound_start, "classic-combat-spell-start")
	var summoned_ids: Array[String] = []
	for index: int in target_coordinates.size():
		var instance_id := state.next_instance_id("monster.summoned")
		var summoned := _rules.monsters.build_monster(definition, instance_id, 1 if caster.traitor else 0, state.difficulty, state.clock.day(), rng)
		if summoned == null:
			return _rollback_failed_summon(state, rng, state_checkpoint, rng_checkpoint, &"summon_construction_failed", "The selected Classic monster could not be constructed.")
		summoned.summoned = true
		if not state.combat.add_monster(summoned) or not battlefield.place_monster(summoned.id, target_coordinates[index], definition.size):
			return _rollback_failed_summon(state, rng, state_checkpoint, rng_checkpoint, &"summon_placement_failed", "The selected Classic monster could not enter the battlefield.")
		state.combat.append_turn_actor(summoned.id)
		summoned_ids.append(summoned.id)
		_flow()._append_spell_projectile_event(events, caster.id, summoned.id, spell, event_source)
		_flow()._append_spell_sound(events, spell.sound_end, "classic-combat-spell-result")
		events.append(DomainEvent.new(&"combat_summoned", {"actorId": caster.id, "monsterId": summoned.id, "monsterDefinitionId": definition.id, "classicMonsterId": definition.classic_id, "coordinate": [target_coordinates[index].x, target_coordinates[index].y], "size": definition.size, "spellId": spell.id, "power": power_level, "castSequenceIndex": index, "castSequenceCount": target_coordinates.size(), "source": event_source}))
	events.insert(1, DomainEvent.new(&"combat_spell_cast", {"actorId": caster.id, "targetId": summoned_ids[0] if not summoned_ids.is_empty() else "", "targetIds": summoned_ids, "targetCoordinates": target_coordinates.map(func(coordinate: Vector2i) -> Array[int]: return [coordinate.x, coordinate.y]), "spellId": spell.id, "spellName": spell.name, "classicEffectResourceId": 11_992 + spell.look_start * 8, "source": event_source}))
	var advances_turn: bool = not _flow()._character_can_continue(caster)
	if advances_turn:
		_flow()._advance_turn(state, content, rng, events)
	if _flow()._finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_flow()._process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func cast_monster_summon(state: GameState, content: RealmzContent, caster: MonsterState, spell: SpellDefinition, power_level: int, rng: RealmzRng, target_coordinates: Array[Vector2i]) -> CombatFlowResult:
	if state == null or content == null or caster == null or spell == null or rng == null:
		return CombatFlowResult.failed(&"summon_unavailable", "The monster summon transaction is incomplete.")
	var probe := probe_coordinates(state, content, caster.id, spell, power_level, target_coordinates)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	var definition := _select_classic_summon_definition(state, content, spell, rng)
	if definition == null:
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_summon_denied", {"actorId": caster.id, "spellId": spell.id, "power": power_level, "reason": "no-eligible-classic-monster", "source": "classic-monster"})])
	var battlefield := state.combat.battlefield
	var map := content.world.map_by_id(battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	var planned_cells: Dictionary = {}
	for coordinate: Vector2i in target_coordinates:
		if not _rules.battlefield.monster_footprint_is_open(battlefield, terrain_set, coordinate, definition.size, planned_cells):
			return _rollback_failed_summon(state, rng, state_checkpoint, rng_checkpoint, &"summon_footprint_unavailable", "The selected space cannot hold the source-selected monster summon footprint.")
		for cell: Vector2i in BattlefieldState.footprint_cells(coordinate, definition.size):
			planned_cells[cell] = true
	var cost := spell.cost * power_level
	if cost < 0 or caster.spell_points < cost:
		return _rollback_failed_summon(state, rng, state_checkpoint, rng_checkpoint, &"insufficient_spell_points", "The monster no longer has enough spell points for this summon.")
	caster.spell_points -= cost
	state.combat.active_turn.spell_cast_count += 1
	var events: Array[DomainEvent] = []
	_flow()._append_spell_sound(events, spell.sound_start, "classic-monster-spell-start")
	var summoned_ids: Array[String] = []
	for index: int in target_coordinates.size():
		var instance_id := state.next_instance_id("monster.summoned")
		var summoned := _rules.monsters.build_monster(definition, instance_id, 1 if caster.traitor else 0, state.difficulty, state.clock.day(), rng)
		if summoned == null:
			return _rollback_failed_summon(state, rng, state_checkpoint, rng_checkpoint, &"summon_construction_failed", "The selected Classic monster could not be constructed.")
		summoned.summoned = true
		if not state.combat.add_monster(summoned) or not battlefield.place_monster(summoned.id, target_coordinates[index], definition.size):
			return _rollback_failed_summon(state, rng, state_checkpoint, rng_checkpoint, &"summon_placement_failed", "The selected Classic monster could not enter the battlefield.")
		state.combat.append_turn_actor(summoned.id)
		summoned_ids.append(summoned.id)
		_flow()._append_spell_projectile_event(events, caster.id, summoned.id, spell, "classic-monster")
		_flow()._append_spell_sound(events, spell.sound_end, "classic-monster-spell-result")
		events.append(DomainEvent.new(&"combat_summoned", {"actorId": caster.id, "monsterId": summoned.id, "monsterDefinitionId": definition.id, "classicMonsterId": definition.classic_id, "coordinate": [target_coordinates[index].x, target_coordinates[index].y], "size": definition.size, "spellId": spell.id, "power": power_level, "castSequenceIndex": index, "castSequenceCount": target_coordinates.size(), "source": "classic-monster"}))
	events.insert(1, DomainEvent.new(&"combat_spell_cast", {"actorId": caster.id, "targetId": summoned_ids[0] if not summoned_ids.is_empty() else "", "targetIds": summoned_ids, "targetCoordinates": target_coordinates.map(func(coordinate: Vector2i) -> Array[int]: return [coordinate.x, coordinate.y]), "spellId": spell.id, "spellName": spell.name, "classicEffectResourceId": 11_992 + spell.look_start * 8, "source": "classic-monster"}))
	return CombatFlowResult.succeeded(events)


func automatic_coordinate(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int) -> Vector2i:
	return _automatic_coordinate(state, content, caster.id, caster.traitor, spell, power_level)


func automatic_monster_coordinate(state: GameState, content: RealmzContent, caster: MonsterState, spell: SpellDefinition, power_level: int) -> Vector2i:
	return _automatic_coordinate(state, content, caster.id, caster.traitor, spell, power_level)


func _automatic_coordinate(state: GameState, content: RealmzContent, caster_id: String, caster_traitor: bool, spell: SpellDefinition, power_level: int) -> Vector2i:
	if not probe_choice(state, content, caster_id, spell, power_level).allowed:
		return INVALID_COORDINATE
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	var require_line_of_sight := spell.range_min + spell.range_max > 0
	var candidates: Array[Vector2i] = []
	var bounds := _candidate_bounds(state.combat.battlefield, caster_id, maximum_range)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var coordinate := Vector2i(x, y)
			if _rules.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster_id, coordinate, maximum_range, require_line_of_sight) and _rules.battlefield.monster_footprint_is_open(state.combat.battlefield, terrain_set, coordinate, 3):
				candidates.append(coordinate)
	if candidates.is_empty():
		return INVALID_COORDINATE
	var hostile_positions: Array[Vector2i] = []
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health > 0 and monster.traitor != caster_traitor and state.combat.battlefield.has_actor(monster.id):
			hostile_positions.append(state.combat.battlefield.actor_position(monster.id))
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor != caster_traitor and state.combat.battlefield.has_actor(character.id):
			hostile_positions.append(state.combat.battlefield.actor_position(character.id))
	candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := _nearest_distance(left, hostile_positions)
		var right_distance := _nearest_distance(right, hostile_positions)
		return left_distance < right_distance or left_distance == right_distance and (left.y < right.y or left.y == right.y and left.x < right.x)
	)
	return candidates[0]


func _select_classic_summon_definition(state: GameState, content: RealmzContent, spell: SpellDefinition, rng: RealmzRng) -> MonsterDefinition:
	var sum_size := 6 * spell.size
	var low_hit_dice := int(sum_size / 2) - 1
	var high_hit_dice := 200 if sum_size > 27 else sum_size
	for attempt: int in MAX_CLASSIC_SELECTION_ATTEMPTS:
		var classic_id := rng.draw_between(0, 200, StringName("combat.summon.%s.selection.%d" % [spell.id, attempt]))
		if spell.spell_class != 0:
			classic_id = absi(spell.spell_class)
		var definition := content.monster_by_classic_id_for_set(classic_id, state.monster_set)
		if definition == null:
			definition = content.monster_by_classic_id(classic_id)
		if definition == null:
			continue
		if spell.spell_class != 0:
			return definition
		var lower := 1 if attempt >= 101 else low_hit_dice
		var upper := 200 if attempt >= 101 else high_hit_dice
		if definition.hit_dice >= lower and definition.hit_dice <= upper and definition.hit_dice != 0 and definition.can_summon == 1:
			return definition
	return null


func _rollback_failed_summon(state: GameState, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary, error_code: StringName, error_message: String) -> CombatFlowResult:
	if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
		return CombatFlowResult.failed(&"combat_summon_rollback_failed", "Combat summoning failed and its deterministic transaction could not be restored.")
	return CombatFlowResult.failed(error_code, error_message)


static func _nearest_distance(coordinate: Vector2i, targets: Array[Vector2i]) -> int:
	var result := 0x3fff_ffff
	for target: Vector2i in targets:
		result = mini(result, floori(Vector2(target - coordinate).length()))
	return result


static func _candidate_bounds(battlefield: BattlefieldState, caster_id: String, maximum_range: int) -> Rect2i:
	var origin := battlefield.actor_position(caster_id)
	var minimum := Vector2i(maxi(0, origin.x - maximum_range), maxi(0, origin.y - maximum_range))
	var maximum_exclusive := Vector2i(mini(BattlefieldState.SIZE, origin.x + maximum_range + 1), mini(BattlefieldState.SIZE, origin.y + maximum_range + 1))
	return Rect2i(minimum, maximum_exclusive - minimum)
