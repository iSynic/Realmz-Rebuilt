## Commits source teleport destinations and exposes their native recheck work separately from events.
class_name ClassicWorldTransferOperations
extends RefCounted

var _content: RealmzContent
var _game_state: GameState
var _native_header: ClassicExecutionState


func _init(content: RealmzContent, state: GameState, native_header: ClassicExecutionState) -> void:
	_content = content
	_game_state = state
	_native_header = native_header


func move(action: ClassicActionDefinition, dungeon_move: bool, activate_destination: bool = false) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic map movement requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic map movement requires the party's current map.")
	var target_type := (&"dungeon" if action.extra_code[0] == 0 else &"land") if dungeon_move else current_map.level_type
	var map_index := action.extra_code[1] if dungeon_move else current_map.level_index if action.extra_code[0] < 0 else action.extra_code[0]
	var coordinate := Vector2i(action.extra_code[2], action.extra_code[3]) if dungeon_move else Vector2i(_game_state.party.coordinate.x if action.extra_code[1] < 0 else action.extra_code[1], _game_state.party.coordinate.y if action.extra_code[2] < 0 else action.extra_code[2])
	var target_map := _content.world.map_by_type_and_index(target_type, map_index)
	if target_map == null or target_map.topology.cell_at(coordinate) == null:
		if _content.classic_records != null and (target_map != null or ClassicCompatibility.source_unavailable(_content, "Data DL" if target_type == &"dungeon" else "Data LD", map_index)):
			return ClassicCompatibility.skip(&"unavailable-teleport-destination", "Data DL" if target_type == &"dungeon" else "Data LD", map_index)
		return ScenarioRuntimeOperationResult.failed(&"invalid_teleport", "Classic map movement references an unavailable destination.")
	var authored_heading := action.extra_code[4] if dungeon_move and target_type == &"dungeon" else 0
	if dungeon_move and target_type == &"dungeon" and (absi(authored_heading) < 1 or absi(authored_heading) > 4):
		return ScenarioRuntimeOperationResult.failed(&"invalid_dungeon_heading", "Classic dungeon movement requires a heading from 1 through 4.")
	var source_map_id := _game_state.party.map_id
	var source_coordinate := _game_state.party.coordinate
	_game_state.party.map_id = target_map.id
	_game_state.party.coordinate = coordinate
	_game_state.world.exploration.mark_visited(target_map.id, coordinate)
	if dungeon_move and target_type == &"dungeon":
		_game_state.dungeon_heading = absi(authored_heading)
		_game_state.dungeon_multiview = authored_heading >= 0
	var sound_id := 0 if dungeon_move else action.extra_code[3]
	var message_id := 0 if dungeon_move else action.extra_code[4]
	var events: Array[DomainEvent] = [DomainEvent.new(&"party_teleported", {"sourceMapId": source_map_id, "sourceX": source_coordinate.x, "sourceY": source_coordinate.y, "mapId": target_map.id, "x": coordinate.x, "y": coordinate.y, "soundId": sound_id, "messageId": message_id, "dungeonHeading": _game_state.dungeon_heading, "dungeonMultiview": _game_state.dungeon_multiview, "source": "classic"})]
	if _game_state.combat != null and not _game_state.combat.completed:
		# FD-COMBAT-021: Castle loadland overwrites combat's shared field, including
		# live actor occupancy (Bywater 191 / alternate 41 / XAP 111). Commit the
		# authored world destination while retaining the last coherent battlefield.
		events.append(DomainEvent.new(&"combat_battlefield_retained", {"battleId": _game_state.combat.battle_id, "battlefieldMapId": _game_state.combat.battlefield.map_id, "destinationMapId": target_map.id, "opcode": action.opcode, "source": "unsafe-native-map-reload"}))
	if sound_id != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "source": "classic-teleport"}))
	if message_id != 0:
		var message := _content.scenario_records.message_by_id(absi(message_id))
		if message == null and not ClassicCompatibility.source_unavailable(_content, "Data SD2", absi(message_id)):
			return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic teleport references unavailable message %d." % message_id)
		if message != null:
			events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-teleport"}))
	if not dungeon_move: _native_header.set_destination(target_map.id, coordinate)
	if activate_destination and target_map.topology.action_point_is_marked(coordinate, _game_state.world, true):
		events.append(DomainEvent.new(&"destination_trigger_recheck_requested", {"mapId": target_map.id, "x": coordinate.x, "y": coordinate.y, "source": "classic-opcode-20"}))
		var result := ScenarioRuntimeOperationResult.completed(target_map.id, events)
		result.recheck_destination = true
		return result
	# Unlike teleport, opcode 37 returns from newland immediately.
	return ScenarioRuntimeOperationResult.completed(target_map.id, events, ScenarioVmDirective.native_return(1) if dungeon_move else null)
