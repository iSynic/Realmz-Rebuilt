class_name UiInputActions
extends RefCounted

const DEFINITIONS: Array[Dictionary] = [
	{"id": &"realmz_move_up", "keys": [KEY_UP, KEY_W, KEY_KP_8]},
	{"id": &"realmz_move_up_right", "keys": [KEY_KP_9]},
	{"id": &"realmz_move_right", "keys": [KEY_RIGHT, KEY_D, KEY_KP_6]},
	{"id": &"realmz_move_down_right", "keys": [KEY_KP_3]},
	{"id": &"realmz_move_down", "keys": [KEY_DOWN, KEY_S, KEY_KP_2]},
	{"id": &"realmz_move_down_left", "keys": [KEY_KP_1]},
	{"id": &"realmz_move_left", "keys": [KEY_LEFT, KEY_A, KEY_KP_4]},
	{"id": &"realmz_move_up_left", "keys": [KEY_KP_7]},
	{"id": &"realmz_search", "keys": [KEY_F]},
	{"id": &"realmz_camp", "keys": [KEY_C]},
	{"id": &"realmz_rest", "keys": [KEY_R]},
	{"id": &"realmz_heal", "keys": [KEY_H]},
	{"id": &"realmz_inspect_movement", "keys": [KEY_SHIFT]},
	{"id": &"realmz_target", "keys": [KEY_T]},
	{"id": &"realmz_confirm_target", "keys": [KEY_SPACE]},
	{"id": &"realmz_back", "keys": [KEY_ESCAPE]},
	{"id": &"realmz_debug_tools", "keys": [KEY_F12]},
	{"id": &"realmz_debug_console", "keys": [KEY_QUOTELEFT]},
	{"id": &"ui_screen_explore", "keys": [KEY_1], "alt": true},
	{"id": &"ui_screen_characters", "keys": [KEY_2], "alt": true},
	{"id": &"ui_screen_inventory", "keys": [KEY_3], "alt": true},
	{"id": &"ui_screen_spells", "keys": [KEY_4], "alt": true},
	{"id": &"ui_screen_journal", "keys": [KEY_5], "alt": true},
	{"id": &"ui_screen_system", "keys": [KEY_6], "alt": true},
	{"id": &"ui_screen_vault", "keys": [KEY_7], "alt": true},
	{"id": &"ui_screen_services", "keys": [KEY_8], "alt": true},
	{"id": &"ui_screen_battle", "keys": [KEY_9], "alt": true},
]


static func ensure_defaults() -> void:
	for definition: Dictionary in DEFINITIONS:
		var action_id: StringName = definition["id"]
		if not InputMap.has_action(action_id):
			InputMap.add_action(action_id)
		if not InputMap.action_get_events(action_id).is_empty():
			continue
		for keycode: Key in definition["keys"]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			event.alt_pressed = bool(definition.get("alt", false))
			InputMap.action_add_event(action_id, event)


static func fast_spell_slot(event: InputEvent, allow_alt: bool = false) -> int:
	if not event is InputEventKey:
		return -1
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or (key_event.alt_pressed and not allow_alt) or key_event.physical_keycode < KEY_0 or key_event.physical_keycode > KEY_9:
		return -1
	return 9 if key_event.physical_keycode == KEY_0 else int(key_event.physical_keycode - KEY_1)


static func fast_spell_use_requested(event: InputEvent) -> bool:
	return event is InputEventKey and ((event as InputEventKey).ctrl_pressed or (event as InputEventKey).meta_pressed)


static func combat_fast_spell_use_requested(event: InputEvent) -> bool:
	return event is InputEventKey and ((event as InputEventKey).alt_pressed or fast_spell_use_requested(event))


static func movement_direction(event: InputEvent) -> Vector2i:
	if event.is_action_pressed(&"realmz_move_up"):
		return Vector2i.UP
	if event.is_action_pressed(&"realmz_move_up_right"):
		return Vector2i(1, -1)
	if event.is_action_pressed(&"realmz_move_right"):
		return Vector2i.RIGHT
	if event.is_action_pressed(&"realmz_move_down_right"):
		return Vector2i(1, 1)
	if event.is_action_pressed(&"realmz_move_down"):
		return Vector2i.DOWN
	if event.is_action_pressed(&"realmz_move_down_left"):
		return Vector2i(-1, 1)
	if event.is_action_pressed(&"realmz_move_left"):
		return Vector2i.LEFT
	if event.is_action_pressed(&"realmz_move_up_left"):
		return Vector2i(-1, -1)
	return Vector2i.ZERO


static func released_movement_direction(event: InputEvent) -> Vector2i:
	if event.is_action_released(&"realmz_move_up"):
		return Vector2i.UP
	if event.is_action_released(&"realmz_move_up_right"):
		return Vector2i(1, -1)
	if event.is_action_released(&"realmz_move_right"):
		return Vector2i.RIGHT
	if event.is_action_released(&"realmz_move_down_right"):
		return Vector2i(1, 1)
	if event.is_action_released(&"realmz_move_down"):
		return Vector2i.DOWN
	if event.is_action_released(&"realmz_move_down_left"):
		return Vector2i(-1, 1)
	if event.is_action_released(&"realmz_move_left"):
		return Vector2i.LEFT
	if event.is_action_released(&"realmz_move_up_left"):
		return Vector2i(-1, -1)
	return Vector2i.ZERO
