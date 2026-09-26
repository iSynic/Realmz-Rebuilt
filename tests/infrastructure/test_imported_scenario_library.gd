extends RealmzTestCase

const TEST_ROOT: String = "user://realmz2-tests/imported-scenario-library"
const TestFiles := preload("res://tests/infrastructure/imported_scenario_test_files.gd")


func run() -> void:
	_test_bootstrap_is_deterministic_and_stable()
	_test_install_deduplicates_and_persists_preference()
	_test_unavailable_revisions_are_hidden_but_preserved()
	_test_failed_and_corrupt_indexes_are_preserved()
	_test_backup_recovery_and_import_origin_identity()
	_test_campaign_removal_tombstone_and_reimport()
	_test_removal_failures_roll_back()
	_test_legacy_index_is_upgraded()
	TestFiles.remove_tree(TEST_ROOT)


func _test_bootstrap_is_deterministic_and_stable() -> void:
	var root := TEST_ROOT + "/bootstrap"
	TestFiles.remove_tree(root)
	var first := TestFiles.write_package_record(root, "z.realmz2", "a".repeat(64), "campaign.bootstrap")
	var second := TestFiles.write_package_record(root, "a.realmz2", "b".repeat(64), "campaign.bootstrap")
	var index_path := root + "/index.json"
	var library := ImportedScenarioLibrary.new(index_path)
	var selected := library.select_revisions([first, second])
	assert_true(library.last_error.is_empty(), "deterministic bootstrap writes a valid revision index: %s" % library.last_error)
	assert_equal(selected.size(), 1, "discovery exposes one preferred revision for each imported campaign")
	assert_equal(selected[0].package_hash, second.package_hash, "a prior-install bootstrap selects the first path in deterministic sorted order")
	assert_equal(library.revisions("campaign.bootstrap").size(), 2, "bootstrap retains both discovered immutable revisions")
	var initial_index := FileAccess.get_file_as_string(index_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(index_path + ".tmp"))
	var reopened := ImportedScenarioLibrary.new(index_path)
	selected = reopened.select_revisions([first, second])
	assert_equal(selected[0].package_hash, second.package_hash, "repeated discovery retains the durable bootstrap choice")
	assert_true(reopened.last_error.is_empty(), "repeated discovery skips the write path when no index data changed")
	assert_equal(FileAccess.get_file_as_string(index_path), initial_index, "unchanged discovery does not rewrite the index")
	assert_equal(DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path + ".tmp")), OK, "the no-rewrite sentinel directory is removable")
	TestFiles.remove_tree(root)


func _test_install_deduplicates_and_persists_preference() -> void:
	var root := TEST_ROOT + "/preference"
	TestFiles.remove_tree(root)
	var first := TestFiles.write_package_record(root, "first.realmz2", "c".repeat(64), "campaign.preference")
	var second := TestFiles.write_package_record(root, "second.realmz2", "d".repeat(64), "campaign.preference")
	var index_path := root + "/index.json"
	var library := ImportedScenarioLibrary.new(index_path)
	assert_false(library.contains_revision("campaign.preference", first.package_hash), "a same-campaign package identity is not treated as imported before explicit installation")
	var first_install_ok := library.record_install(first, ["Compatibility warning"], "Release 1")
	assert_true(first_install_ok, "a validated installation becomes the preferred revision: %s" % library.last_error)
	assert_true(library.contains_revision("campaign.preference", first.package_hash), "explicit import records the package identity independently of campaign ID")
	var first_metadata := library.revisions("campaign.preference")[0]
	assert_equal([first_metadata.get("origin"), first_metadata.get("diagnostics"), first_metadata.get("version_label")], ["imported", ["Compatibility warning"], "Release 1"], "import origin, diagnostics, and authored version label persist with a revision")
	assert_true(library.record_install(second), "a later validated revision can become preferred")
	var imported_at := String(library.revisions("campaign.preference")[1].get("imported_at", ""))
	assert_true(not imported_at.is_empty(), "newly installed revisions record their import time")
	assert_true(library.record_install(second), "reimporting identical package bytes succeeds as an idempotent update")
	var revision_list := library.revisions("campaign.preference")
	assert_equal(revision_list.size(), 2, "identical reimport does not duplicate a revision")
	assert_equal(String(revision_list[1].get("imported_at", "")), imported_at, "identical reimport preserves the original import time")
	var persisted_index := FileAccess.get_file_as_string(index_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(index_path + ".tmp"))
	assert_true(library.record_install(second), "identical reimport succeeds without another index write")
	assert_equal(library.last_error, "", "idempotent reimport does not report a blocked rewrite")
	assert_equal(FileAccess.get_file_as_string(index_path), persisted_index, "identical reimport leaves index bytes unchanged")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path + ".tmp"))
	var reopened := ImportedScenarioLibrary.new(index_path)
	var selected := reopened.select_revisions([first, second])
	assert_equal(selected.size(), 1, "reopened library selects one preferred revision")
	assert_equal(selected[0].package_hash, second.package_hash, "the preferred package hash survives reopening")
	var imported_view := CampaignPackageView.from_discovery(second)
	assert_equal(imported_view.origin, "imported", "a same-ID campaign package view keeps imported origin explicit")
	TestFiles.remove_tree(root)


func _test_unavailable_revisions_are_hidden_but_preserved() -> void:
	var root := TEST_ROOT + "/unavailable"
	TestFiles.remove_tree(root)
	var available := TestFiles.write_package_record(root, "available.realmz2", "e".repeat(64), "campaign.availability")
	var removed := TestFiles.write_package_record(root, "removed.realmz2", "f".repeat(64), "campaign.availability")
	var index_path := root + "/index.json"
	var library := ImportedScenarioLibrary.new(index_path)
	assert_true(library.record_install(removed), "the second revision is recorded before its archive is removed")
	assert_true(library.record_install(available), "the available revision remains in the library")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(removed.path))
	var selected := library.select_revisions([available])
	assert_equal(selected.size(), 1, "discovery still selects an existing ready revision")
	assert_equal(selected[0].package_hash, available.package_hash, "an unavailable preferred archive cannot be selected")
	var visible_revisions := library.revisions("campaign.availability")
	assert_equal(visible_revisions.size(), 1, "the detached revision list excludes an unavailable archive")
	assert_equal(String(visible_revisions[0].get("package_hash", "")), available.package_hash, "the visible revision is the one confirmed by discovery")
	assert_false(library.prefer("campaign.availability", removed.package_hash), "an unavailable revision cannot be made preferred")
	assert_true(FileAccess.get_file_as_string(index_path).contains(removed.package_hash), "unavailable revision metadata remains durable for future recovery")
	TestFiles.remove_tree(root)


func _test_failed_and_corrupt_indexes_are_preserved() -> void:
	var root := TEST_ROOT + "/failure"
	TestFiles.remove_tree(root)
	var first := TestFiles.write_package_record(root, "first.realmz2", "1".repeat(64), "campaign.failure")
	var second := TestFiles.write_package_record(root, "second.realmz2", "2".repeat(64), "campaign.failure")
	var index_path := root + "/index.json"
	var library := ImportedScenarioLibrary.new(index_path)
	assert_true(library.record_install(first), "the initial index is installed before simulating write failure")
	var prior_index := FileAccess.get_file_as_string(index_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(index_path + ".tmp"))
	assert_false(library.record_install(second), "a failed temporary write rejects the revision update")
	assert_true(not library.last_error.is_empty(), "a failed write reports its reason")
	assert_equal(FileAccess.get_file_as_string(index_path), prior_index, "failed replacement leaves the previous index byte-for-byte intact")
	assert_equal(library.revisions("campaign.failure").size(), 1, "failed replacement also restores the in-memory index")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path + ".tmp"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(index_path + ".previous"))
	assert_false(library.record_install(second), "a blocked same-directory rename rejects replacement")
	assert_equal(FileAccess.get_file_as_string(index_path), prior_index, "a failed rename preserves the previous index at its original path")
	assert_equal(library.revisions("campaign.failure").size(), 1, "a failed rename restores the previous in-memory revision set")
	TestFiles.remove_tree(index_path + ".previous")
	var corrupt_path := root + "/corrupt.json"
	TestFiles.write_text(corrupt_path + ".previous", prior_index)
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt_file.store_string("{broken json")
	corrupt_file.close()
	var corrupt_original := FileAccess.get_file_as_string(corrupt_path)
	var corrupt_library := ImportedScenarioLibrary.new(corrupt_path)
	assert_false(corrupt_library.record_install(first), "a corrupt index blocks durable mutation until it is repaired")
	assert_true(not corrupt_library.last_error.is_empty(), "a corrupt index failure is visible to the caller")
	corrupt_library.select_revisions([first])
	assert_true(not corrupt_library.last_error.is_empty(), "discovery retains the corrupt-index diagnostic")
	assert_equal(FileAccess.get_file_as_string(corrupt_path), corrupt_original, "discovery never silently overwrites a corrupt index")
	assert_equal(FileAccess.get_file_as_string(corrupt_path + ".previous"), prior_index, "a valid backup does not mask a corrupt existing primary")
	TestFiles.remove_tree(root)


func _test_backup_recovery_and_import_origin_identity() -> void:
	var root := TEST_ROOT + "/recovery"
	TestFiles.remove_tree(root)
	var record := TestFiles.write_package_record(root, "scenario.realmz2", "3".repeat(64), "campaign.shared-id")
	var index_path := root + "/index.json"
	var library := ImportedScenarioLibrary.new(index_path)
	assert_true(library.record_install(record), "the recovery fixture writes an imported revision")
	var previous_bytes := FileAccess.get_file_as_string(index_path)
	TestFiles.write_text(index_path + ".previous", previous_bytes)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path))
	var recovered := ImportedScenarioLibrary.new(index_path)
	assert_true(FileAccess.file_exists(index_path), "a valid previous index is restored when the primary is missing")
	assert_true(recovered.contains_revision("campaign.shared-id", record.package_hash), "recovery retains explicit imported identity for campaign-ID collision filtering")
	assert_equal(FileAccess.get_file_as_string(index_path), previous_bytes, "backup recovery preserves the exact prior index contents")
	TestFiles.remove_tree(root)


func _test_campaign_removal_tombstone_and_reimport() -> void:
	var root := TEST_ROOT + "/removal"
	TestFiles.remove_tree(root)
	var record := TestFiles.write_package_record(root, "scenario.realmz2", "4".repeat(64), "campaign.remove")
	var index_path := root + "/index.json"
	var library := ImportedScenarioLibrary.new(index_path)
	assert_true(library.record_install(record), "scenario is installed before removal")
	assert_true(library.remove_campaign("campaign.remove"), "known imported campaign can be removed")
	assert_true(FileAccess.file_exists(record.path), "removing a library entry retains its immutable package")
	assert_equal(library.revisions("campaign.remove").size(), 0, "removed revisions are hidden from the library")
	var reopened := ImportedScenarioLibrary.new(index_path)
	assert_equal(reopened.select_revisions([record]).size(), 0, "discovery does not resurrect a removed campaign")
	assert_equal(reopened.revisions("campaign.remove").size(), 0, "removal remains hidden after reopening")
	assert_true(reopened.record_install(record), "explicit reimport restores a removed campaign")
	assert_equal(reopened.select_revisions([record]).size(), 1, "restored campaign becomes discoverable")
	TestFiles.remove_tree(root)


func _test_removal_failures_roll_back() -> void:
	var root := TEST_ROOT + "/removal-failure"
	TestFiles.remove_tree(root)
	var record := TestFiles.write_package_record(root, "scenario.realmz2", "5".repeat(64), "campaign.remove-failure")
	var index_path := root + "/index.json"
	var library := ImportedScenarioLibrary.new(index_path)
	assert_true(library.record_install(record), "scenario is installed before failed removal")
	var previous_index := FileAccess.get_file_as_string(index_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(index_path + ".tmp"))
	assert_false(library.remove_campaign("campaign.remove-failure"), "failed persistence rejects removal")
	assert_equal(FileAccess.get_file_as_string(index_path), previous_index, "failed removal leaves persisted index unchanged")
	assert_equal(library.revisions("campaign.remove-failure").size(), 1, "failed removal restores in-memory availability")
	assert_false(library.remove_campaign("campaign.unknown"), "unknown campaign cannot be removed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(index_path + ".tmp"))
	TestFiles.remove_tree(root)


func _test_legacy_index_is_upgraded() -> void:
	var root := TEST_ROOT + "/legacy-index"
	TestFiles.remove_tree(root)
	var index_path := root + "/index.json"
	TestFiles.write_text(index_path, JSON.stringify({
		"formatVersion": 1,
		"campaigns": {"campaign.legacy": {"preferred_package_hash": "", "revisions": []}},
	}))
	var record := TestFiles.write_package_record(root, "scenario.realmz2", "6".repeat(64), "campaign.legacy")
	var library := ImportedScenarioLibrary.new(index_path)
	assert_true(library.record_install(record), "format-1 indexes remain readable and upgrade on mutation: %s" % library.last_error)
	var upgraded: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	assert_equal(upgraded.get("formatVersion"), 2, "the next mutation writes the current index format")
	assert_false(upgraded.get("campaigns", {}).get("campaign.legacy", {}).get("removed", true), "legacy campaigns upgrade as visible library entries")
	TestFiles.remove_tree(root)
