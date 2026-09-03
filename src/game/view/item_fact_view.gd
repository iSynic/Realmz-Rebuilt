class_name ItemFactView
extends RefCounted

var id: StringName
var label: String
var value: String


func _init(fact_id: StringName, display_label: String, display_value: String) -> void:
	id = fact_id
	label = display_label
	value = display_value
