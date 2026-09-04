## Carries one typed player command across the gameplay transaction boundary.

class_name PlayerIntent
extends RefCounted

enum Kind {
	MOVE,
	DUNGEON_TURN,
	SEARCH,
	TOGGLE_SEARCH,
	USE_TORCH,
	CONTEXTUAL_ENCOUNTER,
	CAMP,
	REST,
	HEAL,
	USE_ITEM,
	CAST_SPELL,
	CHOOSE_COMBAT_ACTION,
	CREATE_PARTY,
	BEGIN_ADVENTURE,
	IMPORT_VAULT_CHARACTER,
	GENERATE_CHARACTER_DRAFT,
	CANCEL_CHARACTER_DRAFT,
	SET_CHARACTER_DRAFT_SPELLS,
	FINALIZE_CHARACTER,
	REMOVE_PARTY_MEMBER,
	REORDER_PARTY,
	CHANGE_CHARACTER_APPEARANCE,
	EQUIP_ITEM,
	UNEQUIP_ITEM,
	USE_ITEM_ON_TARGET,
	DROP_ITEM,
	SPLIT_ITEM,
	JOIN_ITEM,
	TRADE_ITEM,
	MONEY_ACTION,
	SERVICE_ACTION,
	COMBAT_MOVE,
	SET_LOCATION_NOTE,
	SET_COMBAT_AUTO,
	SET_FAST_SPELL,
	SET_PARTY_SETUP_OPTIONS,
}

var kind: Kind
var payload: PlayerIntentPayload


func _init(intent_kind: Kind, intent_payload: PlayerIntentPayload = null) -> void:
	kind = intent_kind
	payload = intent_payload if intent_payload != null else EmptyIntentPayload.new()


func is_valid() -> bool:
	return PlayerIntentRegistry.payload_matches(kind, payload)
