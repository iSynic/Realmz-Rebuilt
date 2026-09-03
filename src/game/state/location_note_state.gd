class_name LocationNoteState
extends RefCounted

const MAX_TEXT_BYTES: int = 255
const MAX_NOTES_PER_MAP_KIND: int = 501

var map_id: String = ""
var map_kind: StringName = &""
var level_index: int = -1
var coordinate: Vector2i = Vector2i.ZERO
var native_location_id: int = -1
var darkness_value: int = 0
var record_ordinal: int = -1
var text: String = ""


func _init(note_map_id: String = "", note_map_kind: StringName = &"", note_level_index: int = -1, note_coordinate: Vector2i = Vector2i.ZERO, note_text: String = "", note_darkness_value: int = 0, note_record_ordinal: int = -1) -> void:
	map_id = note_map_id
	map_kind = note_map_kind
	level_index = note_level_index
	coordinate = note_coordinate
	native_location_id = native_id_for(level_index, coordinate)
	darkness_value = note_darkness_value
	record_ordinal = note_record_ordinal
	text = note_text


func id() -> String:
	return key_for(map_id, coordinate)


func to_data() -> Dictionary:
	return {
		"mapId": map_id,
		"mapKind": String(map_kind),
		"levelIndex": level_index,
		"x": coordinate.x,
		"y": coordinate.y,
		"nativeLocationId": native_location_id,
		"darknessValue": darkness_value,
		"recordOrdinal": record_ordinal,
		"text": text,
	}


static func from_data(data: Variant) -> LocationNoteState:
	if not data is Dictionary:
		return null
	for field: String in ["mapId", "mapKind", "levelIndex", "x", "y", "nativeLocationId", "darknessValue", "recordOrdinal", "text"]:
		if not data.has(field):
			return null
	if not data["mapId"] is String or String(data["mapId"]).is_empty() or not data["mapKind"] is String or not data["text"] is String:
		return null
	var map_kind_value := StringName(String(data["mapKind"]))
	if map_kind_value != &"land" and map_kind_value != &"dungeon":
		return null
	var level := _integer(data["levelIndex"])
	var x := _integer(data["x"])
	var y := _integer(data["y"])
	var native_id := _integer(data["nativeLocationId"])
	var darkness := _integer(data["darknessValue"])
	var ordinal := _integer(data["recordOrdinal"])
	var note_text := String(data["text"])
	if level < 0 or x < 0 or y < 0 or native_id != native_id_for(level, Vector2i(x, y)) or darkness < 0 or darkness > 255 or ordinal < 0 or ordinal >= MAX_NOTES_PER_MAP_KIND or note_text.is_empty() or not text_is_valid(note_text):
		return null
	return LocationNoteState.new(String(data["mapId"]), map_kind_value, level, Vector2i(x, y), note_text, darkness, ordinal)


static func text_is_valid(value: String) -> bool:
	return value.to_utf8_buffer().size() <= MAX_TEXT_BYTES


func is_structurally_valid() -> bool:
	return (
		not map_id.is_empty()
		and (map_kind == &"land" or map_kind == &"dungeon")
		and level_index >= 0
		and coordinate.x >= 0
		and coordinate.y >= 0
		and native_location_id == native_id_for(level_index, coordinate)
		and darkness_value >= 0
		and darkness_value <= 255
		and record_ordinal >= 0
		and record_ordinal < MAX_NOTES_PER_MAP_KIND
		and not text.is_empty()
		and text_is_valid(text)
	)


static func key_for(note_map_id: String, note_coordinate: Vector2i) -> String:
	return "%s:%d,%d" % [note_map_id, note_coordinate.x, note_coordinate.y]


static func native_id_for(note_level_index: int, note_coordinate: Vector2i) -> int:
	return 10_000 * note_level_index + note_coordinate.x * 90 + note_coordinate.y


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
