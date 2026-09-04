## Carries typed interaction request data across the gameplay transaction boundary.

class_name InteractionRequest
extends RefCounted

const ServiceDecoder := preload("res://src/game/session/interaction_request_service_decoder.gd")

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
		var option := InteractionRequestValueDecoder.choice_option(entry)
		if option == null: return null
		value.options.append(option)
	return InteractionRequest.new(id, INDEXED_CHOICE, value)


static func from_payload(id: String, request_kind: StringName, payload: Dictionary) -> InteractionRequest:
	return _from_payload(id, request_kind, payload)


static func from_data(data: Variant) -> InteractionRequest:
	if not data is Dictionary or data.size() != 3 or data.get("version") != VERSION or not data.get("kind") is String or not data.get("data") is Dictionary:
		return null
	var envelope: Dictionary = data["data"]
	if envelope.size() != 2 or not envelope.get("requestId") is String or envelope["requestId"].is_empty() or not envelope.get("payload") is Dictionary:
		return null
	var request_kind := StringName(data["kind"])
	if not kind_is_supported(request_kind): return null
	return _from_payload(envelope["requestId"], request_kind, envelope["payload"])


static func _from_payload(id: String, request_kind: StringName, payload: Dictionary) -> InteractionRequest:
	var parsed: InteractionRequestBody = null
	match request_kind:
		ACKNOWLEDGE, AGE_UPDATE, YES_NO:
			parsed = _parse_dialog_body(request_kind, payload)
		INDEXED_CHOICE, ENCOUNTER_CHOICE, CHARACTER_SELECTION, ALLY_SELECTION, WORD_AND_ACTION:
			parsed = _parse_selection_body(request_kind, payload)
		THIEF_ENCOUNTER, PICK_LOCK:
			parsed = _parse_thief_body(request_kind, payload)
		SHOP:
			parsed = _parse_shop_body(payload)
		TEMPLE:
			parsed = _parse_temple_body(payload)
		BANK, POOLED_WEALTH_DEPARTURE:
			parsed = _parse_bank_body(payload, request_kind == POOLED_WEALTH_DEPARTURE)
		TREASURE_DISTRIBUTION, LEVEL_UP:
			parsed = _parse_reward_body(request_kind, payload)
		COMBAT:
			parsed = _parse_combat_body(payload)
		SESSION_LIFECYCLE:
			parsed = _parse_lifecycle_body(payload)
	if parsed == null: return null
	return InteractionRequest.new(id, request_kind, parsed)


static func _parse_dialog_body(request_kind: StringName, payload: Dictionary) -> InteractionRequestBody:
	if request_kind == ACKNOWLEDGE:
		if not _fields_are_exact(payload, ["prompt", "messageId", "presentation", "journalEligible", "journalRecorded", "soundId", "playerMapId", "resourceType", "resourceId"], ["prompt"]) or not payload["prompt"] is String or not _optional_ints(payload, ["messageId", "soundId", "resourceId"]) or not _optional_strings(payload, ["presentation", "playerMapId", "resourceType"]) or not _optional_bools(payload, ["journalEligible", "journalRecorded"]): return null
		if payload.has("journalEligible") != payload.has("journalRecorded"): return null
		if payload.has("resourceType") != payload.has("resourceId") or (payload.has("resourceType") and String(payload["resourceType"]).is_empty()): return null
		var acknowledge_body := AcknowledgeRequestBody.new()
		acknowledge_body.prompt = payload["prompt"]
		acknowledge_body.message_id = int(payload.get("messageId", 0))
		acknowledge_body.presentation = StringName(payload.get("presentation", ""))
		acknowledge_body.journal_eligible = bool(payload.get("journalEligible", false))
		acknowledge_body.journal_recorded = bool(payload.get("journalRecorded", false))
		acknowledge_body.sound_id = int(payload.get("soundId", 0))
		acknowledge_body.player_map_id = String(payload.get("playerMapId", ""))
		acknowledge_body.resource_type = String(payload.get("resourceType", ""))
		acknowledge_body.resource_id = int(payload.get("resourceId", 0))
		acknowledge_body.has_message_id = payload.has("messageId")
		acknowledge_body.has_presentation = payload.has("presentation")
		acknowledge_body.has_journal_state = payload.has("journalEligible") or payload.has("journalRecorded")
		acknowledge_body.has_sound_id = payload.has("soundId")
		acknowledge_body.has_player_map_id = payload.has("playerMapId")
		acknowledge_body.has_resource = payload.has("resourceType")
		return acknowledge_body
	if request_kind == YES_NO:
		if not _fields_are_exact(payload, ["prompt", "yesId", "yesLabel", "noId", "noLabel", "regionId"], ["yesLabel", "noLabel"]) or not _required_strings(payload, ["yesLabel", "noLabel"]) or not _optional_strings(payload, ["prompt", "regionId"]) or not _optional_ints(payload, ["yesId", "noId"]): return null
		if payload.has("yesId") != payload.has("noId"): return null
		var yes_no_body := YesNoRequestBody.new()
		yes_no_body.prompt = String(payload.get("prompt", ""))
		yes_no_body.yes_id = int(payload.get("yesId", 0))
		yes_no_body.yes_label = payload["yesLabel"]
		yes_no_body.no_id = int(payload.get("noId", 0))
		yes_no_body.no_label = payload["noLabel"]
		yes_no_body.region_id = String(payload.get("regionId", ""))
		yes_no_body.has_prompt = payload.has("prompt")
		yes_no_body.has_ids = payload.has("yesId") or payload.has("noId")
		yes_no_body.has_region_id = payload.has("regionId")
		return yes_no_body
	var fields: Array[String] = ["characterId", "characterName", "portraitId", "combatIconId", "raceId", "raceName", "previousAgeDays", "ageDays", "previousAgeGroup", "ageGroup", "ageGroupName", "ageMinimumYears", "ageMaximumYears", "transition", "appliedAgeGroup", "changes", "prompt", "presentation", "soundId", "source"]
	if request_kind != AGE_UPDATE or not _fields_are_exact(payload, fields, fields) or not _required_strings(payload, ["characterId", "characterName", "portraitId", "combatIconId", "raceId", "raceName", "ageGroupName", "prompt", "presentation", "source"]) or not _required_ints(payload, ["previousAgeDays", "ageDays", "previousAgeGroup", "ageGroup", "ageMinimumYears", "ageMaximumYears", "transition", "appliedAgeGroup", "soundId"]) or not payload["changes"] is Array: return null
	var age_body := AgeUpdateRequestBody.new()
	age_body.character_id = payload["characterId"]
	age_body.character_name = payload["characterName"]
	age_body.portrait_id = payload["portraitId"]
	age_body.combat_icon_id = payload["combatIconId"]
	age_body.race_id = payload["raceId"]
	age_body.race_name = payload["raceName"]
	age_body.previous_age_days = payload["previousAgeDays"]
	age_body.age_days = payload["ageDays"]
	age_body.previous_age_group = payload["previousAgeGroup"]
	age_body.age_group = payload["ageGroup"]
	age_body.age_group_name = payload["ageGroupName"]
	age_body.age_minimum_years = payload["ageMinimumYears"]
	age_body.age_maximum_years = payload["ageMaximumYears"]
	age_body.transition = payload["transition"]
	age_body.applied_age_group = payload["appliedAgeGroup"]
	for change: Variant in payload["changes"]:
		if not _whole_number(change): return null
		age_body.changes.append(int(change))
	age_body.prompt = payload["prompt"]
	age_body.presentation = StringName(payload["presentation"])
	age_body.sound_id = payload["soundId"]
	age_body.source = StringName(payload["source"])
	return age_body


static func _parse_selection_body(request_kind: StringName, payload: Dictionary) -> InteractionRequestBody:
	if request_kind in [INDEXED_CHOICE, ENCOUNTER_CHOICE]:
		if not _fields_are_exact(payload, ["prompt", "options", "canBackOut", "encounterKind", "encounterId"], ["prompt", "options"]) or not payload["prompt"] is String or not payload["options"] is Array or not _optional_bools(payload, ["canBackOut"]) or not _optional_strings(payload, ["encounterKind"]) or not _optional_ints(payload, ["encounterId"]): return null
		var choice := ChoiceRequestBody.new()
		choice.prompt = payload["prompt"]
		for entry: Variant in payload["options"]:
			var option := InteractionRequestValueDecoder.choice_option(entry)
			if option == null: return null
			choice.options.append(option)
		choice.can_back_out = bool(payload.get("canBackOut", false))
		choice.encounter_kind = StringName(payload.get("encounterKind", ""))
		choice.encounter_id = int(payload.get("encounterId", 0))
		choice.has_can_back_out = payload.has("canBackOut")
		choice.has_encounter = payload.has("encounterKind") or payload.has("encounterId")
		return choice
	if request_kind == CHARACTER_SELECTION:
		if not _fields_are_exact(payload, ["prompt", "count", "eligible", "allowDead", "mode", "itemInstanceId", "spellId", "scrollSlot", "spellContext"], ["count", "eligible"]) or not _whole_number(payload["count"]) or not payload["eligible"] is Array or not _optional_strings(payload, ["prompt", "mode", "itemInstanceId", "spellId"]) or not _optional_ints(payload, ["scrollSlot"]) or not _optional_bools(payload, ["allowDead"]): return null
		var characters := CharacterSelectionRequestBody.new()
		characters.prompt = String(payload.get("prompt", ""))
		characters.count = int(payload["count"])
		for entry: Variant in payload["eligible"]:
			var candidate := InteractionRequestValueDecoder.selection_candidate(entry)
			if candidate == null: return null
			characters.eligible.append(candidate)
		characters.allow_dead = bool(payload.get("allowDead", false))
		characters.mode = StringName(payload.get("mode", ""))
		characters.item_instance_id = String(payload.get("itemInstanceId", ""))
		characters.spell_id = String(payload.get("spellId", ""))
		characters.scroll_slot = int(payload.get("scrollSlot", -1))
		if payload.has("spellContext"):
			characters.spell_context = InteractionRequestValueDecoder.spell_target_context(payload["spellContext"])
			if characters.spell_context == null or not characters.spell_id.is_empty() and characters.spell_context.spell_id != characters.spell_id: return null
		return characters
	if request_kind == ALLY_SELECTION:
		if not _fields_are_exact(payload, ["prompt", "maximum", "selectedIds", "requiredIds", "candidates"], ["prompt", "maximum", "selectedIds", "requiredIds", "candidates"]) or not payload["prompt"] is String or not _whole_number(payload["maximum"]) or not payload["selectedIds"] is Array or not payload["requiredIds"] is Array or not payload["candidates"] is Array: return null
		if not _array_is_strings(payload["selectedIds"]) or not _array_is_strings(payload["requiredIds"]): return null
		var allies := SelectionRequestBody.new()
		allies.prompt = payload["prompt"]
		allies.maximum = int(payload["maximum"])
		allies.selected_ids = _strings(payload["selectedIds"])
		allies.required_ids = _strings(payload["requiredIds"])
		for entry: Variant in payload["candidates"]:
			var candidate := InteractionRequestValueDecoder.selection_candidate(entry)
			if candidate == null: return null
			allies.candidates.append(candidate)
		return allies
	if request_kind != WORD_AND_ACTION or not _fields_are_exact(payload, ["encounterKind", "encounterId", "prompt", "actions", "characters", "items", "spells", "canBackOut", "actionSelectionCount"], ["encounterKind", "encounterId", "prompt", "actions", "characters", "items", "spells", "canBackOut", "actionSelectionCount"]) or not _required_strings(payload, ["encounterKind", "prompt"]) or not _required_ints(payload, ["encounterId", "actionSelectionCount"]) or not payload["actions"] is Array or not payload["characters"] is Array or not payload["items"] is Array or not payload["spells"] is Array or not payload["canBackOut"] is bool: return null
	var complex := ComplexEncounterRequestBody.new()
	complex.encounter_kind = StringName(payload["encounterKind"])
	if complex.encounter_kind != &"complex": return null
	complex.encounter_id = int(payload["encounterId"])
	complex.prompt = payload["prompt"]
	for entry: Variant in payload["actions"]:
		var action := InteractionRequestValueDecoder.encounter_action(entry)
		if action == null: return null
		complex.actions.append(action)
	for entry: Variant in payload["characters"]:
		var character := InteractionRequestValueDecoder.named_character(entry)
		if character == null: return null
		complex.characters.append(character)
	for entry: Variant in payload["items"]:
		var item := InteractionRequestValueDecoder.encounter_catalog_entry(entry, &"item")
		if item == null: return null
		complex.items.append(item)
	for entry: Variant in payload["spells"]:
		var spell := InteractionRequestValueDecoder.encounter_catalog_entry(entry, &"spell")
		if spell == null: return null
		complex.spells.append(spell)
	complex.can_back_out = payload["canBackOut"]
	complex.action_selection_count = int(payload["actionSelectionCount"])
	return complex if complex.action_selection_count >= 0 and complex.action_selection_count <= 8 else null


static func _parse_thief_body(request_kind: StringName, payload: Dictionary) -> InteractionRequestBody:
	if request_kind == THIEF_ENCOUNTER:
		var fields: Array[String] = ["encounterId", "prompt", "soundId", "characters"]
		if not _fields_are_exact(payload, fields, fields) or not _required_ints(payload, ["encounterId", "soundId"]) or not _required_strings(payload, ["prompt"]) or not payload["characters"] is Array:
			return null
		var result := ThiefEncounterRequestBody.new()
		result.encounter_id = int(payload["encounterId"])
		result.prompt = payload["prompt"]
		result.sound_id = int(payload["soundId"])
		for entry: Variant in payload["characters"]:
			var character := InteractionRequestValueDecoder.thief_character(entry)
			if character == null:
				return null
			result.characters.append(character)
		return result if result.encounter_id >= 0 and not result.characters.is_empty() else null
	var fields: Array[String] = ["encounterId", "actionIndex", "actionLabel", "characterId", "characterName", "portraitId", "chancePercent", "yellowThreshold", "greenThreshold", "frameRate", "timeLimitFrames", "frames"]
	if request_kind != PICK_LOCK or not _fields_are_exact(payload, fields, fields) or not _required_ints(payload, ["encounterId", "actionIndex", "chancePercent", "yellowThreshold", "greenThreshold", "frameRate", "timeLimitFrames"]) or not _required_strings(payload, ["actionLabel", "characterId", "characterName", "portraitId"]) or not payload["frames"] is Array:
		return null
	var lock := PickLockRequestBody.new()
	lock.encounter_id = int(payload["encounterId"])
	lock.action_index = int(payload["actionIndex"])
	lock.action_label = payload["actionLabel"]
	lock.character_id = payload["characterId"]
	lock.character_name = payload["characterName"]
	lock.portrait_id = payload["portraitId"]
	lock.chance_percent = int(payload["chancePercent"])
	lock.yellow_threshold = int(payload["yellowThreshold"])
	lock.green_threshold = int(payload["greenThreshold"])
	lock.frame_rate = int(payload["frameRate"])
	lock.time_limit_frames = int(payload["timeLimitFrames"])
	if lock.encounter_id < 0 or lock.action_index not in [2, 4, 6, 7] or lock.chance_percent < 1 or lock.chance_percent > 90 or lock.yellow_threshold < 20 or lock.green_threshold < lock.yellow_threshold or lock.green_threshold > 199 or lock.frame_rate < 1 or lock.frame_rate > 60 or lock.time_limit_frames < lock.frame_rate or payload["frames"].is_empty() or payload["frames"].size() > 421:
		return null
	var tumbler_count := -1
	for frame_value: Variant in payload["frames"]:
		if not frame_value is Array or frame_value.size() > 6:
			return null
		if tumbler_count < 0:
			tumbler_count = frame_value.size()
		elif frame_value.size() != tumbler_count:
			return null
		var frame: Array[int] = []
		for position: Variant in frame_value:
			if not _whole_number(position) or int(position) < 10 or int(position) > 208:
				return null
			frame.append(int(position))
		lock.frames.append(frame)
	return lock if lock.time_limit_frames == lock.frames.size() - 1 + lock.frame_rate else null


static func _parse_reward_body(request_kind: StringName, payload: Dictionary) -> InteractionRequestBody:
	if request_kind == LEVEL_UP:
		if not _fields_are_exact(payload, ["mode", "prompt", "characterId", "characterName", "level", "gains", "pointTotal", "spells"], ["mode", "prompt", "characterId", "characterName"]) or not _required_strings(payload, ["mode", "prompt", "characterId", "characterName"]): return null
		var level_up := LevelUpRequestBody.new()
		level_up.mode = StringName(payload["mode"])
		if level_up.mode not in [&"result", &"spell-selection"]: return null
		level_up.prompt = payload["prompt"]
		level_up.character_id = payload["characterId"]
		level_up.character_name = payload["characterName"]
		if level_up.mode == &"result":
			if not _fields_are_exact(payload, ["mode", "prompt", "characterId", "characterName", "level", "gains"], ["mode", "prompt", "characterId", "characterName", "level", "gains"]) or not _whole_number(payload["level"]): return null
			level_up.level = int(payload["level"])
			level_up.gains = InteractionRequestValueDecoder.level_gains(payload["gains"])
			if level_up.gains == null: return null
		else:
			if not _fields_are_exact(payload, ["mode", "prompt", "characterId", "characterName", "pointTotal", "spells"], ["mode", "prompt", "characterId", "characterName", "pointTotal", "spells"]) or not _whole_number(payload["pointTotal"]) or not payload["spells"] is Array: return null
			level_up.point_total = int(payload["pointTotal"])
			for entry: Variant in payload["spells"]:
				var spell := InteractionRequestValueDecoder.spell_choice(entry)
				if spell == null: return null
				level_up.spells.append(spell)
		return level_up
	if request_kind != TREASURE_DISTRIBUTION or not _fields_are_exact(payload, ["mode", "prompt", "item", "items", "remaining", "characters", "wealth", "experienceShare", "detect", "identify", "hasShareCapacity", "summary", "battleId", "origin", "sourceId", "experiencePool"], ["mode"]) or not payload["mode"] is String: return null
	var treasure := TreasureRequestBody.new()
	treasure.mode = StringName(payload["mode"])
	if treasure.mode not in [&"fumbled-item-recovery", &"ordinary", &"completion-confirmation"]: return null
	if not _optional_strings(payload, ["prompt", "summary", "battleId", "origin", "sourceId"]) or not _optional_ints(payload, ["remaining", "experienceShare", "experiencePool"]) or not _optional_bools(payload, ["hasShareCapacity"]): return null
	treasure.prompt = String(payload.get("prompt", ""))
	treasure.has_item = payload.has("item")
	if treasure.has_item and payload["item"] != null:
		treasure.item = InteractionRequestValueDecoder.reward_item(payload["item"])
		if treasure.item == null: return null
	treasure.has_items = payload.has("items")
	if treasure.has_items:
		if not payload["items"] is Array: return null
		for entry: Variant in payload["items"]:
			var reward_item := InteractionRequestValueDecoder.reward_item(entry)
			if reward_item == null: return null
			treasure.items.append(reward_item)
	if treasure.mode == &"ordinary" and (not treasure.has_items or treasure.has_item): return null
	if treasure.mode == &"fumbled-item-recovery" and (not treasure.has_item or treasure.has_items): return null
	if treasure.mode == &"completion-confirmation" and (treasure.has_item or treasure.has_items): return null
	treasure.remaining = int(payload.get("remaining", 0))
	treasure.has_remaining = payload.has("remaining")
	if payload.has("characters"):
		if not payload["characters"] is Array: return null
		for entry: Variant in payload["characters"]:
			var character := InteractionRequestValueDecoder.reward_character(entry, treasure.mode)
			if character == null: return null
			treasure.characters.append(character)
	if treasure.mode == &"ordinary":
		var character_ids: Dictionary = {}
		for character: InteractionRequestValue.RewardCharacter in treasure.characters:
			if character_ids.has(character.id): return null
			character_ids[character.id] = true
		for item: InteractionRequestValue.RewardItem in treasure.items:
			if not item.has_assignments or item.assignments.size() != character_ids.size(): return null
			var assignment_ids: Dictionary = {}
			for assignment: InteractionRequestValue.RewardAssignment in item.assignments:
				if not character_ids.has(assignment.character_id) or assignment_ids.has(assignment.character_id): return null
				assignment_ids[assignment.character_id] = true
	elif treasure.mode == &"fumbled-item-recovery" and treasure.item != null and treasure.item.has_assignments:
		return null
	if payload.has("wealth"):
		treasure.wealth = InteractionRequestValueDecoder.wealth(payload["wealth"])
		if treasure.wealth == null: return null
	treasure.experience_share = int(payload.get("experienceShare", 0))
	if payload.has("detect"):
		treasure.detect = InteractionRequestValueDecoder.reward_method(payload["detect"])
		if treasure.detect == null: return null
	if payload.has("identify"):
		treasure.identify = InteractionRequestValueDecoder.reward_method(payload["identify"])
		if treasure.identify == null: return null
	treasure.has_share_capacity = bool(payload.get("hasShareCapacity", false))
	treasure.summary = String(payload.get("summary", ""))
	treasure.battle_id = String(payload.get("battleId", ""))
	treasure.origin = StringName(payload.get("origin", ""))
	treasure.source_id = String(payload.get("sourceId", ""))
	treasure.experience_pool = int(payload.get("experiencePool", 0))
	return treasure


static func _parse_lifecycle_body(payload: Dictionary) -> LifecycleRequestBody:
	var value := LifecycleRequestBody.new()
	return value if ServiceDecoder.populate_lifecycle(payload, value) else null


static func _parse_shop_body(payload: Dictionary) -> ShopRequestBody:
	var result := ShopRequestBody.new()
	return result if ServiceDecoder.populate_shop(payload, result) else null


static func _parse_temple_body(payload: Dictionary) -> TempleRequestBody:
	var result := TempleRequestBody.new()
	return result if ServiceDecoder.populate_temple(payload, result) else null


static func _parse_bank_body(payload: Dictionary, departure: bool) -> BankRequestBody:
	var result := BankRequestBody.new()
	return result if ServiceDecoder.populate_bank(payload, departure, result) else null


static func _parse_combat_body(payload: Dictionary) -> CombatRequestBody:
	var result := CombatRequestBody.new()
	return result if ServiceDecoder.populate_combat(payload, result) else null


static func _array_is_strings(values: Variant) -> bool:
	if not values is Array: return false
	for value: Variant in values:
		if not value is String: return false
	return true


static func _fields_are_exact(data: Dictionary, allowed: Array[String], required: Array[String] = []) -> bool:
	for key: Variant in data.keys():
		if not key is String or not allowed.has(key): return false
	for key: String in required:
		if not data.has(key): return false
	return true


static func _required_strings(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if not data.get(field) is String: return false
	return true


static func _required_ints(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if not _whole_number(data.get(field)): return false
	return true


static func _optional_strings(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if data.has(field) and not data[field] is String: return false
	return true


static func _optional_ints(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if data.has(field) and not _whole_number(data[field]): return false
	return true


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and is_finite(value) and value == floor(value)


static func _optional_bools(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if data.has(field) and not data[field] is bool: return false
	return true


static func _strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		if not value is String: return []
		result.append(value)
	return result
