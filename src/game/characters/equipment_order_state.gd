## Owns the exact order of equipped item identities without exposing mutable storage.

class_name EquipmentOrderState
extends RefCounted

var _instance_ids: Array[String] = []


func ids() -> Array[String]:
	return _instance_ids.duplicate()


func resolved(inventory: Array[ItemInstance]) -> Array[String]:
	var equipped_by_id: Dictionary = {}
	for item: ItemInstance in inventory:
		if item.equipped:
			equipped_by_id[item.id] = true
	var result: Array[String] = []
	for instance_id: String in _instance_ids:
		if equipped_by_id.has(instance_id):
			result.append(instance_id)
	for item: ItemInstance in inventory:
		if item.equipped and not result.has(item.id):
			result.append(item.id)
	return result


func set_exact(instance_ids: Array[String], inventory: Array[ItemInstance]) -> bool:
	var expected: Array[String] = []
	for item: ItemInstance in inventory:
		if item.equipped:
			expected.append(item.id)
	if instance_ids.size() != expected.size():
		return false
	var seen: Dictionary = {}
	for instance_id: String in instance_ids:
		if instance_id.is_empty() or seen.has(instance_id) or not expected.has(instance_id):
			return false
		seen[instance_id] = true
	_instance_ids = instance_ids.duplicate()
	return true


func record_equipped(item: ItemInstance, inventory: Array[ItemInstance]) -> bool:
	if item == null or not inventory.has(item):
		return false
	item.equipped = true
	_instance_ids.erase(item.id)
	_instance_ids.append(item.id)
	return true


func record_unequipped(item: ItemInstance, inventory: Array[ItemInstance]) -> bool:
	if item == null or not inventory.has(item):
		return false
	item.equipped = false
	_instance_ids.erase(item.id)
	return true


func prune(inventory: Array[ItemInstance]) -> void:
	_instance_ids = resolved(inventory)
