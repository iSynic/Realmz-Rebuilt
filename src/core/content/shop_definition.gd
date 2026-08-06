class_name ShopDefinition
extends RefCounted

var id: String
var classic_id: int
var inflation_percent: int
var _item_ids: Array[String]
var _quantities: Array[int]


func _init(definition_id: String, native_id: int, stock_item_ids: Array[String], quantities: Array[int], inflation: int = 100) -> void:
	id = definition_id
	classic_id = native_id
	_item_ids = stock_item_ids.duplicate()
	_quantities = quantities.duplicate()
	inflation_percent = inflation


func item_ids() -> Array[String]:
	return _item_ids.duplicate()


func quantity(index: int) -> int:
	return 0 if index < 0 or index >= _quantities.size() else _quantities[index]
