class_name PresentationSettings
extends RefCounted

const SCHEMA_VERSION: int = 1

var master_volume: float = 1.0
var topology_debug: bool = false
var text_scale: float = 1.0
var reduced_motion: bool = false


func to_data() -> Dictionary:
	return {
		"kind": "realmz2.presentation-settings",
		"schemaVersion": SCHEMA_VERSION,
		"masterVolume": master_volume,
		"topologyDebug": topology_debug,
		"textScale": text_scale,
		"reducedMotion": reduced_motion,
	}


static func from_data(data: Variant) -> PresentationSettings:
	if not data is Dictionary:
		return null
	if data.get("kind") != "realmz2.presentation-settings" or data.get("schemaVersion") != SCHEMA_VERSION:
		return null
	if not data.get("masterVolume") is float or not data.get("topologyDebug") is bool or not data.get("textScale") is float or not data.get("reducedMotion") is bool:
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
	return settings
