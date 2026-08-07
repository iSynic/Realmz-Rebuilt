class_name OptionLabelDefinition
extends RefCounted

var id: int
var text: String


func _init(option_label_id: int, option_text: String) -> void:
	id = option_label_id
	text = option_text
