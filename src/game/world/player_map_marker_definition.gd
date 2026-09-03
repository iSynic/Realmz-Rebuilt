class_name PlayerMapMarkerDefinition
extends RefCounted

var classic_icon_id: int
var icon_asset_id: String
var coordinate: Vector2i


func _init(source_icon_id: int, asset_id: String, marker_coordinate: Vector2i) -> void:
	classic_icon_id = source_icon_id
	icon_asset_id = asset_id
	coordinate = marker_coordinate
