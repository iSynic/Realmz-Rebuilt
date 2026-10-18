## Captures the pre-consumption resources for a staged combat action.

class_name CombatCastCommitment
extends RefCounted

var selection: CombatCastSelection
var item: ItemInstance
var item_index: int = -1
var carried_load_before: int = -1
var equipment_order_before: Array[String] = []
var scroll: SpellScrollState
var spell_points_paid: int = 0
var reserved_spell_count: bool = false


func to_data() -> Dictionary:
	return {
		"selection": null if selection == null else selection.to_data(),
		"item": null if item == null else item.to_data(),
		"itemIndex": item_index,
		"carriedLoadBefore": carried_load_before,
		"equipmentOrderBefore": equipment_order_before.duplicate(),
		"scroll": null if scroll == null else scroll.to_data(),
		"spellPointsPaid": spell_points_paid,
		"reservedSpellCount": reserved_spell_count,
	}


static func from_data(data: Variant) -> CombatCastCommitment:
	if not data is Dictionary or data.size() != 8 or not _has_exact_keys(data, ["selection", "item", "itemIndex", "carriedLoadBefore", "equipmentOrderBefore", "scroll", "spellPointsPaid", "reservedSpellCount"]):
		return null
	if not _whole_number(data["itemIndex"]) or not _whole_number(data["carriedLoadBefore"]) or not _whole_number(data["spellPointsPaid"]) or not data["reservedSpellCount"] is bool or not data["equipmentOrderBefore"] is Array:
		return null
	var result := CombatCastCommitment.new()
	result.selection = CombatCastSelection.from_data(data["selection"])
	if result.selection == null:
		return null
	if data["item"] != null:
		result.item = ItemInstance.from_data(data["item"])
		if result.item == null:
			return null
	if data["scroll"] != null:
		result.scroll = SpellScrollState.from_data(data["scroll"])
		if result.scroll == null:
			return null
	result.item_index = int(data["itemIndex"])
	result.carried_load_before = int(data["carriedLoadBefore"])
	result.spell_points_paid = int(data["spellPointsPaid"])
	result.reserved_spell_count = data["reservedSpellCount"]
	for actor_item_id: Variant in data["equipmentOrderBefore"]:
		if not actor_item_id is String or actor_item_id.is_empty() or result.equipment_order_before.has(actor_item_id):
			return null
		result.equipment_order_before.append(actor_item_id)
	return result if result.is_valid() else null


func is_valid() -> bool:
	if selection == null or not selection.is_valid() or spell_points_paid < 0 or item_index < -1 or carried_load_before < -1:
		return false
	var seen: Dictionary = {}
	for instance_id: String in equipment_order_before:
		if instance_id.is_empty() or seen.has(instance_id):
			return false
		seen[instance_id] = true
	if selection.action == &"cast_spell":
		return item == null and scroll == null and item_index == -1 and carried_load_before == -1 and equipment_order_before.is_empty() and reserved_spell_count
	if selection.action == &"use_scroll":
		return item == null and scroll != null and scroll.spell_id == selection.spell_id and scroll.power == selection.power and scroll.power > 0 and item_index == -1 and carried_load_before == -1 and equipment_order_before.is_empty() and spell_points_paid == 0 and not reserved_spell_count
	if selection.action in [&"use_item", &"attack"]:
		return item != null and scroll == null and not selection.spell_id.is_empty() and item.id == selection.item_instance_id and item_index >= 0 and carried_load_before >= 0 and item.charges != 0 and spell_points_paid == 0 and not reserved_spell_count
	return false


static func _has_exact_keys(data: Dictionary, expected: Array[String]) -> bool:
	for key: Variant in data.keys():
		if not key is String or key not in expected:
			return false
	return true


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and is_finite(value) and value == floor(value)
