## A colour bar that copies a label's themed font colour, so it follows the label's status
## variation and the chosen interface theme without being recoloured a second time.

class_name ThemeColorBar
extends ColorRect

@export var source: NodePath


func _ready() -> void:
	set_meta(UiThemeService.FOLLOWS, true)
	var label := get_node_or_null(source) as Control
	if label == null:
		return
	label.theme_changed.connect(_follow.bind(label))
	_follow(label)


func _follow(label: Control) -> void:
	color = label.get_theme_color(&"font_color")
