## Owns items dropped through Classic combat fumbles.

class_name CombatDroppedItemState
extends RefCounted

const MAX_ITEMS := 20

var _items: Array[ItemInstance] = []


func items() -> Array[ItemInstance]:
	return _items.duplicate()


func can_queue() -> bool:
	return _items.size() < MAX_ITEMS


func queue(item: ItemInstance) -> bool:
	if item == null or not can_queue() or _contains(item.id):
		return false
	item.equipped = false
	_items.append(item)
	return true


func requeue_first(item: ItemInstance) -> bool:
	if item == null or not can_queue() or _contains(item.id):
		return false
	item.equipped = false
	_items.push_front(item)
	return true


func remove(instance_id: String) -> ItemInstance:
	for index: int in _items.size():
		if _items[index].id == instance_id:
			return _items.pop_at(index)
	return null


func clear() -> void:
	_items.clear()


func to_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: ItemInstance in _items:
		result.append(item.to_data())
	return result


func _contains(instance_id: String) -> bool:
	return _items.any(func(item: ItemInstance) -> bool: return item.id == instance_id)
