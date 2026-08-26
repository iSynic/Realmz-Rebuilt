class_name ShopDefinition
extends RefCounted

var id: String
var classic_id: int
var inflation_percent: int
var _item_ids: Array[String]
var _quantities: Array[int]
var _stock_slots: Array[int]


func _init(definition_id: String, native_id: int, stock_item_ids: Array[String], quantities: Array[int], inflation: int = 100, stock_slots: Array[int] = []) -> void:
	id = definition_id
	classic_id = native_id
	_item_ids = stock_item_ids.duplicate()
	_quantities = quantities.duplicate()
	_stock_slots = stock_slots.duplicate()
	if _stock_slots.is_empty():
		for index: int in _item_ids.size(): _stock_slots.append(index)
	inflation_percent = inflation


func item_ids() -> Array[String]:
	return _item_ids.duplicate()


func quantity(index: int) -> int:
	return 0 if index < 0 or index >= _quantities.size() else _quantities[index]


func stock_slot(index: int) -> int:
	return -1 if index < 0 or index >= _stock_slots.size() else _stock_slots[index]


func stock_index_at_slot(slot: int) -> int:
	return _stock_slots.find(slot)
