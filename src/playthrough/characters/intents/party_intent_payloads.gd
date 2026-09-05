## Defines the typed values carried by party setup and character-management intents.

class_name PartyIntentPayloads
extends RefCounted


class Party:
	extends PlayerIntentPayload
	var members: Array[CharacterCreationSpec]

	func _init(values: Array[CharacterCreationSpec]) -> void:
		members = values.duplicate()


class SetupOptions:
	extends PlayerIntentPayload
	var difficulty: int
	var monster_set: int

	func _init(difficulty_value: int, monster_set_value: int) -> void:
		difficulty = difficulty_value
		monster_set = monster_set_value


class VaultImport:
	extends PlayerIntentPayload
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


class Draft:
	extends PlayerIntentPayload
	var spec: CharacterCreationSpec

	func _init(value: CharacterCreationSpec) -> void:
		spec = value


class StringList:
	extends PlayerIntentPayload
	var values: Array[String]

	func _init(items: Array[String]) -> void:
		values = items.duplicate()


class Character:
	extends PlayerIntentPayload
	var character_id: String

	func _init(value: String) -> void:
		character_id = value


class Appearance:
	extends PlayerIntentPayload
	var character_id: String
	var appearance_kind: StringName
	var appearance_id: String

	func _init(character: String, kind_value: StringName, appearance: String) -> void:
		character_id = character
		appearance_kind = kind_value
		appearance_id = appearance
