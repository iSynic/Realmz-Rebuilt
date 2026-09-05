## Owns validation and mutation of Classic player-authored map notes.

class_name LocationNoteWorkflow
extends RefCounted


static func set_note(context: SessionWorkflowContext, text: String) -> SessionWorkflowResult:
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null or map.topology.cell_at(context.state.party.coordinate) == null:
		return SessionWorkflowResult.failed(&"location_note_unavailable", "The current map location is unavailable.")
	if not LocationNoteState.text_is_valid(text):
		return SessionWorkflowResult.failed(&"location_note_too_long", "Classic location notes are limited to 255 encoded bytes.")
	var existing := context.state.world.exploration.location_note_at(map.id, context.state.party.coordinate)
	var darkness_value := _current_darkness(context, map)
	if existing == null and not text.is_empty() and context.state.world.exploration.next_location_note_ordinal(map.level_type) < 0:
		return SessionWorkflowResult.failed(&"location_note_capacity", "The Classic location-note file for this map type is full.")
	if existing != null and existing.text == text and existing.darkness_value == darkness_value or existing == null and text.is_empty():
		return SessionWorkflowResult.failed(&"location_note_unchanged", "Change or clear the current location note before saving.")
	var committed := false
	if text.is_empty():
		committed = context.state.world.exploration.remove_location_note(map.id, context.state.party.coordinate)
	else:
		var ordinal := existing.record_ordinal if existing != null else context.state.world.exploration.next_location_note_ordinal(map.level_type)
		committed = context.state.world.exploration.upsert_location_note(LocationNoteState.new(map.id, map.level_type, map.level_index, context.state.party.coordinate, text, darkness_value, ordinal))
	if not committed:
		return SessionWorkflowResult.failed(&"invalid_location_note", "The location note could not be committed.")
	var event_kind: StringName = &"location_note_removed" if text.is_empty() else &"location_note_updated"
	return SessionWorkflowResult.completed([DomainEvent.new(event_kind, {
		"mapId": map.id,
		"x": context.state.party.coordinate.x,
		"y": context.state.party.coordinate.y,
		"textBytes": text.to_utf8_buffer().size(),
		"source": "classic",
	})])


static func _current_darkness(context: SessionWorkflowContext, map: MapDefinition) -> int:
	if map == null or map.level_type == &"dungeon" or not context.state.world.topology.map_is_dark(map):
		return 0
	return clampi(int(context.state.party.conditions.value(0) / 30) + 1, 1, 255)
