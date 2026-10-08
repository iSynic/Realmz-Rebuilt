extends RealmzTestCase

const ROOT := "user://realmz2-tests/music-library"
const TestFiles := preload("res://tests/infrastructure/imported_scenario_test_files.gd")


func run() -> void:
	_test_atomic_library_and_validation()
	_test_native_result_admission()
	await _test_cancelled_import()
	TestFiles.remove_tree(ROOT)


func _test_atomic_library_and_validation() -> void:
	TestFiles.remove_tree(ROOT)
	var repository := MusicLibraryRepository.new(ROOT)
	var hash := "a".repeat(64)
	var id := hash + ":0"
	var track := {"sourceHash": hash, "sourceName": "Original.mp3", "title": "A track", "format": "mp3", "playbackFormat": "mp3", "duration": 12.5, "subsong": 0, "converter": "realmz-music-1:" + "b".repeat(64), "cacheHash": ""}
	assert_true(repository.accept_import({id: track}), "a validated import commits: " + repository.last_error)
	assert_true(repository.accept_import({id: track}), "identical import preserves the same identity")
	assert_equal(repository.snapshot().tracks.size(), 1, "duplicate bytes do not create duplicate library tracks")
	var playlist_id := "c".repeat(32)
	var playlists := {playlist_id: {"name": "Roads", "tracks": [id], "shuffle": false, "repeat": "all"}}
	var assignments := {"": {"1": {"kind": "playlist", "playlistId": playlist_id}}, "campaign.example": {"1": {"kind": "original", "playlistId": ""}}}
	assert_true(repository.save_preferences(playlists, assignments), "global and campaign music choices commit atomically")
	var reopened := MusicLibraryRepository.new(ROOT)
	assert_equal(reopened.snapshot(), repository.snapshot(), "library, order, and stable campaign assignments survive restart")
	var before := FileAccess.get_file_as_string(ROOT.path_join("index.json"))
	for field: String in ["sourceHash", "subsong", "duration", "cacheHash", "playbackFormat"]:
		var malformed := track.duplicate()
		malformed[field] = "../outside"
		assert_false(repository.accept_import({id: malformed}), "untrusted track field is rejected: " + field)
	assert_equal(FileAccess.get_file_as_string(ROOT.path_join("index.json")), before, "rejected imports preserve the complete committed index")
	DirAccess.make_dir_absolute(ROOT.path_join("index.json.tmp"))
	assert_false(repository.save_preferences({}, {}), "an unwritable staging index does not commit")
	assert_equal(repository.snapshot(), reopened.snapshot(), "failed persistence leaves in-memory preferences unchanged")
	DirAccess.remove_absolute(ROOT.path_join("index.json.tmp"))
	assert_true(repository.remove_track(id), "explicit removal commits")
	assert_equal(repository.snapshot().playlists[playlist_id].tracks, [], "removal clears playlist references in the same transaction")
	assert_true(FileAccess.file_exists(ROOT.path_join("index.json.bak")), "the prior valid index remains backed up")
	var corrupt := FileAccess.open(ROOT.path_join("index.json"), FileAccess.WRITE)
	corrupt.store_string("broken")
	corrupt.close()
	var damaged := MusicLibraryRepository.new(ROOT)
	assert_false(damaged.save_preferences({}, {}), "damaged indexes cannot be silently overwritten")
	assert_equal(FileAccess.get_file_as_string(ROOT.path_join("index.json")), "broken", "damaged index bytes remain recoverable")


func _test_native_result_admission() -> void:
	TestFiles.remove_tree(ROOT)
	var root := ProjectSettings.globalize_path(ROOT)
	var job := root.path_join("staging/import-fixture")
	DirAccess.make_dir_recursive_absolute(job.path_join("audio"))
	var source := job.path_join("source")
	assert_equal(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://src/ui/shared/assets/classic-media/music/playlist-01-outdoor.ogg"), source), OK, "the provenance-pinned bank supplies a licensed decoder fixture")
	var hash := FileAccess.get_sha256(source)
	var converter := "realmz-music-1:" + "b".repeat(64)
	var track := {"subsong": 0, "title": "Fixture", "format": "ogg", "playbackFormat": "ogg", "duration": 10.0, "cacheFile": ""}
	var report := {"formatVersion": 1, "converter": converter, "ok": true, "tracks": [track]}
	var file := FileAccess.open(job.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	var imported := MusicImportFiles.finalize(job, root, hash, "renamed.data", converter, func() -> bool: return false)
	assert_true(imported.has("tracks"), "native output must pass metadata and Godot playback admission")
	assert_equal(FileAccess.get_sha256(root.path_join("originals").path_join(hash)), hash, "managed import retains exact original bytes independently of its filename")
	assert_true(MusicLibraryRepository.new(root).accept_import(imported.tracks), "validated artifacts become visible only after index commit")
	var repository := MusicLibraryRepository.new(root)
	assert_equal(repository.playback_path(hash + ":0"), root.path_join("originals").path_join(hash), "native Vorbis plays directly from managed storage")
	var helper := root.path_join("helper")
	DirAccess.make_dir_recursive_absolute(helper)
	var executable := "realmz-music-importer" + (".exe" if OS.get_name() == "Windows" else "")
	DirAccess.copy_absolute(repository.playback_path(hash + ":0"), helper.path_join(executable))
	file = FileAccess.open(helper.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"formatVersion": 1, "converter": converter, "files": {executable: hash}}))
	file.close()
	var prepared := MusicImportFiles.prepare(repository.playback_path(hash + ":0"), root.path_join("staging/import-prepare"), helper, func() -> bool: return false)
	assert_equal(prepared.get("converter", ""), converter, "staging admits the complete source-hash identity before helper execution")
	MusicImportFiles.remove_job(job)
	assert_false(DirAccess.dir_exists_absolute(job), "completed staging has bounded cleanup")


func _test_cancelled_import() -> void:
	var task := MusicImportTask.new()
	var root := ProjectSettings.globalize_path(ROOT.path_join("cancelled"))
	assert_true(task.start("res://src/ui/shared/assets/classic-media/music/playlist-01-outdoor.ogg", root, root.path_join("missing-helper")), "preparation starts asynchronously")
	task.cancel()
	while task.state == &"running":
		task.poll()
		await (Engine.get_main_loop() as SceneTree).process_frame
	assert_equal(task.state, &"cancelled", "cancellation wins over an in-flight preparation failure")
	assert_true(task.records.is_empty() and not FileAccess.file_exists(root.path_join("index.json")), "cancellation never publishes partial tracks")
	task.close()
