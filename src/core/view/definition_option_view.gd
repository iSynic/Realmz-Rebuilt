class_name DefinitionOptionView
extends RefCounted

var id: String
var name: String
var description: String = ""
var related_ids: Array[String] = []


func _init(definition_id: String, display_name: String, display_description: String = "", related_definition_ids: Array[String] = []) -> void:
	id = definition_id
	name = display_name
	description = display_description
	related_ids = related_definition_ids.duplicate()
