## Carries typed interaction request data across the gameplay transaction boundary.

class_name InteractionRequest
extends RefCounted

const DialogRequestDecoder = preload("res://src/game/shared/interactions/interaction_dialog_request_decoder.gd")
const SelectionRequestDecoder = preload("res://src/game/shared/interactions/interaction_selection_request_decoder.gd")
const ThiefRequestDecoder = preload("res://src/game/shared/interactions/interaction_thief_request_decoder.gd")
const ServiceRequestDecoder = preload("res://src/game/shared/interactions/interaction_service_request_decoder.gd")
const RewardRequestDecoder = preload("res://src/game/shared/interactions/interaction_reward_request_decoder.gd")

const VERSION: int = 1

const ACKNOWLEDGE: StringName = &"acknowledge"
const AGE_UPDATE: StringName = &"age_update"
const YES_NO: StringName = &"yes_no"
const INDEXED_CHOICE: StringName = &"scenario_choice"
const ENCOUNTER_CHOICE: StringName = &"encounter_choice"
const CHARACTER_SELECTION: StringName = &"character_selection"
const ALLY_SELECTION: StringName = &"ally_selection"
const TREASURE_DISTRIBUTION: StringName = &"treasure_distribution"
const LEVEL_UP: StringName = &"level_up"
const WORD_AND_ACTION: StringName = &"complex_encounter"
const THIEF_ENCOUNTER: StringName = &"thief_encounter"
const PICK_LOCK: StringName = &"pick_lock"
const SHOP: StringName = &"shop_action"
const TEMPLE: StringName = &"temple_action"
const BANK: StringName = &"bank_action"
const POOLED_WEALTH_DEPARTURE: StringName = &"pooled_wealth_departure"
const COMBAT: StringName = &"combat_action"
const SESSION_LIFECYCLE: StringName = &"session_lifecycle"


var request_id: String
var kind: StringName
var body: InteractionRequestBody
# Revision-local detached projection prepared while constructing a combat
# request. It is deliberately excluded from to_data(); restored requests rebuild
# it from authoritative state, while live commits can avoid projecting combat
# twice before their first frame.
var transient_combat_view: CombatView


func _init(id: String, request_kind: StringName, request_body: InteractionRequestBody) -> void:
	request_id = id
	kind = request_kind
	body = request_body


func to_data() -> Dictionary:
	return {"kind": String(kind), "version": VERSION, "data": {"requestId": request_id, "payload": body.to_data()}}


func is_supported_kind() -> bool:
	if request_id.is_empty() or body == null:
		return false
	match kind:
		ACKNOWLEDGE: return body is AcknowledgeRequestBody
		AGE_UPDATE: return body is AgeUpdateRequestBody
		YES_NO: return body is YesNoRequestBody
		INDEXED_CHOICE, ENCOUNTER_CHOICE: return body is ChoiceRequestBody
		CHARACTER_SELECTION: return body is CharacterSelectionRequestBody
		ALLY_SELECTION: return body is SelectionRequestBody
		WORD_AND_ACTION: return body is ComplexEncounterRequestBody
		THIEF_ENCOUNTER: return body is ThiefEncounterRequestBody
		PICK_LOCK: return body is PickLockRequestBody
		SHOP: return body is ShopRequestBody
		TEMPLE: return body is TempleRequestBody
		BANK, POOLED_WEALTH_DEPARTURE: return body is BankRequestBody
		TREASURE_DISTRIBUTION: return body is TreasureRequestBody
		LEVEL_UP: return body is LevelUpRequestBody
		COMBAT: return body is CombatRequestBody
		SESSION_LIFECYCLE: return body is LifecycleRequestBody
	return false


static func kind_is_supported(request_kind: StringName) -> bool:
	return request_kind in [ACKNOWLEDGE, AGE_UPDATE, YES_NO, INDEXED_CHOICE, ENCOUNTER_CHOICE, CHARACTER_SELECTION, ALLY_SELECTION, TREASURE_DISTRIBUTION, LEVEL_UP, WORD_AND_ACTION, THIEF_ENCOUNTER, PICK_LOCK, SHOP, TEMPLE, BANK, POOLED_WEALTH_DEPARTURE, COMBAT, SESSION_LIFECYCLE]


static func acknowledge(id: String, prompt: String, message_id: int = 0) -> InteractionRequest:
	var value := AcknowledgeRequestBody.new()
	value.prompt = prompt
	value.message_id = message_id
	value.presentation = &"classic-textbox"
	value.has_message_id = true
	value.has_presentation = true
	return InteractionRequest.new(id, ACKNOWLEDGE, value)


static func age_update(id: String, update_payload: Dictionary) -> InteractionRequest:
	return _from_payload(id, AGE_UPDATE, update_payload)


static func age_update_body(id: String, update: AgeUpdateRequestBody) -> InteractionRequest:
	if update == null:
		return null
	return _from_payload(id, AGE_UPDATE, update.to_data())


static func yes_no(id: String, prompt: String, yes_label: String, no_label: String) -> InteractionRequest:
	var value := YesNoRequestBody.new()
	value.prompt = prompt
	value.yes_label = yes_label
	value.no_label = no_label
	value.has_prompt = true
	return InteractionRequest.new(id, YES_NO, value)


static func indexed_choice(id: String, prompt: String, options: Array) -> InteractionRequest:
	var value := ChoiceRequestBody.new()
	value.prompt = prompt
	for entry: Variant in options:
		var option := InteractionSelectionValueDecoder.choice_option(entry)
		if option == null:
			return null
		value.options.append(option)
	return InteractionRequest.new(id, INDEXED_CHOICE, value)


static func from_payload(id: String, request_kind: StringName, payload: Dictionary) -> InteractionRequest:
	return _from_payload(id, request_kind, payload)


static func from_data(data: Variant) -> InteractionRequest:
	if not data is Dictionary or data.size() != 3 or data.get("version") != VERSION:
		return null
	if not data.get("kind") is String or not data.get("data") is Dictionary:
		return null
	var envelope: Dictionary = data["data"]
	if envelope.size() != 2 or not envelope.get("requestId") is String:
		return null
	if envelope["requestId"].is_empty() or not envelope.get("payload") is Dictionary:
		return null
	var request_kind := StringName(data["kind"])
	if not kind_is_supported(request_kind):
		return null
	return _from_payload(envelope["requestId"], request_kind, envelope["payload"])


static func _from_payload(id: String, request_kind: StringName, payload: Dictionary) -> InteractionRequest:
	var parsed: InteractionRequestBody = null
	match request_kind:
		ACKNOWLEDGE, AGE_UPDATE, YES_NO:
			parsed = DialogRequestDecoder.parse(request_kind, payload)
		INDEXED_CHOICE, ENCOUNTER_CHOICE, CHARACTER_SELECTION, ALLY_SELECTION, WORD_AND_ACTION:
			parsed = SelectionRequestDecoder.parse(request_kind, payload)
		THIEF_ENCOUNTER, PICK_LOCK:
			parsed = ThiefRequestDecoder.parse(request_kind, payload)
		SHOP, TEMPLE, BANK, POOLED_WEALTH_DEPARTURE, COMBAT, SESSION_LIFECYCLE:
			parsed = ServiceRequestDecoder.parse(request_kind, payload)
		TREASURE_DISTRIBUTION, LEVEL_UP:
			parsed = RewardRequestDecoder.parse(request_kind, payload)
	if parsed == null:
		return null
	return InteractionRequest.new(id, request_kind, parsed)
