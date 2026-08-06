class_name DefinitionOptionView
extends RefCounted

var id: String
var name: String


func _init(definition_id: String, display_name: String) -> void:
	id = definition_id
	name = display_name
