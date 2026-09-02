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


class Payload:
	extends RefCounted


class EmptyPayload:
	extends Payload


class MovePayload:
	extends Payload
	var direction: Vector2i
	var aligns_dungeon_heading: bool

	func _init(value: Vector2i, align_heading: bool = false) -> void:
		direction = value
		aligns_dungeon_heading = align_heading


class DungeonTurnPayload:
	extends Payload
	var delta: int

	func _init(value: int) -> void:
		delta = value


class ItemUsePayload:
	extends Payload
	var item_id: String
	var actor_id: String

	func _init(item: String, actor: String) -> void:
		item_id = item
		actor_id = actor


class ItemTargetPayload:
	extends Payload
	var item_id: String
	var actor_id: String
	var target_id: String
	var target_ids: Array[String]
	var target_coordinates: Array[Vector2i]
	var coordinate: Vector2i
	var rotation: int

	func _init(item: String, actor: String, target: String, targets: Array[String], target_coordinate: Vector2i, area_rotation: int, coordinates: Array[Vector2i] = []) -> void:
		item_id = item
		actor_id = actor
		target_id = target
		target_ids = targets.duplicate()
		target_coordinates = coordinates.duplicate()
		coordinate = target_coordinate
		rotation = area_rotation


class SpellPayload:
	extends Payload
	var operation: StringName
	var spell_id: String
	var caster_id: String
	var target_id: String
	var target_ids: Array[String]
	var target_coordinates: Array[Vector2i]
	var power: int
	var coordinate: Vector2i
	var rotation: int
	var scroll_slot: int

	func _init(operation_value: StringName, spell: String, caster: String, target: String = "", targets: Array[String] = [], power_value: int = 1, target_coordinate: Vector2i = Vector2i(-100_000, -100_000), area_rotation: int = 0, slot: int = -1, coordinates: Array[Vector2i] = []) -> void:
		operation = operation_value
		spell_id = spell
		caster_id = caster
		target_id = target
		target_ids = targets.duplicate()
		target_coordinates = coordinates.duplicate()
		power = power_value
		coordinate = target_coordinate
		rotation = area_rotation
		scroll_slot = slot


class CombatActionPayload:
	extends Payload
	var action: StringName
	var actor_id: String
	var target_id: String

	func _init(action_value: StringName, actor: String, target: String) -> void:
		action = action_value
		actor_id = actor
		target_id = target


class PartyPayload:
	extends Payload
	var members: Array[CharacterCreationSpec]

	func _init(values: Array[CharacterCreationSpec]) -> void:
		members = values.duplicate()


class PartySetupOptionsPayload:
	extends Payload
	var difficulty: int
	var monster_set: int

	func _init(difficulty_value: int, monster_set_value: int) -> void:
		difficulty = difficulty_value
		monster_set = monster_set_value


class VaultImportPayload:
	extends Payload
	var character_id: String
	var revision_hash: String
	var character_state: CharacterState
	var source_campaign_id: String
	var source_package_hash: String

	func _init(character: String, revision: String, state: CharacterState = null, source_campaign: String = "", source_package: String = "") -> void:
		character_id = character
		revision_hash = revision
		character_state = state
		source_campaign_id = source_campaign
		source_package_hash = source_package


class CharacterDraftPayload:
	extends Payload
	var spec: CharacterCreationSpec

	func _init(value: CharacterCreationSpec) -> void:
		spec = value


class StringListPayload:
	extends Payload
	var values: Array[String]

	func _init(items: Array[String]) -> void:
		values = items.duplicate()


class CharacterPayload:
	extends Payload
	var character_id: String

	func _init(value: String) -> void:
		character_id = value


class AppearancePayload:
	extends Payload
	var character_id: String
	var appearance_kind: StringName
	var appearance_id: String

	func _init(character: String, kind_value: StringName, appearance: String) -> void:
		character_id = character
		appearance_kind = kind_value
		appearance_id = appearance


class ItemActionPayload:
	extends Payload
	var item_id: String
	var actor_id: String
	var destination_character_id: String
	var quantity: int

	func _init(item: String, actor: String, count: int = 1, destination: String = "") -> void:
		item_id = item
		actor_id = actor
		quantity = maxi(1, count)
		destination_character_id = destination


class MoneyPayload:
	extends Payload
	var action: StringName
	var character_id: String
	var denomination: String
	var amount: int

	func _init(action_value: StringName, character: String, denomination_value: String, amount_value: int) -> void:
		action = action_value
		character_id = character
		denomination = denomination_value
		amount = maxi(0, amount_value)


class ServicePayload:
	extends Payload
	var service_id: String
	var action: StringName
	var actor_id: String
	var amount: int

	func _init(service: String, action_value: StringName, actor: String, amount_value: int) -> void:
		service_id = service
		action = action_value
		actor_id = actor
		amount = maxi(0, amount_value)


class CombatMovePayload:
	extends Payload
	var actor_id: String
	var destination: Vector2i
	var auto_switch_to_melee: bool

	func _init(actor: String, value: Vector2i, switch_to_melee: bool = false) -> void:
		actor_id = actor
		destination = value
		auto_switch_to_melee = switch_to_melee


class CombatAutoPayload:
	extends Payload
	var character_id: String
	var enabled: bool

	func _init(character: String, value: bool) -> void:
		character_id = character
		enabled = value


class LocationNotePayload:
	extends Payload
	var text: String

	func _init(value: String) -> void:
		text = value


var kind: Kind
var payload: Payload


func _init(intent_kind: Kind, intent_payload: Payload = null) -> void:
	kind = intent_kind
	payload = intent_payload if intent_payload != null else EmptyPayload.new()


func is_valid() -> bool:
	match kind:
		Kind.SEARCH, Kind.TOGGLE_SEARCH, Kind.USE_TORCH, Kind.CONTEXTUAL_ENCOUNTER, Kind.CAMP, Kind.REST, Kind.HEAL, Kind.BEGIN_ADVENTURE, Kind.CANCEL_CHARACTER_DRAFT, Kind.FINALIZE_CHARACTER:
			return payload is EmptyPayload
		Kind.MOVE:
			return payload is MovePayload
		Kind.DUNGEON_TURN:
			return payload is DungeonTurnPayload and (payload as DungeonTurnPayload).delta in [-1, 1]
		Kind.USE_ITEM:
			return payload is ItemUsePayload
		Kind.USE_ITEM_ON_TARGET:
			return payload is ItemTargetPayload
		Kind.CAST_SPELL, Kind.SET_FAST_SPELL:
			return payload is SpellPayload
		Kind.CHOOSE_COMBAT_ACTION:
			return payload is CombatActionPayload
		Kind.CREATE_PARTY:
			return payload is PartyPayload
		Kind.SET_PARTY_SETUP_OPTIONS:
			return payload is PartySetupOptionsPayload
		Kind.IMPORT_VAULT_CHARACTER:
			return payload is VaultImportPayload
		Kind.GENERATE_CHARACTER_DRAFT:
			return payload is CharacterDraftPayload
		Kind.SET_CHARACTER_DRAFT_SPELLS, Kind.REORDER_PARTY:
			return payload is StringListPayload
		Kind.REMOVE_PARTY_MEMBER:
			return payload is CharacterPayload
		Kind.CHANGE_CHARACTER_APPEARANCE:
			return payload is AppearancePayload
		Kind.EQUIP_ITEM, Kind.UNEQUIP_ITEM, Kind.DROP_ITEM, Kind.SPLIT_ITEM, Kind.JOIN_ITEM, Kind.TRADE_ITEM:
			return payload is ItemActionPayload
		Kind.MONEY_ACTION:
			return payload is MoneyPayload
		Kind.SERVICE_ACTION:
			return payload is ServicePayload
		Kind.COMBAT_MOVE:
			return payload is CombatMovePayload
		Kind.SET_COMBAT_AUTO:
			return payload is CombatAutoPayload
		Kind.SET_LOCATION_NOTE:
			return payload is LocationNotePayload
	return false


static func move(move_direction: Vector2i) -> PlayerIntent:
	return PlayerIntent.new(Kind.MOVE, MovePayload.new(move_direction))


static func overhead_dungeon_move(move_direction: Vector2i) -> PlayerIntent:
	return PlayerIntent.new(Kind.MOVE, MovePayload.new(move_direction, true))


static func dungeon_turn(delta: int) -> PlayerIntent:
	return PlayerIntent.new(Kind.DUNGEON_TURN, DungeonTurnPayload.new(delta))


static func toggle_search() -> PlayerIntent:
	return PlayerIntent.new(Kind.TOGGLE_SEARCH)


static func use_torch() -> PlayerIntent:
	return PlayerIntent.new(Kind.USE_TORCH)


static func contextual_encounter() -> PlayerIntent:
	return PlayerIntent.new(Kind.CONTEXTUAL_ENCOUNTER)


static func use_item(item_id: String, user_id: String = "") -> PlayerIntent:
	return PlayerIntent.new(Kind.USE_ITEM, ItemUsePayload.new(item_id, user_id))


static func use_item_on_target(item_id: String, user_id: String, target_combatant_id: String = "", target_combatant_ids: Array[String] = [], coordinate: Vector2i = Vector2i(-100_000, -100_000), area_rotation: int = 0, target_coordinates: Array[Vector2i] = []) -> PlayerIntent:
	return PlayerIntent.new(Kind.USE_ITEM_ON_TARGET, ItemTargetPayload.new(item_id, user_id, target_combatant_id, target_combatant_ids, coordinate, area_rotation, target_coordinates))


static func camp() -> PlayerIntent:
	return PlayerIntent.new(Kind.CAMP)


static func rest() -> PlayerIntent:
	return PlayerIntent.new(Kind.REST)


static func heal() -> PlayerIntent:
	return PlayerIntent.new(Kind.HEAL)


static func cast_spell(spell_id: String, caster_id: String = "", target_combatant_id: String = "", power: int = 1) -> PlayerIntent:
	return PlayerIntent.new(Kind.CAST_SPELL, SpellPayload.new(&"cast", spell_id, caster_id, target_combatant_id, [], power))


static func identify_carried_items(spell_id: String, caster_id: String, target_character_id: String) -> PlayerIntent:
	return PlayerIntent.new(Kind.CAST_SPELL, SpellPayload.new(&"identify-inventory", spell_id, caster_id, target_character_id))


static func make_scroll(spell_id: String, caster_id: String, power: int = 1) -> PlayerIntent:
	return PlayerIntent.new(Kind.CAST_SPELL, SpellPayload.new(&"make-scroll", spell_id, caster_id, "", [], power))


static func use_scroll(caster_id: String, slot_index: int, target_character_ids: Array[String] = []) -> PlayerIntent:
	return PlayerIntent.new(Kind.CAST_SPELL, SpellPayload.new(&"use-scroll", "", caster_id, "", target_character_ids, 1, Vector2i(-100_000, -100_000), 0, slot_index))


static func use_scroll_on_target(caster_id: String, slot_index: int, target_combatant_id: String = "", target_combatant_ids: Array[String] = [], coordinate: Vector2i = Vector2i(-100_000, -100_000), area_rotation: int = 0) -> PlayerIntent:
	return PlayerIntent.new(Kind.CAST_SPELL, SpellPayload.new(&"use-scroll", "", caster_id, target_combatant_id, target_combatant_ids, 1, coordinate, area_rotation, slot_index))


static func use_scroll_at_coordinates(caster_id: String, slot_index: int, coordinates: Array[Vector2i]) -> PlayerIntent:
	return PlayerIntent.new(Kind.CAST_SPELL, SpellPayload.new(&"use-scroll", "", caster_id, "", [], 1, Vector2i(-100_000, -100_000), 0, slot_index, coordinates))


static func cast_spell_at(spell_id: String, caster_id: String, coordinate: Vector2i, power: int = 1, area_rotation: int = 0) -> PlayerIntent:
	return PlayerIntent.new(Kind.CAST_SPELL, SpellPayload.new(&"cast", spell_id, caster_id, "", [], power, coordinate, area_rotation))


static func cast_spell_at_targets(spell_id: String, caster_id: String, target_combatant_ids: Array[String], power: int = 1) -> PlayerIntent:
	return PlayerIntent.new(Kind.CAST_SPELL, SpellPayload.new(&"cast", spell_id, caster_id, "", target_combatant_ids, power))


static func cast_spell_at_coordinates(spell_id: String, caster_id: String, coordinates: Array[Vector2i], power: int = 1) -> PlayerIntent:
	return PlayerIntent.new(Kind.CAST_SPELL, SpellPayload.new(&"cast", spell_id, caster_id, "", [], power, Vector2i(-100_000, -100_000), 0, -1, coordinates))


static func set_fast_spell(caster_id: String, slot_index: int, spell_id: String = "", power: int = 0) -> PlayerIntent:
	return PlayerIntent.new(Kind.SET_FAST_SPELL, SpellPayload.new(&"bind-fast", spell_id, caster_id, "", [], power, Vector2i(-100_000, -100_000), 0, slot_index))


static func combat_action(action_kind: StringName, actor: String, target: String = "") -> PlayerIntent:
	return PlayerIntent.new(Kind.CHOOSE_COMBAT_ACTION, CombatActionPayload.new(action_kind, actor, target))


static func create_party(members: Array[CharacterCreationSpec]) -> PlayerIntent:
	return PlayerIntent.new(Kind.CREATE_PARTY, PartyPayload.new(members))


static func begin_adventure() -> PlayerIntent:
	return PlayerIntent.new(Kind.BEGIN_ADVENTURE)


static func set_party_setup_options(difficulty_value: int, monster_set_value: int) -> PlayerIntent:
	return PlayerIntent.new(Kind.SET_PARTY_SETUP_OPTIONS, PartySetupOptionsPayload.new(difficulty_value, monster_set_value))


static func import_vault_character(character_id: String, revision: String, state: CharacterState = null, source_campaign_id: String = "", source_package_hash: String = "") -> PlayerIntent:
	return PlayerIntent.new(Kind.IMPORT_VAULT_CHARACTER, VaultImportPayload.new(character_id, revision, state, source_campaign_id, source_package_hash))


static func generate_character_draft(spec: CharacterCreationSpec) -> PlayerIntent:
	return PlayerIntent.new(Kind.GENERATE_CHARACTER_DRAFT, CharacterDraftPayload.new(spec))


static func cancel_character_draft() -> PlayerIntent:
	return PlayerIntent.new(Kind.CANCEL_CHARACTER_DRAFT)


static func set_character_draft_spells(spell_ids: Array[String]) -> PlayerIntent:
	return PlayerIntent.new(Kind.SET_CHARACTER_DRAFT_SPELLS, StringListPayload.new(spell_ids))


static func finalize_character() -> PlayerIntent:
	return PlayerIntent.new(Kind.FINALIZE_CHARACTER)


static func remove_party_member(character_id: String) -> PlayerIntent:
	return PlayerIntent.new(Kind.REMOVE_PARTY_MEMBER, CharacterPayload.new(character_id))


static func reorder_party(character_ids: Array[String]) -> PlayerIntent:
	return PlayerIntent.new(Kind.REORDER_PARTY, StringListPayload.new(character_ids))


static func change_character_appearance(character_id_value: String, appearance_kind: StringName, appearance_id: String) -> PlayerIntent:
	return PlayerIntent.new(Kind.CHANGE_CHARACTER_APPEARANCE, AppearancePayload.new(character_id_value, appearance_kind, appearance_id))


static func item_action(action_kind: Kind, item_id: String, actor_id: String = "", count: int = 1) -> PlayerIntent:
	return PlayerIntent.new(action_kind, ItemActionPayload.new(item_id, actor_id, count))


static func trade_item(item_id: String, from_character_id: String, to_character_id: String) -> PlayerIntent:
	return PlayerIntent.new(Kind.TRADE_ITEM, ItemActionPayload.new(item_id, from_character_id, 1, to_character_id))


static func money_action(action_kind: StringName, character_id: String = "", denomination: String = "", amount_value: int = 0) -> PlayerIntent:
	return PlayerIntent.new(Kind.MONEY_ACTION, MoneyPayload.new(action_kind, character_id, denomination, amount_value))


static func service_action(service: String, action_kind: StringName, actor: String = "", amount_value: int = 0) -> PlayerIntent:
	return PlayerIntent.new(Kind.SERVICE_ACTION, ServicePayload.new(service, action_kind, actor, amount_value))


static func combat_move(actor: String, destination: Vector2i, auto_switch_to_melee: bool = false) -> PlayerIntent:
	return PlayerIntent.new(Kind.COMBAT_MOVE, CombatMovePayload.new(actor, destination, auto_switch_to_melee))


static func set_combat_auto(character_id: String, auto_enabled: bool) -> PlayerIntent:
	return PlayerIntent.new(Kind.SET_COMBAT_AUTO, CombatAutoPayload.new(character_id, auto_enabled))


static func set_location_note(text: String) -> PlayerIntent:
	return PlayerIntent.new(Kind.SET_LOCATION_NOTE, LocationNotePayload.new(text))
