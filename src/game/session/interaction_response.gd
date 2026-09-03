class_name InteractionResponse
extends RefCounted


class Body:
	extends RefCounted

	func is_valid() -> bool:
		return true

	func to_data() -> Dictionary:
		return {}


class EmptyBody:
	extends Body


class AcknowledgeBody:
	extends Body
	var take_note: bool

	func _init(value: bool = false) -> void:
		take_note = value

	func to_data() -> Dictionary:
		return {"takeNote": true} if take_note else {}


class YesNoBody:
	extends Body
	var accepted: bool

	func _init(value: bool) -> void:
		accepted = value

	func to_data() -> Dictionary:
		return {"accepted": accepted}


class ChoiceBody:
	extends Body
	var index: int
	var cancelled: bool
	var take_note: bool

	func _init(value: int, was_cancelled: bool = false, should_take_note: bool = false) -> void:
		index = value
		cancelled = was_cancelled
		take_note = should_take_note

	func is_valid() -> bool:
		return cancelled or index >= 0

	func to_data() -> Dictionary:
		var data := {"index": index}
		if cancelled:
			data["cancelled"] = true
		if take_note:
			data["takeNote"] = true
		return data


class SelectionBody:
	extends Body
	var character_ids: Array[String]
	var cancelled: bool

	func _init(values: Array[String], was_cancelled: bool = false) -> void:
		character_ids = values.duplicate()
		cancelled = was_cancelled

	func is_valid() -> bool:
		return cancelled or not character_ids.is_empty()

	func to_data() -> Dictionary:
		var data := {"characterIds": character_ids.duplicate()}
		if cancelled:
			data["cancelled"] = true
		return data


class AllySelectionBody:
	extends Body
	var selected_ids: Array[String]

	func _init(values: Array[String]) -> void:
		selected_ids = values.duplicate()

	func to_data() -> Dictionary:
		return {"selectedIds": selected_ids.duplicate()}


class ComplexEncounterBody:
	extends Body
	var action: StringName
	var slot: int
	var word: String
	var classic_spell_id: int
	var classic_item_id: int
	var action_index: int
	var character_id: String
	var selected_slots: Array[int]
	var instance_id: String

	func _init(action_value: StringName, slot_value: int = -1, word_value: String = "", spell_id: int = 0, item_id: int = 0, thief_action_index: int = -1, character: String = "", slots: Array[int] = [], instance: String = "") -> void:
		action = action_value
		slot = slot_value
		word = word_value
		classic_spell_id = spell_id
		classic_item_id = item_id
		action_index = thief_action_index
		character_id = character
		selected_slots = slots.duplicate()
		instance_id = instance

	func is_valid() -> bool:
		return not action.is_empty()

	func to_data() -> Dictionary:
		var data := {"action": String(action)}
		if not selected_slots.is_empty():
			data["slots"] = selected_slots.duplicate()
		elif slot >= 0:
			data["slot"] = slot
		if not word.is_empty():
			data["word"] = word
		if classic_spell_id != 0:
			data["classicSpellId"] = classic_spell_id
		if classic_item_id != 0:
			data["classicItemId"] = classic_item_id
		if action_index >= 0:
			data["actionIndex"] = action_index
		if not character_id.is_empty():
			data["characterId"] = character_id
		if not instance_id.is_empty():
			data["instanceId"] = instance_id
		return data


class ThiefEncounterBody:
	extends Body
	var action: StringName
	var character_id: String
	var action_index: int

	func _init(action_value: StringName, character: String = "", selected_action_index: int = -1) -> void:
		action = action_value
		character_id = character
		action_index = selected_action_index

	func is_valid() -> bool:
		return action == &"back" or action == &"attempt" and not character_id.is_empty() and action_index >= 0 and action_index < 8

	func to_data() -> Dictionary:
		var data := {"action": String(action)}
		if action == &"attempt":
			data["characterId"] = character_id
			data["actionIndex"] = action_index
		return data


class PickLockBody:
	extends Body
	var frame_index: int

	func _init(selected_frame_index: int) -> void:
		frame_index = selected_frame_index

	func is_valid() -> bool:
		return frame_index >= 0

	func to_data() -> Dictionary:
		return {"frameIndex": frame_index}


class ShopBody:
	extends Body
	var action: StringName
	var character_id: String
	var instance_id: String
	var stock_key: String

	func _init(action_value: StringName, character: String = "", instance: String = "", stock: String = "") -> void:
		action = action_value
		character_id = character
		instance_id = instance
		stock_key = stock

	func is_valid() -> bool:
		return not action.is_empty()

	func to_data() -> Dictionary:
		var data := {"action": String(action)}
		if not character_id.is_empty():
			data["characterId"] = character_id
		if not instance_id.is_empty():
			data["instanceId"] = instance_id
		if not stock_key.is_empty():
			data["stockKey"] = stock_key
		return data


class TempleBody:
	extends Body
	var action: StringName
	var character_id: String
	var service_id: String

	func _init(action_value: StringName, character: String = "", service: String = "") -> void:
		action = action_value
		character_id = character
		service_id = service

	func is_valid() -> bool:
		return not action.is_empty()

	func to_data() -> Dictionary:
		var data := {"action": String(action)}
		if not character_id.is_empty():
			data["characterId"] = character_id
		if not service_id.is_empty():
			data["serviceId"] = service_id
		return data


class BankBody:
	extends Body
	var action: StringName
	var character_id: String
	var denomination: String
	var amount: int

	func _init(action_value: StringName, character: String = "", denomination_value: String = "", amount_value: int = 0) -> void:
		action = action_value
		character_id = character
		denomination = denomination_value
		amount = amount_value

	func is_valid() -> bool:
		return not action.is_empty() and amount >= 0

	func to_data() -> Dictionary:
		var data := {"action": String(action)}
		if not character_id.is_empty():
			data["characterId"] = character_id
		if not denomination.is_empty():
			data["denomination"] = denomination
		if amount != 0:
			data["amount"] = amount
		return data


class TreasureBody:
	extends Body
	var action: StringName
	var instance_id: String
	var character_id: String
	var direction: StringName
	var wealth_kind: StringName
	var amount: int

	func _init(action_value: StringName, instance: String = "", character: String = "", direction_value: StringName = &"", wealth_kind_value: StringName = &"", amount_value: int = 0) -> void:
		action = action_value
		instance_id = instance
		character_id = character
		direction = direction_value
		wealth_kind = wealth_kind_value
		amount = amount_value

	func is_valid() -> bool:
		return not action.is_empty()

	func to_data() -> Dictionary:
		var data := {"action": String(action)}
		if not instance_id.is_empty():
			data["instanceId"] = instance_id
		if not character_id.is_empty():
			data["characterId"] = character_id
		if not direction.is_empty():
			data["direction"] = String(direction)
		if not wealth_kind.is_empty():
			data["kind"] = String(wealth_kind)
		if amount != 0:
			data["amount"] = amount
		return data


class LevelUpBody:
	extends Body
	var action: StringName
	var character_id: String
	var spell_ids: Array[String]

	func _init(action_value: StringName, character: String, spells: Array[String] = []) -> void:
		action = action_value
		character_id = character
		spell_ids = spells.duplicate()

	func is_valid() -> bool:
		return not action.is_empty() and not character_id.is_empty()

	func to_data() -> Dictionary:
		var data := {"action": String(action), "characterId": character_id}
		if action == &"confirm-spells" or not spell_ids.is_empty():
			data["spellIds"] = spell_ids.duplicate()
		return data


class CombatBody:
	extends Body
	var action: StringName
	var actor_id: String
	var target_id: String
	var enabled: bool
	var destination: Vector2i
	var has_destination: bool
	var auto_switch_to_melee: bool
	var spell_id: String
	var power: int
	var target_coordinate: Vector2i
	var has_target_coordinate: bool
	var rotation: int
	var target_ids: Array[String]
	var target_coordinates: Array[Vector2i]
	var item_instance_id: String
	var scroll_slot: int

	func _init(action_value: StringName, actor: String, target: String = "") -> void:
		action = action_value
		actor_id = actor
		target_id = target
		destination = Vector2i.ZERO
		target_coordinate = Vector2i.ZERO
		scroll_slot = -1
		power = 1

	func is_valid() -> bool:
		return not action.is_empty() and not actor_id.is_empty()

	func duplicate_body() -> CombatBody:
		var result := CombatBody.new(action, actor_id, target_id)
		result.enabled = enabled
		result.destination = destination
		result.has_destination = has_destination
		result.auto_switch_to_melee = auto_switch_to_melee
		result.spell_id = spell_id
		result.power = power
		result.target_coordinate = target_coordinate
		result.has_target_coordinate = has_target_coordinate
		result.rotation = rotation
		result.target_ids = target_ids.duplicate()
		result.target_coordinates = target_coordinates.duplicate()
		result.item_instance_id = item_instance_id
		result.scroll_slot = scroll_slot
		return result

	func to_data() -> Dictionary:
		var data := {"actorId": actor_id, "action": String(action), "targetId": target_id}
		if action == &"set_auto":
			data["enabled"] = enabled
		if has_destination:
			data["destination"] = [destination.x, destination.y]
		if auto_switch_to_melee:
			data["autoSwitchToMelee"] = true
		if not spell_id.is_empty():
			data["spellId"] = spell_id
			data["power"] = power
		if has_target_coordinate:
			data["targetCoordinate"] = [target_coordinate.x, target_coordinate.y]
			data["rotation"] = rotation
		if not target_ids.is_empty():
			data["targetIds"] = target_ids.duplicate()
		if not target_coordinates.is_empty():
			data["targetCoordinates"] = target_coordinates.map(func(coordinate: Vector2i) -> Array[int]: return [coordinate.x, coordinate.y])
		if not item_instance_id.is_empty():
			data["itemInstanceId"] = item_instance_id
		if scroll_slot >= 0:
			data["scrollSlot"] = scroll_slot
		return data


class LifecycleBody:
	extends Body
	var action: StringName

	func _init(value: StringName) -> void:
		action = value

	func is_valid() -> bool:
		return not action.is_empty()

	func to_data() -> Dictionary:
		return {"action": String(action)}


var request_id: String
var kind: StringName
var body: Body

func _init(id: String, response_kind: StringName, response_body: Body) -> void:
	request_id = id
	kind = response_kind
	body = response_body


func is_supported_kind() -> bool:
	if body == null or not body.is_valid():
		return false
	match kind:
		InteractionRequest.ACKNOWLEDGE:
			return body is AcknowledgeBody
		InteractionRequest.AGE_UPDATE:
			return body is EmptyBody
		InteractionRequest.YES_NO:
			return body is YesNoBody
		InteractionRequest.INDEXED_CHOICE, InteractionRequest.ENCOUNTER_CHOICE:
			return body is ChoiceBody
		InteractionRequest.CHARACTER_SELECTION:
			return body is SelectionBody
		InteractionRequest.ALLY_SELECTION:
			return body is AllySelectionBody
		InteractionRequest.WORD_AND_ACTION:
			return body is ComplexEncounterBody
		InteractionRequest.THIEF_ENCOUNTER:
			return body is ThiefEncounterBody
		InteractionRequest.PICK_LOCK:
			return body is PickLockBody
		InteractionRequest.SHOP:
			return body is ShopBody
		InteractionRequest.TEMPLE:
			return body is TempleBody
		InteractionRequest.BANK, InteractionRequest.POOLED_WEALTH_DEPARTURE:
			return body is BankBody
		InteractionRequest.TREASURE_DISTRIBUTION:
			return body is TreasureBody
		InteractionRequest.LEVEL_UP:
			return body is LevelUpBody
		InteractionRequest.COMBAT:
			return body is CombatBody
		InteractionRequest.SESSION_LIFECYCLE:
			return body is LifecycleBody
	return false


static func acknowledge(request: InteractionRequest) -> InteractionResponse:
	return InteractionResponse.new(request.request_id, InteractionRequest.ACKNOWLEDGE, AcknowledgeBody.new())


static func age_update(request: InteractionRequest) -> InteractionResponse:
	return InteractionResponse.new(request.request_id, InteractionRequest.AGE_UPDATE, EmptyBody.new())


static func yes_no(request: InteractionRequest, accepted: bool) -> InteractionResponse:
	return InteractionResponse.new(request.request_id, InteractionRequest.YES_NO, YesNoBody.new(accepted))


static func indexed_choice(request: InteractionRequest, index: int) -> InteractionResponse:
	return InteractionResponse.new(request.request_id, request.kind, ChoiceBody.new(index))


static func from_data(id: String, response_kind: StringName, data: Variant) -> InteractionResponse:
	return InteractionResponse.new(id, response_kind, _body_from_data(response_kind, data) if data is Dictionary else null)


static func _body_from_data(response_kind: StringName, data: Dictionary) -> Body:
	match response_kind:
		InteractionRequest.ACKNOWLEDGE:
			if not _fields_are_exact(data, ["takeNote"]):
				return null
			if data.is_empty():
				return AcknowledgeBody.new()
			return AcknowledgeBody.new(data["takeNote"]) if data.size() == 1 and data.get("takeNote") is bool else null
		InteractionRequest.AGE_UPDATE:
			return EmptyBody.new() if data.is_empty() else null
		InteractionRequest.YES_NO:
			if not _fields_are_exact(data, ["accepted"], ["accepted"]):
				return null
			return YesNoBody.new(bool(data.get("accepted", false))) if data.size() == 1 and data.get("accepted") is bool else null
		InteractionRequest.INDEXED_CHOICE, InteractionRequest.ENCOUNTER_CHOICE:
			if not _fields_are_exact(data, ["index", "cancelled", "takeNote"]):
				return null
			if data.has("index") and not data["index"] is int or data.has("cancelled") and not data["cancelled"] is bool or data.has("takeNote") and not data["takeNote"] is bool:
				return null
			return ChoiceBody.new(int(data.get("index", -1)), data.get("cancelled", false), data.get("takeNote", false))
		InteractionRequest.CHARACTER_SELECTION:
			if not _fields_are_exact(data, ["characterIds", "cancelled"]):
				return null
			if data.has("characterIds") and not data["characterIds"] is Array or data.has("cancelled") and not data["cancelled"] is bool:
				return null
			var ids: Array[String] = []
			for value: Variant in data.get("characterIds", []):
				if not value is String:
					return null
				ids.append(value)
			return SelectionBody.new(ids, data.get("cancelled", false))
		InteractionRequest.ALLY_SELECTION:
			if not _fields_are_exact(data, ["selectedIds"], ["selectedIds"]) or not data["selectedIds"] is Array:
				return null
			var selected_ids: Array[String] = []
			for value: Variant in data.get("selectedIds", []):
				if not value is String:
					return null
				selected_ids.append(value)
			return AllySelectionBody.new(selected_ids)
		InteractionRequest.WORD_AND_ACTION:
			if not _fields_are_exact(data, ["action", "slot", "slots", "word", "classicSpellId", "classicItemId", "actionIndex", "characterId", "instanceId"], ["action"]) or not _is_string_value(data["action"]):
				return null
			if not _optional_strings_are_valid(data, ["word", "characterId", "instanceId"]) or not _optional_integers_are_valid(data, ["slot", "classicSpellId", "classicItemId", "actionIndex"]) or data.has("slot") and data.has("slots") or data.has("slots") and not data["slots"] is Array:
				return null
			var slots: Array[int] = []
			for value: Variant in data.get("slots", []):
				if not value is int or slots.has(value): return null
				slots.append(value)
			return ComplexEncounterBody.new(StringName(data.get("action", "")), int(data.get("slot", -1)), String(data.get("word", "")), int(data.get("classicSpellId", 0)), int(data.get("classicItemId", 0)), int(data.get("actionIndex", -1)), String(data.get("characterId", "")), slots, String(data.get("instanceId", "")))
		InteractionRequest.THIEF_ENCOUNTER:
			if not _fields_are_exact(data, ["action", "characterId", "actionIndex"], ["action"]) or not _is_string_value(data["action"]) or not _optional_strings_are_valid(data, ["characterId"]) or not _optional_integers_are_valid(data, ["actionIndex"]):
				return null
			var thief := ThiefEncounterBody.new(StringName(data["action"]), String(data.get("characterId", "")), int(data.get("actionIndex", -1)))
			return thief if thief.is_valid() else null
		InteractionRequest.PICK_LOCK:
			if not _fields_are_exact(data, ["frameIndex"], ["frameIndex"]) or not data["frameIndex"] is int:
				return null
			return PickLockBody.new(data["frameIndex"]) if data["frameIndex"] >= 0 else null
		InteractionRequest.SHOP:
			if not _fields_are_exact(data, ["action", "characterId", "instanceId", "stockKey"], ["action"]) or not _is_string_value(data["action"]):
				return null
			if not _optional_strings_are_valid(data, ["characterId", "instanceId", "stockKey"]):
				return null
			return ShopBody.new(StringName(data.get("action", "")), String(data.get("characterId", "")), String(data.get("instanceId", "")), String(data.get("stockKey", "")))
		InteractionRequest.TEMPLE:
			if not _fields_are_exact(data, ["action", "characterId", "serviceId"], ["action"]) or not _is_string_value(data["action"]):
				return null
			if not _optional_strings_are_valid(data, ["characterId", "serviceId"]):
				return null
			return TempleBody.new(StringName(data.get("action", "")), String(data.get("characterId", "")), String(data.get("serviceId", "")))
		InteractionRequest.BANK, InteractionRequest.POOLED_WEALTH_DEPARTURE:
			if not _fields_are_exact(data, ["action", "characterId", "denomination", "amount"], ["action"]) or not _is_string_value(data["action"]):
				return null
			if not _optional_strings_are_valid(data, ["characterId", "denomination"]) or not _optional_integers_are_valid(data, ["amount"]):
				return null
			return BankBody.new(StringName(data.get("action", "")), String(data.get("characterId", "")), String(data.get("denomination", "")), int(data.get("amount", 0)))
		InteractionRequest.TREASURE_DISTRIBUTION:
			if not _fields_are_exact(data, ["action", "instanceId", "characterId", "direction", "kind", "amount"], ["action"]) or not _is_string_value(data["action"]):
				return null
			if not _optional_strings_are_valid(data, ["instanceId", "characterId", "direction", "kind"]) or not _optional_integers_are_valid(data, ["amount"]):
				return null
			return TreasureBody.new(StringName(data.get("action", "")), String(data.get("instanceId", "")), String(data.get("characterId", "")), StringName(data.get("direction", "")), StringName(data.get("kind", "")), int(data.get("amount", 0)))
		InteractionRequest.LEVEL_UP:
			if not _fields_are_exact(data, ["action", "characterId", "spellIds"], ["action", "characterId"]) or not _is_string_value(data["action"]) or not data["characterId"] is String or data.has("spellIds") and not data["spellIds"] is Array:
				return null
			var spell_ids: Array[String] = []
			for value: Variant in data.get("spellIds", []):
				if not value is String:
					return null
				spell_ids.append(value)
			return LevelUpBody.new(StringName(data.get("action", "")), String(data.get("characterId", "")), spell_ids)
		InteractionRequest.COMBAT:
			if not _fields_are_exact(data, ["actorId", "action", "targetId", "enabled", "destination", "autoSwitchToMelee", "spellId", "power", "targetCoordinate", "targetCoordinates", "rotation", "targetIds", "itemInstanceId", "scrollSlot"], ["actorId", "action", "targetId"]):
				return null
			if not data["actorId"] is String or not _is_string_value(data["action"]) or not data["targetId"] is String:
				return null
			var combat := CombatBody.new(StringName(data.get("action", "")), String(data.get("actorId", "")), String(data.get("targetId", "")))
			if data.has("enabled") and not data["enabled"] is bool or data.has("autoSwitchToMelee") and not data["autoSwitchToMelee"] is bool:
				return null
			if not _optional_strings_are_valid(data, ["spellId", "itemInstanceId"]) or not _optional_integers_are_valid(data, ["power", "rotation", "scrollSlot"]):
				return null
			if data.has("destination") and not _coordinate_is_valid(data["destination"]) or data.has("targetCoordinate") and not _coordinate_is_valid(data["targetCoordinate"]):
				return null
			if data.has("targetIds") and not data["targetIds"] is Array or data.has("targetCoordinates") and not data["targetCoordinates"] is Array:
				return null
			if data.has("targetCoordinate") and data.has("targetCoordinates") or data.has("targetIds") and data.has("targetCoordinates"):
				return null
			combat.enabled = data.get("enabled", false)
			if data.get("destination") is Array and data["destination"].size() == 2:
				combat.destination = Vector2i(int(data["destination"][0]), int(data["destination"][1]))
				combat.has_destination = true
			combat.auto_switch_to_melee = data.get("autoSwitchToMelee", false)
			combat.spell_id = String(data.get("spellId", ""))
			combat.power = int(data.get("power", 1))
			if data.get("targetCoordinate") is Array and data["targetCoordinate"].size() == 2:
				combat.target_coordinate = Vector2i(int(data["targetCoordinate"][0]), int(data["targetCoordinate"][1]))
				combat.has_target_coordinate = true
			combat.rotation = int(data.get("rotation", 0))
			for value: Variant in data.get("targetIds", []):
				if not value is String:
					return null
				combat.target_ids.append(value)
			for value: Variant in data.get("targetCoordinates", []):
				if not _coordinate_is_valid(value):
					return null
				combat.target_coordinates.append(Vector2i(int(value[0]), int(value[1])))
			combat.item_instance_id = String(data.get("itemInstanceId", ""))
			combat.scroll_slot = int(data.get("scrollSlot", -1))
			return combat
		InteractionRequest.SESSION_LIFECYCLE:
			if not _fields_are_exact(data, ["action"], ["action"]) or not _is_string_value(data["action"]):
				return null
			return LifecycleBody.new(StringName(data.get("action", "")))
	return null


static func _fields_are_exact(data: Dictionary, allowed: Array[String], required: Array[String] = []) -> bool:
	for field: Variant in data.keys():
		if not field is String or not allowed.has(field):
			return false
	for field: String in required:
		if not data.has(field):
			return false
	return true


static func _is_string_value(value: Variant) -> bool:
	return value is String or value is StringName


static func _optional_strings_are_valid(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if data.has(field) and not data[field] is String:
			return false
	return true


static func _optional_integers_are_valid(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if data.has(field) and not data[field] is int:
			return false
	return true


static func _coordinate_is_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value[0] is int and value[1] is int
