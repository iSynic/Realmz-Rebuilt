## Defines the pure gameplay presentation settings contract.

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
	var schema_version := _schema_version_from_data(data)
	if schema_version == 0 or not _base_fields_are_valid(data) or not _versioned_fields_are_valid(data, schema_version):
		return null
	return _settings_from_valid_data(data)


static func _schema_version_from_data(data: Dictionary) -> int:
	var value: Variant = data.get("schemaVersion")
	if (not value is int and not value is float) or float(int(value)) != float(value):
		return 0
	var version := int(value)
	return version if data.get("kind") == "realmz2.presentation-settings" and version >= 1 and version <= SCHEMA_VERSION else 0


static func _base_fields_are_valid(data: Dictionary) -> bool:
	if not data.get("masterVolume") is float or not data.get("textScale") is float:
		return false
	if not data.get("topologyDebug") is bool or not data.get("reducedMotion") is bool:
		return false
	var volume: float = data["masterVolume"]
	var scale: float = data["textScale"]
	return volume >= 0.0 and volume <= 1.0 and scale >= 0.8 and scale <= 1.5


static func _versioned_fields_are_valid(data: Dictionary, schema_version: int) -> bool:
	if schema_version >= 2 and not data.get("dungeon3d") is bool:
		return false
	if schema_version >= 3 and not _window_fields_are_valid(data):
		return false
	if schema_version >= 4 and not data.get("autoSwitchToMelee") is bool:
		return false
	if schema_version >= 5 and not _stepped_number_is_valid(data.get("explorationSpeedPercent"), 25, 400):
		return false
	if schema_version >= 6 and (not data.get("showExplorationMinimap") is bool or not data.get("autojournalEnabled") is bool):
		return false
	if schema_version >= 7 and (not data.get("typographyMode") is String or data["typographyMode"] not in [TYPOGRAPHY_CLASSIC, TYPOGRAPHY_READABLE]):
		return false
	if schema_version >= 8 and not _music_fields_are_valid(data):
		return false
	if schema_version >= 9 and not data.get("classicExplorationVisibility") is bool:
		return false
	if schema_version >= 10 and not data.get("reducedSound") is bool:
		return false
	if schema_version >= 11 and not _stepped_number_is_valid(data.get("combatPlaybackSpeedPercent"), 25, 200):
		return false
	return schema_version < 12 or data.get("lastCampaignId") is String


static func _window_fields_are_valid(data: Dictionary) -> bool:
	if not data.get("uiScaleMode") is String or not data.get("windowMode") is String:
		return false
	return data["uiScaleMode"] in [UI_SCALE_AUTO, UI_SCALE_100, UI_SCALE_125, UI_SCALE_150] and data["windowMode"] in [WINDOWED, BORDERLESS_FULLSCREEN]


static func _music_fields_are_valid(data: Dictionary) -> bool:
	if not data.get("soundVolume") is float or not data.get("musicVolume") is float:
		return false
	if not data.get("musicEnabled") is bool or not data.get("musicPlaylistModes") is Array:
		return false
	if float(data["soundVolume"]) < 0.0 or float(data["soundVolume"]) > 1.0 or float(data["musicVolume"]) < 0.0 or float(data["musicVolume"]) > 1.0:
		return false
	var modes := data["musicPlaylistModes"] as Array
	if modes.size() != MUSIC_SLOT_COUNT:
		return false
	for mode: Variant in modes:
		if (not mode is int and not mode is float) or float(int(mode)) != float(mode) or int(mode) not in [MUSIC_OFF, MUSIC_PLAY, MUSIC_CONTINUE]:
			return false
	return true


static func _stepped_number_is_valid(value: Variant, minimum: int, maximum: int) -> bool:
	if not value is int and not value is float:
		return false
	var number := int(value)
	return float(number) == float(value) and number >= minimum and number <= maximum and number % 25 == 0


static func _settings_from_valid_data(data: Dictionary) -> PresentationSettings:
	var settings := PresentationSettings.new()
	settings.master_volume = data["masterVolume"]
	settings.sound_volume = float(data.get("soundVolume", 1.0))
	settings.music_volume = float(data.get("musicVolume", 0.8))
	settings.music_enabled = bool(data.get("musicEnabled", true))
	settings.music_playlist_modes = _music_modes_from_data(data.get("musicPlaylistModes", []))
	settings.topology_debug = data["topologyDebug"]
	settings.text_scale = data["textScale"]
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
