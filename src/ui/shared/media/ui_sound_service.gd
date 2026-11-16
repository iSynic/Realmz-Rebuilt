## Plays the short interface sounds on menu-style screens: navigate on keyboard or controller
## focus, confirm, cancel, toggle and apply on button presses, and error on request. Classic
## in-game screens stay silent here; they keep their own Classic sounds.

class_name UiSoundService
extends RefCounted

const SOUND_DIR := "res://src/ui/shared/assets/ui/sounds/"
const SOUNDS: Array[StringName] = [&"navigate", &"confirm", &"cancel", &"toggle", &"apply", &"error"]
## Words that mark a button as leaving or undoing rather than confirming.
const CANCEL_WORDS: Array[String] = ["back", "cancel", "discard", "close", "keep editing", "undo", "dismiss"]
const APPLY_WORDS: Array[String] = ["apply", "save"]
## Buttons that hand over to something with its own sound; they stay silent.
const SILENT_WORDS: Array[String] = ["begin adventure"]
## Focus can move many times a second with a held direction; closer repeats are dropped.
const NAVIGATE_GAP_MSEC := 45
const BOUND := &"ui_sound_bound"

static var _tree: SceneTree
static var _player: AudioStreamPlayer
static var _streams: Dictionary = {}
static var _volume := 1.0
static var _last_navigate_msec := 0


## Starts listening on `tree`; safe to call again.
static func attach(tree: SceneTree) -> void:
	if tree == null or tree == _tree:
		return
	_tree = tree
	_player = AudioStreamPlayer.new()
	_player.name = "UiSoundPlayer"
	_player.max_polyphony = 4
	tree.root.add_child.call_deferred(_player)
	tree.node_added.connect(_bind)
	for node: Node in tree.root.find_children("*", "BaseButton", true, false):
		_bind(node)


## Linear volume, the product of the master and sound-effect sliders.
static func set_volume(linear: float) -> void:
	_volume = clampf(linear, 0.0, 1.0)


## Plays one of SOUNDS now, wherever the caller is.
static func play(sound: StringName) -> void:
	if sound == &"" or _player == null or not _player.is_inside_tree() or _volume <= 0.0:
		return
	if not _streams.has(sound):
		var path := "%sui-%s.wav" % [SOUND_DIR, sound]
		_streams[sound] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	var stream := _streams[sound] as AudioStream
	if stream == null:
		return
	_player.stream = stream
	_player.volume_db = linear_to_db(_volume)
	_player.play()


static func _bind(node: Node) -> void:
	var button := node as BaseButton
	# A node re-entering the tree is announced again; bind each button once.
	if button == null or button.has_meta(BOUND):
		return
	button.set_meta(BOUND, true)
	button.pressed.connect(_on_pressed.bind(button.get_instance_id()))
	button.focus_entered.connect(_on_focused.bind(button.get_instance_id()))


static func _on_pressed(instance_id: int) -> void:
	var button := instance_from_id(instance_id) as BaseButton
	if button != null and UiThemeService.is_menu_control(button):
		play(sound_for(button))


static func _on_focused(instance_id: int) -> void:
	var button := instance_from_id(instance_id) as BaseButton
	# A mouse click also moves focus; only keyboard and controller movement ticks.
	if button == null or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not UiThemeService.is_menu_control(button):
		return
	var now := Time.get_ticks_msec()
	if now - _last_navigate_msec < NAVIGATE_GAP_MSEC:
		return
	_last_navigate_msec = now
	play(&"navigate")


## Which sound pressing `button` makes, from its label and kind.
static func sound_for(button: BaseButton) -> StringName:
	# Labels are matched from their first word, so "Edit save…" confirms and "Save revision" applies.
	var text := String(button.get("text")).to_lower().trim_prefix("‹").strip_edges() if "text" in button else ""
	for word: String in SILENT_WORDS:
		if text.begins_with(word):
			return &""
	for word: String in APPLY_WORDS:
		if text.begins_with(word):
			return &"apply"
	for word: String in CANCEL_WORDS:
		if text.begins_with(word):
			return &"cancel"
	if button.toggle_mode or button is OptionButton:
		return &"toggle"
	return &"confirm"
