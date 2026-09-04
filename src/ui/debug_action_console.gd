## Presents debug action console through the Godot interface.

class_name DebugActionConsole
extends PanelContainer


signal close_requested
signal clear_requested

var _log: RichTextLabel
var _count: Label


func _ready() -> void:
	var readable_font := load(ClassicTypography.READABLE_UI_PATH) as Font
	var title := get_node("Content/Toolbar/Title") as Label
	title.add_theme_font_override("font", readable_font)
	_count = %Count
	_count.add_theme_font_override("font", readable_font)
	for button: Button in [%Clear, %CopyAll, %Close]:
		button.add_theme_font_override("font", readable_font)
	(%Clear as Button).pressed.connect(func() -> void: clear_requested.emit())
	(%CopyAll as Button).pressed.connect(_copy_all)
	(%Close as Button).pressed.connect(func() -> void: close_requested.emit())
	_log = %GameActionLog
	_log.add_theme_font_override("normal_font", readable_font)


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
