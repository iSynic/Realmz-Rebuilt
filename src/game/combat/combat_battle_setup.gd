## Builds one deterministic Classic battlefield and commits its initial combat state.

class_name CombatBattleSetup
extends RefCounted

const MAX_MONSTERS := 100


class BattleInputs extends RefCounted:
	var map: MapDefinition
	var terrain_set: BattleTerrainSetDefinition
	var party_characters: Array[CharacterState]
	var initial_weapon_modes: Dictionary
	var ally_definitions: Dictionary
	var authored_slots: Array[BattleMonsterSlotDefinition]
	var authored_definitions: Dictionary


class BattleAssembly extends RefCounted:
	var inputs: BattleInputs
	var builder: BattlefieldBuilder
	var battlefield: BattlefieldState
	var formation: Dictionary
	var monsters: Array[MonsterState] = []
	var consumed_ally_ids: Array[String] = []
	var consumed_ally_states: Array[MonsterState] = []
	var pending_authored: Array[Dictionary] = []


var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context


func start(state: GameState, content: RealmzContent, battle: BattleDefinition, rng: RealmzRng, surprise: int = 0, participant_character_ids: Array[String] = []) -> CombatFlowResult:
	if state == null or content == null or battle == null or rng == null:
		return CombatFlowResult.failed(&"invalid_battle", "Battle setup requires validated state, content, and randomness.")
	if state.combat != null and not state.combat.completed:
		return CombatFlowResult.failed(&"battle_already_active", "A Realmz battle is already active.")
	var inputs_value: Variant = _prepare_inputs(state, content, battle, participant_character_ids)
	if inputs_value is CombatFlowResult:
		return inputs_value
	var inputs: BattleInputs = inputs_value
	var rng_checkpoint := rng.checkpoint()
	var instance_checkpoint := state.instance_id_checkpoint()
	var builder := BattlefieldBuilder.new()
	var terrain_result := builder.build_terrain(inputs.map, state.world, inputs.terrain_set, state.party.coordinate, rng)
	if not terrain_result.is_ok():
		return _setup_failure(state, instance_checkpoint, rng, rng_checkpoint, terrain_result.error_code, terrain_result.error_message)
	var formation := builder.roll_formation(terrain_result.battlefield, battle, rng)
	if formation.is_empty():
		return _setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"invalid_battle_formation", "Battle '%s' could not derive Castle's opening formation." % battle.id)
	var assembly := BattleAssembly.new()
	assembly.inputs = inputs
	assembly.builder = builder
	assembly.battlefield = terrain_result.battlefield
	assembly.formation = formation
	for phase: Callable in [_place_characters, _place_allies, _prepare_authored_monsters]:
		var phase_error: CombatFlowResult = phase.call(assembly, state, battle, rng, instance_checkpoint, rng_checkpoint)
		if phase_error != null:
			return phase_error
	return _commit(assembly, state, content, battle, rng, surprise, instance_checkpoint, rng_checkpoint)


func _place_characters(assembly: BattleAssembly, state: GameState, battle: BattleDefinition, rng: RealmzRng, instance_checkpoint: int, rng_checkpoint: Dictionary) -> CombatFlowResult:
	for party_index: int in assembly.inputs.party_characters.size():
		var character := assembly.inputs.party_characters[party_index]
		if not assembly.builder.place_character(assembly.battlefield, assembly.inputs.terrain_set, character.id, party_index, assembly.formation):
			return _setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"character_placement_failed", "Battle '%s' has no legal battlefield cell for '%s'." % [battle.id, character.id])
	return null


func _place_allies(assembly: BattleAssembly, state: GameState, battle: BattleDefinition, rng: RealmzRng, instance_checkpoint: int, rng_checkpoint: Dictionary) -> CombatFlowResult:
	if state.allies_suspended:
		return null
	for ally: MonsterState in state.party.allies():
		if ally.current_health <= 0 or assembly.monsters.size() >= MAX_MONSTERS:
			continue
		var definition: MonsterDefinition = assembly.inputs.ally_definitions[ally.id]
		if not assembly.builder.place_monster(assembly.battlefield, assembly.inputs.terrain_set, ally.id, Vector2i.ZERO, definition.size):
			return _setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"ally_placement_failed", "Battle '%s' has no legal battlefield footprint for ally '%s'." % [battle.id, ally.id])
		assembly.monsters.append(ally)
		assembly.consumed_ally_ids.append(ally.id)
		assembly.consumed_ally_states.append(ally)
	return null


func _prepare_authored_monsters(assembly: BattleAssembly, state: GameState, battle: BattleDefinition, rng: RealmzRng, instance_checkpoint: int, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var monster_origin: Vector2i = assembly.formation["monsterOrigin"]
	for slot_index: int in assembly.inputs.authored_slots.size():
		if assembly.monsters.size() + assembly.pending_authored.size() >= MAX_MONSTERS:
			break
		var slot: BattleMonsterSlotDefinition = assembly.inputs.authored_slots[slot_index]
		var definition: MonsterDefinition = assembly.inputs.authored_definitions[slot.monster_id]
		var pending_id := "pending.authored.%d" % slot_index
		if not assembly.builder.place_monster(assembly.battlefield, assembly.inputs.terrain_set, pending_id, monster_origin + slot.coordinate, definition.size):
			return _setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"monster_placement_failed", "Battle '%s' has no legal battlefield footprint for authored monster at %s." % [battle.id, slot.coordinate])
		var monster := _context.monsters.build_battle_monster(definition, pending_id, slot.invert_traitor, state.difficulty, state.clock.day(), rng)
		if monster == null:
			return _setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"invalid_monster", "Battle '%s' could not construct monster '%s'." % [battle.id, slot.monster_id])
		assembly.pending_authored.append({"placeholderId": pending_id, "monster": monster})
	return null


func _commit(assembly: BattleAssembly, state: GameState, content: RealmzContent, battle: BattleDefinition, rng: RealmzRng, surprise: int, instance_checkpoint: int, rng_checkpoint: Dictionary) -> CombatFlowResult:
	for character: CharacterState in assembly.inputs.party_characters:
		if character.current_health <= 0:
			assembly.battlefield.actors.remove_character(character.id)
	for pending: Dictionary in assembly.pending_authored:
		var monster: MonsterState = pending["monster"]
		var instance_id := state.next_instance_id("combat.monster")
		if not assembly.battlefield.actors.replace_monster_id(pending["placeholderId"], instance_id):
			return _setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"invalid_battlefield_identity", "Battle '%s' could not commit a stable monster identity." % battle.id)
		monster.id = instance_id
		assembly.monsters.append(monster)
	var combat := CombatState.new(battle.id, assembly.monsters, battle.macro_id, assembly.battlefield)
	combat.set_turn_order(_context.combat.initiative_order(assembly.inputs.party_characters, assembly.monsters, surprise, rng))
	for character: CharacterState in assembly.inputs.party_characters:
		if character.current_health <= 0:
			continue
		var initial_mode := StringName(assembly.inputs.initial_weapon_modes.get(character.id, &"melee"))
		if not combat.actor_statuses.set_character_weapon_mode(character.id, initial_mode):
			return _setup_failure(state, instance_checkpoint, rng, rng_checkpoint, &"invalid_weapon_mode", "Battle '%s' could not initialize '%s' weapon mode." % [battle.id, character.id])
	for ally: MonsterState in assembly.consumed_ally_states:
		ally.traitor = false
	if not state.allies_suspended:
		state.party.set_allies([])
	for character: CharacterState in assembly.inputs.party_characters:
		character.traitor = false
		character.attacks_remaining = 0
		character.movement = character.maximum_movement
	state.combat = combat
	var events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 10049, "waitForCompletion": false, "source": "classic-battle-entry"}), DomainEvent.new(&"battle_started", {"battleId": battle.id, "classicId": battle.classic_id, "distance": battle.distance, "rolledDistance": assembly.battlefield.rolled_distance, "direction": assembly.battlefield.direction_degrees, "mapId": assembly.battlefield.map_id, "surprise": surprise, "turnOrder": combat.turns.turn_order(), "participantCharacterIds": assembly.inputs.party_characters.map(func(character: CharacterState) -> String: return character.id), "consumedAllyIds": assembly.consumed_ally_ids})]
	_context.automation().process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func _prepare_inputs(state: GameState, content: RealmzContent, battle: BattleDefinition, participant_character_ids: Array[String]) -> Variant:
	var result := BattleInputs.new()
	result.map = content.world.map_by_id(state.party.map_id)
	if result.map == null or result.map.topology.width != 90 or result.map.topology.height != 90:
		return CombatFlowResult.failed(&"invalid_battle_map", "Battle '%s' requires the party's validated 90 by 90 Classic map." % battle.id)
	result.terrain_set = content.world.battle_terrain_set_for_map(result.map, state.world)
	if result.terrain_set == null:
		return CombatFlowResult.failed(&"missing_battle_terrain", "Map '%s' has no validated Classic battle-terrain catalog." % result.map.id)
	result.party_characters = state.party.characters()
	if not participant_character_ids.is_empty():
		var participant_set: Dictionary = {}
		for character_id: String in participant_character_ids:
			if participant_set.has(character_id) or state.party.character_by_id(character_id) == null:
				return CombatFlowResult.failed(&"invalid_battle_participants", "Battle participants must be unique members of the current party.")
			participant_set[character_id] = true
		result.party_characters = result.party_characters.filter(func(character: CharacterState) -> bool: return participant_set.has(character.id))
		if result.party_characters.is_empty():
			return CombatFlowResult.failed(&"invalid_battle_participants", "A selective battle requires at least one party participant.")
	result.initial_weapon_modes = {}
	for character: CharacterState in result.party_characters:
		if character.current_health <= 0:
			continue
		var equipment := _context.equipment.combat_equipment(character, content.items.definitions())
		if not equipment.valid:
			return CombatFlowResult.failed(equipment.error_code, equipment.error_message)
		result.initial_weapon_modes[character.id] = &"missile" if equipment.melee_weapon == null and equipment.missile_weapon != null else &"melee"
	result.ally_definitions = {}
	if not state.allies_suspended:
		for ally: MonsterState in state.party.allies():
			if ally.current_health <= 0:
				continue
			var definition := content.combat.monster_by_id(ally.definition_id)
			if definition == null:
				return CombatFlowResult.failed(&"unknown_ally", "Held-over ally '%s' references unavailable monster '%s'." % [ally.id, ally.definition_id])
			result.ally_definitions[ally.id] = definition
	result.authored_slots = battle.monster_slots()
	if result.authored_slots.is_empty():
		return CombatFlowResult.failed(&"empty_battle", "Battle '%s' has no viable monsters." % battle.id)
	result.authored_slots.sort_custom(func(left: BattleMonsterSlotDefinition, right: BattleMonsterSlotDefinition) -> bool:
		return left.coordinate.y < right.coordinate.y or left.coordinate.y == right.coordinate.y and left.coordinate.x < right.coordinate.x
	)
	result.authored_definitions = {}
	for slot: BattleMonsterSlotDefinition in result.authored_slots:
		var definition := content.combat.monster_by_id_for_set(slot.monster_id, state.monster_set)
		if definition == null:
			return CombatFlowResult.failed(&"unknown_monster", "Battle '%s' references unavailable monster '%s'." % [battle.id, slot.monster_id])
		result.authored_definitions[slot.monster_id] = definition
	return result


static func _setup_failure(state: GameState, instance_checkpoint: int, rng: RealmzRng, checkpoint: Dictionary, code: StringName, message: String) -> CombatFlowResult:
	if state == null or not state.rollback_instance_ids(instance_checkpoint) or not rng.rollback(checkpoint):
		return CombatFlowResult.failed(&"battle_setup_rollback_failed", "Battle setup failed and could not restore the deterministic RNG boundary.")
	return CombatFlowResult.failed(code, message)
