class_name PresentationSettings
extends RefCounted

const SCHEMA_VERSION: int = 2

var master_volume: float = 1.0
var topology_debug: bool = false
var text_scale: float = 1.0
var reduced_motion: bool = false
var dungeon_3d: bool = false


func to_data() -> Dictionary:
	return {
		"kind": "realmz2.presentation-settings",
		"schemaVersion": SCHEMA_VERSION,
		"masterVolume": master_volume,
		"topologyDebug": topology_debug,
		"textScale": text_scale,
		"reducedMotion": reduced_motion,
		"dungeon3d": dungeon_3d,
	}


static func from_data(data: Variant) -> PresentationSettings:
	if not data is Dictionary:
		return null
	var schema_value: Variant = data.get("schemaVersion")
	if not schema_value is int and not schema_value is float:
		return null
	var schema_version := int(schema_value)
	if float(schema_version) != float(schema_value):
		return null
	if data.get("kind") != "realmz2.presentation-settings" or schema_version not in [1, SCHEMA_VERSION]:
		return null
	if not data.get("masterVolume") is float or not data.get("topologyDebug") is bool or not data.get("textScale") is float or not data.get("reducedMotion") is bool:
		return null
	if schema_version == SCHEMA_VERSION and not data.get("dungeon3d") is bool:
		return null
	var volume: float = data["masterVolume"]
	var scale: float = data["textScale"]
	if volume < 0.0 or volume > 1.0 or scale < 0.8 or scale > 1.5:
		return null
	var settings := PresentationSettings.new()
	settings.master_volume = volume
	settings.topology_debug = data["topologyDebug"]
	settings.text_scale = scale
	settings.reduced_motion = data["reducedMotion"]
	settings.dungeon_3d = bool(data.get("dungeon3d", false))
	return settings
