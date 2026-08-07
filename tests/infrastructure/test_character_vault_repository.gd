extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var repository := CharacterVaultRepository.new("user://realmz2-tests/character-vault-v1")
	var character := CharacterState.new("vault-fixture-character", "Vault Fixture", 12, 12)
	character.race_id = "classic.race.0"
	character.caste_id = "classic.caste.0"
	var record := CharacterVaultRecord.new(character.id, "realmz-classic-1", "realmz2-synthetic-fixture", "0000000000000000000000000000000000000000000000000000000000000000", character, "synthetic-v1")
	record.publication_metadata = {"label": "Fixture vault character"}
	assert_true(repository.publish_revision(record), "vault publication uses a temporary typed write and readback")
	assert_equal(record.revision_hash.length(), 64, "published character revisions receive a stable SHA-256 identity")
	var loaded := repository.load_revision(record.character_id, record.revision_hash)
	assert_not_null(loaded, "published character revisions can be loaded by stable identity")
	if loaded != null:
		assert_equal(loaded.state.name, "Vault Fixture", "vault state round-trips through the detached character record")
		assert_equal(loaded.publication_metadata.get("label"), "Fixture vault character", "publication metadata remains separate from gameplay state")
	var records := repository.list_current_records()
	assert_true(records.any(func(candidate: CharacterVaultRecord) -> bool: return candidate.character_id == record.character_id), "the current-revision index exposes published characters")
	var package := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(package.is_ok(), "the fixture package loads for campaign eligibility checks")
	if package.is_ok():
		var eligibility := repository.campaign_eligibility(record, package.content)
		assert_true(eligibility.eligible, "a matching race and class are eligible for the target campaign")
	var first_revision_hash := record.revision_hash
	character.name = "Vault Fixture Revision Two"
	record.state = character
	assert_true(repository.publish_revision(record), "publishing a changed character creates a new immutable revision")
	assert_true(record.revision_hash != first_revision_hash, "changed character state receives a distinct revision hash")
	assert_not_null(repository.load_revision(record.character_id, first_revision_hash), "older character revisions remain loadable after a new publication")
	character.race_id = "missing.race"
	record.state = character
	var rejected := repository.campaign_eligibility(record, package.content)
	assert_false(rejected.eligible, "a missing campaign definition makes a vault character ineligible")
	assert_true(not rejected.reasons.is_empty(), "vault eligibility reports an actionable reason")
	assert_true(repository.archive_character(record.character_id), "archiving removes the current index without destructive character deletion")
	assert_true(repository.list_current_records().all(func(candidate: CharacterVaultRecord) -> bool: return candidate.character_id != record.character_id), "archived characters leave the current vault listing")
