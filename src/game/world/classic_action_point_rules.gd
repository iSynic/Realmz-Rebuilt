## Selects Castle placed AP records independently of program admission.
class_name ClassicActionPointRules
extends RefCounted


static func selected_placed_trigger_ids(content: RealmzContent, map: MapDefinition, coordinate: Vector2i, world_state: WorldState, destination_recheck: bool = false) -> Array[String]:
	if not map.topology.action_point_is_marked(coordinate, world_state, destination_recheck):
		return []
	return first_placed_trigger_ids(content, map.topology.cell_at(coordinate))


static func first_placed_trigger_ids(content: RealmzContent, cell: MapCell) -> Array[String]:
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
