class_name LocationNoteView
extends RefCounted

var id: String = ""
var map_id: String = ""
var map_name: String = ""
var level_type: StringName = &""
var level_index: int = -1
var coordinate: Vector2i = Vector2i.ZERO
var darkness_value: int = 0
var record_ordinal: int = -1
var text: String = ""
var current: bool = false
var preview_map: MapView


func _init(note_map_id: String = "", note_map_name: String = "", note_level_type: StringName = &"", note_level_index: int = -1, note_coordinate: Vector2i = Vector2i.ZERO, note_text: String = "", note_darkness_value: int = 0, note_record_ordinal: int = -1, is_current: bool = false, note_preview_map: MapView = null) -> void:
	map_id = note_map_id
	map_name = note_map_name
	level_type = note_level_type
	level_index = note_level_index
	coordinate = note_coordinate
	darkness_value = note_darkness_value
	record_ordinal = note_record_ordinal
	text = note_text
	current = is_current
	preview_map = note_preview_map
	id = LocationNoteState.key_for(map_id, coordinate)
