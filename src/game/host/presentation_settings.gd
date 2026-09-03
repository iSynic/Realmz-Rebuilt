class_name PresentationSettings
extends RefCounted

const SCHEMA_VERSION: int = 12
const MUSIC_SLOT_COUNT: int = 20
const MUSIC_OFF: int = 0
const MUSIC_PLAY: int = 1
const MUSIC_CONTINUE: int = 2

const UI_SCALE_AUTO: String = "auto"
const UI_SCALE_100: String = "100"
const UI_SCALE_125: String = "125"
const UI_SCALE_150: String = "150"
const WINDOWED: String = "windowed"
const BORDERLESS_FULLSCREEN: String = "borderless-fullscreen"
const TYPOGRAPHY_CLASSIC: String = "classic"
const TYPOGRAPHY_READABLE: String = "readable"

var master_volume: float = 1.0
var sound_volume: float = 1.0
var music_volume: float = 0.8
var music_enabled: bool = true
var music_playlist_modes: Array[int] = _default_music_modes()
var topology_debug: bool = false
var text_scale: float = 1.0
var reduced_motion: bool = false
var reduced_sound: bool = false
var auto_switch_to_melee: bool = true
var dungeon_3d: bool = false
var ui_scale_mode: String = UI_SCALE_AUTO
var window_mode: String = WINDOWED
var exploration_speed_percent: int = 100
var combat_playback_speed_percent: int = 100
var show_exploration_minimap: bool = false
var classic_exploration_visibility: bool = true
var autojournal_enabled: bool = false
var typography_mode: String = TYPOGRAPHY_CLASSIC
var last_campaign_id: String = ""


func to_data() -> Dictionary:
	return {
		"kind": "realmz2.presentation-settings",
		"schemaVersion": SCHEMA_VERSION,
		"masterVolume": master_volume,
		"soundVolume": sound_volume,
		"musicVolume": music_volume,
		"musicEnabled": music_enabled,
		"musicPlaylistModes": music_playlist_modes.duplicate(),
		"topologyDebug": topology_debug,
		"textScale": text_scale,
		"reducedMotion": reduced_motion,
		"reducedSound": reduced_sound,
		"autoSwitchToMelee": auto_switch_to_melee,
		"dungeon3d": dungeon_3d,
		"uiScaleMode": ui_scale_mode,
		"windowMode": window_mode,
		"explorationSpeedPercent": exploration_speed_percent,
		"combatPlaybackSpeedPercent": combat_playback_speed_percent,
		"showExplorationMinimap": show_exploration_minimap,
		"classicExplorationVisibility": classic_exploration_visibility,
		"autojournalEnabled": autojournal_enabled,
		"typographyMode": typography_mode,
		"lastCampaignId": last_campaign_id,
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
	if data.get("kind") != "realmz2.presentation-settings" or schema_version not in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, SCHEMA_VERSION]:
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
	if schema_version >= 5:
		var speed_value: Variant = data.get("explorationSpeedPercent")
		if not speed_value is int and not speed_value is float:
			return null
		var speed := int(speed_value)
		if float(speed) != float(speed_value) or speed < 25 or speed > 400 or speed % 25 != 0:
			return null
	if schema_version >= 6 and (not data.get("showExplorationMinimap") is bool or not data.get("autojournalEnabled") is bool):
		return null
	if schema_version >= 7:
		if not data.get("typographyMode") is String or data["typographyMode"] not in [TYPOGRAPHY_CLASSIC, TYPOGRAPHY_READABLE]:
			return null
	if schema_version >= 8:
		if not data.get("soundVolume") is float or not data.get("musicVolume") is float or not data.get("musicEnabled") is bool or not data.get("musicPlaylistModes") is Array:
			return null
		if float(data["soundVolume"]) < 0.0 or float(data["soundVolume"]) > 1.0 or float(data["musicVolume"]) < 0.0 or float(data["musicVolume"]) > 1.0:
			return null
		var modes := data["musicPlaylistModes"] as Array
		if modes.size() != MUSIC_SLOT_COUNT:
			return null
		for mode: Variant in modes:
			if (not mode is int and not mode is float) or float(int(mode)) != float(mode) or int(mode) not in [MUSIC_OFF, MUSIC_PLAY, MUSIC_CONTINUE]:
				return null
	if schema_version >= 9 and not data.get("classicExplorationVisibility") is bool:
		return null
	if schema_version >= 10 and not data.get("reducedSound") is bool:
		return null
	if schema_version >= 11:
		var combat_speed_value: Variant = data.get("combatPlaybackSpeedPercent")
		if (not combat_speed_value is int and not combat_speed_value is float) or float(int(combat_speed_value)) != float(combat_speed_value) or int(combat_speed_value) < 25 or int(combat_speed_value) > 200 or int(combat_speed_value) % 25 != 0:
			return null
	if schema_version >= 12 and not data.get("lastCampaignId") is String:
		return null
	var volume: float = data["masterVolume"]
	var scale: float = data["textScale"]
	if volume < 0.0 or volume > 1.0 or scale < 0.8 or scale > 1.5:
		return null
	var settings := PresentationSettings.new()
	settings.master_volume = volume
	settings.sound_volume = float(data.get("soundVolume", 1.0))
	settings.music_volume = float(data.get("musicVolume", 0.8))
	settings.music_enabled = bool(data.get("musicEnabled", true))
	settings.music_playlist_modes = _music_modes_from_data(data.get("musicPlaylistModes", []))
	settings.topology_debug = data["topologyDebug"]
	settings.text_scale = scale
	settings.reduced_motion = data["reducedMotion"]
	settings.reduced_sound = bool(data.get("reducedSound", false))
	settings.auto_switch_to_melee = bool(data.get("autoSwitchToMelee", true))
	settings.dungeon_3d = bool(data.get("dungeon3d", false))
	settings.ui_scale_mode = String(data.get("uiScaleMode", UI_SCALE_AUTO))
	settings.window_mode = String(data.get("windowMode", WINDOWED))
	settings.exploration_speed_percent = int(data.get("explorationSpeedPercent", 100))
	settings.combat_playback_speed_percent = int(data.get("combatPlaybackSpeedPercent", 100))
	settings.show_exploration_minimap = bool(data.get("showExplorationMinimap", false))
	settings.classic_exploration_visibility = bool(data.get("classicExplorationVisibility", true))
	settings.autojournal_enabled = bool(data.get("autojournalEnabled", false))
	settings.typography_mode = String(data.get("typographyMode", TYPOGRAPHY_CLASSIC))
	settings.last_campaign_id = String(data.get("lastCampaignId", "")).strip_edges()
	return settings


func music_mode(playlist_id: int) -> int:
	return music_playlist_modes[playlist_id - 1] if playlist_id >= 1 and playlist_id <= MUSIC_SLOT_COUNT else MUSIC_OFF


func set_music_mode(playlist_id: int, mode: int) -> bool:
	if playlist_id < 1 or playlist_id > MUSIC_SLOT_COUNT or mode not in [MUSIC_OFF, MUSIC_PLAY, MUSIC_CONTINUE]:
		return false
	music_playlist_modes[playlist_id - 1] = mode
	return true


static func _default_music_modes() -> Array[int]:
	var result: Array[int] = []
	for _slot: int in MUSIC_SLOT_COUNT:
		result.append(MUSIC_PLAY)
	return result


static func _music_modes_from_data(value: Variant) -> Array[int]:
	if not value is Array or (value as Array).size() != MUSIC_SLOT_COUNT:
		return _default_music_modes()
	var result: Array[int] = []
	for mode: Variant in value as Array:
		result.append(int(mode))
	return result
