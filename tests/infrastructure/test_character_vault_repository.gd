extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var repository := CharacterVaultRepository.new("user://realmz2-tests/character-vault-v1")
	var character := CharacterState.new("party.character.1", "Vault Fixture", 12, 12)
	character.race_id = "classic.race.1"
	character.caste_id = "classic.caste.1"
	character.two_hand = 24
	character.set_ability_value(4, 63)
	var record := CharacterVaultRecord.new(character.id, "realmz-classic-1", "realmz2-synthetic-fixture", "0000000000000000000000000000000000000000000000000000000000000000", character, "synthetic-v1")
	record.publication_metadata = {"label": "Fixture vault character"}
	assert_true(repository.publish_revision(record), "vault publication uses a temporary typed write and readback")
	assert_equal(record.revision_hash.length(), 64, "published character revisions receive a stable SHA-256 identity"); var loaded := repository.load_revision(record.character_id, record.revision_hash)
	assert_not_null(loaded, "published character revisions can be loaded by stable identity")
	if loaded != null:
		assert_equal(loaded.state.name, "Vault Fixture", "vault state round-trips through the detached character record")
		assert_equal([loaded.state.two_hand, loaded.state.ability_value(4)], [24, 63], "vault revisions preserve the source-owned combat statistic and trained abilities separately")
		assert_equal(loaded.publication_metadata.get("label"), "Fixture vault character", "publication metadata remains separate from gameplay state")
	assert_false(CharacterVaultRepository.new("user://realmz2-tests/character-vault-invalid").publish_revision(CharacterVaultRecord.new("..", "realmz-classic-1", "realmz2-synthetic-fixture", "0".repeat(64), CharacterState.new("..", "Invalid", 1, 1))), "portable dotted character IDs do not permit traversal components")
	var charmed_state := CharacterState.from_data(character.to_data())
	charmed_state.traitor = true
	var charmed_record := CharacterVaultRecord.new("vault-charmed-character", "realmz-classic-1", "realmz2-synthetic-fixture", "0000000000000000000000000000000000000000000000000000000000000000", charmed_state)
	charmed_record.state.id = charmed_record.character_id
	assert_false(repository.publish_revision(charmed_record), "battle-scoped Charm allegiance cannot leak into a reusable vault revision")
	var records := repository.list_current_records()
	assert_true(records.any(func(candidate: CharacterVaultRecord) -> bool: return candidate.character_id == record.character_id), "the current-revision index exposes published characters")
	assert_true(repository.list_character_ids().has(record.character_id), "vault enumeration includes active character identities without reading presentation state")
	var package := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(package.is_ok(), "the fixture package loads for campaign eligibility checks")
	if package.is_ok():
		var eligibility := repository.campaign_eligibility(record, package.content)
		assert_true(eligibility.eligible, "a matching race and class are eligible for the target campaign")
		var wrong_role := CharacterVaultRecord.from_data(record.to_data())
		wrong_role.state.portrait_id = "realmz-combat-icon-9000"
		assert_false(repository.campaign_eligibility(wrong_role, package.content).eligible, "campaign eligibility rejects a known package asset used in the wrong appearance role")
		record.state.portrait_id = "realmz-portrait-257"
		record.state.combat_icon_id = "realmz-combat-icon-9000"
		assert_true(repository.campaign_eligibility(record, package.content).eligible, "matching package portrait and combat-icon identities remain vault-eligible")
		var local_appearances: Array[CharacterAppearanceDefinition] = package.content.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT).filter(func(option: CharacterAppearanceDefinition) -> bool: return option.classic_resource_id != 257); local_appearances.append_array(package.content.appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON)); local_appearances.append(CharacterAppearanceDefinition.new("realmz-player-map-cicn-257", "Map marker", &"player-map-marker", 257)); var scenario_content := RealmzContent.new("scenario", "0".repeat(64), "scenario", package.content.rules_version, "", Vector2i.ZERO, WorldDefinition.new([]), ScenarioDefinition.new([], []), [], [], [], package.content.race_definitions(), package.content.caste_definitions(), [], [], [], [], [], [], [], [], [], [], package.content.campaign_definition(), local_appearances); assert_false(repository.campaign_eligibility(record, scenario_content).eligible, "a scenario-local role collision does not masquerade as the stock portrait identity"); scenario_content.set_application_appearance_catalog(package.content); assert_true(repository.campaign_eligibility(record, scenario_content).eligible, "the application appearance catalog restores a stable stock portrait identity across scenarios")
	var first_revision_hash := record.revision_hash
	character.name = "Vault Fixture Revision Two"
	character.portrait_id = "realmz-portrait-257"
	character.combat_icon_id = "realmz-combat-icon-9000"
	record.state = character
	assert_true(repository.publish_revision(record), "publishing a changed character creates a new immutable revision")
	assert_true(record.revision_hash != first_revision_hash, "changed character state receives a distinct revision hash")
	var second_revision_hash := record.revision_hash
	assert_not_null(repository.load_revision(record.character_id, first_revision_hash), "older character revisions remain loadable after a new publication")
	var revision_count_before_archive := repository.list_revisions(record.character_id).size()
	assert_true(revision_count_before_archive >= 2, "vault history exposes both immutable revisions instead of only the current index")
	character.race_id = "missing.race"
	record.state = character
	var rejected := repository.campaign_eligibility(record, package.content)
	assert_false(rejected.eligible, "a missing campaign definition makes a vault character ineligible")
	assert_true(not rejected.reasons.is_empty(), "vault eligibility reports an actionable reason")
	assert_true(repository.archive_character(record.character_id), "archiving removes the current index without destructive character deletion")
	assert_true(repository.list_current_records().all(func(candidate: CharacterVaultRecord) -> bool: return candidate.character_id != record.character_id), "archived characters leave the current vault listing")
	assert_true(repository.current_revision_hash(record.character_id).is_empty(), "archive clears the recoverable current-revision index")
	assert_true(repository.revision_is_archived(record.character_id, second_revision_hash), "the archived current revision remains explicitly discoverable")
	assert_equal(repository.list_revisions(record.character_id).size(), revision_count_before_archive, "archive preserves the complete immutable history")
	assert_true(repository.restore_revision(record.character_id, first_revision_hash), "an earlier immutable revision can be restored as current")
	assert_equal(repository.current_revision_hash(record.character_id), first_revision_hash, "recovery indexes the exact requested revision")
	assert_true(repository.archive_character(record.character_id), "a restored earlier revision can be archived again without deleting history")
	assert_true(repository.restore_revision(record.character_id, second_revision_hash), "the previously archived latest revision can be recovered")
	assert_equal(repository.current_revision_hash(record.character_id), second_revision_hash, "archive recovery moves the exact latest revision back into the active vault")
	assert_true(repository.archive_character(record.character_id), "the test leaves the fixture character archived and recoverable")
	var fast_character := CharacterState.new("vault.fast-spell", "Quickcaster", 10, 10)
	fast_character.set_known_spells(["classic.spell.quick"])
	fast_character.bind_fast_spell(9, "classic.spell.quick", 3)
	var fast_record := CharacterVaultRecord.new(fast_character.id, "realmz-classic-1", "fixture", "0".repeat(64), fast_character)
	assert_true(repository.publish_revision(fast_record), "vault publication accepts character-owned Fast Spell state")
	var loaded_fast := repository.load_revision(fast_record.character_id, fast_record.revision_hash)
	assert_equal(loaded_fast.state.fast_spell_at(9).to_data(), {"spellId": "classic.spell.quick", "power": 3}, "vault revisions preserve the exact Fast Spell slot and power")
	assert_true(repository.archive_character(fast_record.character_id), "the Fast Spell vault fixture is archived without destructive deletion")
