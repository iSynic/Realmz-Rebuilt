class_name CharacterMetricView
extends RefCounted

var id: StringName
var index: int
var name: String
var value: int
var detail: String


func _init(metric_id: StringName, metric_index: int, display_name: String, amount: int, display_detail: String = "") -> void:
	id = metric_id
	index = metric_index
	name = display_name
	value = amount
	detail = display_detail
