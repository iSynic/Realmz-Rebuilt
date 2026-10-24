## Executes the Classic world time opcode handler family of validated Classic instructions.

class_name ClassicWorldTimeOpcodeHandler
extends ClassicOpcodeHandler

const PLAYER_MAP_ACQUIRED_TEXT := "You gain a map, to view the map use Maps/Notes in the Menu."
const PLAYER_MAP_ACQUIRED_SOUND_ID := 30005

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng) -> void:
	_content = content
	_game_state = game_state
	_rng = rng


func opcode_ids() -> Array[int]:
	return [-23, 12, 13, 20, 23, 29, 37, 45, 47, 57, 61, 66, 68, 70, 76, 92, 95, 101, 103, 104, 106]


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		-23, 23:
			return _mutate_random_region(action, action.opcode == -23)
		12:
			return _mutate_tile(action)
		13:
			return _mutate_triggers(action)
		20:
			return _move_between_maps(action, false, true)
		29:
			return _acquire_player_map(action, request_id, context)
		37:
			return _move_between_maps(action, true)
		45:
			return _move_between_maps(action, false, false)
		47:
			var quest_id := absi(action.operand_id)
			if _content.package_schema_version >= 7 and quest_id >= ClassicCompatibility.quest_limit(_content):
				return ClassicCompatibility.skip(&"unavailable-quest-mutation", "quest-slots", quest_id)
			if quest_id >= ClassicCompatibility.quest_limit(_content) or not _game_state.scenario_progress.set_quest_value(quest_id, 0 if action.operand_id < 0 or action.operand_id == 0 and _content.package_schema_version >= 7 else 1):
				return ScenarioRuntimeOperationResult.failed(&"invalid_quest", "Classic opcode 47 references quest %d outside 0 through 99." % quest_id)
			return ScenarioRuntimeOperationResult.completed(_game_state.scenario_progress.quest_value(quest_id), [DomainEvent.new(&"quest_changed", {"questId": quest_id, "value": _game_state.scenario_progress.quest_value(quest_id)})])
		57:
			return _change_land_look(action)
		61:
			return _shift_party(action)
		66:
			_game_state.camping_allowed = action.operand_id == 0
			return ScenarioRuntimeOperationResult.completed(_game_state.camping_allowed, [DomainEvent.new(&"camping_availability_changed", {"allowed": _game_state.camping_allowed, "source": "classic"})])
		68:
			return _alter_party_fatigue(action)
		70:
			return _save_or_restore_party_position(action)
		76:
			return _adjust_quest_value(action)
		92:
			return _alter_random_region_geometry(action)
		95:
			return _change_dungeon_heading(action)
		101:
			return _back_up_party()
		103:
			return _test_or_set_party_mode(action)
		104:
			_game_state.random_encounters_enabled = action.operand_id != 0
			return ScenarioRuntimeOperationResult.completed(_game_state.random_encounters_enabled, [DomainEvent.new(&"random_encounters_changed", {"enabled": _game_state.random_encounters_enabled})])
		106:
			return _set_map_darkness(action)
	return super.execute(action, request_id, context)


func _change_land_look(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	var native_values := _content.package_schema_version >= 7 and _content.classic_records != null
	if action.extra_code.size() < 5 or not native_values and action.extra_code[1] not in [0, 1]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_land_look", "Classic opcode 57 requires a landlook, darkness flag, and land-level identity.")
	# newland.c assigns the signed short to char landlook and unsigned Boolean.
	var look := RealmzArithmetic.new().signed_8(action.extra_code[0]) if native_values else action.extra_code[0]
	var dark_byte := RealmzArithmetic.new().unsigned_8(action.extra_code[1]) if native_values else action.extra_code[1]
	var dark := dark_byte != 0
	var map := _content.world.map_by_type_and_index(&"land", action.extra_code[2])
	if map == null and native_values and ClassicCompatibility.map_source_unavailable(_content, "land:%d" % action.extra_code[2]):
		return ClassicCompatibility.skip(&"unavailable-landlook-map", "Data LD", action.extra_code[2])
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_land_look", "Classic opcode 57 references an unavailable land level.")
	if _content.world.battle_terrain_set_by_landlook(look) == null and native_values and look not in [0, 3, 4, 5, 9, 10]:
		var source := _content.classic_records.source_by_path("Data Custom %d BD" % (look - 5)) if look in [6, 7, 8] else null
		if source == null or source.effective_byte_length < 8044:
			return ClassicCompatibility.skip(&"unavailable-landlook-table", "Map Stats", look)
	if _content.world.battle_terrain_set_by_landlook(look) == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_land_look", "Classic opcode 57 references an unavailable land level or landlook.")
	var previous_landlook := _game_state.world.topology.map_landlook(map)
	var previous_dark := _game_state.world.topology.map_is_dark(map)
	_game_state.world.topology.set_map_landlook(map.id, look)
	_game_state.world.topology.set_map_darkness(map.id, dark, dark_byte)
	return ScenarioRuntimeOperationResult.completed(map.id, [DomainEvent.new(&"map_appearance_changed", {"mapId": map.id, "previousLandlook": previous_landlook, "landlook": look, "previousDark": previous_dark, "dark": dark, "offscreen": map.id != _game_state.party.map_id, "source": "classic-opcode-57"}), DomainEvent.new(&"world_projection_invalidated", {"mapId": map.id, "reason": "map-appearance"})])


func _save_or_restore_party_position(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 70 requires a five-value Extra Code row.")
	match action.extra_code[0]:
		1:
			var current_map := _content.world.map_by_id(_game_state.party.map_id)
			if not _game_state.save_party_position(current_map):
				return ScenarioRuntimeOperationResult.failed(&"invalid_party_position", "Classic opcode 70 cannot save the current party position.")
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"party_position_saved", {"mapId": _game_state.saved_party_map_id, "x": _game_state.saved_party_coordinate.x, "y": _game_state.saved_party_coordinate.y, "levelType": String(_game_state.saved_party_level_type), "source": "classic-opcode-70"})])
		2:
			if not _game_state.has_saved_party_position():
				return ScenarioRuntimeOperationResult.failed(&"missing_party_position", "Classic opcode 70 has no saved party position to restore.")
			var target_map := _content.world.map_by_id(_game_state.saved_party_map_id)
			if target_map == null or target_map.level_type != _game_state.saved_party_level_type or target_map.topology.cell_at(_game_state.saved_party_coordinate) == null:
				return ScenarioRuntimeOperationResult.failed(&"invalid_party_position", "Classic opcode 70's saved party position is unavailable.")
			var source_map_id := _game_state.party.map_id
			var source_coordinate := _game_state.party.coordinate
			_game_state.party.map_id = target_map.id
			_game_state.party.coordinate = _game_state.saved_party_coordinate
			_game_state.world.exploration.mark_visited(target_map.id, _game_state.saved_party_coordinate)
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"party_position_restored", {"fromMapId": source_map_id, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": target_map.id, "x": _game_state.saved_party_coordinate.x, "y": _game_state.saved_party_coordinate.y, "levelType": String(target_map.level_type), "suppressActionPointDestination": true, "source": "classic-opcode-70"}), DomainEvent.new(&"world_projection_invalidated", {"mapId": target_map.id, "reason": "party-position-restore"})])
	return ScenarioRuntimeOperationResult.completed(false)


func _alter_random_region_geometry(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() != 10:
		return ScenarioRuntimeOperationResult.failed(&"invalid_random_region_geometry", "Classic opcode 92 requires two five-value Extra Code rows.")
	var map_type := &"dungeon" if action.extra_code[2] != 0 else &"land"
	# Castle's PC build falls back to the first map on a negative file seek and
	# explicitly clamps an out-of-range rectangle to slot zero.
	var map_index: int = maxi(action.extra_code[0], 0)
	var region_index: int = action.extra_code[1] if action.extra_code[1] >= 0 and action.extra_code[1] < 20 else 0
	var map := _content.world.map_by_type_and_index(map_type, map_index)
	var region := null if map == null else map.random_region_by_index(region_index)
	if region == null:
		if ClassicCompatibility.source_unavailable(_content, "Data RDD" if map_type == &"dungeon" else "Data RD", map_index):
			return ClassicCompatibility.skip(&"random-region-geometry", "Data RDD" if map_type == &"dungeon" else "Data RD", map_index)
		return ScenarioRuntimeOperationResult.failed(&"unknown_random_region", "Classic opcode 92 references an unavailable random rectangle.")
	var previous := _game_state.world.triggers.random_region(region)
	var edges := previous.bounds_edges()
	if not previous.bounds_overridden:
		edges = [region.bounds.position.x, region.bounds.end.x - 1, region.bounds.position.y, region.bounds.end.y - 1]
	var geometry := action.extra_code.slice(5, 10)
	match action.extra_code[4]:
		0: edges = [geometry[0], geometry[1], geometry[2], geometry[3]]
		1: edges = [edges[0] + geometry[0], edges[1] + geometry[0], edges[2] + geometry[1], edges[3] + geometry[1]]
		2: edges = [edges[0] + geometry[0], edges[1] + geometry[1], edges[2] + geometry[2], edges[3] + geometry[3]]
	var updated := RandomRegionState.new(region.id, RealmzArithmetic.new().signed_16(previous.chance_ten_thousand + action.extra_code[3]), previous.battle_minimum, previous.battle_maximum, previous.random_door_percents(), region.bounds, previous.bounds_overridden)
	if action.extra_code[4] in [0, 1, 2] and not updated.set_bounds_edges(edges):
		return ScenarioRuntimeOperationResult.failed(&"invalid_random_region_geometry", "Classic opcode 92 could not preserve its rectangle geometry.")
	elif previous.bounds_overridden:
		updated.set_bounds_edges(edges)
	_game_state.world.triggers.set_random_region(updated)
	return ScenarioRuntimeOperationResult.completed(region.id, [DomainEvent.new(&"random_region_geometry_changed", {"mapId": map.id, "regionId": region.id, "chanceTenThousand": updated.chance_ten_thousand, "bounds": updated.bounds_edges(), "geometryMode": action.extra_code[4], "offscreen": map.id != _game_state.party.map_id, "source": "classic-opcode-92"}), DomainEvent.new(&"world_projection_invalidated", {"mapId": map.id, "reason": "random-region"})])


func _alter_party_fatigue(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 68 requires a five-value Extra Code row.")
	var previous := _game_state.party.fatigue
	match action.extra_code[0]:
		1:
			_game_state.party.fatigue = 135
		2:
			_game_state.party.fatigue = 4
		3:
			var scaled_fatigue := previous * action.extra_code[1]
			@warning_ignore("integer_division")
			var calculated_fatigue: int = scaled_fatigue / 100
			_game_state.party.fatigue = clampi(calculated_fatigue, 4, 135)
		_:
			return ScenarioRuntimeOperationResult.completed(previous)
	var current := _game_state.party.fatigue
	return ScenarioRuntimeOperationResult.completed(current, [DomainEvent.new(&"fatigue_changed", {"previous": previous, "current": current, "reason": "classic-opcode-68", "source": "classic"})])


func _change_dungeon_heading(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	var previous := _game_state.dungeon_heading
	var randomized := action.operand_id < 1 or action.operand_id > 4
	_game_state.dungeon_heading = _rng.draw_classic(4, &"classic.opcode95.heading") if randomized else action.operand_id
	return ScenarioRuntimeOperationResult.completed(_game_state.dungeon_heading, [DomainEvent.new(&"dungeon_heading_changed", {"previous": previous, "current": _game_state.dungeon_heading, "randomized": randomized, "source": "classic"})])


func _acquire_player_map(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var classic_id := absi(action.operand_id)
	# Castle stores acquired maps in twenty fixed slots. A supplied extra native
	# row remains inspectable; it does not authorize an out-of-bounds state write.
	if _content.classic_records != null and classic_id not in range(20):
		return ClassicCompatibility.skip(&"player-map-slot", "Data MD2", classic_id)
	if _content.classic_records != null:
		return _acquire_native_player_map(action, classic_id, request_id, context)
	var definition := _content.world.player_map_by_classic_id(classic_id)
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_player_map", "Classic opcode 29 references unavailable player-map record %d." % classic_id)
	var unavailable_reference := _player_map_reference_result(definition, context)
	if unavailable_reference != null: return unavailable_reference
	var already_acquired: bool = _game_state.world.exploration.has_map(definition.id)
	_game_state.world.exploration.acquire_map(definition.id)
	var event_payload := {"playerMapId": definition.id, "classicId": definition.classic_id, "name": definition.name, "alreadyAcquired": already_acquired, "source": "classic"}
	if action.operand_id >= 0:
		event_payload.merge({"notificationText": PLAYER_MAP_ACQUIRED_TEXT, "notificationSoundId": PLAYER_MAP_ACQUIRED_SOUND_ID})
	var events: Array[DomainEvent] = [DomainEvent.new(&"player_map_acquired", event_payload)]
	if action.operand_id >= 0:
		return ScenarioRuntimeOperationResult.completed(definition.id, events)
	var request := InteractionRequest.from_payload(request_id, &"acknowledge", {"prompt": definition.name, "presentation": "player-map", "playerMapId": definition.id})
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioInteractionContinuations.player_map(definition.id), events)


func _acquire_native_player_map(action: ClassicActionDefinition, classic_id: int, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var definition := _content.world.player_map_by_classic_id(classic_id)
	var facts := _content.classic_records.player_map_by_id(classic_id)
	if definition == null and facts != null and facts.can_project():
		return ScenarioRuntimeOperationResult.failed(&"unknown_player_map", "The compiler omitted usable native Player Map %d." % classic_id)
	# newland.c acquires the fixed map slot before attempting an optional display.
	var map_id := "classic.player-map.%d" % classic_id
	var payload := {"playerMapId": map_id, "classicId": classic_id, "name": definition.name if definition != null else "", "alreadyAcquired": _game_state.world.exploration.has_map(map_id), "source": "classic"}
	_game_state.world.exploration.acquire_map(map_id)
	if action.operand_id >= 0:
		payload.merge({"notificationText": PLAYER_MAP_ACQUIRED_TEXT, "notificationSoundId": PLAYER_MAP_ACQUIRED_SOUND_ID})
	var events: Array[DomainEvent] = [DomainEvent.new(&"player_map_acquired", payload)]
	if action.operand_id >= 0:
		return ScenarioRuntimeOperationResult.completed(map_id, events)
	if definition == null:
		events.append_array(ClassicCompatibility.skip(&"unavailable-player-map-display", "Data MD2", classic_id).events)
		return ScenarioRuntimeOperationResult.completed(map_id, events)
	var unavailable := _player_map_reference_result(definition, context)
	if unavailable != null:
		if unavailable.state == ScenarioRuntimeOperationResult.State.FAILED: return unavailable
		events.append_array(unavailable.events)
		return ScenarioRuntimeOperationResult.completed(map_id, events)
	var request := InteractionRequest.from_payload(request_id, &"acknowledge", {"prompt": definition.name, "presentation": "player-map", "playerMapId": map_id})
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioInteractionContinuations.player_map(map_id), events)


func _player_map_reference_result(definition: PlayerMapDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if (definition.mode in [PlayerMapDefinition.LAND_CROP, PlayerMapDefinition.DUNGEON_CROP] or _content.classic_records == null and definition.mode == PlayerMapDefinition.PICTURE) and _content.world.map_by_id(definition.map_id) == null:
		if ClassicCompatibility.map_source_unavailable(_content, definition.map_id):
			return ClassicCompatibility.cancel_interaction(&"player-map-source", "Data MD2", definition.classic_id, context)
		return ScenarioRuntimeOperationResult.failed(&"deferred_player_map_reference", "Classic opcode 29 Player Map %d requires source map '%s', which is unavailable." % [definition.classic_id, definition.map_id])
	for field: String in ["picture", "scrolling text", "party marker"]:
		var asset_id := ""
		match field:
			"picture": asset_id = definition.picture_asset_id
			"scrolling text": asset_id = definition.scrolling_text_asset_id
			"party marker": asset_id = definition.party_marker_asset_id
		if not asset_id.is_empty() and not _has_media_asset(asset_id):
			if ClassicCompatibility.media_reference_source_absent(_content, asset_id):
				if field == "party marker": continue
				return ClassicCompatibility.cancel_interaction(&"player-map-media", "Data MD2", definition.classic_id, context)
			return ScenarioRuntimeOperationResult.failed(&"deferred_player_map_reference", "Classic opcode 29 Player Map %d requires unavailable %s asset '%s'." % [definition.classic_id, field, asset_id])
	for marker: PlayerMapMarkerDefinition in definition.markers():
		if not _has_media_asset(marker.icon_asset_id):
			if ClassicCompatibility.media_reference_source_absent(_content, marker.icon_asset_id):
				continue
			return ScenarioRuntimeOperationResult.failed(&"deferred_player_map_reference", "Classic opcode 29 Player Map %d requires unavailable CICN resource %d ('%s')." % [definition.classic_id, marker.classic_icon_id, marker.icon_asset_id])
	return null


func _has_media_asset(asset_id: String) -> bool:
	for asset: MediaAsset in _content.media_assets:
		if asset.id == asset_id:
			return true
	return false


func _move_between_maps(action: ClassicActionDefinition, dungeon_move: bool, activate_destination: bool = false) -> ScenarioRuntimeOperationResult:
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
	if activate_destination and target_map.topology.action_point_is_marked(coordinate, _game_state.world, true):
		events.append(DomainEvent.new(&"destination_trigger_recheck_requested", {"mapId": target_map.id, "x": coordinate.x, "y": coordinate.y, "source": "classic-opcode-20"}))
		return ScenarioRuntimeOperationResult.completed(target_map.id, events, ScenarioVmDirective.finish_timeline())
	# Unlike teleport, opcode 37 returns from newland immediately.
	return ScenarioRuntimeOperationResult.completed(target_map.id, events, ScenarioVmDirective.finish_timeline() if dungeon_move else null)


func _mutate_random_region(action: ClassicActionDefinition, dungeon: bool) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic random-region mutation requires a five-value Extra Code row.")
	var map := _content.world.map_by_type_and_index(&"dungeon" if dungeon else &"land", action.extra_code[0])
	if map == null:
		if ClassicCompatibility.source_unavailable(_content, "Data DL" if dungeon else "Data LD", action.extra_code[0]):
			return ClassicCompatibility.skip(&"random-region-map-mutation", "Data DL" if dungeon else "Data LD", action.extra_code[0])
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic random-region mutation references unavailable map %d." % action.extra_code[0])
	if action.extra_code[1] < 0 or action.extra_code[1] >= 20:
		# FD-SCENARIO-014: safely skip Castle's unchecked array write, not the timeline.
		return ScenarioRuntimeOperationResult.completed(false)
	var region := map.random_region_by_index(action.extra_code[1])
	if region == null:
		if ClassicCompatibility.source_unavailable(_content, "Data RDD" if dungeon else "Data RD", action.extra_code[0]):
			return ClassicCompatibility.skip(&"random-region-mutation", "Data RDD" if dungeon else "Data RD", action.extra_code[0])
		return ScenarioRuntimeOperationResult.failed(&"unknown_random_region", "Classic random-region mutation references unavailable rectangle %d." % action.extra_code[1])
	var previous := _game_state.world.triggers.random_region(region)
	var battle_min := previous.battle_minimum if action.extra_code[3] < 0 else action.extra_code[3]
	var battle_max := previous.battle_maximum if action.extra_code[4] < 0 else action.extra_code[4]
	var updated := RandomRegionState.new(region.id, action.extra_code[2], battle_min, battle_max, previous.random_door_percents(), region.bounds, previous.bounds_overridden)
	if previous.bounds_overridden:
		updated.set_bounds_edges(previous.bounds_edges())
	_game_state.world.triggers.set_random_region(updated)
	return ScenarioRuntimeOperationResult.completed(updated.id, [DomainEvent.new(&"random_region_changed", {"regionId": updated.id, "chanceTenThousand": updated.chance_ten_thousand, "battleMinimum": updated.battle_minimum, "battleMaximum": updated.battle_maximum})])


func _mutate_tile(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 12 requires a five-value Extra Code row.")
	var dungeon := action.extra_code[4] != 0
	var map := _content.world.map_by_type_and_index(&"dungeon" if dungeon else &"land", action.extra_code[0])
	var coordinate := Vector2i(action.extra_code[2], action.extra_code[1]) if dungeon else Vector2i(action.extra_code[1], action.extra_code[2])
	if map == null or map.topology.cell_at(coordinate) == null:
		if _content.classic_records != null and (map != null or ClassicCompatibility.source_unavailable(_content, "Data DL" if dungeon else "Data LD", action.extra_code[0])):
			return ClassicCompatibility.skip(&"tile-mutation", "Data DL" if dungeon else "Data LD", action.extra_code[0])
		return ScenarioRuntimeOperationResult.failed(&"unknown_map_cell", "Classic tile mutation references an unavailable map cell.")
	var terrain_id := "classic.terrain.%d" % action.extra_code[3]
	_game_state.world.topology.replace_terrain(map.id, coordinate, terrain_id)
	return ScenarioRuntimeOperationResult.completed(terrain_id, [DomainEvent.new(&"tile_replaced", {"mapId": map.id, "x": coordinate.x, "y": coordinate.y, "terrainId": terrain_id, "source": "classic"})])


func _mutate_triggers(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 13 requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 13 requires the party's current map.")
	var level_type := current_map.level_type
	if action.extra_code[3] < 0:
		level_type = &"dungeon"
	elif action.extra_code[3] > 0:
		level_type = &"land"
	var map := _content.world.map_by_type_and_index(level_type, action.extra_code[0])
	if map == null:
		if ClassicCompatibility.source_unavailable(_content, "Data DL" if level_type == &"dungeon" else "Data LD", action.extra_code[0]):
			return ClassicCompatibility.skip(&"action-point-map-mutation", "Data DL" if level_type == &"dungeon" else "Data LD", action.extra_code[0])
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic trigger mutation references unavailable map %d." % action.extra_code[0])
	var record_indexes: Array[int] = []
	if action.extra_code[1] != 0:
		record_indexes.append(action.extra_code[1])
	if action.extra_code[3] != 0:
		for record_index: int in range(absi(action.extra_code[3]), absi(action.extra_code[4]) + 1):
			if not record_indexes.has(record_index):
				record_indexes.append(record_index)
	var changed: Array[String] = []
	for record_index: int in record_indexes:
		var trigger := _content.scenario_records.trigger_by_map_record(map.id, record_index)
		if trigger == null:
			continue
		_game_state.world.triggers.set_trigger_chance(trigger.id, action.extra_code[2])
		changed.append(trigger.id)
	return ScenarioRuntimeOperationResult.completed(changed, [DomainEvent.new(&"trigger_chances_changed", {"triggerIds": changed, "chancePercent": action.extra_code[2]})])


func _shift_party(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 61 requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 61 requires the party's current map.")
	var delta := Vector2i(action.extra_code[1], action.extra_code[2])
	var random_shift := action.extra_code[3] != 0
	if random_shift:
		if _content.package_schema_version < 7 and (action.extra_code[1] < 1 or action.extra_code[2] < 1):
			return ScenarioRuntimeOperationResult.failed(&"invalid_shift_range", "Classic opcode 61 random shift ranges must be positive.")
		var x_sign := 1 if _rng.draw(100, &"classic.opcode61.x-sign") < 50 else -1
		var x_magnitude := _rng.draw_between_classic(1, action.extra_code[1], &"classic.opcode61.x-magnitude") if _content.package_schema_version >= 7 else _rng.draw_between(1, action.extra_code[1], &"classic.opcode61.x-magnitude")
		var y_sign := 1 if _rng.draw(100, &"classic.opcode61.y-sign") < 50 else -1
		var y_magnitude := _rng.draw_between_classic(1, action.extra_code[2], &"classic.opcode61.y-magnitude") if _content.package_schema_version >= 7 else _rng.draw_between(1, action.extra_code[2], &"classic.opcode61.y-magnitude")
		delta = Vector2i(x_sign * x_magnitude, y_sign * y_magnitude)
		if _content.package_schema_version >= 7:
			delta = Vector2i(RealmzArithmetic.new().signed_16(delta.x), RealmzArithmetic.new().signed_16(delta.y))
	var source_coordinate := _game_state.party.coordinate
	var requested_coordinate := source_coordinate + delta
	var target_coordinate := requested_coordinate
	# Castle applies the shift before centerpict(), whose land-view recentering
	# collapses either axis back into the 0..89 field at the map boundary.
	if current_map.level_type == &"land":
		target_coordinate = Vector2i(
			clampi(requested_coordinate.x, 0, current_map.topology.width - 1),
			clampi(requested_coordinate.y, 0, current_map.topology.height - 1)
		)
	if current_map.topology.cell_at(target_coordinate) == null:
		if _content.package_schema_version >= 7:
			return ClassicCompatibility.skip(&"unavailable-shift-coordinate", "Data EDCD", action.operand_id)
		return ScenarioRuntimeOperationResult.failed(&"shift_out_of_bounds", "Classic opcode 61 shifts the party outside the current map.")
	_game_state.party.coordinate = target_coordinate
	_game_state.world.exploration.mark_visited(current_map.id, target_coordinate)
	var committed_delta := target_coordinate - source_coordinate
	return ScenarioRuntimeOperationResult.completed(target_coordinate, [DomainEvent.new(&"party_shifted", {
		"mapId": current_map.id,
		"sourceX": source_coordinate.x,
		"sourceY": source_coordinate.y,
		"x": target_coordinate.x,
		"y": target_coordinate.y,
		"deltaX": committed_delta.x,
		"deltaY": committed_delta.y,
		"requestedDeltaX": delta.x,
		"requestedDeltaY": delta.y,
		"clamped": target_coordinate != requested_coordinate,
		"random": random_shift,
		"source": "classic",
	})])


func _adjust_quest_value(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 76 requires a five-value Extra Code row.")
	var quest_id := action.extra_code[0]
	if quest_id < 0 or quest_id >= ClassicCompatibility.quest_limit(_content):
		if _content.package_schema_version >= 7:
			return ClassicCompatibility.skip(&"unavailable-quest-mutation", "quest-slots", quest_id)
		return ScenarioRuntimeOperationResult.failed(&"invalid_quest", "Classic opcode 76 references quest %d outside 0 through 99." % quest_id)
	var value := _game_state.scenario_progress.quest_value(quest_id)
	var events: Array[DomainEvent] = []
	# Castle only mutates slots below 100; its later test reads the full 128-slot bank.
	if quest_id < 100:
		value = clampi(value + action.extra_code[1], -127, 127)
		_game_state.scenario_progress.set_quest_value(quest_id, value)
		events.append(DomainEvent.new(&"quest_value_changed", {"questId": quest_id, "value": value, "delta": action.extra_code[1], "source": "classic"}))
	if action.extra_code[3] == 0 or value < action.extra_code[3]:
		return ScenarioRuntimeOperationResult.completed(value, events)
	var directive: ScenarioVmDirective = null
	match action.extra_code[2]:
		1:
			directive = ScenarioVmDirective.branch_xap(action.extra_code[4], action.gosub)
		2:
			directive = ScenarioVmDirective.enter_encounter(&"simple", action.extra_code[4], action.gosub)
		3:
			directive = ScenarioVmDirective.enter_encounter(&"complex", action.extra_code[4], action.gosub)
		_:
			return ScenarioRuntimeOperationResult.completed(value, events)
	return ScenarioRuntimeOperationResult.completed(true, events, directive)


func _back_up_party() -> ScenarioRuntimeOperationResult:
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 101 requires the party's current map.")
	if current_map.level_type == &"dungeon":
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"party_backup_ignored", {"reason": "dungeon", "source": "classic"})])
	if _game_state.last_move_direction == Vector2i.ZERO:
		return ScenarioRuntimeOperationResult.failed(&"missing_move_direction", "Classic opcode 101 requires a prior party movement direction.")
	var source_coordinate := _game_state.party.coordinate
	var target_coordinate := source_coordinate - _game_state.last_move_direction
	if current_map.topology.cell_at(target_coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"backup_out_of_bounds", "Classic opcode 101 backs the party outside the current map.")
	_game_state.party.coordinate = target_coordinate
	_game_state.world.exploration.mark_visited(current_map.id, target_coordinate)
	return ScenarioRuntimeOperationResult.completed(target_coordinate, [DomainEvent.new(&"party_backed_up", {
		"mapId": current_map.id,
		"sourceX": source_coordinate.x,
		"sourceY": source_coordinate.y,
		"x": target_coordinate.x,
		"y": target_coordinate.y,
		"directionX": _game_state.last_move_direction.x,
		"directionY": _game_state.last_move_direction.y,
		"source": "classic",
	})], ScenarioVmDirective.finish_timeline())


func _set_map_darkness(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 106 requires a five-value Extra Code row.")
	var native_values := _content.package_schema_version >= 7 and _content.classic_records != null
	if not native_values and action.extra_code[0] not in [1, 2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_darkness", "Classic opcode 106 darkness value must be 1 or 2.")
	var map := _content.world.map_by_id(_game_state.party.map_id)
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 106 requires the party's current map.")
	var darkness_state := _game_state.world.topology
	var darkness_byte := action.extra_code[0] - 1 if native_values else (1 if action.extra_code[0] == 2 else 0)
	var initial_byte := 1 if map.dark else 0
	if native_values:
		initial_byte = _content.classic_records.initial_map_darkness_byte(map.level_type, map.level_index, initial_byte)
	var current_byte := darkness_state.map_darkness_byte(map.id, initial_byte)
	var unchanged := current_byte == darkness_byte
	if unchanged and action.extra_code[1] != 0:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"map_darkness_unchanged", {"mapId": map.id, "dark": current_byte != 0})], ScenarioVmDirective.finish())
	var assigned_byte := darkness_byte & 0xff if native_values else darkness_byte
	darkness_state.set_map_darkness(map.id, assigned_byte != 0, assigned_byte)
	var dark := assigned_byte != 0
	return ScenarioRuntimeOperationResult.completed(dark, [DomainEvent.new(&"map_darkness_changed", {"mapId": map.id, "dark": dark, "source": "classic"})])


func _test_or_set_party_mode(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 103 requires a five-value Extra Code row.")
	var should_finish := action.extra_code[0] == 1 and not _game_state.party_in_boat or action.extra_code[0] == 2 and _game_state.party_in_boat
	should_finish = should_finish or action.extra_code[1] == 1 and not _game_state.party_camping or action.extra_code[1] == 2 and _game_state.party_camping
	if action.extra_code[2] == 1:
		_game_state.party_in_boat = true
	elif action.extra_code[2] == 2:
		_game_state.party_in_boat = false
	var event := DomainEvent.new(&"party_mode_checked", {"inBoat": _game_state.party_in_boat, "camping": _game_state.party_camping, "finished": should_finish, "source": "classic"})
	return ScenarioRuntimeOperationResult.completed(not should_finish, [event], ScenarioVmDirective.finish() if should_finish else null)
