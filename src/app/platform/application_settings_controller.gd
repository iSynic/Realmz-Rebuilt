## Applies presentation settings and persists changes from the scene-owned settings surface.

class_name ApplicationSettingsController
extends RefCounted

var _application: Control
var _settings: PresentationSettings
var _repository: SettingsRepository
var _shell: GameShell
var _map: ClassicMapPresenter
var _interaction: InteractionPresenter
var _audio: ClassicAudioPresenter
var _presentation: PresentationCoordinator
var _dungeon: DungeonMap3DPresenter
var _held_movement: HeldMovementController
var _debug_tools: DebugToolsHost


func _init(
	application: Control,
	settings: PresentationSettings,
	repository: SettingsRepository,
	shell: GameShell,
	map: ClassicMapPresenter,
	interaction: InteractionPresenter,
	audio: ClassicAudioPresenter,
	presentation: PresentationCoordinator,
	dungeon: DungeonMap3DPresenter,
	held_movement: HeldMovementController,
	debug_tools: DebugToolsHost
) -> void:
	_application = application
	_settings = settings
	_repository = repository
	_shell = shell
	_map = map
	_interaction = interaction
	_audio = audio
	_presentation = presentation
	_dungeon = dungeon
	_held_movement = held_movement
	_debug_tools = debug_tools


func bind() -> void:
	_shell.topology_debug_changed.connect(_on_topology_debug_changed)
	_shell.dungeon_3d_changed.connect(_on_dungeon_3d_changed)
	_shell.master_volume_changed.connect(_on_master_volume_changed)
	_shell.sound_volume_changed.connect(_on_sound_volume_changed)
	_shell.music_volume_changed.connect(_on_music_volume_changed)
	_shell.music_enabled_changed.connect(_on_music_enabled_changed)
	_shell.music_playlist_mode_changed.connect(_on_music_playlist_mode_changed)
	_shell.text_scale_changed.connect(_on_text_scale_changed)
	_shell.typography_mode_changed.connect(_on_typography_mode_changed)
	_shell.ui_scale_mode_changed.connect(_on_ui_scale_mode_changed)
	_shell.window_mode_changed.connect(_on_window_mode_changed)
	_shell.reduced_motion_changed.connect(_on_reduced_motion_changed)
	_shell.reduced_sound_changed.connect(_on_reduced_sound_changed)
	_shell.auto_switch_to_melee_changed.connect(_on_auto_switch_to_melee_changed)
	_shell.exploration_speed_changed.connect(_on_exploration_speed_changed)
	_shell.combat_playback_speed_changed.connect(_on_combat_playback_speed_changed)
	_shell.exploration_minimap_changed.connect(_on_exploration_minimap_changed)
	_shell.classic_exploration_visibility_changed.connect(_on_classic_exploration_visibility_changed)
	_shell.autojournal_changed.connect(_on_autojournal_changed)
	_debug_tools.topology_debug_changed.connect(_on_topology_debug_changed)


func apply_initial_settings() -> void:
	_shell.apply_settings(_settings)
	_presentation.set_reduced_motion(_settings.reduced_motion)
	_presentation.set_combat_playback_speed_percent(_settings.combat_playback_speed_percent)
	_presentation.set_exploration_speed_percent(_settings.exploration_speed_percent)
	_apply_application_theme()
	_interaction.set_text_scale(_settings.text_scale)
	_interaction.set_autojournal_enabled(_settings.autojournal_enabled)
	_map.set_travel_preview_visible(_settings.show_exploration_minimap)
	_map.set_classic_exploration_visibility(_settings.classic_exploration_visibility)
	_apply_window_mode(_settings.window_mode)
	_audio.set_master_volume(_settings.master_volume)
	_audio.set_sound_volume(_settings.sound_volume)
	_audio.set_reduced_sound(_settings.reduced_sound)
	_audio.set_music_volume(_settings.music_volume)
	_apply_topology_debug(_settings.topology_debug)
	_presentation.set_dungeon_3d_enabled(_settings.dungeon_3d)


func _on_topology_debug_changed(enabled: bool) -> void:
	_apply_topology_debug(enabled)
	_settings.topology_debug = enabled
	_save()


func _apply_topology_debug(enabled: bool) -> void:
	_map.set_topology_debug_visible(enabled)
	_debug_tools.set_topology_debug(enabled)


func _on_dungeon_3d_changed(enabled: bool) -> void:
	_presentation.set_dungeon_3d_enabled(enabled)
	_settings.dungeon_3d = enabled
	_save()


func _on_master_volume_changed(value: float) -> void:
	_audio.set_master_volume(value)
	_settings.master_volume = value
	_save()


func _on_sound_volume_changed(value: float) -> void:
	_audio.set_sound_volume(value)
	_settings.sound_volume = clampf(value, 0.0, 1.0)
	_shell.apply_settings(_settings)
	_save()


func _on_music_volume_changed(value: float) -> void:
	_audio.set_music_volume(value)
	_settings.music_volume = clampf(value, 0.0, 1.0)
	_shell.apply_settings(_settings)
	_save()


func _on_music_enabled_changed(enabled: bool) -> void:
	_settings.music_enabled = enabled
	_shell.apply_settings(_settings)
	_save()
	_presentation.refresh_music()


func _on_music_playlist_mode_changed(playlist_id: int, mode: int) -> void:
	if not _settings.set_music_mode(playlist_id, mode):
		return
	_save()
	_presentation.refresh_music()


func _on_text_scale_changed(value: float) -> void:
	_settings.text_scale = value
	_apply_application_theme()
	_interaction.set_text_scale(value)
	_shell.apply_settings(_settings)
	_save()


func _on_ui_scale_mode_changed(value: String) -> void:
	_settings.ui_scale_mode = value
	_shell.apply_settings(_settings)
	_save()


func _on_window_mode_changed(value: String) -> void:
	_settings.window_mode = value
	_apply_window_mode(value)
	_save()


func _apply_window_mode(value: String) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if value == PresentationSettings.BORDERLESS_FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func _apply_application_theme() -> void:
	var base_theme := load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme
	_application.theme = ClassicTypography.themed_copy(base_theme, _settings)


func _on_typography_mode_changed(value: String) -> void:
	if value not in [PresentationSettings.TYPOGRAPHY_CLASSIC, PresentationSettings.TYPOGRAPHY_READABLE]:
		return
	_settings.typography_mode = value
	_apply_application_theme()
	_shell.apply_settings(_settings)
	_save()


func _on_reduced_motion_changed(enabled: bool) -> void:
	_settings.reduced_motion = enabled
	_presentation.set_reduced_motion(enabled)
	_save()


func _on_reduced_sound_changed(enabled: bool) -> void:
	_settings.reduced_sound = enabled
	_audio.set_reduced_sound(enabled)
	_save()


func _on_auto_switch_to_melee_changed(enabled: bool) -> void:
	_settings.auto_switch_to_melee = enabled
	_save()


func _on_exploration_speed_changed(percent: int) -> void:
	_settings.exploration_speed_percent = clampi(snappedi(percent, 25), 25, 400)
	_held_movement.set_speed_percent(_settings.exploration_speed_percent)
	_presentation.set_exploration_speed_percent(_settings.exploration_speed_percent)
	_save()


func _on_combat_playback_speed_changed(percent: int) -> void:
	_settings.combat_playback_speed_percent = clampi(snappedi(percent, 25), 25, 200)
	_presentation.set_combat_playback_speed_percent(_settings.combat_playback_speed_percent)
	_save()


func _on_exploration_minimap_changed(enabled: bool) -> void:
	_settings.show_exploration_minimap = enabled
	_map.set_travel_preview_visible(enabled)
	_save()


func _on_classic_exploration_visibility_changed(enabled: bool) -> void:
	_settings.classic_exploration_visibility = enabled
	_map.set_classic_exploration_visibility(enabled)
	_save()


func _on_autojournal_changed(enabled: bool) -> void:
	_settings.autojournal_enabled = enabled
	_interaction.set_autojournal_enabled(enabled)
	_save()


func _save() -> void:
	_repository.save_settings(_settings)
