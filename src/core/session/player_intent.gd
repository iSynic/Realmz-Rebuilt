class_name PlayerIntent
extends RefCounted

enum Kind {
	MOVE,
	SEARCH,
	CAMP,
	USE_ITEM,
	CAST_SPELL,
	CHOOSE_COMBAT_ACTION,
	CREATE_PARTY,
	BEGIN_ADVENTURE,
	IMPORT_VAULT_CHARACTER,
	FINALIZE_CHARACTER,
	REMOVE_PARTY_MEMBER,
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
	LOOT_ASSIGNMENT,
	TREASURE_COMPLETE,
	LEVEL_UP,
	OPEN_JOURNAL,
	OPEN_MAPS,
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


func _init(intent_kind: Kind) -> void:
	kind = intent_kind


static func move(move_direction: Vector2i) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.MOVE)
	intent.direction = move_direction
	return intent


static func use_item(item_id: String) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.USE_ITEM)
	intent.target_id = item_id
	return intent


static func camp() -> PlayerIntent:
	return PlayerIntent.new(Kind.CAMP)


static func cast_spell(spell_id: String, caster_id: String = "", target_combatant_id: String = "", power: int = 1) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.CAST_SPELL)
	intent.target_id = spell_id
	intent.actor_id = caster_id
	intent.secondary_target_id = target_combatant_id
	intent.power_level = power
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


static func finalize_character(spec: CharacterCreationSpec) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.FINALIZE_CHARACTER)
	if spec != null:
		intent.party_members = [spec]
	return intent


static func remove_party_member(character_id: String) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.REMOVE_PARTY_MEMBER)
	intent.target_id = character_id
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


static func money_action(action_kind: StringName, amount_value: int) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.MONEY_ACTION)
	intent.action = action_kind
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


static func loot_assignment(item_id: String, character_ids: Array[String]) -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.LOOT_ASSIGNMENT)
	intent.target_id = item_id
	intent.selected_ids = character_ids.duplicate()
	return intent


static func treasure_complete() -> PlayerIntent:
	return PlayerIntent.new(Kind.TREASURE_COMPLETE)


static func level_up(character_id: String, choice: StringName = &"") -> PlayerIntent:
	var intent := PlayerIntent.new(Kind.LEVEL_UP)
	intent.target_id = character_id
	intent.action = choice
	return intent


static func open_journal() -> PlayerIntent:
	return PlayerIntent.new(Kind.OPEN_JOURNAL)


static func open_maps() -> PlayerIntent:
	return PlayerIntent.new(Kind.OPEN_MAPS)
