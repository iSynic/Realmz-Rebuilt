class_name InteractionRequest
extends RefCounted

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


class Body:
	extends RefCounted

	func to_data() -> Dictionary:
		return {}

	func prompt_text() -> String:
		return ""


class AcknowledgeBody:
	extends Body
	var prompt: String
	var message_id: int
	var presentation: StringName
	var journal_eligible: bool
	var journal_recorded: bool
	var sound_id: int
	var player_map_id: String
	var resource_type: String
	var resource_id: int
	var has_message_id: bool
	var has_presentation: bool
	var has_journal_state: bool
	var has_sound_id: bool
	var has_player_map_id: bool
	var has_resource: bool

	func to_data() -> Dictionary:
		var data := {"prompt": prompt}
		if has_message_id: data["messageId"] = message_id
		if has_presentation: data["presentation"] = String(presentation)
		if has_journal_state:
			data["journalEligible"] = journal_eligible
			data["journalRecorded"] = journal_recorded
		if has_sound_id: data["soundId"] = sound_id
		if has_player_map_id: data["playerMapId"] = player_map_id
		if has_resource:
			data["resourceType"] = resource_type
			data["resourceId"] = resource_id
		return data

	func prompt_text() -> String: return prompt


class AgeUpdateBody:
	extends Body
	var character_id: String
	var character_name: String
	var portrait_id: String
	var combat_icon_id: String
	var race_id: String
	var race_name: String
	var previous_age_days: int
	var age_days: int
	var previous_age_group: int
	var age_group: int
	var age_group_name: String
	var age_minimum_years: int
	var age_maximum_years: int
	var transition: int
	var applied_age_group: int
	var changes: Array[int] = []
	var prompt: String
	var presentation: StringName
	var sound_id: int
	var source: StringName

	func to_data() -> Dictionary:
		return {"characterId": character_id, "characterName": character_name, "portraitId": portrait_id, "combatIconId": combat_icon_id, "raceId": race_id, "raceName": race_name, "previousAgeDays": previous_age_days, "ageDays": age_days, "previousAgeGroup": previous_age_group, "ageGroup": age_group, "ageGroupName": age_group_name, "ageMinimumYears": age_minimum_years, "ageMaximumYears": age_maximum_years, "transition": transition, "appliedAgeGroup": applied_age_group, "changes": changes.duplicate(), "prompt": prompt, "presentation": String(presentation), "soundId": sound_id, "source": String(source)}

	func prompt_text() -> String: return prompt

	func same_values(other: AgeUpdateBody) -> bool:
		return other != null \
			and character_id == other.character_id and character_name == other.character_name \
			and portrait_id == other.portrait_id and combat_icon_id == other.combat_icon_id \
			and race_id == other.race_id and race_name == other.race_name \
			and previous_age_days == other.previous_age_days and age_days == other.age_days \
			and previous_age_group == other.previous_age_group and age_group == other.age_group \
			and age_group_name == other.age_group_name \
			and age_minimum_years == other.age_minimum_years and age_maximum_years == other.age_maximum_years \
			and transition == other.transition and applied_age_group == other.applied_age_group \
			and changes == other.changes and prompt == other.prompt and presentation == other.presentation \
			and sound_id == other.sound_id and source == other.source


class YesNoRequestBody:
	extends Body
	var prompt: String
	var yes_id: int
	var yes_label: String
	var no_id: int
	var no_label: String
	var region_id: String
	var has_prompt: bool
	var has_ids: bool
	var has_region_id: bool

	func to_data() -> Dictionary:
		var data := {"yesLabel": yes_label, "noLabel": no_label}
		if has_prompt: data["prompt"] = prompt
		if has_ids:
			data["yesId"] = yes_id
			data["noId"] = no_id
		if has_region_id: data["regionId"] = region_id
		return data

	func prompt_text() -> String: return prompt


class ChoiceRequestBody:
	extends Body
	var prompt: String
	var options: Array[InteractionRequestValue.ChoiceOption] = []
	var can_back_out: bool
	var encounter_kind: StringName
	var encounter_id: int
	var has_can_back_out: bool
	var has_encounter: bool

	func to_data() -> Dictionary:
		var data := {"prompt": prompt, "options": options.map(func(value: InteractionRequestValue.ChoiceOption) -> Dictionary: return value.to_data())}
		if has_can_back_out: data["canBackOut"] = can_back_out
		if has_encounter:
			data["encounterKind"] = String(encounter_kind)
			data["encounterId"] = encounter_id
		return data

	func prompt_text() -> String: return prompt


class CharacterSelectionRequestBody:
	extends Body
	var prompt: String
	var count: int = 1
	var eligible: Array[InteractionRequestValue.SelectionCandidate] = []
	var allow_dead: bool
	var mode: StringName
	var item_instance_id: String
	var spell_id: String
	var scroll_slot: int = -1
	var spell_context: InteractionRequestValue.SpellTargetContext

	func to_data() -> Dictionary:
		var data := {"count": count, "eligible": eligible.map(func(value: InteractionRequestValue.SelectionCandidate) -> Dictionary: return value.to_data())}
		if not prompt.is_empty(): data["prompt"] = prompt
		if allow_dead: data["allowDead"] = true
		if not mode.is_empty(): data["mode"] = String(mode)
		if not item_instance_id.is_empty(): data["itemInstanceId"] = item_instance_id
		if not spell_id.is_empty(): data["spellId"] = spell_id
		if scroll_slot >= 0: data["scrollSlot"] = scroll_slot
		if spell_context != null: data["spellContext"] = spell_context.to_data()
		return data

	func prompt_text() -> String: return prompt


class SelectionRequestBody:
	extends Body
	var prompt: String
	var maximum: int
	var selected_ids: Array[String] = []
	var required_ids: Array[String] = []
	var candidates: Array[InteractionRequestValue.SelectionCandidate] = []

	func to_data() -> Dictionary:
		return {"prompt": prompt, "maximum": maximum, "selectedIds": selected_ids.duplicate(), "requiredIds": required_ids.duplicate(), "candidates": candidates.map(func(value: InteractionRequestValue.SelectionCandidate) -> Dictionary: return value.to_data())}

	func prompt_text() -> String: return prompt


class ComplexEncounterRequestBody:
	extends Body
	var encounter_kind: StringName
	var encounter_id: int
	var prompt: String
	var actions: Array[InteractionRequestValue.EncounterAction] = []
	var characters: Array[InteractionRequestValue.NamedCharacter] = []
	var items: Array[InteractionRequestValue.EncounterCatalogEntry] = []
	var spells: Array[InteractionRequestValue.EncounterCatalogEntry] = []
	var can_back_out: bool
	var action_selection_count: int

	func to_data() -> Dictionary:
		return {"encounterKind": String(encounter_kind), "encounterId": encounter_id, "prompt": prompt, "actions": actions.map(func(value: InteractionRequestValue.EncounterAction) -> Dictionary: return value.to_data()), "characters": characters.map(func(value: InteractionRequestValue.NamedCharacter) -> Dictionary: return value.to_data()), "items": items.map(func(value: InteractionRequestValue.EncounterCatalogEntry) -> Dictionary: return value.to_data()), "spells": spells.map(func(value: InteractionRequestValue.EncounterCatalogEntry) -> Dictionary: return value.to_data()), "canBackOut": can_back_out, "actionSelectionCount": action_selection_count}

	func prompt_text() -> String: return prompt


class ThiefEncounterRequestBody:
	extends Body
	var encounter_id: int
	var prompt: String
	var sound_id: int
	var characters: Array[InteractionRequestValue.ThiefCharacter] = []

	func to_data() -> Dictionary:
		return {"encounterId": encounter_id, "prompt": prompt, "soundId": sound_id, "characters": characters.map(func(value: InteractionRequestValue.ThiefCharacter) -> Dictionary: return value.to_data())}

	func prompt_text() -> String: return prompt


class PickLockRequestBody:
	extends Body
	var encounter_id: int
	var action_index: int
	var action_label: String
	var character_id: String
	var character_name: String
	var portrait_id: String
	var chance_percent: int
	var yellow_threshold: int
	var green_threshold: int
	var frame_rate: int
	var time_limit_frames: int
	var frames: Array[Array] = []

	func to_data() -> Dictionary:
		var serialized: Array[Array] = []
		for frame: Array in frames:
			serialized.append(frame.duplicate())
		return {"encounterId": encounter_id, "actionIndex": action_index, "actionLabel": action_label, "characterId": character_id, "characterName": character_name, "portraitId": portrait_id, "chancePercent": chance_percent, "yellowThreshold": yellow_threshold, "greenThreshold": green_threshold, "frameRate": frame_rate, "timeLimitFrames": time_limit_frames, "frames": serialized}

	func prompt_text() -> String:
		return "Stop the tumblers when every marker reaches the gold zone."


class ServiceRequestBody:
	extends Body
	var characters: Array[InteractionRequestValue.ServiceCharacter] = []
	var actions: Array[String] = []


class ShopRequestBody:
	extends ServiceRequestBody
	var shop_id: String
	var inflation_percent: int
	var party_gold: int
	var identify_price: int
	var stock: Array[InteractionRequestValue.ShopStock] = []
	var accept_ranges: Array[int] = []

	func to_data() -> Dictionary:
		return {"shopId": shop_id, "inflationPercent": inflation_percent, "partyGold": party_gold, "identifyPrice": identify_price, "stock": stock.map(func(value: InteractionRequestValue.ShopStock) -> Dictionary: return value.to_data()), "characters": characters.map(func(value: InteractionRequestValue.ServiceCharacter) -> Dictionary: return value.to_shop_data()), "acceptRanges": accept_ranges.duplicate(), "actions": actions.duplicate()}


class TempleRequestBody:
	extends ServiceRequestBody
	var cost_percent: int
	var services: Array[InteractionRequestValue.TempleService] = []
	var pooled_wealth: InteractionRequestValue.Wealth
	var bank_available: bool
	var selected_character_id: String

	func to_data() -> Dictionary:
		return {"costPercent": cost_percent, "characters": characters.map(func(value: InteractionRequestValue.ServiceCharacter) -> Dictionary: return value.to_temple_data()), "services": services.map(func(value: InteractionRequestValue.TempleService) -> Dictionary: return value.to_data()), "pooledWealth": pooled_wealth.to_data(), "bankAvailable": bank_available, "selectedCharacterId": selected_character_id, "actions": actions.duplicate()}


class BankRequestBody:
	extends ServiceRequestBody
	var mode: StringName
	var has_mode: bool
	var selected_character_id: String
	var pooled_wealth: InteractionRequestValue.Wealth
	var banked_wealth: InteractionRequestValue.Wealth
	var pool: InteractionRequestValue.Availability
	var share: InteractionRequestValue.Availability

	func to_data() -> Dictionary:
		var data := {"selectedCharacterId": selected_character_id, "pooledWealth": pooled_wealth.to_data(), "bankedWealth": banked_wealth.to_data(), "pool": pool.to_data(), "share": share.to_data(), "characters": characters.map(func(value: InteractionRequestValue.ServiceCharacter) -> Dictionary: return value.to_bank_data())}
		if has_mode: data["mode"] = String(mode)
		if not actions.is_empty(): data["actions"] = actions.duplicate()
		return data

class TreasureRequestBody:
	extends Body
	var mode: StringName
	var prompt: String
	var item: InteractionRequestValue.RewardItem
	var items: Array[InteractionRequestValue.RewardItem] = []
	var remaining: int
	var characters: Array[InteractionRequestValue.RewardCharacter] = []
	var wealth: InteractionRequestValue.Wealth
	var experience_share: int
	var detect: InteractionRequestValue.RewardMethod
	var identify: InteractionRequestValue.RewardMethod
	var has_share_capacity: bool
	var summary: String
	var battle_id: String
	var origin: StringName
	var source_id: String
	var experience_pool: int
	var has_item: bool
	var has_items: bool
	var has_remaining: bool

	func to_data() -> Dictionary:
		var data := {"mode": String(mode)}
		if not prompt.is_empty(): data["prompt"] = prompt
		if has_item: data["item"] = null if item == null else item.to_data()
		if has_items: data["items"] = items.map(func(value: InteractionRequestValue.RewardItem) -> Dictionary: return value.to_data())
		if has_remaining: data["remaining"] = remaining
		if not characters.is_empty(): data["characters"] = characters.map(func(value: InteractionRequestValue.RewardCharacter) -> Dictionary: return value.to_data())
		if wealth != null: data["wealth"] = wealth.to_data()
		if experience_share != 0: data["experienceShare"] = experience_share
		if detect != null: data["detect"] = detect.to_data()
		if identify != null: data["identify"] = identify.to_data()
		if has_share_capacity: data["hasShareCapacity"] = true
		if not summary.is_empty(): data["summary"] = summary
		if not battle_id.is_empty(): data["battleId"] = battle_id
		if not origin.is_empty(): data["origin"] = String(origin)
		if not source_id.is_empty(): data["sourceId"] = source_id
		if experience_pool != 0: data["experiencePool"] = experience_pool
		return data

	func prompt_text() -> String: return prompt

	func same_fumble_values(other: TreasureRequestBody) -> bool:
		if other == null or mode != &"fumbled-item-recovery" or other.mode != mode \
				or prompt != other.prompt or battle_id != other.battle_id \
				or not has_item or not other.has_item or not has_remaining or not other.has_remaining \
				or remaining != other.remaining or item == null or other.item == null \
				or characters.size() != other.characters.size():
			return false
		if item.to_data() != other.item.to_data():
			return false
		for index: int in characters.size():
			var left := characters[index]
			var right := other.characters[index]
			if left.id != right.id or left.name != right.name or left.enabled != right.enabled \
					or left.reason != right.reason or left.has_health != right.has_health \
					or not left.has_health or not right.has_health \
					or left.current_health != right.current_health or left.maximum_health != right.maximum_health:
				return false
		return true


class LevelUpRequestBody:
	extends Body
	var mode: StringName
	var prompt: String
	var character_id: String
	var character_name: String
	var level: int
	var gains: InteractionRequestValue.LevelGains
	var point_total: int
	var spells: Array[InteractionRequestValue.SpellChoice] = []

	func to_data() -> Dictionary:
		var data := {"mode": String(mode), "prompt": prompt, "characterId": character_id, "characterName": character_name}
		if mode == &"result":
			data["level"] = level
			data["gains"] = gains.to_data()
		else:
			data["pointTotal"] = point_total
			data["spells"] = spells.map(func(value: InteractionRequestValue.SpellChoice) -> Dictionary: return value.to_data())
		return data

	func prompt_text() -> String: return prompt


class CombatRequestBody:
	extends Body
	var battle_id: String
	var round_number: int
	var actor_id: String
	var attack_units_remaining: int
	var movement_remaining: int
	var enemies_remaining: int
	var actions: Array[String] = []
	var weapon_mode: StringName
	var weapon_switch: InteractionRequestValue.Availability
	var ranged_attack: InteractionRequestValue.Availability
	var retreat: InteractionRequestValue.Availability
	var melee_attack_reason: String
	var targets: Array[InteractionRequestValue.CombatTarget] = []
	var combatants: Array[InteractionRequestValue.Combatant] = []
	var movement: Array[InteractionRequestValue.MovementOption] = []
	var spell_casts: Array[InteractionRequestValue.CastOption] = []
	var spell_cast_reason: String
	var fast_spells: Array[InteractionRequestValue.FastSpell] = []
	var item_casts: Array[InteractionRequestValue.CastOption] = []
	var item_cast_reason: String
	var scroll_casts: Array[InteractionRequestValue.CastOption] = []
	var scroll_cast_reason: String
	var auto_turn: InteractionRequestValue.Availability
	var auto_character_ids: Array[String] = []
	var delay: InteractionRequestValue.Availability
	var bandage: InteractionRequestValue.Availability
	var bandage_targets: Array[InteractionRequestValue.CombatTarget] = []
	var turn_undead: InteractionRequestValue.Availability
	var turn_undead_targets: Array[InteractionRequestValue.CombatTarget] = []
	var undo: InteractionRequestValue.Availability

	func to_data() -> Dictionary:
		var bandage_data := bandage.to_data(); bandage_data["targets"] = bandage_targets.map(func(value: InteractionRequestValue.CombatTarget) -> Dictionary: return value.to_data())
		var turn_data := turn_undead.to_data(); turn_data["targets"] = turn_undead_targets.map(func(value: InteractionRequestValue.CombatTarget) -> Dictionary: return value.to_data())
		return {"battleId": battle_id, "round": round_number, "actorId": actor_id, "attackUnitsRemaining": attack_units_remaining, "movementRemaining": movement_remaining, "enemiesRemaining": enemies_remaining, "actions": actions.duplicate(), "weaponMode": String(weapon_mode), "weaponSwitch": weapon_switch.to_data(), "rangedAttack": ranged_attack.to_data(), "retreat": retreat.to_data(), "meleeAttackReason": melee_attack_reason, "targets": targets.map(func(value: InteractionRequestValue.CombatTarget) -> Dictionary: return value.to_data()), "combatants": combatants.map(func(value: InteractionRequestValue.Combatant) -> Dictionary: return value.to_data()), "movement": movement.map(func(value: InteractionRequestValue.MovementOption) -> Dictionary: return value.to_data()), "spellCasts": spell_casts.map(func(value: InteractionRequestValue.CastOption) -> Dictionary: return value.to_data()), "spellCastReason": spell_cast_reason, "fastSpells": fast_spells.map(func(value: InteractionRequestValue.FastSpell) -> Dictionary: return value.to_data()), "itemCasts": item_casts.map(func(value: InteractionRequestValue.CastOption) -> Dictionary: return value.to_data()), "itemCastReason": item_cast_reason, "scrollCasts": scroll_casts.map(func(value: InteractionRequestValue.CastOption) -> Dictionary: return value.to_data()), "scrollCastReason": scroll_cast_reason, "autoTurn": auto_turn.to_data(), "autoCharacterIds": auto_character_ids.duplicate(), "delay": delay.to_data(), "bandage": bandage_data, "turnUndead": turn_data, "undo": undo.to_data()}


class LifecycleRequestBody:
	extends Body
	var operation: StringName
	var prompt: String
	var has_active_session: bool
	var in_combat: bool
	var includes_active_session: bool
	var options: Array[InteractionRequestValue.LifecycleOption] = []

	func to_data() -> Dictionary:
		var data := {"operation": String(operation), "prompt": prompt, "inCombat": in_combat, "options": options.map(func(value: InteractionRequestValue.LifecycleOption) -> Dictionary: return value.to_data())}
		if includes_active_session: data["hasActiveSession"] = has_active_session
		return data

	func prompt_text() -> String: return prompt


var request_id: String
var kind: StringName
var body: Body
# Revision-local detached projection prepared while constructing a combat
# request. It is deliberately excluded from to_data(); restored requests rebuild
# it from authoritative state, while live commits can avoid projecting combat
# twice before their first frame.
var transient_combat_view: CombatView


func _init(id: String, request_kind: StringName, request_body: Body) -> void:
	request_id = id
	kind = request_kind
	body = request_body


func to_data() -> Dictionary:
	return {"kind": String(kind), "version": VERSION, "data": {"requestId": request_id, "payload": body.to_data()}}


func is_supported_kind() -> bool:
	if request_id.is_empty() or body == null:
		return false
	match kind:
		ACKNOWLEDGE: return body is AcknowledgeBody
		AGE_UPDATE: return body is AgeUpdateBody
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
	var value := AcknowledgeBody.new()
	value.prompt = prompt
	value.message_id = message_id
	value.presentation = &"classic-textbox"
	value.has_message_id = true
	value.has_presentation = true
	return InteractionRequest.new(id, ACKNOWLEDGE, value)


static func age_update(id: String, update_payload: Dictionary) -> InteractionRequest:
	return _from_payload(id, AGE_UPDATE, update_payload)


static func age_update_body(id: String, update: AgeUpdateBody) -> InteractionRequest:
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
		var option := InteractionRequestValue.choice_option(entry)
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
	var parsed: Body = null
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


static func _parse_dialog_body(request_kind: StringName, payload: Dictionary) -> Body:
	if request_kind == ACKNOWLEDGE:
		if not _fields_are_exact(payload, ["prompt", "messageId", "presentation", "journalEligible", "journalRecorded", "soundId", "playerMapId", "resourceType", "resourceId"], ["prompt"]) or not payload["prompt"] is String or not _optional_ints(payload, ["messageId", "soundId", "resourceId"]) or not _optional_strings(payload, ["presentation", "playerMapId", "resourceType"]) or not _optional_bools(payload, ["journalEligible", "journalRecorded"]): return null
		if payload.has("journalEligible") != payload.has("journalRecorded"): return null
		if payload.has("resourceType") != payload.has("resourceId") or (payload.has("resourceType") and String(payload["resourceType"]).is_empty()): return null
		var acknowledge_body := AcknowledgeBody.new()
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
	var age_body := AgeUpdateBody.new()
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


static func _parse_selection_body(request_kind: StringName, payload: Dictionary) -> Body:
	if request_kind in [INDEXED_CHOICE, ENCOUNTER_CHOICE]:
		if not _fields_are_exact(payload, ["prompt", "options", "canBackOut", "encounterKind", "encounterId"], ["prompt", "options"]) or not payload["prompt"] is String or not payload["options"] is Array or not _optional_bools(payload, ["canBackOut"]) or not _optional_strings(payload, ["encounterKind"]) or not _optional_ints(payload, ["encounterId"]): return null
		var choice := ChoiceRequestBody.new()
		choice.prompt = payload["prompt"]
		for entry: Variant in payload["options"]:
			var option := InteractionRequestValue.choice_option(entry); if option == null: return null
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
			var candidate := InteractionRequestValue.selection_candidate(entry); if candidate == null: return null
			characters.eligible.append(candidate)
		characters.allow_dead = bool(payload.get("allowDead", false))
		characters.mode = StringName(payload.get("mode", ""))
		characters.item_instance_id = String(payload.get("itemInstanceId", ""))
		characters.spell_id = String(payload.get("spellId", ""))
		characters.scroll_slot = int(payload.get("scrollSlot", -1))
		if payload.has("spellContext"):
			characters.spell_context = InteractionRequestValue.spell_target_context(payload["spellContext"])
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
			var candidate := InteractionRequestValue.selection_candidate(entry); if candidate == null: return null
			allies.candidates.append(candidate)
		return allies
	if request_kind != WORD_AND_ACTION or not _fields_are_exact(payload, ["encounterKind", "encounterId", "prompt", "actions", "characters", "items", "spells", "canBackOut", "actionSelectionCount"], ["encounterKind", "encounterId", "prompt", "actions", "characters", "items", "spells", "canBackOut", "actionSelectionCount"]) or not _required_strings(payload, ["encounterKind", "prompt"]) or not _required_ints(payload, ["encounterId", "actionSelectionCount"]) or not payload["actions"] is Array or not payload["characters"] is Array or not payload["items"] is Array or not payload["spells"] is Array or not payload["canBackOut"] is bool: return null
	var complex := ComplexEncounterRequestBody.new()
	complex.encounter_kind = StringName(payload["encounterKind"])
	if complex.encounter_kind != &"complex": return null
	complex.encounter_id = int(payload["encounterId"])
	complex.prompt = payload["prompt"]
	for entry: Variant in payload["actions"]:
		var action := InteractionRequestValue.encounter_action(entry); if action == null: return null
		complex.actions.append(action)
	for entry: Variant in payload["characters"]:
		var character := InteractionRequestValue.named_character(entry); if character == null: return null
		complex.characters.append(character)
	for entry: Variant in payload["items"]:
		var item := InteractionRequestValue.encounter_catalog_entry(entry, &"item"); if item == null: return null
		complex.items.append(item)
	for entry: Variant in payload["spells"]:
		var spell := InteractionRequestValue.encounter_catalog_entry(entry, &"spell"); if spell == null: return null
		complex.spells.append(spell)
	complex.can_back_out = payload["canBackOut"]
	complex.action_selection_count = int(payload["actionSelectionCount"])
	return complex if complex.action_selection_count >= 0 and complex.action_selection_count <= 8 else null


static func _parse_thief_body(request_kind: StringName, payload: Dictionary) -> Body:
	if request_kind == THIEF_ENCOUNTER:
		var fields: Array[String] = ["encounterId", "prompt", "soundId", "characters"]
		if not _fields_are_exact(payload, fields, fields) or not _required_ints(payload, ["encounterId", "soundId"]) or not _required_strings(payload, ["prompt"]) or not payload["characters"] is Array:
			return null
		var result := ThiefEncounterRequestBody.new()
		result.encounter_id = int(payload["encounterId"])
		result.prompt = payload["prompt"]
		result.sound_id = int(payload["soundId"])
		for entry: Variant in payload["characters"]:
			var character := InteractionRequestValue.thief_character(entry)
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


static func _parse_reward_body(request_kind: StringName, payload: Dictionary) -> Body:
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
			level_up.gains = InteractionRequestValue.level_gains(payload["gains"])
			if level_up.gains == null: return null
		else:
			if not _fields_are_exact(payload, ["mode", "prompt", "characterId", "characterName", "pointTotal", "spells"], ["mode", "prompt", "characterId", "characterName", "pointTotal", "spells"]) or not _whole_number(payload["pointTotal"]) or not payload["spells"] is Array: return null
			level_up.point_total = int(payload["pointTotal"])
			for entry: Variant in payload["spells"]:
				var spell := InteractionRequestValue.spell_choice(entry); if spell == null: return null
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
		treasure.item = InteractionRequestValue.reward_item(payload["item"])
		if treasure.item == null: return null
	treasure.has_items = payload.has("items")
	if treasure.has_items:
		if not payload["items"] is Array: return null
		for entry: Variant in payload["items"]:
			var reward_item := InteractionRequestValue.reward_item(entry); if reward_item == null: return null
			treasure.items.append(reward_item)
	if treasure.mode == &"ordinary" and (not treasure.has_items or treasure.has_item): return null
	if treasure.mode == &"fumbled-item-recovery" and (not treasure.has_item or treasure.has_items): return null
	if treasure.mode == &"completion-confirmation" and (treasure.has_item or treasure.has_items): return null
	treasure.remaining = int(payload.get("remaining", 0))
	treasure.has_remaining = payload.has("remaining")
	if payload.has("characters"):
		if not payload["characters"] is Array: return null
		for entry: Variant in payload["characters"]:
			var character := InteractionRequestValue.reward_character(entry, treasure.mode); if character == null: return null
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
		treasure.wealth = InteractionRequestValue.wealth(payload["wealth"])
		if treasure.wealth == null: return null
	treasure.experience_share = int(payload.get("experienceShare", 0))
	if payload.has("detect"):
		treasure.detect = InteractionRequestValue.reward_method(payload["detect"])
		if treasure.detect == null: return null
	if payload.has("identify"):
		treasure.identify = InteractionRequestValue.reward_method(payload["identify"])
		if treasure.identify == null: return null
	treasure.has_share_capacity = bool(payload.get("hasShareCapacity", false))
	treasure.summary = String(payload.get("summary", ""))
	treasure.battle_id = String(payload.get("battleId", ""))
	treasure.origin = StringName(payload.get("origin", ""))
	treasure.source_id = String(payload.get("sourceId", ""))
	treasure.experience_pool = int(payload.get("experiencePool", 0))
	return treasure


static func _parse_lifecycle_body(payload: Dictionary) -> LifecycleRequestBody:
	if not _fields_are_exact(payload, ["operation", "prompt", "hasActiveSession", "inCombat", "options"], ["operation", "prompt", "inCombat", "options"]) or not _required_strings(payload, ["operation", "prompt"]) or not payload["inCombat"] is bool or not payload["options"] is Array or not _optional_bools(payload, ["hasActiveSession"]): return null
	var value := LifecycleRequestBody.new()
	value.operation = StringName(payload["operation"])
	value.prompt = payload["prompt"]
	value.has_active_session = bool(payload.get("hasActiveSession", false))
	value.in_combat = payload["inCombat"]
	value.includes_active_session = payload.has("hasActiveSession")
	for entry: Variant in payload["options"]:
		var option := InteractionRequestValue.lifecycle_option(entry); if option == null: return null
		value.options.append(option)
	return value


static func _parse_shop_body(payload: Dictionary) -> ShopRequestBody:
	var fields: Array[String] = ["shopId", "inflationPercent", "partyGold", "identifyPrice", "stock", "characters", "acceptRanges", "actions"]
	if not _fields_are_exact(payload, fields, fields) or not _required_strings(payload, ["shopId"]) or not _required_ints(payload, ["inflationPercent", "partyGold", "identifyPrice"]) or not payload["stock"] is Array or not payload["characters"] is Array or not payload["acceptRanges"] is Array or not payload["actions"] is Array: return null
	var result := ShopRequestBody.new()
	result.shop_id = payload["shopId"]
	result.inflation_percent = int(payload["inflationPercent"])
	result.party_gold = int(payload["partyGold"])
	result.identify_price = int(payload["identifyPrice"])
	for entry: Variant in payload["stock"]:
		var stock := InteractionRequestValue.shop_stock(entry)
		if stock == null: return null
		result.stock.append(stock)
	for entry: Variant in payload["characters"]:
		var character := InteractionRequestValue.service_character(entry, &"shop")
		if character == null: return null
		result.characters.append(character)
	for entry: Variant in payload["acceptRanges"]:
		if not _whole_number(entry): return null
		result.accept_ranges.append(int(entry))
	if not _array_is_strings(payload["actions"]): return null
	result.actions = _strings(payload["actions"])
	return result


static func _parse_temple_body(payload: Dictionary) -> TempleRequestBody:
	var fields: Array[String] = ["costPercent", "characters", "services", "pooledWealth", "bankAvailable", "selectedCharacterId", "actions"]
	if not _fields_are_exact(payload, fields, fields) or not _required_ints(payload, ["costPercent"]) or not payload["characters"] is Array or not payload["services"] is Array or not payload["bankAvailable"] is bool or not payload["selectedCharacterId"] is String or not payload["actions"] is Array: return null
	var result := TempleRequestBody.new()
	result.cost_percent = int(payload["costPercent"])
	result.pooled_wealth = InteractionRequestValue.wealth(payload["pooledWealth"])
	if result.pooled_wealth == null: return null
	result.bank_available = payload["bankAvailable"]
	result.selected_character_id = payload["selectedCharacterId"]
	for entry: Variant in payload["characters"]:
		var character := InteractionRequestValue.service_character(entry, &"temple")
		if character == null: return null
		result.characters.append(character)
	for entry: Variant in payload["services"]:
		var service := InteractionRequestValue.temple_service(entry)
		if service == null: return null
		result.services.append(service)
	if not _array_is_strings(payload["actions"]): return null
	result.actions = _strings(payload["actions"])
	return result


static func _parse_bank_body(payload: Dictionary, departure: bool) -> BankRequestBody:
	var allowed: Array[String] = ["mode", "selectedCharacterId", "pooledWealth", "bankedWealth", "pool", "share", "characters", "actions"]
	var required: Array[String] = ["selectedCharacterId", "pooledWealth", "bankedWealth", "pool", "share", "characters"]
	if not departure: required.append("actions")
	if not _fields_are_exact(payload, allowed, required) or not payload["selectedCharacterId"] is String or not payload["characters"] is Array or not _optional_strings(payload, ["mode"]): return null
	if departure and String(payload.get("mode", "")) != "departure": return null
	var result := BankRequestBody.new()
	result.mode = StringName(payload.get("mode", ""))
	result.has_mode = payload.has("mode")
	result.selected_character_id = payload["selectedCharacterId"]
	result.pooled_wealth = InteractionRequestValue.wealth(payload["pooledWealth"])
	result.banked_wealth = InteractionRequestValue.wealth(payload["bankedWealth"])
	result.pool = InteractionRequestValue.availability(payload["pool"])
	result.share = InteractionRequestValue.availability(payload["share"])
	if result.pooled_wealth == null or result.banked_wealth == null or result.pool == null or result.share == null: return null
	for entry: Variant in payload["characters"]:
		var character := InteractionRequestValue.service_character(entry, &"bank")
		if character == null: return null
		result.characters.append(character)
	if payload.has("actions"):
		if not _array_is_strings(payload["actions"]): return null
		result.actions = _strings(payload["actions"])
	return result


static func _parse_combat_body(payload: Dictionary) -> CombatRequestBody:
	var fields: Array[String] = ["battleId", "round", "actorId", "attackUnitsRemaining", "movementRemaining", "enemiesRemaining", "actions", "weaponMode", "weaponSwitch", "rangedAttack", "retreat", "meleeAttackReason", "targets", "combatants", "movement", "spellCasts", "spellCastReason", "fastSpells", "itemCasts", "itemCastReason", "scrollCasts", "scrollCastReason", "autoTurn", "autoCharacterIds", "delay", "bandage", "turnUndead", "undo"]
	if not _fields_are_exact(payload, fields, fields) or not _required_strings(payload, ["battleId", "actorId", "weaponMode", "meleeAttackReason", "spellCastReason", "itemCastReason", "scrollCastReason"]) or not _required_ints(payload, ["round", "attackUnitsRemaining", "movementRemaining", "enemiesRemaining"]): return null
	for field: String in ["actions", "targets", "combatants", "movement", "spellCasts", "fastSpells", "itemCasts", "scrollCasts", "autoCharacterIds"]:
		if not payload[field] is Array: return null
	var result := CombatRequestBody.new()
	result.battle_id = payload["battleId"]; result.round_number = int(payload["round"]); result.actor_id = payload["actorId"]; result.attack_units_remaining = int(payload["attackUnitsRemaining"]); result.movement_remaining = int(payload["movementRemaining"]); result.enemies_remaining = int(payload["enemiesRemaining"]); result.weapon_mode = StringName(payload["weaponMode"]); result.melee_attack_reason = payload["meleeAttackReason"]; result.spell_cast_reason = payload["spellCastReason"]; result.item_cast_reason = payload["itemCastReason"]; result.scroll_cast_reason = payload["scrollCastReason"]
	if not _array_is_strings(payload["actions"]) or not _array_is_strings(payload["autoCharacterIds"]): return null
	result.actions = _strings(payload["actions"]); result.auto_character_ids = _strings(payload["autoCharacterIds"])
	result.weapon_switch = InteractionRequestValue.availability(payload["weaponSwitch"]); result.ranged_attack = InteractionRequestValue.availability(payload["rangedAttack"]); result.retreat = InteractionRequestValue.availability(payload["retreat"]); result.auto_turn = InteractionRequestValue.availability(payload["autoTurn"]); result.delay = InteractionRequestValue.availability(payload["delay"]); result.undo = InteractionRequestValue.availability(payload["undo"])
	if result.weapon_switch == null or result.ranged_attack == null or result.retreat == null or result.auto_turn == null or result.delay == null or result.undo == null: return null
	var bandage_parse: Variant = _parse_target_availability(payload["bandage"]); var turn_parse: Variant = _parse_target_availability(payload["turnUndead"])
	if bandage_parse == null or turn_parse == null: return null
	result.bandage = bandage_parse[0]; result.bandage_targets = bandage_parse[1]; result.turn_undead = turn_parse[0]; result.turn_undead_targets = turn_parse[1]
	for entry: Variant in payload["targets"]:
		var parsed_target := InteractionRequestValue.combat_target(entry); if parsed_target == null: return null
		result.targets.append(parsed_target)
	for entry: Variant in payload["combatants"]:
		var parsed_combatant := InteractionRequestValue.combatant(entry); if parsed_combatant == null: return null
		result.combatants.append(parsed_combatant)
	for entry: Variant in payload["movement"]:
		var parsed_movement := InteractionRequestValue.movement_option(entry); if parsed_movement == null: return null
		result.movement.append(parsed_movement)
	for entry: Variant in payload["spellCasts"]:
		var parsed_cast := InteractionRequestValue.cast_option(entry, &"spell"); if parsed_cast == null: return null
		result.spell_casts.append(parsed_cast)
	for entry: Variant in payload["itemCasts"]:
		var parsed_cast := InteractionRequestValue.cast_option(entry, &"item"); if parsed_cast == null: return null
		result.item_casts.append(parsed_cast)
	for entry: Variant in payload["scrollCasts"]:
		var parsed_cast := InteractionRequestValue.cast_option(entry, &"scroll"); if parsed_cast == null: return null
		result.scroll_casts.append(parsed_cast)
	for entry: Variant in payload["fastSpells"]:
		var parsed_fast := InteractionRequestValue.fast_spell(entry); if parsed_fast == null: return null
		result.fast_spells.append(parsed_fast)
	return result


static func _parse_target_availability(data: Variant) -> Variant:
	if not data is Dictionary or not _fields_are_exact(data, ["enabled", "reason", "targets"], ["enabled", "reason", "targets"]) or not data["enabled"] is bool or not data["reason"] is String or not data["targets"] is Array: return null
	var availability_data := {"enabled": data["enabled"], "reason": data["reason"]}
	var availability := InteractionRequestValue.availability(availability_data)
	var targets: Array[InteractionRequestValue.CombatTarget] = []
	for entry: Variant in data["targets"]:
		var target := InteractionRequestValue.combat_target(entry)
		if target == null: return null
		targets.append(target)
	return [availability, targets]


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
