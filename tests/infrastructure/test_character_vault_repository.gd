extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const STARTER_CATALOG_PATH: String = "res://src/storage/characters/realmz-classic-starter-characters.json"
const CHARACTER_LIBRARY_HASH: String = ApplicationLibraryIdentity.PACKAGE_HASH
const ClassicStarterCharacterCatalogScript := preload("res://src/storage/characters/classic_starter_character_catalog.gd")


func run() -> void:
	_test_classic_starter_seeding()
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
	var legacy_record := record.to_data(); legacy_record["formatVersion"] = 1
	assert_equal(CharacterVaultRecord.from_data(legacy_record), null, "Character Files v1 is explicitly incompatible with the ordered-equipment v2 contract")
	assert_not_null(loaded, "published character revisions can be loaded by stable identity")
	if loaded != null:
		assert_equal(loaded.state.name, "Vault Fixture", "vault state round-trips through the detached character record")
		assert_equal([loaded.state.two_hand, loaded.state.ability_value(4)], [24, 63], "vault revisions preserve the source-owned combat statistic and trained abilities separately")
		assert_equal(loaded.publication_metadata.get("label"), "Fixture vault character", "publication metadata remains separate from gameplay state")
	assert_false(CharacterVaultRepository.new("user://realmz2-tests/character-vault-invalid").publish_revision(CharacterVaultRecord.new("..", "realmz-classic-1", "realmz2-synthetic-fixture", "0".repeat(64), CharacterState.new("..", "Invalid", 1, 1))), "portable dotted character IDs do not permit traversal components")
	var charmed_state := CharacterStateCodec.copy(character)
	charmed_state.traitor = true
	var charmed_record := CharacterVaultRecord.new("vault-charmed-character", "realmz-classic-1", "realmz2-synthetic-fixture", "0000000000000000000000000000000000000000000000000000000000000000", charmed_state)
	charmed_record.state.id = charmed_record.character_id
	assert_false(repository.publish_revision(charmed_record), "battle-scoped Charm allegiance cannot leak into a reusable vault revision"); var records := repository.list_current_records()
	assert_true(records.any(func(candidate: CharacterVaultRecord) -> bool: return candidate.character_id == record.character_id), "the current-revision index exposes published characters")
	assert_true(repository.list_character_ids().has(record.character_id), "vault enumeration includes active character identities without reading presentation state")
	var vault_controller := CharacterVaultController.new(repository); var cached_views := vault_controller.revisions(null); assert_true(not cached_views.is_empty() and vault_controller.cached_revision_count() >= 1, "listing Character Files retains each already validated revision by stable identity"); assert_true(repository.archive_character(record.character_id), "the cache proof temporarily removes the source record from the active vault without deleting it"); var first_cached_intent := vault_controller.import_intent(record.character_id, record.revision_hash); var second_cached_intent := vault_controller.import_intent(record.character_id, record.revision_hash); assert_true(first_cached_intent != null and second_cached_intent != null and (first_cached_intent.payload as PartyIntentPayloads.VaultImport).character_state != (second_cached_intent.payload as PartyIntentPayloads.VaultImport).character_state, "cached imports remain available without a drop-frame read and return detached state clones"); (first_cached_intent.payload as PartyIntentPayloads.VaultImport).character_state.name = "Detached mutation"; assert_equal((second_cached_intent.payload as PartyIntentPayloads.VaultImport).character_state.name, "Vault Fixture", "one cached import cannot mutate another"); assert_true(repository.restore_revision(record.character_id, record.revision_hash), "the cache proof restores the active revision before ordinary repository checks continue")
	var package := load_test_package(FIXTURE_PATH)
	if package.is_ok():
		var eligibility := repository.campaign_eligibility(record, package.content)
		assert_true(eligibility.eligible, "a matching race and class are eligible for the target campaign")
		var wrong_role := CharacterVaultRecord.from_data(record.to_data())
		wrong_role.state.portrait_id = "realmz-combat-icon-9000"
		assert_false(repository.campaign_eligibility(wrong_role, package.content).eligible, "campaign eligibility rejects a known package asset used in the wrong appearance role")
		record.state.portrait_id = "realmz-portrait-257"
		record.state.combat_icon_id = "realmz-combat-icon-9000"
		assert_true(repository.campaign_eligibility(record, package.content).eligible, "matching package portrait and combat-icon identities remain vault-eligible")
		var local_appearances: Array[CharacterAppearanceDefinition] = package.content.characters.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT).filter(func(option: CharacterAppearanceDefinition) -> bool: return option.classic_resource_id != 257); local_appearances.append_array(package.content.characters.appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON)); local_appearances.append(CharacterAppearanceDefinition.new("realmz-player-map-cicn-257", "Map marker", &"player-map-marker", 257)); var scenario_content := RealmzContent.new("scenario", "0".repeat(64), "scenario", package.content.rules_version, "", Vector2i.ZERO, WorldDefinition.new([]), ScenarioDefinition.new([], []), [], [], [], package.content.characters.race_definitions(), package.content.characters.caste_definitions(), [], [], [], [], [], [], [], [], [], [], package.content.campaign, local_appearances); assert_false(repository.campaign_eligibility(record, scenario_content).eligible, "a scenario-local role collision does not masquerade as the stock portrait identity"); scenario_content.characters.install_application_catalog(package.content.characters); assert_true(repository.campaign_eligibility(record, scenario_content).eligible, "the application appearance catalog restores a stable stock portrait identity across scenarios")
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


func _test_classic_starter_seeding() -> void:
	var catalog := ClassicStarterCharacterCatalogScript.new()
	var records: Array[CharacterVaultRecord] = catalog.load_records(STARTER_CATALOG_PATH, CHARACTER_LIBRARY_HASH)
	assert_equal(records.map(func(record: CharacterVaultRecord) -> String: return record.character_id), ["classic.starter.kevlar", "classic.starter.lothlorian", "classic.starter.silver-leaf", "classic.starter.traskelion", "classic.starter.trevor", "classic.starter.vormale"], "the trusted catalog exposes exactly the six pinned Realmz 7.1.2 starter identities")
	assert_equal(records.map(func(record: CharacterVaultRecord) -> String: return record.revision_hash), ["7859725d73fb3ef46328f40f6cf31725894d1539103b1ca2aedf019f5e63bd60", "ec89f73fc3e0d685823d51e38377b61c99bc3f0272972f2f6d4393ee55547e4f", "e44480503b748a0b91851e45ec0079c41023f492bf35c8fc7104ac5280fee73a", "36f97466aed5ff5110c83cd30ae35c2faa7b6316782aedc95f51ede044c3d345", "7ad580175b08afb61a6663fb33a664168e49a93004a477d2ac50f4c8a7fa1f24", "d8b2cb6fb97f89b1aa54d8026a940e5426d460937a0fea242d28310c23ca7482"], "the format-v2 offline conversion produces deterministic canonical revision hashes")
	var seeded_root := "user://realmz2-tests/classic-starter-seed"
	_remove_test_tree(seeded_root); _remove_test_tree(seeded_root + ".starter-seed")
	var repository := CharacterVaultRepository.new(seeded_root)
	assert_true(repository.seed_if_empty(records) and repository.list_current_records().size() == 6, "an absent vault installs all six validated records atomically")
	var original_hash := repository.current_revision_hash("classic.starter.kevlar")
	assert_true(repository.seed_if_empty(records) and repository.current_revision_hash("classic.starter.kevlar") == original_hash, "an existing vault is never reinstalled or overwritten")
	var occupied_root := "user://realmz2-tests/classic-starter-occupied"
	_remove_test_tree(occupied_root); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(occupied_root)); var sentinel := FileAccess.open(occupied_root + "/unknown.tmp", FileAccess.WRITE); sentinel.store_string("preserve"); sentinel.close()
	var occupied := CharacterVaultRepository.new(occupied_root)
	assert_true(occupied.seed_if_empty(records) and occupied.list_current_records().is_empty() and FileAccess.file_exists(occupied_root + "/unknown.tmp"), "any unknown, invalid, temporary, or archived vault entry suppresses seeding without mutation")
	var legacy_root := "user://realmz2-tests/classic-starter-legacy"; _remove_test_tree(legacy_root); var legacy_id := records[0].character_id; var legacy_hash := records[0].revision_hash; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [legacy_root, legacy_id])); var legacy_data := records[0].to_data(); legacy_data["formatVersion"] = 1; legacy_data["state"].erase("equipmentOrder"); var legacy_file := FileAccess.open("%s/%s/%s.r2char" % [legacy_root, legacy_id, legacy_hash], FileAccess.WRITE); legacy_file.store_string(CanonicalJson.encode(legacy_data)); legacy_file.close(); var legacy_index := FileAccess.open("%s/%s/current.json" % [legacy_root, legacy_id], FileAccess.WRITE); legacy_index.store_string(CanonicalJson.encode({"characterId": legacy_id, "revisionHash": legacy_hash})); legacy_index.close()
	var legacy_repository := CharacterVaultRepository.new(legacy_root); var diagnostics: Variant = legacy_repository.diagnostics(); assert_equal([diagnostics.valid_current_count, diagnostics.incompatible_current_count, diagnostics.invalid_current_count, diagnostics.stored_identity_count], [0, 1, 0, 1], "an incompatible current revision remains preserved and is reported separately from an empty vault"); assert_true(legacy_repository.seed_if_empty(records) and FileAccess.file_exists("%s/%s/%s.r2char" % [legacy_root, legacy_id, legacy_hash]) and diagnostics.unavailable_notice().contains("incompatible older format"), "starter seeding does not overwrite the incompatible vault and supplies an actionable detached notice")
	var failed_root := "user://realmz2-tests/classic-starter-failure"
	_remove_test_tree(failed_root); _remove_test_tree(failed_root + ".starter-seed")
	var invalid_records: Array[CharacterVaultRecord] = records.duplicate(); var invalid := CharacterVaultRecord.from_data(records[0].to_data()); invalid.state.traitor = true; invalid_records[0] = invalid
	var failing := CharacterVaultRepository.new(failed_root)
	assert_false(failing.seed_if_empty(invalid_records), "one invalid catalog record rejects the complete seed transaction")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(failed_root)) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(failed_root + ".starter-seed")), "failed seeding leaves neither a partial vault nor a staging directory")
	_remove_test_tree(seeded_root); _remove_test_tree(occupied_root); _remove_test_tree(legacy_root); _remove_test_tree(failed_root)


func _remove_test_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := "%s/%s" % [path, entry]
		if directory.current_is_dir(): _remove_test_tree(child)
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
