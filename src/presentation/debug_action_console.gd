class_name DebugActionConsole
extends PanelContainer

const ClassicTypographyScript := preload("res://src/presentation/classic_typography.gd")

signal close_requested
signal clear_requested

var _log: RichTextLabel
var _count: Label


func _ready() -> void:
	name = "DebugActionConsole"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	z_index = 510
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101317")
	style.border_color = Color("bd9c55")
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	add_theme_stylebox_override("panel", style)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var toolbar := HBoxContainer.new()
	var title := Label.new()
	var readable_font := load(ClassicTypographyScript.READABLE_UI_PATH) as Font
	title.text = "GAME-ACTION CONSOLE · DEBUG"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_font_override("font", readable_font)
	toolbar.add_child(title)
	_count = Label.new()
	_count.add_theme_font_override("font", readable_font)
	toolbar.add_child(_count)
	toolbar.add_child(_button("Clear", func() -> void: clear_requested.emit()))
	toolbar.add_child(_button("Copy all", _copy_all))
	toolbar.add_child(_button("Close · ` / ~", func() -> void: close_requested.emit()))
	root.add_child(toolbar)
	_log = RichTextLabel.new()
	_log.name = "GameActionLog"
	_log.bbcode_enabled = false
	_log.selection_enabled = true
	_log.context_menu_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 15)
	_log.add_theme_font_override("normal_font", readable_font)
	_log.add_theme_color_override("default_color", Color("eef2f4"))
	root.add_child(_log)
	visible = false


func present(lines: Array[String]) -> void:
	set_lines(lines)
	show()
	_log.grab_focus()


func set_lines(lines: Array[String]) -> void:
	_log.text = "\n".join(lines) if not lines.is_empty() else "No committed game actions recorded yet."
	_count.text = "%d lines" % lines.size()
	if not lines.is_empty():
		_log.scroll_to_line(lines.size() - 1)


func close_console() -> void:
	hide()
	if is_inside_tree():
		release_focus()


func _copy_all() -> void:
	DisplayServer.clipboard_set(_log.text)


static func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", load(ClassicTypographyScript.READABLE_UI_PATH) as Font)
	button.pressed.connect(pressed)
	return button
