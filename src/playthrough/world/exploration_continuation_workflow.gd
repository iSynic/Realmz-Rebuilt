## Builds and validates the saved continuation state around exploration time and movement.

class_name ExplorationContinuationWorkflow
extends RefCounted


static func post_time(context: SessionWorkflowContext, map: MapDefinition, resume_kind: StringName, direction: Vector2i = Vector2i.ZERO, check_random: bool = true, timed_day: int = 0, timed_coordinate: Vector2i = Vector2i(-1, -1)) -> SessionContinuation:
	var cell := map.topology.cell_at(context.state.party.coordinate)
	var exploration := ExplorationContinuationBody.new()
	exploration.map_id = map.id
	exploration.coordinate = context.state.party.coordinate
	exploration.timed_day = timed_day
	exploration.timed_encounter_index = 0
	exploration.active_timed_program_id = ""
	exploration.midnight_recovery_pending = timed_day > 0
	exploration.timed_check_coordinate = timed_coordinate
	exploration.check_random = check_random
	var region_ids: Array[String] = [] if cell == null else context.state.world.triggers.random_region_ids_at(map, context.state.party.coordinate)
	exploration.random_region_ids.assign(region_ids)
	exploration.random_region_index = region_ids.size() - 1
	exploration.active_random_program_id = ""
	exploration.active_random_region_id = ""
	exploration.random_battle_stage = &""
	exploration.resume_kind = resume_kind
	exploration.direction = direction
	return ExplorationContinuations.post_clock(exploration)


static func post_move(context: SessionWorkflowContext, map: MapDefinition, coordinate: Vector2i, destination_depth: int = 0) -> SessionContinuation:
	var cell := map.topology.cell_at(coordinate)
	var exploration := ExplorationContinuationBody.new()
	exploration.map_id = map.id
	exploration.coordinate = coordinate
	exploration.trigger_ids.assign(selected_placed_trigger_ids(context.content, cell, context.state.world))
	exploration.trigger_index = 0
	exploration.active_trigger_id = ""
	var region_ids := context.state.world.triggers.random_region_ids_at(map, coordinate)
	exploration.random_region_ids.assign(region_ids)
	exploration.random_region_index = region_ids.size() - 1
	exploration.active_random_program_id = ""
	exploration.active_random_region_id = ""
	exploration.random_battle_stage = &""
	exploration.action_point_destination_depth = destination_depth
	return ExplorationContinuations.post_move(exploration)


static func rebase_post_time_location(context: SessionWorkflowContext, continuation: SessionContinuation) -> bool:
	var exploration := continuation.exploration()
	if continuation.kind != &"post-clock" or exploration == null:
		return false
	var map := context.content.world.map_by_id(context.state.party.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(context.state.party.coordinate)
	if cell == null:
		return false
	exploration.map_id = map.id
	exploration.coordinate = context.state.party.coordinate
	exploration.timed_check_coordinate = context.state.party.coordinate
	var region_ids := context.state.world.triggers.random_region_ids_at(map, context.state.party.coordinate)
	exploration.random_region_ids.assign(region_ids)
	exploration.random_region_index = region_ids.size() - 1
	return true


static func apply_pending_midnight_recovery(context: SessionWorkflowContext, exploration: ExplorationContinuationBody, events: Array[DomainEvent]) -> void:
	if exploration == null or not exploration.midnight_recovery_pending:
		return
	exploration.midnight_recovery_pending = false
	events.append_array(context.rules.clock.restore_half_day_health(context.state.party, context.content))


static func timed_encounter_requirements_met(context: SessionWorkflowContext, encounter: TimedEncounterDefinition, map: MapDefinition, exploration: ExplorationContinuationBody) -> bool:
	if encounter.required_item_id > 0 and not _party_has_classic_item(context, encounter.required_item_id):
		return false
	if encounter.required_quest_id > -1 and not context.state.scenario_progress.quest_is_set(encounter.required_quest_id):
		return false
	if encounter.location_kind == TimedEncounterDefinition.LocationKind.ANY:
		return true
	if encounter.location_kind == TimedEncounterDefinition.LocationKind.LAND and map.level_type != &"land" or encounter.location_kind == TimedEncounterDefinition.LocationKind.DUNGEON and map.level_type != &"dungeon":
		return false
	if map.level_index != encounter.required_level or exploration == null:
		return false
	var coordinate := exploration.timed_check_coordinate
	if encounter.required_random_rectangle > -1:
		var region := map.random_region_by_index(encounter.required_random_rectangle)
		if region == null or not context.state.world.triggers.random_region(region).contains(region.bounds, coordinate):
			return false
	if encounter.required_x > -1 and coordinate.x != encounter.required_x:
		return false
	if encounter.required_y > -1 and coordinate.y != encounter.required_y:
		return false
	return true


static func selected_placed_trigger_ids(content: RealmzContent, cell: MapCell, world_state: WorldState) -> Array[String]:
	for feature: MapFeature in cell.features():
		if cell.is_land and feature.kind == &"secret" and feature.orientation.is_empty() and not world_state.topology.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
			return []
	var selected_id := ""
	var selected_record_index := 2_147_483_647
	for trigger_id: String in cell.trigger_ids():
		var trigger := content.scenario_records.trigger_by_id(trigger_id)
		if trigger != null and trigger.classic_record_index < selected_record_index:
			selected_id = trigger.id
			selected_record_index = trigger.classic_record_index
	var selected_ids: Array[String] = []
	if not selected_id.is_empty():
		selected_ids.append(selected_id)
	return selected_ids


static func _party_has_classic_item(context: SessionWorkflowContext, classic_item_id: int) -> bool:
	var definition := context.content.items.item_by_classic_id(classic_item_id)
	if definition == null:
		return false
	for character: CharacterState in context.state.party.characters():
		for item: ItemInstance in character.inventory():
			if item.definition_id == definition.id:
				return true
	return false
