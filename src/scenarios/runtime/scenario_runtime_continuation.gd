## Defines the stable saved envelope for typed scenario runtime continuations.

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

var kind: StringName
var body: ScenarioRuntimeContinuationBody


func _init(continuation_kind: StringName = &"", continuation_body: ScenarioRuntimeContinuationBody = null) -> void:
	kind = continuation_kind
	body = continuation_body


func text() -> ScenarioTextContinuationBody:
	return body as ScenarioTextContinuationBody


func choice() -> ScenarioChoiceContinuationBody:
	return body as ScenarioChoiceContinuationBody


func character() -> ScenarioCharacterContinuationBody:
	return body as ScenarioCharacterContinuationBody


func thief() -> ScenarioThiefContinuationBody:
	return body as ScenarioThiefContinuationBody


func age() -> ScenarioAgeContinuationBody:
	return body as ScenarioAgeContinuationBody


func service() -> ScenarioServiceContinuationBody:
	return body as ScenarioServiceContinuationBody


func combat() -> ScenarioCombatContinuationBody:
	return body as ScenarioCombatContinuationBody


func opcode_death() -> ScenarioOpcodeDeathContinuationBody:
	return body as ScenarioOpcodeDeathContinuationBody


func reward() -> ScenarioRewardContinuationBody:
	return body as ScenarioRewardContinuationBody


func copy() -> ScenarioRuntimeContinuation:
	var duplicate := from_data(to_data())
	assert(duplicate != null, "A live scenario runtime continuation must round-trip through its wire codec")
	return duplicate


func to_data() -> Dictionary:
	return {"kind": String(kind), "version": VERSION, "data": body.wire_payload() if body != null else {}}


static func from_data(value: Variant) -> ScenarioRuntimeContinuation:
	return ScenarioRuntimeContinuationCodec.decode(value)
