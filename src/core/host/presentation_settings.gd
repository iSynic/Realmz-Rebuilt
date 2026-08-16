class_name PresentationSettings
extends RefCounted

const SCHEMA_VERSION: int = 5

const UI_SCALE_AUTO: String = "auto"
const UI_SCALE_100: String = "100"
const UI_SCALE_125: String = "125"
const UI_SCALE_150: String = "150"
const WINDOWED: String = "windowed"
const BORDERLESS_FULLSCREEN: String = "borderless-fullscreen"

var master_volume: float = 1.0
var topology_debug: bool = false
var text_scale: float = 1.0
var reduced_motion: bool = false
var auto_switch_to_melee: bool = true
var dungeon_3d: bool = false
var ui_scale_mode: String = UI_SCALE_AUTO
var window_mode: String = WINDOWED
var exploration_speed_percent: int = 100


func to_data() -> Dictionary:
	return {
		"kind": "realmz2.presentation-settings",
		"schemaVersion": SCHEMA_VERSION,
		"masterVolume": master_volume,
		"topologyDebug": topology_debug,
		"textScale": text_scale,
		"reducedMotion": reduced_motion,
		"autoSwitchToMelee": auto_switch_to_melee,
		"dungeon3d": dungeon_3d,
		"uiScaleMode": ui_scale_mode,
		"windowMode": window_mode,
		"explorationSpeedPercent": exploration_speed_percent,
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
	if data.get("kind") != "realmz2.presentation-settings" or schema_version not in [1, 2, 3, 4, SCHEMA_VERSION]:
		return null
	if not data.get("masterVolume") is float or not data.get("topologyDebug") is bool or not data.get("textScale") is float or not data.get("reducedMotion") is bool:
		return null
	if schema_version >= 2 and not data.get("dungeon3d") is bool:
		return null
	if schema_version >= 3:
		if not data.get("uiScaleMode") is String or not data.get("windowMode") is String:
			return null
		if data["uiScaleMode"] not in [UI_SCALE_AUTO, UI_SCALE_100, UI_SCALE_125, UI_SCALE_150]:
			return null
		if data["windowMode"] not in [WINDOWED, BORDERLESS_FULLSCREEN]:
			return null
	if schema_version >= 4 and not data.get("autoSwitchToMelee") is bool:
		return null
	if schema_version == SCHEMA_VERSION:
		var speed_value: Variant = data.get("explorationSpeedPercent")
		if not speed_value is int and not speed_value is float:
			return null
		var speed := int(speed_value)
		if float(speed) != float(speed_value) or speed < 25 or speed > 400 or speed % 25 != 0:
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
	settings.auto_switch_to_melee = bool(data.get("autoSwitchToMelee", true))
	settings.dungeon_3d = bool(data.get("dungeon3d", false))
	settings.ui_scale_mode = String(data.get("uiScaleMode", UI_SCALE_AUTO))
	settings.window_mode = String(data.get("windowMode", WINDOWED))
	settings.exploration_speed_percent = int(data.get("explorationSpeedPercent", 100))
	return settings
