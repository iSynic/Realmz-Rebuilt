## Finds and focuses existing settings without constructing another editor.
class_name PreferencesSearch
extends VBoxContainer

signal result_selected(category: StringName, target: Control)

const SETTINGS_INDEX = [
	{"title": "Display scaling", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/Window & Scale/DisplayTopRow/DisplaySettingsColumn/ScaleGroup/Content/DisplayScalingRow/DisplayScalingPicker", "terms": "screen scale renderer display mode"},
	{"title": "Window mode", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/Window & Scale/DisplayTopRow/DisplaySettingsColumn/ScaleGroup/Content/WindowModeRow/WindowModePicker", "terms": "window fullscreen responsive integer fill resolution"},
	{"title": "Interface size", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/Window & Scale/DisplayTopRow/DisplaySettingsColumn/ScaleGroup/Content/InterfaceScaleRow/InterfaceScalePicker", "terms": "size ui scaling 100 125 150 175 200 225 250 275 300 auto"},
	{"title": "World zoom", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/Window & Scale/DisplayTopRow/DisplaySettingsColumn/ScaleGroup/Content/WorldZoomRow/WorldZoomPicker", "terms": "world map zoom size integer tiles"},
	{"title": "Pixel-art smoothing", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/Image Effects/VisualEffectsGroup/Content/PixelSmoothingRow/PixelSmoothingPicker", "terms": "pixels xbrz filter smooth image"},
	{"title": "CRT effect", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/Image Effects/VisualEffectsGroup/Content/CrtEnabled", "terms": "crt television scanline phosphor shader"},
	{"title": "CRT shader", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/Image Effects/VisualEffectsGroup/Content/CrtShaderRow/CrtShaderPicker", "terms": "crt pi lottes filter preset"},
	{"title": "CRT area", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/Image Effects/VisualEffectsGroup/Content/CrtAreaRow/CrtAreaPicker", "terms": "crt world canvas whole window scope"},
	{"title": "3D dungeons", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/World View/WorldViewGroup/Content/WorldOptions/Dungeon3d", "terms": "dungeon rendering 3d"},
	{"title": "Exploration visibility", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/World View/WorldViewGroup/Content/WorldOptions/ClassicExplorationVisibility", "terms": "exploration map visited distance visibility"},
	{"title": "Fog-of-war tile", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/World View/WorldViewGroup/Content/WorldOptions/CustomFogTile", "terms": "fog black tile hidden unseen map"},
	{"title": "Indoor party icon", "category": &"Display", "path": ^"Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/World View/WorldViewGroup/Content/IndoorPartyIcon/Summary/Change", "terms": "icon portrait party dungeon marker"},
	{"title": "Interface font", "category": &"Interface", "path": ^"Interface/InterfaceSettingsScroll/InterfaceSettingsPanel/Content/InterfaceTabs/Text/InterfaceFontRow/ChooseFont", "terms": "font typeface text ui classic installed imported"},
	{"title": "Interface text size", "category": &"Interface", "path": ^"Interface/InterfaceSettingsScroll/InterfaceSettingsPanel/Content/InterfaceTabs/Text/InterfaceTextScaleRow/TextScaleSlider", "terms": "font size percentage ui interface"},
	{"title": "Narrative font", "category": &"Interface", "path": ^"Interface/InterfaceSettingsScroll/InterfaceSettingsPanel/Content/InterfaceTabs/Text/NarrativeFontRow/ChooseFont", "terms": "font typeface story text classic installed imported"},
	{"title": "Narrative text size", "category": &"Interface", "path": ^"Interface/InterfaceSettingsScroll/InterfaceSettingsPanel/Content/InterfaceTabs/Text/NarrativeTextScaleRow/TextScaleSlider", "terms": "font size percentage story narrative"},
	{"title": "Overworld command titles", "category": &"Interface", "path": ^"Interface/InterfaceSettingsScroll/InterfaceSettingsPanel/Content/InterfaceTabs/Commands/OverworldCommandTitles", "terms": "command titles captions search torch visible hide"},
	{"title": "Fit hidden command art", "category": &"Interface", "path": ^"Interface/InterfaceSettingsScroll/InterfaceSettingsPanel/Content/InterfaceTabs/Commands/FitHiddenCommandArt", "terms": "command icon art size fit scale"},
	{"title": "HUD panels", "category": &"Interface", "path": ^"Interface/InterfaceSettingsScroll/InterfaceSettingsPanel/Content/InterfaceTabs/HUD panels/SettingsScroll/SettingsPanel/Content/LayoutGroup/Content/LayoutRow/LayoutChoice", "terms": "hud panels fixed modular layout roster narration world party"},
	{"title": "Master volume", "category": &"Audio", "path": ^"Audio/AudioSettingsScroll/AudioSettingsPanel/Content/MasterVolumeRow/MasterVolumeSlider", "terms": "sound audio loudness volume"},
	{"title": "Sound effects volume", "category": &"Audio", "path": ^"Audio/AudioSettingsScroll/AudioSettingsPanel/Content/SoundVolumeRow/SoundVolumeSlider", "terms": "sound effects volume audio"},
	{"title": "Music volume", "category": &"Audio", "path": ^"Audio/AudioSettingsScroll/AudioSettingsPanel/Content/MusicVolumeRow/MusicVolumeSlider", "terms": "music volume audio loudness"},
	{"title": "Music enabled", "category": &"Audio", "path": ^"Audio/AudioSettingsScroll/AudioSettingsPanel/Content/MusicEnabled", "terms": "music on off soundtrack"},
	{"title": "Music transitions", "category": &"Audio", "path": ^"Audio/AudioSettingsScroll/AudioSettingsPanel/Content/MusicTransitionRow/MusicTransition", "terms": "music restart resume playlist transition"},
	{"title": "Music library and playlists", "category": &"Audio", "path": ^"Audio/AudioSettingsScroll/AudioSettingsPanel/Content/OpenMusicPlaylist", "terms": "music library playlist tracks import"},
	{"title": "Combat and animation speed", "category": &"Pacing", "path": ^"Pacing/PacingSettingsScroll/PacingSettingsPanel/Content/CombatSpeedRow/CombatPlaybackSpeedSlider", "terms": "speed combat animation timing playback"},
	{"title": "Scrolling combat text speed", "category": &"Pacing", "path": ^"Pacing/PacingSettingsScroll/PacingSettingsPanel/Content/CombatTextSpeedRow/CombatTextSpeedSlider", "terms": "damage healing status buff resist floating scrolling text speed reading duration"},
	{"title": "Condense multi-target playback", "category": &"Pacing", "path": ^"Pacing/PacingSettingsScroll/PacingSettingsPanel/Content/HurrySpellResolution", "terms": "speed combat spell multi target animation shorten"},
	{"title": "Combat text background opacity", "category": &"Pacing", "path": ^"Pacing/PacingSettingsScroll/PacingSettingsPanel/Content/CombatTextBackgroundRow/CombatTextBackgroundSlider", "terms": "combat damage spell status text background opacity transparent backing plate"},
	{"title": "Exploration movement speed", "category": &"Pacing", "path": ^"Pacing/PacingSettingsScroll/PacingSettingsPanel/Content/MovementSpeedRow/ExplorationSpeedSlider", "terms": "movement speed travel overworld walking"},
	{"title": "Reduced motion", "category": &"Accessibility", "path": ^"Accessibility/AccessibilitySettingsScroll/AccessibilitySettingsPanel/Content/ReducedMotion", "terms": "accessibility animation effects motion"},
	{"title": "Reduce modal sounds", "category": &"Accessibility", "path": ^"Accessibility/AccessibilitySettingsScroll/AccessibilitySettingsPanel/Content/ReducedSound", "terms": "accessibility audio sound effects quiet"},
	{"title": "Move to with a click", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Keyboard & Mouse/ClickToMove", "terms": "mouse click movement destination move to"},
	{"title": "WASD or Classic keyboard shortcuts", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Keyboard & Mouse/ClassicKeyboardShortcuts", "terms": "keyboard keys wasd arrows classic movement"},
	{"title": "Auto-switch to melee", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Gameplay/AutoSwitchToMelee", "terms": "combat weapon melee automatic"},
	{"title": "Immediate single-target actions", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Gameplay/ImmediateSingleTargetActions", "terms": "combat action target confirm"},
	{"title": "Exploration minimap", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Gameplay/ShowExplorationMinimap", "terms": "map minimap exploration world"},
	{"title": "Autojournal", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Gameplay/AutojournalEnabled", "terms": "journal log notes automatic"},
	{"title": "Controller button bindings", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Controller/ControllerSettings/Content/BindingColumn/Content/BindingRows/ControllerBinding_confirm", "terms": "controller gamepad keybindings button rebind confirm"},
	{"title": "Controller back binding", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Controller/ControllerSettings/Content/BindingColumn/Content/BindingRows/ControllerBinding_back", "terms": "controller gamepad keybindings cancel back"},
	{"title": "Controller prompt style", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Controller/ControllerSettings/Content/TuningColumn/PromptFamily", "terms": "controller xbox playstation switch prompts"},
	{"title": "Controller left stick dead zone", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Controller/ControllerSettings/Content/TuningColumn/LeftDeadZone", "terms": "controller stick sensitivity drift deadzone"},
	{"title": "Controller right stick dead zone", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Controller/ControllerSettings/Content/TuningColumn/RightDeadZone", "terms": "controller stick sensitivity drift deadzone"},
	{"title": "Controller repeat delay", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Controller/ControllerSettings/Content/TuningColumn/RepeatInitial", "terms": "controller repeat speed navigation delay"},
	{"title": "Controller repeat interval", "category": &"Controls", "path": ^"Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Controller/ControllerSettings/Content/TuningColumn/RepeatInterval", "terms": "controller repeat speed navigation interval"},
	{"title": "Action point and encounter overlays", "category": &"Diagnostics", "path": ^"Diagnostics/DiagnosticsSettingsScroll/DiagnosticsSettingsPanel/Content/TopologyDebug", "terms": "diagnostics action points ap random rectangles encounters map"},
]

@onready var _search_field: LineEdit = $SearchRow/SearchField
@onready var _clear_button: Button = $SearchRow/ClearButton
@onready var _results: ItemList = $Results

var _pages: TabContainer


func _ready() -> void:
	_search_field.text_changed.connect(_on_search_text_changed)
	_clear_button.pressed.connect(_on_clear_pressed)
	_results.item_activated.connect(_on_result_activated)
	_refresh_results()


func bind_pages(tabs: TabContainer) -> void:
	_pages = tabs
	_refresh_results()


func hide_results() -> void:
	_results.visible = false
	_clear_button.visible = false


func _on_search_text_changed(_text: String) -> void:
	_refresh_results()


func _on_clear_pressed() -> void:
	_search_field.clear()
	_refresh_results()
	_search_field.grab_focus()


func _refresh_results() -> void:
	_results.clear()
	var query := _search_field.text.strip_edges().to_lower()
	var searching := not query.is_empty() and _pages != null
	_results.visible = searching
	_clear_button.visible = searching
	if not searching:
		return

	var query_terms := query.split(" ", false)
	var match_count := 0
	for index in SETTINGS_INDEX.size():
		var entry: Dictionary = SETTINGS_INDEX[index]
		if not _matches(entry, query_terms) or _resolve_target(entry) == null:
			continue
		var category: StringName = entry["category"]
		var title: String = entry["title"]
		var item_index := _results.add_item(title)
		_results.set_item_tooltip(item_index, "%s · %s" % [category, title])
		_results.set_item_metadata(item_index, index)
		match_count += 1

	if match_count == 0:
		var empty_index := _results.add_item("No matching settings")
		_results.set_item_selectable(empty_index, false)


func _matches(entry: Dictionary, query_terms: PackedStringArray) -> bool:
	var searchable := "%s %s %s" % [entry["category"], entry["title"], entry["terms"]]
	searchable = searchable.to_lower()
	for term in query_terms:
		if not searchable.contains(term):
			return false
	return true


func _resolve_target(entry: Dictionary) -> Control:
	if _pages == null:
		return null
	return _pages.get_node_or_null(entry["path"]) as Control


func _on_result_activated(item_index: int) -> void:
	var setting_index := int(_results.get_item_metadata(item_index))
	if setting_index < 0 or setting_index >= SETTINGS_INDEX.size():
		return
	var entry: Dictionary = SETTINGS_INDEX[setting_index]
	var target := _resolve_target(entry)
	if target == null:
		return
	result_selected.emit(StringName(entry["category"]), target)
