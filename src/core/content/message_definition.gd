class_name MessageDefinition
extends RefCounted

var id: int
var text: String


func _init(message_id: int, message_text: String) -> void:
	id = message_id
	text = message_text
