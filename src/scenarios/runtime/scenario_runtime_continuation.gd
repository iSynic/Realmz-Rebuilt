class_name ScenarioRuntimeContinuation
extends RefCounted

const VERSION: int = 1

const CLASSIC_TEXTBOX: StringName = &"classic-textbox"
const CLASSIC_ACKNOWLEDGE: StringName = &"classic-acknowledge"
const CLASSIC_PLAYER_MAP: StringName = &"classic-player-map"
const SAFE_CHOICE: StringName = &"safe-choice"
const CLASSIC_CHOICE: StringName = &"classic-choice"
const CLASSIC_SIMPLE_ENCOUNTER: StringName = &"classic-simple-encounter"
const CLASSIC_COMPLEX_ENCOUNTER: StringName = &"classic-complex-encounter"
const CLASSIC_THIEF_ENCOUNTER: StringName = &"classic-thief-encounter"
const CLASSIC_PICK_LOCK: StringName = &"classic-pick-lock"
const CLASSIC_THIEF_RESOLUTION: StringName = &"classic-thief-resolution"
const CLASSIC_CHARACTER_SELECTION: StringName = &"classic-character-selection"
const CLASSIC_CHARACTER_ABILITY: StringName = &"classic-character-ability"
const CLASSIC_AGE_UPDATES: StringName = &"classic-age-updates"
const SAFE_AGE_UPDATES: StringName = &"safe-age-updates"
const CLASSIC_SHOP: StringName = &"classic-shop"
const CLASSIC_TEMPLE: StringName = &"classic-temple"
const CLASSIC_TEMPLE_EXIT: StringName = &"classic-temple-exit"
const CLASSIC_BANKING: StringName = &"classic-banking"
const CLASSIC_COMBAT: StringName = &"classic-combat"
const SAFE_COMBAT: StringName = &"safe-combat"
const CLASSIC_COMBAT_RETREAT: StringName = &"classic-combat-retreat-confirmation"
const SAFE_COMBAT_RETREAT: StringName = &"safe-combat-retreat-confirmation"
const CLASSIC_COMBAT_AGE: StringName = &"classic-combat-age-updates"
const SAFE_COMBAT_AGE: StringName = &"safe-combat-age-updates"
const CLASSIC_COMBAT_MACRO: StringName = &"classic-combat-macro"
const SAFE_COMBAT_MACRO: StringName = &"safe-combat-macro"
const CLASSIC_COMBAT_DEATH_MACRO: StringName = &"classic-combat-death-macro"
const SAFE_COMBAT_DEATH_MACRO: StringName = &"safe-combat-death-macro"
const CLASSIC_OPCODE_DEATH_MACRO: StringName = &"classic-opcode-death-macro"
const CLASSIC_COMBAT_ALLY: StringName = &"classic-combat-ally-selection"
const SAFE_COMBAT_ALLY: StringName = &"safe-combat-ally-selection"
const CLASSIC_COMBAT_FUMBLE: StringName = &"classic-combat-fumble-recovery"
const SAFE_COMBAT_FUMBLE: StringName = &"safe-combat-fumble-recovery"
const CLASSIC_REWARD: StringName = &"classic-reward"


class Body:
	extends RefCounted

	func to_data() -> Dictionary:
		return {}


class EmptyBody:
	extends Body


class TextBody:
	extends Body
	var message_id: int
	var player_map_id: String

	func to_data() -> Dictionary:
		if not player_map_id.is_empty():
			return {"playerMapId": player_map_id}
		return {"messageId": message_id}


class ChoiceBody:
	extends Body
	var option_count: int
	var values: Array[int]
	var gosub: bool
	var encounter_id: int = -1
	var encounter_attempt: int = 0
	var option_indexes: Array[int]

	func to_data() -> Dictionary:
		if option_count > 0:
			return {"optionCount": option_count}
		if encounter_id >= 0:
			var data := {"encounterId": encounter_id, "gosub": gosub}
			if encounter_attempt > 0:
				data["encounterAttempt"] = encounter_attempt
			if not option_indexes.is_empty():
				data["optionIndexes"] = option_indexes.duplicate()
			return data
		return {"values": values.duplicate(), "gosub": gosub}


class CharacterBody:
	extends Body
	var count: int
	var allow_dead: bool
	var invert: bool
	var values: Array[int]
	var gosub: bool

	func to_data() -> Dictionary:
		if not values.is_empty():
			return {"values": values.duplicate(), "gosub": gosub}
		return {"count": count, "allowDead": allow_dead, "invert": invert}


class ThiefBody:
	extends Body
	var encounter_id: int
	var encounter_attempt: int = 0
	var gosub: bool
	var action_index: int = -1
	var character_id: String
	var phase: StringName
	var succeeded: bool
	var trap_pending: bool

	func to_data() -> Dictionary:
		var data := {"encounterId": encounter_id, "gosub": gosub}
		if encounter_attempt > 0:
			data["encounterAttempt"] = encounter_attempt
		if action_index >= 0:
			data["actionIndex"] = action_index
			data["characterId"] = character_id
		if not phase.is_empty():
			data["phase"] = String(phase)
			data["succeeded"] = succeeded
			data["trapPending"] = trap_pending
		return data


class AgeBody:
	extends Body
	var updates: Array[InteractionRequest.AgeUpdateBody]
	var index: int
	var value: Variant
	var directive: ScenarioVmDirective

	func to_data() -> Dictionary:
		var serialized: Array[Dictionary] = []
		for update: InteractionRequest.AgeUpdateBody in updates:
			serialized.append(update.to_data())
		return {"updates": serialized, "index": index, "value": value.duplicate(true) if value is Array or value is Dictionary else value, "directive": {} if directive == null else directive.to_data()}


class ServiceBody:
	extends Body
	var shop_id: String
	var accept_ranges: Array[int]
	var cost_percent: int
	var bank_available: bool
	var selected_character_id: String

	func to_data() -> Dictionary:
		if not shop_id.is_empty():
			return {"shopId": shop_id, "acceptRanges": accept_ranges.duplicate()}
		return {"costPercent": cost_percent, "bankAvailable": bank_available, "selectedCharacterId": selected_character_id}


class CombatBody:
	extends Body
	var source_kind: StringName
	var battle_id: String
	var caller: ScenarioBattleCaller
	var actor_id: String
	var mode: StringName
	var destination: Vector2i
	var updates: Array[InteractionRequest.AgeUpdateBody]
	var index: int
	var round_before: int
	var program_id: String
	var macro_vm: ScenarioVmSnapshot
	var combatant_id: String
	var reset_traitor_on_complete: bool = true

	func to_data() -> Dictionary:
		var data := {"sourceKind": String(source_kind), "battleId": battle_id, "battleCaller": caller.to_data()}
		if not actor_id.is_empty():
			data["actorId"] = actor_id
			data["mode"] = String(mode)
			data["destination"] = [destination.x, destination.y]
		elif not updates.is_empty():
			var serialized: Array[Dictionary] = []
			for update: InteractionRequest.AgeUpdateBody in updates:
				serialized.append(update.to_data())
			data["updates"] = serialized
			data["index"] = index
			data["roundBefore"] = round_before
		elif macro_vm != null:
			data["programId"] = program_id
			data["macroVm"] = macro_vm.to_data()
			if not combatant_id.is_empty():
				data["combatantId"] = combatant_id
				data["resetTraitorOnComplete"] = reset_traitor_on_complete
		return data


class OpcodeDeathBody:
	extends Body
	var battle_id: String
	var combatant_id: String
	var program_id: String
	var remaining_combatant_ids: Array[String]
	var macro_vm: ScenarioVmSnapshot

	func to_data() -> Dictionary:
		return {"battleId": battle_id, "combatantId": combatant_id, "programId": program_id, "remainingCombatantIds": remaining_combatant_ids.duplicate(), "macroVm": macro_vm.to_data()}


class RewardBody:
	extends Body
	var state: ClassicRewardState

	func to_data() -> Dictionary:
		return {"state": state.to_data()}


var kind: StringName
var body: Body


func _init(continuation_kind: StringName = &"", continuation_body: Body = null) -> void:
	kind = continuation_kind
	body = continuation_body


static func empty(continuation_kind: StringName) -> ScenarioRuntimeContinuation:
	assert(continuation_kind in [CLASSIC_ACKNOWLEDGE, CLASSIC_BANKING])
	return ScenarioRuntimeContinuation.new(continuation_kind, EmptyBody.new())


static func textbox(message_id: int) -> ScenarioRuntimeContinuation:
	var typed := TextBody.new()
	typed.message_id = message_id
	return ScenarioRuntimeContinuation.new(CLASSIC_TEXTBOX, typed)


static func player_map(player_map_id: String) -> ScenarioRuntimeContinuation:
	var typed := TextBody.new()
	typed.player_map_id = player_map_id
	return ScenarioRuntimeContinuation.new(CLASSIC_PLAYER_MAP, typed)


static func safe_choice(option_count: int) -> ScenarioRuntimeContinuation:
	var typed := ChoiceBody.new()
	typed.option_count = option_count
	return ScenarioRuntimeContinuation.new(SAFE_CHOICE, typed)


static func classic_choice(values: Array[int], gosub: bool) -> ScenarioRuntimeContinuation:
	var typed := ChoiceBody.new()
	typed.values.assign(values)
	typed.gosub = gosub
	return ScenarioRuntimeContinuation.new(CLASSIC_CHOICE, typed)


static func encounter(continuation_kind: StringName, encounter_id: int, gosub: bool, option_indexes: Array[int] = [], encounter_attempt: int = 0) -> ScenarioRuntimeContinuation:
	assert(continuation_kind in [CLASSIC_SIMPLE_ENCOUNTER, CLASSIC_COMPLEX_ENCOUNTER])
	var typed := ChoiceBody.new()
	typed.encounter_id = encounter_id
	typed.encounter_attempt = encounter_attempt
	typed.gosub = gosub
	typed.option_indexes.assign(option_indexes)
	return ScenarioRuntimeContinuation.new(continuation_kind, typed)


static func character_selection(count: int, allow_dead: bool, invert: bool) -> ScenarioRuntimeContinuation:
	var typed := CharacterBody.new()
	typed.count = count
	typed.allow_dead = allow_dead
	typed.invert = invert
	return ScenarioRuntimeContinuation.new(CLASSIC_CHARACTER_SELECTION, typed)


static func thief_encounter(encounter_id: int, gosub: bool, encounter_attempt: int = 0) -> ScenarioRuntimeContinuation:
	var typed := ThiefBody.new()
	typed.encounter_id = encounter_id
	typed.encounter_attempt = encounter_attempt
	typed.gosub = gosub
	return ScenarioRuntimeContinuation.new(CLASSIC_THIEF_ENCOUNTER, typed)


static func pick_lock(encounter_id: int, gosub: bool, action_index: int, character_id: String, encounter_attempt: int = 0) -> ScenarioRuntimeContinuation:
	var typed := ThiefBody.new()
	typed.encounter_id = encounter_id
	typed.encounter_attempt = encounter_attempt
	typed.gosub = gosub
	typed.action_index = action_index
	typed.character_id = character_id
	return ScenarioRuntimeContinuation.new(CLASSIC_PICK_LOCK, typed)


static func thief_resolution(encounter_id: int, gosub: bool, action_index: int, character_id: String, phase: StringName, succeeded: bool, trap_pending: bool, encounter_attempt: int = 0) -> ScenarioRuntimeContinuation:
	var typed := ThiefBody.new()
	typed.encounter_id = encounter_id
	typed.encounter_attempt = encounter_attempt
	typed.gosub = gosub
	typed.action_index = action_index
	typed.character_id = character_id
	typed.phase = phase
	typed.succeeded = succeeded
	typed.trap_pending = trap_pending
	return ScenarioRuntimeContinuation.new(CLASSIC_THIEF_RESOLUTION, typed)


static func character_ability(values: Array[int], gosub: bool) -> ScenarioRuntimeContinuation:
	var typed := CharacterBody.new()
	typed.values.assign(values)
	typed.gosub = gosub
	return ScenarioRuntimeContinuation.new(CLASSIC_CHARACTER_ABILITY, typed)


static func age_updates(continuation_kind: StringName, updates: Array[InteractionRequest.AgeUpdateBody], index: int, result_value: Variant, directive: ScenarioVmDirective) -> ScenarioRuntimeContinuation:
	assert(continuation_kind in [CLASSIC_AGE_UPDATES, SAFE_AGE_UPDATES])
	var typed := AgeBody.new()
	for update: InteractionRequest.AgeUpdateBody in updates:
		typed.updates.append(_copy_age_update(update))
	typed.index = index
	typed.value = _detached(result_value)
	typed.directive = directive.copy() if directive != null else null
	return ScenarioRuntimeContinuation.new(continuation_kind, typed)


static func shop(shop_id: String, accept_ranges: Array[int]) -> ScenarioRuntimeContinuation:
	var typed := ServiceBody.new()
	typed.shop_id = shop_id
	typed.accept_ranges.assign(accept_ranges)
	return ScenarioRuntimeContinuation.new(CLASSIC_SHOP, typed)


static func temple(continuation_kind: StringName, cost_percent: int, bank_available: bool, selected_character_id: String) -> ScenarioRuntimeContinuation:
	assert(continuation_kind in [CLASSIC_TEMPLE, CLASSIC_TEMPLE_EXIT])
	var typed := ServiceBody.new()
	typed.cost_percent = cost_percent
	typed.bank_available = bank_available
	typed.selected_character_id = selected_character_id
	return ScenarioRuntimeContinuation.new(continuation_kind, typed)


static func banking() -> ScenarioRuntimeContinuation:
	return empty(CLASSIC_BANKING)


static func combat(continuation_kind: StringName, battle_id: String, caller: ScenarioBattleCaller) -> ScenarioRuntimeContinuation:
	assert(continuation_kind in [CLASSIC_COMBAT, SAFE_COMBAT])
	var typed := CombatBody.new()
	typed.source_kind = continuation_kind
	typed.battle_id = battle_id
	typed.caller = caller.copy()
	return ScenarioRuntimeContinuation.new(continuation_kind, typed)


static func combat_retreat(continuation_kind: StringName, source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller, actor_id: String, mode: StringName, destination: Vector2i) -> ScenarioRuntimeContinuation:
	assert(continuation_kind in [CLASSIC_COMBAT_RETREAT, SAFE_COMBAT_RETREAT])
	var typed := CombatBody.new()
	typed.source_kind = source_kind
	typed.battle_id = battle_id
	typed.caller = caller.copy()
	typed.actor_id = actor_id
	typed.mode = mode
	typed.destination = destination
	return ScenarioRuntimeContinuation.new(continuation_kind, typed)


static func combat_age(continuation_kind: StringName, source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller, updates: Array[InteractionRequest.AgeUpdateBody], index: int, round_before: int) -> ScenarioRuntimeContinuation:
	assert(continuation_kind in [CLASSIC_COMBAT_AGE, SAFE_COMBAT_AGE])
	var typed := CombatBody.new()
	typed.source_kind = source_kind
	typed.battle_id = battle_id
	typed.caller = caller.copy()
	for update: InteractionRequest.AgeUpdateBody in updates:
		typed.updates.append(_copy_age_update(update))
	typed.index = index
	typed.round_before = round_before
	return ScenarioRuntimeContinuation.new(continuation_kind, typed)


static func combat_macro(continuation_kind: StringName, source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller, program_id: String, macro_vm: ScenarioVmSnapshot, combatant_id: String = "", reset_traitor_on_complete: bool = true) -> ScenarioRuntimeContinuation:
	assert(continuation_kind in [CLASSIC_COMBAT_MACRO, SAFE_COMBAT_MACRO, CLASSIC_COMBAT_DEATH_MACRO, SAFE_COMBAT_DEATH_MACRO])
	var typed := CombatBody.new()
	typed.source_kind = source_kind
	typed.battle_id = battle_id
	typed.caller = caller.copy()
	typed.program_id = program_id
	typed.macro_vm = ScenarioVmSnapshot.from_data(macro_vm.to_data())
	typed.combatant_id = combatant_id
	typed.reset_traitor_on_complete = reset_traitor_on_complete
	return ScenarioRuntimeContinuation.new(continuation_kind, typed)


static func opcode_death_macro(battle_id: String, combatant_id: String, program_id: String, remaining_combatant_ids: Array[String], macro_vm: ScenarioVmSnapshot) -> ScenarioRuntimeContinuation:
	var typed := OpcodeDeathBody.new()
	typed.battle_id = battle_id
	typed.combatant_id = combatant_id
	typed.program_id = program_id
	typed.remaining_combatant_ids.assign(remaining_combatant_ids)
	typed.macro_vm = macro_vm
	return ScenarioRuntimeContinuation.new(CLASSIC_OPCODE_DEATH_MACRO, typed)


static func combat_terminal(continuation_kind: StringName, source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller) -> ScenarioRuntimeContinuation:
	assert(continuation_kind in [CLASSIC_COMBAT_ALLY, SAFE_COMBAT_ALLY, CLASSIC_COMBAT_FUMBLE, SAFE_COMBAT_FUMBLE])
	var typed := CombatBody.new()
	typed.source_kind = source_kind
	typed.battle_id = battle_id
	typed.caller = caller.copy()
	return ScenarioRuntimeContinuation.new(continuation_kind, typed)


static func reward(state: ClassicRewardState) -> ScenarioRuntimeContinuation:
	var typed := RewardBody.new()
	typed.state = ClassicRewardState.from_data(state.to_data())
	return ScenarioRuntimeContinuation.new(CLASSIC_REWARD, typed)


func copy() -> ScenarioRuntimeContinuation:
	return from_data(to_data())


func to_data() -> Dictionary:
	var continuation_data := body.to_data() if body != null else {}
	return {"kind": String(kind), "version": VERSION, "data": continuation_data}


static func from_data(value: Variant) -> ScenarioRuntimeContinuation:
	if not value is Dictionary or value.size() != 3 or not value.get("kind") is String or value.get("version") != VERSION or not value.get("data") is Dictionary:
		return null
	var continuation_kind := StringName(value["kind"])
	var data: Dictionary = value["data"]
	match continuation_kind:
		CLASSIC_ACKNOWLEDGE, CLASSIC_BANKING:
			return empty(continuation_kind) if data.is_empty() else null
		CLASSIC_TEXTBOX:
			var message_id := _integer(data.get("messageId"))
			return textbox(message_id) if data.size() == 1 and message_id > 0 else null
		CLASSIC_PLAYER_MAP:
			return player_map(data["playerMapId"]) if data.size() == 1 and data.get("playerMapId") is String and not data["playerMapId"].is_empty() else null
		SAFE_CHOICE:
			var option_count := _integer(data.get("optionCount"))
			return safe_choice(option_count) if data.size() == 1 and option_count >= 1 and option_count <= 256 else null
		CLASSIC_CHOICE:
			var values := _integers(data.get("values"))
			return classic_choice(values, data["gosub"]) if data.size() == 2 and values.size() == 5 and data.get("gosub") is bool else null
		CLASSIC_SIMPLE_ENCOUNTER, CLASSIC_COMPLEX_ENCOUNTER:
			return _decode_encounter(continuation_kind, data)
		CLASSIC_THIEF_ENCOUNTER, CLASSIC_PICK_LOCK, CLASSIC_THIEF_RESOLUTION:
			return _decode_thief(continuation_kind, data)
		CLASSIC_CHARACTER_SELECTION:
			var count := _integer(data.get("count"))
			if data.size() != 3 or count < 1 or count > 6 or not data.get("allowDead") is bool or not data.get("invert") is bool:
				return null
			return character_selection(count, data["allowDead"], data["invert"])
		CLASSIC_CHARACTER_ABILITY:
			var ability_values := _integers(data.get("values"))
			return character_ability(ability_values, data["gosub"]) if data.size() == 2 and ability_values.size() == 5 and data.get("gosub") is bool else null
		CLASSIC_AGE_UPDATES, SAFE_AGE_UPDATES:
			return _decode_age(continuation_kind, data)
		CLASSIC_SHOP:
			var ranges := _integers(data.get("acceptRanges"))
			return shop(data["shopId"], ranges) if data.size() == 2 and data.get("shopId") is String and not data["shopId"].is_empty() and ranges.size() in [0, 4] and ranges.size() == data["acceptRanges"].size() else null
		CLASSIC_TEMPLE, CLASSIC_TEMPLE_EXIT:
			var cost_percent := _integer(data.get("costPercent"))
			if data.size() != 3 or cost_percent < -32768 or cost_percent > 32767 or not data.get("bankAvailable") is bool or not data.get("selectedCharacterId") is String or data["selectedCharacterId"].is_empty():
				return null
			return temple(continuation_kind, cost_percent, data["bankAvailable"], data["selectedCharacterId"])
		CLASSIC_COMBAT, SAFE_COMBAT, CLASSIC_COMBAT_RETREAT, SAFE_COMBAT_RETREAT, CLASSIC_COMBAT_AGE, SAFE_COMBAT_AGE, CLASSIC_COMBAT_MACRO, SAFE_COMBAT_MACRO, CLASSIC_COMBAT_DEATH_MACRO, SAFE_COMBAT_DEATH_MACRO, CLASSIC_COMBAT_ALLY, SAFE_COMBAT_ALLY, CLASSIC_COMBAT_FUMBLE, SAFE_COMBAT_FUMBLE:
			return _decode_combat(continuation_kind, data)
		CLASSIC_OPCODE_DEATH_MACRO:
			return _decode_opcode_death_macro(data)
		CLASSIC_REWARD:
			var reward_state := ClassicRewardState.from_data(data.get("state"))
			return reward(reward_state) if data.size() == 1 and reward_state != null else null
	return null


static func _decode_encounter(continuation_kind: StringName, data: Dictionary) -> ScenarioRuntimeContinuation:
	var encounter_id := _integer(data.get("encounterId"))
	var encounter_attempt := _integer(data.get("encounterAttempt", 0))
	# Classic encounter tables are zero-based; encounter 0 is ordinary authored
	# content, not a missing identity.
	if encounter_id < 0 or encounter_attempt < 0 or not data.get("gosub") is bool:
		return null
	if continuation_kind == CLASSIC_COMPLEX_ENCOUNTER:
		return encounter(continuation_kind, encounter_id, data["gosub"], [], encounter_attempt) if data.size() == (3 if data.has("encounterAttempt") else 2) else null
	var indexes := _integers(data.get("optionIndexes"))
	if data.size() != (4 if data.has("encounterAttempt") else 3) or indexes.is_empty() or indexes.size() > 10:
		return null
	for index: int in indexes:
		if index < 0:
			return null
	return encounter(continuation_kind, encounter_id, data["gosub"], indexes, encounter_attempt)


static func _decode_thief(continuation_kind: StringName, data: Dictionary) -> ScenarioRuntimeContinuation:
	var encounter_id := _integer(data.get("encounterId"))
	var encounter_attempt := _integer(data.get("encounterAttempt", 0))
	var attempt_field_count := 1 if data.has("encounterAttempt") else 0
	if encounter_id < 0 or encounter_attempt < 0 or not data.get("gosub") is bool:
		return null
	if continuation_kind == CLASSIC_THIEF_ENCOUNTER:
		return thief_encounter(encounter_id, data["gosub"], encounter_attempt) if data.size() == 2 + attempt_field_count else null
	var action_index := _integer(data.get("actionIndex"))
	if action_index < 0 or action_index > 7 or not data.get("characterId") is String or data["characterId"].is_empty():
		return null
	if continuation_kind == CLASSIC_PICK_LOCK:
		return pick_lock(encounter_id, data["gosub"], action_index, data["characterId"], encounter_attempt) if data.size() == 4 + attempt_field_count and action_index in [2, 4, 6, 7] else null
	var phase := StringName(data.get("phase", ""))
	if data.size() != 7 + attempt_field_count or phase not in [&"action-message", &"trap-message"] or not data.get("succeeded") is bool or not data.get("trapPending") is bool:
		return null
	return thief_resolution(encounter_id, data["gosub"], action_index, data["characterId"], phase, data["succeeded"], data["trapPending"], encounter_attempt)


static func _decode_age(continuation_kind: StringName, data: Dictionary) -> ScenarioRuntimeContinuation:
	if data.size() != 4 or not data.has_all(["updates", "index", "value", "directive"]) or not data.get("updates") is Array or data["updates"].is_empty() or data["updates"].size() > 30 or not data.get("directive") is Dictionary:
		return null
	var index := _integer(data.get("index"))
	if index < 1 or index > data["updates"].size() or not _json_safe(data.get("value"), 0):
		return null
	var updates: Array[InteractionRequest.AgeUpdateBody] = []
	for update: Variant in data["updates"]:
		var typed_update := _age_update_from_data(update)
		if typed_update == null:
			return null
		updates.append(typed_update)
	var directive_data: Dictionary = data["directive"]
	var directive := ScenarioVmDirective.from_data(directive_data) if not directive_data.is_empty() else null
	if not directive_data.is_empty() and directive == null:
		return null
	return age_updates(continuation_kind, updates, index, data["value"], directive)


static func _decode_combat(continuation_kind: StringName, data: Dictionary) -> ScenarioRuntimeContinuation:
	var expected_source := SAFE_COMBAT if continuation_kind in [SAFE_COMBAT, SAFE_COMBAT_RETREAT, SAFE_COMBAT_AGE, SAFE_COMBAT_MACRO, SAFE_COMBAT_DEATH_MACRO, SAFE_COMBAT_ALLY, SAFE_COMBAT_FUMBLE] else CLASSIC_COMBAT
	if not data.get("sourceKind") is String or StringName(data["sourceKind"]) != expected_source or not data.get("battleId") is String or data["battleId"].is_empty():
		return null
	var caller := ScenarioBattleCaller.from_data(data.get("battleCaller"))
	if caller == null or expected_source == SAFE_COMBAT and caller.kind != ScenarioBattleCaller.SAFE or expected_source == CLASSIC_COMBAT and caller.kind != ScenarioBattleCaller.CLASSIC:
		return null
	if continuation_kind in [CLASSIC_COMBAT, SAFE_COMBAT]:
		return combat(continuation_kind, data["battleId"], caller) if data.size() == 3 else null
	if continuation_kind in [CLASSIC_COMBAT_ALLY, SAFE_COMBAT_ALLY, CLASSIC_COMBAT_FUMBLE, SAFE_COMBAT_FUMBLE]:
		return combat_terminal(continuation_kind, expected_source, data["battleId"], caller) if data.size() == 3 else null
	if continuation_kind in [CLASSIC_COMBAT_RETREAT, SAFE_COMBAT_RETREAT]:
		if data.size() != 6 or not data.get("actorId") is String or data["actorId"].is_empty() or data.get("mode") not in ["explicit", "edge"] or not data.get("destination") is Array or data["destination"].size() != 2:
			return null
		var x_value: Variant = _signed_integer_or_null(data["destination"][0])
		var y_value: Variant = _signed_integer_or_null(data["destination"][1])
		if x_value == null or y_value == null:
			return null
		var destination := Vector2i(int(x_value), int(y_value))
		if data["mode"] == "explicit" and destination != Vector2i(-100_000, -100_000) or data["mode"] == "edge" and destination == Vector2i(-100_000, -100_000):
			return null
		return combat_retreat(continuation_kind, expected_source, data["battleId"], caller, data["actorId"], StringName(data["mode"]), destination)
	if continuation_kind in [CLASSIC_COMBAT_AGE, SAFE_COMBAT_AGE]:
		if data.size() != 6 or not data.get("updates") is Array or data["updates"].is_empty() or data["updates"].size() > 30:
			return null
		var index := _integer(data.get("index"))
		var round_before := _integer(data.get("roundBefore"))
		if index < 1 or index > data["updates"].size() or round_before < 1:
			return null
		var updates: Array[InteractionRequest.AgeUpdateBody] = []
		for update: Variant in data["updates"]:
			var typed_update := _age_update_from_data(update)
			if typed_update == null:
				return null
			updates.append(typed_update)
		return combat_age(continuation_kind, expected_source, data["battleId"], caller, updates, index, round_before)
	if not data.get("programId") is String or data["programId"].is_empty():
		return null
	var macro_vm := ScenarioVmSnapshot.from_data(data.get("macroVm"))
	if macro_vm == null:
		return null
	if continuation_kind in [CLASSIC_COMBAT_MACRO, SAFE_COMBAT_MACRO]:
		return combat_macro(continuation_kind, expected_source, data["battleId"], caller, data["programId"], macro_vm) if data.size() == 5 else null
	if data.size() != 7 or not data.get("combatantId") is String or data["combatantId"].is_empty() or not data.get("resetTraitorOnComplete") is bool:
		return null
	return combat_macro(continuation_kind, expected_source, data["battleId"], caller, data["programId"], macro_vm, data["combatantId"], data["resetTraitorOnComplete"])


static func _decode_opcode_death_macro(data: Dictionary) -> ScenarioRuntimeContinuation:
	if data.size() != 5 or not data.get("battleId") is String or data["battleId"].is_empty() or not data.get("combatantId") is String or data["combatantId"].is_empty() or not data.get("programId") is String or data["programId"].is_empty():
		return null
	var remaining := _strings(data.get("remainingCombatantIds"))
	if remaining.size() != data["remainingCombatantIds"].size() or remaining.size() > 100:
		return null
	var macro_vm := ScenarioVmSnapshot.from_data(data.get("macroVm"))
	return opcode_death_macro(data["battleId"], data["combatantId"], data["programId"], remaining, macro_vm) if macro_vm != null else null


static func _integers(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		var normalized := _signed_integer(entry)
		if normalized == -100000:
			return []
		result.append(normalized)
	return result


static func _strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if not entry is String or entry.is_empty() or result.has(entry):
			return []
		result.append(entry)
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100000


static func _signed_integer_or_null(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return null


static func _json_safe(value: Variant, depth: int) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool or value is int or value is float or value is String:
		return true
	if value is Array:
		if value.size() > 4096:
			return false
		for child: Variant in value:
			if not _json_safe(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > 4096:
			return false
		for key: Variant in value:
			if not key is String or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false


static func _detached(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value


static func _age_update_from_data(value: Variant) -> InteractionRequest.AgeUpdateBody:
	if not value is Dictionary:
		return null
	var request := InteractionRequest.age_update("continuation.age", value)
	return null if request == null else request.body as InteractionRequest.AgeUpdateBody


static func _copy_age_update(update: InteractionRequest.AgeUpdateBody) -> InteractionRequest.AgeUpdateBody:
	return _age_update_from_data(update.to_data()) if update != null else null
