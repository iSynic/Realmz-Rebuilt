## Binds detached inventory view queries data to scene-owned controls.

class_name InventoryViewQueries
extends RefCounted

## Selects detached Inventory characters, items, and legal transfer destinations.


static func character_by_id(view: GameView, character_id: String) -> CharacterView:
	if view == null:
		return null
	for character: CharacterView in view.party_members:
		if character.id == character_id:
			return character
	return null


static func item_by_id(character: CharacterView, instance_id: String) -> ItemView:
	if character == null:
		return null
	for item: ItemView in character.items:
		if item.instance_id == instance_id:
			return item
	return null


static func trade_target(item: ItemView, target_id: String) -> ItemTransferTargetView:
	if item == null or item.actions == null:
		return null
	for target: ItemTransferTargetView in item.actions.trade_targets:
		if target.character_id == target_id:
			return target
	return null


static func first_enabled_trade_target(item: ItemView, preferred_id: String = "") -> String:
	var preferred := trade_target(item, preferred_id)
	if preferred != null and preferred.enabled:
		return preferred.character_id
	if item != null and item.actions != null:
		for target: ItemTransferTargetView in item.actions.trade_targets:
			if target.enabled:
				return target.character_id
	return ""


static func eligible_characters(view: GameView, encounter_mode: bool, encounter_items: Dictionary) -> Array[CharacterView]:
	if not encounter_mode:
		return view.party_members
	var result: Array[CharacterView] = []
	for character: CharacterView in view.party_members:
		if encounter_items.has(character.id) and not eligible_items(character, true, encounter_items).is_empty():
			result.append(character)
	return result


static func selected_character(view: GameView, selected_id: String, encounter_mode: bool, encounter_items: Dictionary) -> CharacterView:
	for character: CharacterView in view.party_members:
		if character.id == selected_id and (not encounter_mode or encounter_items.has(character.id)):
			return character
	return null


static func eligible_items(character: CharacterView, encounter_mode: bool, encounter_items: Dictionary) -> Array[ItemView]:
	if not encounter_mode:
		return character.items
	var result: Array[ItemView] = []
	var instances := encounter_items.get(character.id, {}) as Dictionary
	for item: ItemView in character.items:
		if instances.has(item.instance_id):
			result.append(item)
	return result


static func selected_item(items: Array[ItemView], selected_instance_id: String) -> ItemView:
	for item: ItemView in items:
		if item.instance_id == selected_instance_id:
			return item
	return null
