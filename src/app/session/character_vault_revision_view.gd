## Carries detached character vault revision data between the application host and presentation.

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
var required_campaign_id: String = ""
var publication_label: String
## What published the file, such as "save-editor/<hold>/<party character>" for a kept party member.
var publication_source: String
var is_current: bool
## For an archived character, the revision that was current when it was archived.
var last_current: bool
var archived: bool
var eligible: bool
var eligibility_reasons: Array[String] = []
var character: CharacterView


static func from_record(record: CharacterVaultRecord, eligibility: CharacterVaultEligibility, current: bool, is_archived: bool, content: RealmzContent = null, character_view: CharacterView = null) -> CharacterVaultRevisionView:
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
	var publication_source: String = record.publication_metadata.get("source", "")
	result.publication_source = publication_source
	result.is_current = current
	result.archived = is_archived
	result.eligible = eligibility != null and eligibility.eligible
	result.character = character_view if character_view != null else CharacterView.new(record.state, content)
	if eligibility == null:
		result.eligibility_reasons.append("Choose a scenario in party setup to see who can join.")
	else:
		result.eligibility_reasons.append_array(eligibility.reasons)
	return result
