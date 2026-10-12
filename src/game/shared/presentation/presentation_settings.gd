## Defines the pure gameplay presentation settings contract.

class_name PresentationSettings
extends RefCounted

const SCHEMA_VERSION: int = 26
const INDOOR_PARTY_ICON_COUNT: int = 120
const DEFAULT_INDOOR_PARTY_ICON: int = 72
const MUSIC_SLOT_COUNT: int = 20
const MUSIC_OFF: int = 0
const MUSIC_PLAY: int = 1
const MUSIC_CONTINUE: int = 2
const MUSIC_RESTART_SONG: String = "restart-song"
const MUSIC_RESTART_PLAYLIST: String = "restart-playlist"
const MUSIC_RESUME: String = "resume"
const MUSIC_TRANSITIONS: Array[String] = [MUSIC_RESTART_SONG, MUSIC_RESTART_PLAYLIST, MUSIC_RESUME]

const UI_SCALE_AUTO: String = "auto"
const UI_SCALE_100: String = "100"
const UI_SCALE_125: String = "125"
const UI_SCALE_150: String = "150"
const UI_SCALE_175: String = "175"
const UI_SCALE_200: String = "200"
const UI_SCALE_225: String = "225"
const UI_SCALE_250: String = "250"
const UI_SCALE_275: String = "275"
const UI_SCALE_300: String = "300"
const UI_SCALE_MODES: Array[String] = [UI_SCALE_AUTO, UI_SCALE_100, UI_SCALE_125, UI_SCALE_150, UI_SCALE_175, UI_SCALE_200, UI_SCALE_225, UI_SCALE_250, UI_SCALE_275, UI_SCALE_300]
const DISPLAY_RESPONSIVE: String = "responsive"
const DISPLAY_INTEGER_WINDOW: String = "integer-window"
const DISPLAY_INTEGER_CANVAS: String = "integer-canvas"
const DISPLAY_FILL_WINDOW: String = "fill-window"
const SMOOTHING_OFF: String = "off"
const SMOOTHING_WORLD: String = "world"
const SMOOTHING_WINDOW: String = "window"
const CRT_PI: String = "crt-pi"
const CRT_LOTTES: String = "crt-lottes"
const CRT_WORLD: String = "world"
const CRT_WINDOW: String = "window"
const WINDOWED: String = "windowed"
const BORDERLESS_FULLSCREEN: String = "borderless-fullscreen"
const MENU_VISIBLE: String = "visible"
const MENU_HOVER: String = "hover"
const MENU_HIDDEN: String = "hidden"
const MENU_MODES: Array[String] = [MENU_VISIBLE, MENU_HOVER, MENU_HIDDEN]

var master_volume: float = 1.0
var sound_volume: float = 1.0
var music_volume: float = 0.8
var music_enabled: bool = true
var music_transition: String = MUSIC_RESTART_SONG
var music_playlist_modes: Array[int] = _default_music_modes()
var topology_debug: bool = false
var interface_text_scale: float = 1.0
var narrative_text_scale: float = 1.0
var reduced_motion: bool = false
var reduced_sound: bool = false
var auto_switch_to_melee: bool = true
var dungeon_3d: bool = true
var ui_scale_mode: String = UI_SCALE_AUTO
var display_scaling_mode: String = DISPLAY_INTEGER_CANVAS
var world_zoom: int = 0
var pixel_art_smoothing: String = SMOOTHING_OFF
var crt_enabled: bool = false
var crt_shader: String = CRT_PI
var crt_area: String = CRT_WORLD
var immediate_single_target_actions: bool = false
var click_to_move_enabled: bool = false
var classic_keyboard_shortcuts: bool = false
var window_mode: String = WINDOWED
var exploration_speed_percent: int = 100
var combat_playback_speed_percent: int = 100
var hurry_spell_resolution: bool = false
var show_exploration_minimap: bool = false
var classic_exploration_visibility: bool = true
var custom_fog_tile_enabled: bool = false
var indoor_party_icon: int = DEFAULT_INDOOR_PARTY_ICON
# FD-SYSTEM-002: new players enable Auto Note; Castle's PRFN 128 defaults it off.
var autojournal_enabled: bool = true
var interface_font: String = ""
var narrative_font: String = ""
var menu_visibility: String = MENU_VISIBLE
var show_overworld_command_titles: bool = true
var integer_fit_hidden_commands: bool = false
var last_campaign_id: String = ""
var controller := ControllerPreferences.new()


func to_data() -> Dictionary:
	return {
		"kind": "realmz2.presentation-settings",
		"schemaVersion": SCHEMA_VERSION,
		"masterVolume": master_volume,
		"soundVolume": sound_volume,
		"musicVolume": music_volume,
		"musicEnabled": music_enabled,
		"musicTransition": music_transition,
		"musicPlaylistModes": music_playlist_modes.duplicate(),
		"topologyDebug": topology_debug,
		"interfaceTextScale": interface_text_scale,
		"narrativeTextScale": narrative_text_scale,
		"reducedMotion": reduced_motion,
		"reducedSound": reduced_sound,
		"autoSwitchToMelee": auto_switch_to_melee,
		"dungeon3d": dungeon_3d,
		"uiScaleMode": ui_scale_mode,
		"displayScalingMode": display_scaling_mode,
		"worldZoom": world_zoom,
		"pixelArtSmoothing": pixel_art_smoothing,
		"crtEnabled": crt_enabled,
		"crtShader": crt_shader,
		"crtArea": crt_area,
		"immediateSingleTargetActions": immediate_single_target_actions,
		"clickToMoveEnabled": click_to_move_enabled,
		"classicKeyboardShortcuts": classic_keyboard_shortcuts,
		"windowMode": window_mode,
		"explorationSpeedPercent": exploration_speed_percent,
		"combatPlaybackSpeedPercent": combat_playback_speed_percent,
		"hurrySpellResolution": hurry_spell_resolution,
		"showExplorationMinimap": show_exploration_minimap,
		"classicExplorationVisibility": classic_exploration_visibility,
		"customFogTileEnabled": custom_fog_tile_enabled,
		"indoorPartyIcon": indoor_party_icon,
		"autojournalEnabled": autojournal_enabled,
		"interfaceFont": interface_font,
		"narrativeFont": narrative_font,
		"menuVisibility": menu_visibility,
		"showOverworldCommandTitles": show_overworld_command_titles,
		"integerFitHiddenCommands": integer_fit_hidden_commands,
		"lastCampaignId": last_campaign_id,
		"controller": controller.to_data(),
	}


static func from_data(data: Variant) -> PresentationSettings:
	if not data is Dictionary:
		return null
	var schema_version := _schema_version_from_data(data)
	if schema_version == 0 or not _base_fields_are_valid(data, schema_version) or not _versioned_fields_are_valid(data, schema_version):
		return null
	return _settings_from_valid_data(data)


static func _schema_version_from_data(data: Dictionary) -> int:
	var value: Variant = data.get("schemaVersion")
	if (not value is int and not value is float) or float(int(value)) != float(value):
		return 0
	var version := int(value)
	return version if data.get("kind") == "realmz2.presentation-settings" and version >= 1 and version <= SCHEMA_VERSION else 0


static func _base_fields_are_valid(data: Dictionary, schema_version: int) -> bool:
	if not data.get("masterVolume") is float:
		return false
	if not data.get("topologyDebug") is bool or not data.get("reducedMotion") is bool:
		return false
	var volume: float = data["masterVolume"]
	if schema_version < 25:
		return volume >= 0.0 and volume <= 1.0 and _font_scale_is_valid(data.get("textScale"), 0.8)
	return volume >= 0.0 and volume <= 1.0 and _font_scale_is_valid(data.get("interfaceTextScale")) and _font_scale_is_valid(data.get("narrativeTextScale"))


static func _font_scale_is_valid(value: Variant, minimum: float = 0.5) -> bool:
	return value is float and value >= minimum and value <= 1.5


static func _versioned_fields_are_valid(data: Dictionary, schema_version: int) -> bool:
	if schema_version >= 2 and not data.get("dungeon3d") is bool:
		return false
	if schema_version >= 3 and not _window_fields_are_valid(data, schema_version):
		return false
	if schema_version >= 4 and not data.get("autoSwitchToMelee") is bool:
		return false
	if schema_version >= 5 and not _stepped_number_is_valid(data.get("explorationSpeedPercent"), 25, 400):
		return false
	if schema_version >= 6 and (not data.get("showExplorationMinimap") is bool or not data.get("autojournalEnabled") is bool):
		return false
	if schema_version >= 7 and schema_version < 25 and data.get("typographyMode") not in ["classic", "readable"]:
		return false
	if schema_version >= 8 and not _music_fields_are_valid(data):
		return false
	if schema_version >= 9 and not data.get("classicExplorationVisibility") is bool:
		return false
	if schema_version >= 10 and not data.get("reducedSound") is bool:
		return false
	if schema_version >= 11 and not _stepped_number_is_valid(data.get("combatPlaybackSpeedPercent"), 25, 200):
		return false
	if schema_version >= 12 and not data.get("lastCampaignId") is String:
		return false
	if schema_version >= 13 and not data.get("customFogTileEnabled") is bool:
		return false
	if schema_version >= 16 and not data.get("hurrySpellResolution") is bool:
		return false
	if schema_version >= 17 and not _scaling_fields_are_valid(data, schema_version):
		return false
	if schema_version >= 18 and (not data.get("crtEnabled") is bool or data.get("crtShader") not in [CRT_PI, CRT_LOTTES] or data.get("crtArea") not in [CRT_WORLD, CRT_WINDOW]):
		return false
	if schema_version >= 19 and not data.get("immediateSingleTargetActions") is bool:
		return false
	if schema_version >= 19 and data.has("clickToMoveEnabled") and not data["clickToMoveEnabled"] is bool:
		return false
	if data.has("classicKeyboardShortcuts") and not data["classicKeyboardShortcuts"] is bool:
		return false
	if schema_version >= 20 and not _indoor_icon_is_valid(data.get("indoorPartyIcon")):
		return false
	if schema_version >= 22 and (not data.get("musicTransition") is String or data["musicTransition"] not in MUSIC_TRANSITIONS):
		return false
	if schema_version >= 23 and (not font_choice_is_valid(data.get("interfaceFont")) or not font_choice_is_valid(data.get("narrativeFont")) or data.get("menuVisibility") not in MENU_MODES):
		return false
	if schema_version >= 24 and (not data.get("showOverworldCommandTitles") is bool or not data.get("integerFitHiddenCommands") is bool):
		return false
	return schema_version < 14 or ControllerPreferences.from_data(data.get("controller")) != null


static func font_choice_is_valid(value: Variant) -> bool:
	if not value is String or value.length() > 512:
		return false
	if value.is_empty():
		return true
	var separator: int = value.find(":")
	if separator < 1 or separator == value.length() - 1:
		return false
	var source: String = value.left(separator)
	var identity: String = value.substr(separator + 1)
	if source == "system":
		return identity == identity.strip_edges() and not identity.contains("\n") and not identity.contains("\r")
	if source == "bundled":
		return identity in ["theldrow", "black-chancery", "chicago", "inter", "alegreya-sans", "alegreya-sans-bold", "alegreya"]
	if source != "imported" or identity.length() != 64:
		return false
	for character: String in identity:
		if not character in "0123456789abcdef":
			return false
	return true


static func _indoor_icon_is_valid(value: Variant) -> bool:
	return (value is int or value is float) and float(int(value)) == float(value) and int(value) >= 0 and int(value) < INDOOR_PARTY_ICON_COUNT


static func _window_fields_are_valid(data: Dictionary, schema_version: int) -> bool:
	if not data.get("uiScaleMode") is String or not data.get("windowMode") is String:
		return false
	var modes: Array[String] = [UI_SCALE_AUTO, UI_SCALE_100, UI_SCALE_125, UI_SCALE_150]
	if schema_version >= 21:
		modes = UI_SCALE_MODES
	return data["uiScaleMode"] in modes and data["windowMode"] in [WINDOWED, BORDERLESS_FULLSCREEN]


static func _scaling_fields_are_valid(data: Dictionary, schema_version: int) -> bool:
	var zoom: Variant = data.get("worldZoom")
	return data.get("displayScalingMode") in [DISPLAY_RESPONSIVE, DISPLAY_INTEGER_WINDOW, DISPLAY_INTEGER_CANVAS, DISPLAY_FILL_WINDOW] and (zoom is int or zoom is float) and float(int(zoom)) == float(zoom) and int(zoom) >= (0 if schema_version >= 26 else 1) and int(zoom) <= 4 and data.get("pixelArtSmoothing") in [SMOOTHING_OFF, SMOOTHING_WORLD, SMOOTHING_WINDOW]


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
	if int(data["schemaVersion"]) >= 22:
		settings.music_transition = data["musicTransition"]
	settings.music_playlist_modes = _music_modes_from_data(data.get("musicPlaylistModes", []))
	settings.topology_debug = data["topologyDebug"]
	settings.interface_text_scale = data["interfaceTextScale"] if int(data["schemaVersion"]) >= 25 else data["textScale"]
	settings.narrative_text_scale = data["narrativeTextScale"] if int(data["schemaVersion"]) >= 25 else data["textScale"]
	settings.reduced_motion = data["reducedMotion"]
	settings.reduced_sound = bool(data.get("reducedSound", false))
	settings.auto_switch_to_melee = bool(data.get("autoSwitchToMelee", true))
	settings.dungeon_3d = bool(data.get("dungeon3d", true))
	settings.ui_scale_mode = String(data.get("uiScaleMode", UI_SCALE_AUTO))
	settings.display_scaling_mode = DISPLAY_RESPONSIVE
	settings.world_zoom = 1
	if int(data["schemaVersion"]) >= 17:
		settings.display_scaling_mode = String(data["displayScalingMode"])
		settings.world_zoom = int(data["worldZoom"])
		settings.pixel_art_smoothing = String(data["pixelArtSmoothing"])
	if int(data["schemaVersion"]) >= 18:
		settings.crt_enabled = data["crtEnabled"]
		settings.crt_shader = String(data["crtShader"])
		settings.crt_area = String(data["crtArea"])
	if int(data["schemaVersion"]) >= 19:
		settings.immediate_single_target_actions = data["immediateSingleTargetActions"]
	settings.click_to_move_enabled = bool(data.get("clickToMoveEnabled", false))
	settings.classic_keyboard_shortcuts = bool(data.get("classicKeyboardShortcuts", false))
	settings.window_mode = String(data.get("windowMode", WINDOWED))
	settings.exploration_speed_percent = int(data.get("explorationSpeedPercent", 100))
	settings.combat_playback_speed_percent = int(data.get("combatPlaybackSpeedPercent", 100))
	settings.hurry_spell_resolution = bool(data.get("hurrySpellResolution", false))
	settings.show_exploration_minimap = bool(data.get("showExplorationMinimap", false))
	settings.classic_exploration_visibility = bool(data.get("classicExplorationVisibility", true))
	settings.custom_fog_tile_enabled = bool(data.get("customFogTileEnabled", false))
	if int(data["schemaVersion"]) >= 20:
		settings.indoor_party_icon = int(data["indoorPartyIcon"])
	settings.autojournal_enabled = bool(data.get("autojournalEnabled", false))
	if int(data["schemaVersion"]) >= 23:
		settings.interface_font = data["interfaceFont"]
		settings.narrative_font = data["narrativeFont"]
		settings.menu_visibility = data["menuVisibility"]
	if int(data["schemaVersion"]) < 25 and data.get("typographyMode") == "readable":
		if settings.interface_font.is_empty():
			settings.interface_font = "bundled:alegreya-sans"
		if settings.narrative_font.is_empty():
			settings.narrative_font = "bundled:alegreya"
	if int(data["schemaVersion"]) >= 24:
		settings.show_overworld_command_titles = data["showOverworldCommandTitles"]
		settings.integer_fit_hidden_commands = data["integerFitHiddenCommands"]
	settings.last_campaign_id = String(data.get("lastCampaignId", "")).strip_edges()
	settings.controller = ControllerPreferences.from_data(data["controller"]) if data.has("controller") else ControllerPreferences.new()
	if int(data.get("schemaVersion", 1)) == 14:
		settings.controller.add_top_menu_default_if_available()
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
