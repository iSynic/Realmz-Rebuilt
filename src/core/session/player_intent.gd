class_name PlayerIntent
extends RefCounted

enum Kind {
	MOVE,
	SEARCH,
	CAMP,
	REST,
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
	IDENTIFY_ITEM,
	SPLIT_ITEM,
	JOIN_ITEM,
	TRADE_ITEM,
	STORE_ITEM,
	MONEY_ACTION,
	SERVICE_ACTION,
	SELECT_SPELL_POWER,
	SELECT_SPELL_TARGET,
	COMBAT_MOVE,
	OPEN_JOURNAL,
	OPEN_MAPS,
	SET_LOCATION_NOTE,
	SET_COMBAT_AUTO,
}

var kind: Kind
var direction: Vector2i = Vector2i.ZERO
var target_id: String = ""
var secondary_target_id: String = ""
var actor_id: String = ""
var action: StringName = &""
var power_level: int = 1
var target_coordinate: Vector2i = Vector2i(-100_000, -100_000)
var rotation: int = 0
var party_members: Array[CharacterCreationSpec] = []
var quantity: int = 1
var amount: int = 0
var revision_hash: String = ""
var selected_ids: Array[String] = []
var vault_state_data: Dictionary = {}
var vault_source_campaign_id: String = ""
var vault_source_package_hash: String = ""
var text_value: String = ""
var enabled: bool = false


func _init(intent_kind: Kind) -> void:
	kind = intent_kind


static func move(move_direction: Vector2i) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.MOVE)
	intent.direction = move_direction
	return intent


static func use_item(item_id: String, user_id: String = "") -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.USE_ITEM)
	intent.target_id = item_id
	intent.actor_id = user_id
	return intent


static func use_item_on_target(item_id: String, user_id: String, target_combatant_id: String = "", target_combatant_ids: Array[String] = [], coordinate: Vector2i = Vector2i(-100_000, -100_000), area_rotation: int = 0) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.USE_ITEM_ON_TARGET)
	intent.target_id = item_id
	intent.actor_id = user_id
	intent.secondary_target_id = target_combatant_id
	intent.selected_ids = target_combatant_ids.duplicate()
	intent.target_coordinate = coordinate
	intent.rotation = area_rotation
	return intent


static func camp() -> PlayerIntent:
	return PlayerIntent.new(Kind.CAMP)


static func rest() -> PlayerIntent:
	return PlayerIntent.new(Kind.REST)


static func cast_spell(spell_id: String, caster_id: String = "", target_combatant_id: String = "", power: int = 1) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.CAST_SPELL)
	intent.target_id = spell_id
	intent.actor_id = caster_id
	intent.secondary_target_id = target_combatant_id
	intent.power_level = power
	return intent


static func make_scroll(spell_id: String, caster_id: String, power: int = 1) -> PlayerIntent:
	var intent := cast_spell(spell_id, caster_id, "", power)
	intent.action = &"make-scroll"
	return intent


static func use_scroll(caster_id: String, slot_index: int, target_character_ids: Array[String] = []) -> PlayerIntent:
	var intent := cast_spell("", caster_id)
	intent.action = &"use-scroll"
	intent.quantity = slot_index
	intent.selected_ids = target_character_ids.duplicate()
	return intent


static func cast_spell_at(spell_id: String, caster_id: String, coordinate: Vector2i, power: int = 1, area_rotation: int = 0) -> PlayerIntent:
	var intent := cast_spell(spell_id, caster_id, "", power)
	intent.target_coordinate = coordinate
	intent.rotation = area_rotation
	return intent


static func cast_spell_at_targets(spell_id: String, caster_id: String, target_combatant_ids: Array[String], power: int = 1) -> PlayerIntent:
	var intent := cast_spell(spell_id, caster_id, "", power)
	intent.selected_ids = target_combatant_ids.duplicate()
	return intent


static func combat_action(action_kind: StringName, actor: String, target: String = "") -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.CHOOSE_COMBAT_ACTION)
	intent.action = action_kind
	intent.actor_id = actor
	intent.target_id = target
	return intent


static func create_party(members: Array[CharacterCreationSpec]) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.CREATE_PARTY)
	intent.party_members = members.duplicate()
	return intent


static func begin_adventure() -> PlayerIntent:
	return PlayerIntent.new(Kind.BEGIN_ADVENTURE)


static func import_vault_character(character_id: String, revision: String, state_data: Dictionary = {}, source_campaign_id: String = "", source_package_hash: String = "") -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.IMPORT_VAULT_CHARACTER)
	intent.target_id = character_id
	intent.revision_hash = revision
	intent.vault_state_data = state_data.duplicate(true)
	intent.vault_source_campaign_id = source_campaign_id
	intent.vault_source_package_hash = source_package_hash
	return intent


static func generate_character_draft(spec: CharacterCreationSpec) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.GENERATE_CHARACTER_DRAFT)
	if spec != null:
		intent.party_members = [spec]
	return intent


static func cancel_character_draft() -> PlayerIntent:
	return PlayerIntent.new(Kind.CANCEL_CHARACTER_DRAFT)


static func set_character_draft_spells(spell_ids: Array[String]) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.SET_CHARACTER_DRAFT_SPELLS)
	intent.selected_ids = spell_ids.duplicate()
	return intent


static func finalize_character() -> PlayerIntent:
	return PlayerIntent.new(Kind.FINALIZE_CHARACTER)


static func remove_party_member(character_id: String) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.REMOVE_PARTY_MEMBER)
	intent.target_id = character_id
	return intent


static func reorder_party(character_ids: Array[String]) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.REORDER_PARTY)
	intent.selected_ids = character_ids.duplicate()
	return intent


static func change_character_appearance(character_id_value: String, appearance_kind: StringName, appearance_id: String) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.CHANGE_CHARACTER_APPEARANCE)
	intent.actor_id = character_id_value
	intent.action = appearance_kind
	intent.target_id = appearance_id
	return intent


static func item_action(action_kind: Kind, item_id: String, actor_id: String = "", count: int = 1) -> PlayerIntent:
	var intent := PlayerIntent.new(action_kind)
	intent.target_id = item_id
	intent.actor_id = actor_id
	intent.quantity = maxi(1, count)
	return intent


static func trade_item(item_id: String, from_character_id: String, to_character_id: String) -> PlayerIntent:
	var intent := item_action(Kind.TRADE_ITEM, item_id, from_character_id)
	intent.secondary_target_id = to_character_id
	return intent


static func money_action(action_kind: StringName, character_id: String = "", denomination: String = "", amount_value: int = 0) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.MONEY_ACTION)
	intent.action = action_kind
	intent.actor_id = character_id
	intent.target_id = denomination
	intent.amount = maxi(0, amount_value)
	return intent


static func service_action(service: String, action_kind: StringName, actor: String = "", amount_value: int = 0) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.SERVICE_ACTION)
	intent.target_id = service
	intent.action = action_kind
	intent.actor_id = actor
	intent.amount = maxi(0, amount_value)
	return intent


static func select_spell_power(spell_id: String, caster_id: String, power: int) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.SELECT_SPELL_POWER)
	intent.target_id = spell_id
	intent.actor_id = caster_id
	intent.power_level = power
	return intent


static func select_spell_target(spell_id: String, caster_id: String, target: String, power: int = 1) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.SELECT_SPELL_TARGET)
	intent.target_id = spell_id
	intent.actor_id = caster_id
	intent.secondary_target_id = target
	intent.power_level = power
	return intent


static func combat_move(actor: String, destination: Vector2i) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.COMBAT_MOVE)
	intent.actor_id = actor
	intent.direction = destination
	return intent


static func set_combat_auto(character_id: String, auto_enabled: bool) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.SET_COMBAT_AUTO)
	intent.actor_id = character_id
	intent.enabled = auto_enabled
	return intent


static func open_journal() -> PlayerIntent:
	return PlayerIntent.new(Kind.OPEN_JOURNAL)


static func open_maps() -> PlayerIntent:
	return PlayerIntent.new(Kind.OPEN_MAPS)


static func set_location_note(text: String) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.SET_LOCATION_NOTE)
	intent.text_value = text
	return intent
