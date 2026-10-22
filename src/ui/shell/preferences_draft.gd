## Detached application preferences; editable values never change live navigation.
class_name PreferencesDraft
extends RefCounted

var baseline: PresentationSettings
var values: PresentationSettings


func reset(settings: PresentationSettings) -> void:
	baseline = PresentationSettings.from_data(settings.to_data())
	values = PresentationSettings.from_data(settings.to_data())


func is_dirty() -> bool:
	return values != null and values.to_data() != baseline.to_data()


func validation_error() -> String:
	if values == null or PresentationSettings.from_data(values.to_data()) == null:
		return "One or more settings are invalid."
	if not values.controller.required_navigation_is_reachable():
		return "Restore the missing controller navigation bindings before applying."
	if not values.controller.conflicts().is_empty():
		return "Resolve controller binding conflicts before applying."
	return ""


func set_value(setting_id: StringName, value: Variant) -> void:
	match setting_id:
		&"hud": values.hud = (value as HudPreferences).duplicate_value()
		&"music_transition": values.music_transition = String(value)
		&"ui_scale_mode": values.ui_scale_mode = String(value)
		&"display_scaling_mode": values.display_scaling_mode = String(value)
		&"pixel_art_smoothing": values.pixel_art_smoothing = String(value)
		&"crt_shader": values.crt_shader = String(value)
		&"crt_area": values.crt_area = String(value)
		&"window_mode": values.window_mode = String(value)
		&"interface_font": values.interface_font = String(value)
		&"narrative_font": values.narrative_font = String(value)
		&"music_enabled": values.music_enabled = bool(value)
		&"topology_debug": values.topology_debug = bool(value)
		&"reduced_motion": values.reduced_motion = bool(value)
		&"reduced_sound": values.reduced_sound = bool(value)
		&"auto_switch_to_melee": values.auto_switch_to_melee = bool(value)
		&"dungeon_3d": values.dungeon_3d = bool(value)
		&"crt_enabled": values.crt_enabled = bool(value)
		&"immediate_single_target_actions": values.immediate_single_target_actions = bool(value)
		&"click_to_move_enabled": values.click_to_move_enabled = bool(value)
		&"classic_keyboard_shortcuts": values.classic_keyboard_shortcuts = bool(value)
		&"hurry_spell_resolution": values.hurry_spell_resolution = bool(value)
		&"show_exploration_minimap": values.show_exploration_minimap = bool(value)
		&"classic_exploration_visibility": values.classic_exploration_visibility = bool(value)
		&"custom_fog_tile_enabled": values.custom_fog_tile_enabled = bool(value)
		&"autojournal_enabled": values.autojournal_enabled = bool(value)
		&"show_overworld_command_titles": values.show_overworld_command_titles = bool(value)
		&"integer_fit_hidden_commands": values.integer_fit_hidden_commands = bool(value)
		&"world_zoom": values.world_zoom = int(value)
		&"exploration_speed_percent": values.exploration_speed_percent = int(value)
		&"combat_text_speed_percent": values.combat_text_speed_percent = int(value)
		&"combat_text_background_opacity_percent": values.combat_text_background_opacity_percent = int(value)
		&"combat_text_motion", &"combat_text_size_percent", &"combat_text_travel_logical_pixels", &"combat_text_anchor", &"combat_text_custom_offset_y_logical_pixels":
			_set_combat_text_value(setting_id, value)
		&"combat_playback_speed_percent": values.combat_playback_speed_percent = int(value)
		&"indoor_party_icon": values.indoor_party_icon = int(value)
		&"master_volume": values.master_volume = float(value)
		&"sound_volume": values.sound_volume = float(value)
		&"music_volume": values.music_volume = float(value)
		&"interface_text_scale": values.interface_text_scale = float(value)
		&"narrative_text_scale": values.narrative_text_scale = float(value)


func _set_combat_text_value(setting_id: StringName, value: Variant) -> void:
	match setting_id:
		&"combat_text_motion":
			if value is String:
				values.combat_text_motion = value
		&"combat_text_size_percent":
			if value is int:
				values.combat_text_size_percent = value
			elif value is float:
				var size_number: float = value
				values.combat_text_size_percent = int(size_number)
		&"combat_text_travel_logical_pixels":
			if value is int:
				values.combat_text_travel_logical_pixels = value
			elif value is float:
				var travel_number: float = value
				values.combat_text_travel_logical_pixels = int(travel_number)
		&"combat_text_anchor":
			if value is String:
				values.combat_text_anchor = value
		&"combat_text_custom_offset_y_logical_pixels":
			if value is int:
				values.combat_text_custom_offset_y_logical_pixels = value
			elif value is float:
				var offset_y_number: float = value
				values.combat_text_custom_offset_y_logical_pixels = int(offset_y_number)
