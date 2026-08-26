class_name PlayerMapView
extends RefCounted

var id: String
var classic_id: int
var name: String
var unavailable_name: String
var acquired: bool
var mode: StringName
var map_id: String
var start: Vector2i
var icon_size: int
var cell_size: int
var picture_asset_id: String
var scrolling_text_asset_id: String
var party_marker_asset_id: String
var picture_rect: Rect2i
var markers: Array[PlayerMapMarkerDefinition]
var note: String
var cells: Array[MapCellView]
var party_marker_visible: bool
var party_coordinate: Vector2i


func _init(definition: PlayerMapDefinition, crop_cells: Array[MapCellView] = [], show_party: bool = false, current_party_coordinate: Vector2i = Vector2i.ZERO, is_acquired: bool = true) -> void:
	id = definition.id
	classic_id = definition.classic_id
	name = definition.name
	unavailable_name = definition.unavailable_name
	acquired = is_acquired
	mode = definition.mode
	map_id = definition.map_id
	start = definition.start
	icon_size = definition.icon_size
	cell_size = 16 if definition.mode == PlayerMapDefinition.DUNGEON_CROP else definition.icon_size
	picture_asset_id = definition.picture_asset_id
	scrolling_text_asset_id = definition.scrolling_text_asset_id
	party_marker_asset_id = definition.party_marker_asset_id
	picture_rect = definition.picture_rect
	markers = definition.markers()
	note = definition.note
	cells = crop_cells.duplicate()
	party_marker_visible = show_party
	party_coordinate = current_party_coordinate
