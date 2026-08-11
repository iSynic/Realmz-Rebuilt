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
	{"id": &"realmz_back", "keys": [KEY_ESCAPE]},
	{"id": &"ui_screen_explore", "keys": [KEY_1]},
	{"id": &"ui_screen_characters", "keys": [KEY_2]},
	{"id": &"ui_screen_inventory", "keys": [KEY_3]},
	{"id": &"ui_screen_spells", "keys": [KEY_4]},
	{"id": &"ui_screen_journal", "keys": [KEY_5]},
	{"id": &"ui_screen_system", "keys": [KEY_6]},
	{"id": &"ui_screen_vault", "keys": [KEY_7]},
	{"id": &"ui_screen_services", "keys": [KEY_8]},
	{"id": &"ui_screen_battle", "keys": [KEY_9]},
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
			InputMap.action_add_event(action_id, event)


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
