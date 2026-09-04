## Creates typed commands for party assembly, Character Files, and character creation.

class_name PartyIntents
extends RefCounted


static func create(members: Array[CharacterCreationSpec]) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CREATE_PARTY, PartyIntentPayloads.Party.new(members))


static func begin_adventure() -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.BEGIN_ADVENTURE)


static func configure_setup(difficulty: int, monster_set: int) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.SET_PARTY_SETUP_OPTIONS, PartyIntentPayloads.SetupOptions.new(difficulty, monster_set))


static func import_vault_character(character_id: String, revision: String, state: CharacterState = null, source_campaign_id: String = "", source_package_hash: String = "") -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.IMPORT_VAULT_CHARACTER, PartyIntentPayloads.VaultImport.new(character_id, revision, state, source_campaign_id, source_package_hash))


static func generate_character_draft(spec: CharacterCreationSpec) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT, PartyIntentPayloads.Draft.new(spec))


static func cancel_character_draft() -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT)


static func set_character_draft_spells(spell_ids: Array[String]) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS, PartyIntentPayloads.StringList.new(spell_ids))


static func finalize_character() -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.FINALIZE_CHARACTER)


static func remove_member(character_id: String) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.REMOVE_PARTY_MEMBER, PartyIntentPayloads.Character.new(character_id))


static func reorder(character_ids: Array[String]) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.REORDER_PARTY, PartyIntentPayloads.StringList.new(character_ids))


static func change_appearance(character_id: String, appearance_kind: StringName, appearance_id: String) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CHANGE_CHARACTER_APPEARANCE, PartyIntentPayloads.Appearance.new(character_id, appearance_kind, appearance_id))
