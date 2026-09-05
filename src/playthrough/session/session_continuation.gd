## Defines the stable saved envelope for typed playthrough continuations.

class_name SessionContinuation
extends RefCounted

const VERSION: int = 1

var kind: StringName
var body: SessionContinuationBody


func _init(continuation_kind: StringName = &"", continuation_body: SessionContinuationBody = null) -> void:
	kind = continuation_kind
	body = continuation_body


func is_empty() -> bool:
	return kind.is_empty() or body == null


func clear() -> void:
	kind = &""
	body = null


func exploration() -> ExplorationContinuationBody:
	return body as ExplorationContinuationBody


func application_hook() -> ScenarioApplicationContinuationBody:
	return body as ScenarioApplicationContinuationBody


func character_spell_confirmation() -> CharacterSpellConfirmationContinuationBody:
	return body as CharacterSpellConfirmationContinuationBody


func character_vault_publication() -> CharacterVaultPublicationContinuationBody:
	return body as CharacterVaultPublicationContinuationBody


func targeting() -> TargetingContinuationBody:
	return body as TargetingContinuationBody


func item_xap_body() -> ItemXapContinuationBody:
	return body as ItemXapContinuationBody


func service() -> ServiceContinuationBody:
	return body as ServiceContinuationBody


func age() -> AgeContinuationBody:
	return body as AgeContinuationBody


func combat() -> CombatContinuationBody:
	return body as CombatContinuationBody


func reward() -> CombatRewardContinuationBody:
	return body as CombatRewardContinuationBody


func boat() -> BoatContinuationBody:
	return body as BoatContinuationBody


func copy() -> SessionContinuation:
	if is_empty():
		return SessionContinuation.new()
	var duplicate := from_data(to_data())
	assert(duplicate != null, "A live typed continuation must round-trip through its wire codec")
	return duplicate


func to_data() -> Dictionary:
	var payload := body.wire_payload(kind) if body != null else {}
	payload.erase("kind")
	return {"kind": String(kind), "version": VERSION, "data": payload}


static func from_data(value: Variant) -> SessionContinuation:
	return SessionContinuationCodec.decode(value)
