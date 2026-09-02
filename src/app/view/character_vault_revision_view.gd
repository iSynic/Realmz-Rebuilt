class_name CharacterVaultRevisionView
extends RefCounted

var character_id: String
var revision_hash: String
var name: String
var level: int
var race_id: String
var caste_id: String
var portrait_id: String
var source_campaign_id: String
var source_package_hash: String
var source_revision: String
var publication_label: String
var is_current: bool
var archived: bool
var eligible: bool
var eligibility_reasons: Array[String] = []
var character: CharacterView


static func from_record(record: CharacterVaultRecord, eligibility: CharacterVaultEligibility, current: bool, is_archived: bool, content: RealmzContent = null) -> CharacterVaultRevisionView:
	var result := CharacterVaultRevisionView.new()
	result.character_id = record.character_id
	result.revision_hash = record.revision_hash
	result.name = record.state.name
	result.level = record.state.level
	result.race_id = record.state.race_id
	result.caste_id = record.state.caste_id
	result.portrait_id = record.state.portrait_id
	result.source_campaign_id = record.source_campaign_id
	result.source_package_hash = record.source_package_hash
	result.source_revision = record.source_revision
	result.publication_label = String(record.publication_metadata.get("label", record.publication_metadata.get("name", "")))
	result.is_current = current
	result.archived = is_archived
	result.eligible = eligibility != null and eligibility.eligible
	result.character = CharacterView.new(record.state, content)
	if eligibility == null:
		result.eligibility_reasons.append("Choose a campaign to calculate import eligibility.")
	else:
		result.eligibility_reasons.append_array(eligibility.reasons)
	return result
