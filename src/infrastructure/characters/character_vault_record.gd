class_name CharacterVaultRecord
extends RefCounted

const FORMAT := "realmz2-character"
const FORMAT_VERSION := 1

var character_id: String
var revision_hash: String
var rules_version: String
var source_campaign_id: String
var source_package_hash: String
var publication_metadata: Dictionary = {}
var state: CharacterState
var source_revision: String


func _init(id: String, rules: String, campaign: String, package_hash: String, character_state: CharacterState, source: String = "") -> void:
	character_id = id
	rules_version = rules
	source_campaign_id = campaign
	source_package_hash = package_hash
	state = character_state
	source_revision = source


func to_data() -> Dictionary:
	return {
		"format": FORMAT,
		"formatVersion": FORMAT_VERSION,
		"characterId": character_id,
		"revisionHash": revision_hash,
		"rulesVersion": rules_version,
		"sourceCampaignId": source_campaign_id,
		"sourcePackageHash": source_package_hash,
		"publication": publication_metadata.duplicate(true),
		"sourceRevision": source_revision,
		"state": state.to_data() if state != null else {},
	}


static func from_data(value: Variant) -> CharacterVaultRecord:
	if not value is Dictionary:
		return null
	for field: String in ["format", "formatVersion", "characterId", "revisionHash", "rulesVersion", "sourceCampaignId", "sourcePackageHash", "publication", "sourceRevision", "state"]:
		if not value.has(field):
			return null
	if value["format"] != FORMAT or value["formatVersion"] != FORMAT_VERSION:
		return null
	if not value["characterId"] is String or value["characterId"].is_empty() or not value["revisionHash"] is String or value["revisionHash"].length() != 64 or not value["rulesVersion"] is String or value["rulesVersion"].is_empty() or not value["sourceCampaignId"] is String or not value["sourcePackageHash"] is String or value["sourcePackageHash"].length() != 64 or not value["publication"] is Dictionary or not value["sourceRevision"] is String:
		return null
	var state := CharacterState.from_data(value["state"])
	if state == null or state.id != value["characterId"] or state.traitor:
		return null
	var result := CharacterVaultRecord.new(value["characterId"], value["rulesVersion"], value["sourceCampaignId"], value["sourcePackageHash"], state, value["sourceRevision"])
	result.revision_hash = value["revisionHash"]
	result.publication_metadata = value["publication"].duplicate(true)
	return result
