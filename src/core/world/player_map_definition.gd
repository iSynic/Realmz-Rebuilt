class_name PlayerMapDefinition
extends RefCounted

const SCROLLING_TEXT: StringName = &"scrolling-text"
const PICTURE: StringName = &"picture"
const LAND_CROP: StringName = &"land-crop"
const DUNGEON_CROP: StringName = &"dungeon-crop"

var id: String
var classic_id: int
var name: String
var unavailable_name: String
var mode: StringName
var map_id: String
var start: Vector2i
var icon_size: int
var picture_asset_id: String
var scrolling_text_asset_id: String
var party_marker_asset_id: String
var picture_rect: Rect2i
var _markers: Array[PlayerMapMarkerDefinition]
var note: String


func _init(definition_id: String, source_id: int, display_name: String, hidden_name: String, display_mode: StringName, source_map_id: String, start_coordinate: Vector2i, map_icon_size: int, picture_id: String, text_id: String, party_marker_id: String, authored_picture_rect: Rect2i, authored_markers: Array[PlayerMapMarkerDefinition], authored_note: String) -> void:
	id = definition_id
	classic_id = source_id
	name = display_name
	unavailable_name = hidden_name
	mode = display_mode
	map_id = source_map_id
	start = start_coordinate
	icon_size = map_icon_size
	picture_asset_id = picture_id
	scrolling_text_asset_id = text_id
	party_marker_asset_id = party_marker_id
	picture_rect = authored_picture_rect
	_markers = authored_markers.duplicate()
	note = authored_note


func markers() -> Array[PlayerMapMarkerDefinition]:
	return _markers.duplicate()
