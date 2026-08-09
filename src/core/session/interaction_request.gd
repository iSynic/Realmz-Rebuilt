class_name InteractionRequest
extends RefCounted

var request_id: String
var kind: StringName
var payload: Dictionary

const ACKNOWLEDGE: StringName = &"acknowledge"
const AGE_UPDATE: StringName = &"age_update"
const YES_NO: StringName = &"yes_no"
const INDEXED_CHOICE: StringName = &"scenario_choice"
const ENCOUNTER_CHOICE: StringName = &"encounter_choice"
const CHARACTER_SELECTION: StringName = &"character_selection"
const ALLY_SELECTION: StringName = &"ally_selection"
const TREASURE_DISTRIBUTION: StringName = &"treasure_distribution"
const WORD_AND_ACTION: StringName = &"complex_encounter"
const SHOP: StringName = &"shop_action"
const TEMPLE: StringName = &"temple_action"
const BANK: StringName = &"bank_action"
const COMBAT: StringName = &"combat_action"


func _init(id: String, request_kind: StringName, request_payload: Dictionary = {}) -> void:
	request_id = id
	kind = request_kind
	payload = request_payload.duplicate(true)


func to_data() -> Dictionary:
	return {"request_id": request_id, "kind": String(kind), "payload": payload.duplicate(true)}


func is_supported_kind() -> bool:
	return InteractionRequest.kind_is_supported(kind)


static func kind_is_supported(request_kind: StringName) -> bool:
	return request_kind in [ACKNOWLEDGE, AGE_UPDATE, YES_NO, INDEXED_CHOICE, ENCOUNTER_CHOICE, CHARACTER_SELECTION, ALLY_SELECTION, TREASURE_DISTRIBUTION, WORD_AND_ACTION, SHOP, TEMPLE, BANK, COMBAT]


static func acknowledge(id: String, prompt: String, message_id: int = 0) -> InteractionRequest:
	return InteractionRequest.new(id, ACKNOWLEDGE, {"prompt": prompt, "messageId": message_id, "presentation": "classic-textbox"})


static func age_update(id: String, update_payload: Dictionary) -> InteractionRequest:
	return InteractionRequest.new(id, AGE_UPDATE, update_payload)


static func yes_no(id: String, prompt: String, yes_label: String, no_label: String) -> InteractionRequest:
	return InteractionRequest.new(id, YES_NO, {"prompt": prompt, "yesLabel": yes_label, "noLabel": no_label})


static func indexed_choice(id: String, prompt: String, options: Array) -> InteractionRequest:
	return InteractionRequest.new(id, INDEXED_CHOICE, {"prompt": prompt, "options": options.duplicate(true)})


static func from_data(data: Variant) -> InteractionRequest:
	if not data is Dictionary:
		return null
	for field: String in ["request_id", "kind", "payload"]:
		if not data.has(field):
			return null
	if not data["request_id"] is String or data["request_id"].is_empty() or not data["kind"] is String or data["kind"].is_empty() or not data["payload"] is Dictionary:
		return null
	var request_kind := StringName(data["kind"])
	if not InteractionRequest.kind_is_supported(request_kind):
		return null
	return InteractionRequest.new(data["request_id"], request_kind, data["payload"])
