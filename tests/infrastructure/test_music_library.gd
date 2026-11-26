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
	assert_true(repository.accept_import({id: track}) and repository.accept_import({id: track}) and MusicLibraryView.from_data(repository.snapshot()).tracks.size() == 1, "validated import commits once without duplicating identical bytes: " + repository.last_error)
	var playlist_id := "c".repeat(32)
	var playlists := {playlist_id: {"name": "Roads", "tracks": [id, "stock:3"], "shuffle": false, "repeat": "all"}}
	var assignments := {"": {"1": {"kind": "playlist", "playlistId": playlist_id}, "3": {"kind": "stock", "trackId": "stock:1"}}, "campaign.example": {"1": {"kind": "original", "playlistId": ""}}}
	assert_true(repository.save_preferences(playlists, assignments) and not repository.save_preferences(playlists, {"": {"1": {"kind": "stock", "trackId": "stock:12"}}}) and not repository.save_preferences({playlist_id: {"name": "Bad", "tracks": ["stock:0"], "shuffle": false, "repeat": "all"}}, {}), "global, stock-track, and campaign choices commit atomically while invalid stock IDs are rejected")
	var reopened := MusicLibraryRepository.new(ROOT)
	assert_equal(reopened.snapshot(), repository.snapshot(), "library, order, and stable campaign assignments survive restart")
	var before := FileAccess.get_file_as_string(ROOT.path_join("index.json"))
	for field: String in ["sourceHash", "subsong", "duration", "cacheHash", "playbackFormat"]:
		var malformed := track.duplicate()
		malformed[field] = "../outside"
		assert_false(repository.accept_import({id: malformed}), "untrusted track field is rejected: " + field)
	assert_equal(FileAccess.get_file_as_string(ROOT.path_join("index.json")), before, "rejected imports preserve the complete committed index")
	DirAccess.make_dir_absolute(ROOT.path_join("index.json.tmp"))
	assert_true(not repository.save_preferences({}, {}) and repository.snapshot() == reopened.snapshot(), "an unwritable staging index does not commit or mutate in-memory preferences")
	DirAccess.remove_absolute(ROOT.path_join("index.json.tmp"))
	assert_true(repository.remove_track(id) and MusicLibraryView.from_data(repository.snapshot()).playlists[playlist_id].tracks == ["stock:3"] and FileAccess.file_exists(ROOT.path_join("index.json.bak")), "removal commits, clears only removed user tracks, retains stock tracks, and backs up the prior index")
	var corrupt := FileAccess.open(ROOT.path_join("index.json"), FileAccess.WRITE)
	corrupt.store_string("broken")
	corrupt.close()
	var damaged := MusicLibraryRepository.new(ROOT)
	assert_true(not damaged.save_preferences({}, {}) and FileAccess.get_file_as_string(ROOT.path_join("index.json")) == "broken", "damaged indexes stay read-only and preserve their bytes")


func _test_native_result_admission() -> void:
	TestFiles.remove_tree(ROOT)
	var root := ProjectSettings.globalize_path(ROOT)
	var job := root.path_join("staging/import-fixture")
	DirAccess.make_dir_recursive_absolute(job.path_join("audio"))
	var source := job.path_join("source")
	assert_equal(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://src/ui/shared/assets/classic-media/music/playlist-01-outdoor.ogg"), source), OK, "the provenance-pinned bank supplies a licensed decoder fixture")
	var hash := FileAccess.get_sha256(source)
	var converter := "realmz-music-1:" + "b".repeat(64)
	var file := FileAccess.open(job.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"formatVersion": 1, "converter": converter, "ok": true, "tracks": [{"subsong": 0, "title": "Fixture", "format": "ogg", "playbackFormat": "ogg", "duration": 10.0, "cacheFile": ""}]}))
	file.close()
	var imported := MusicImportFiles.finalize(job, root, hash, "renamed.data", converter, func() -> bool: return false)
	assert_true(imported.has("tracks") and FileAccess.get_sha256(root.path_join("originals").path_join(hash)) == hash and MusicLibraryRepository.new(root).accept_import(imported.tracks), "native output passes validation, preserves original bytes, and commits")
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
	MusicImportFiles.remove_job(job)
	assert_true(prepared.get("converter", "") == converter and not DirAccess.dir_exists_absolute(job) and ApplicationMusicHost.has_music_header(repository.playback_path(hash + ":0")) and not ApplicationMusicHost.has_music_header(helper.path_join("manifest.json")), "staging admits source-hash identity, cleans up, and header sniffing separates audio from non-audio files")


func _test_cancelled_import() -> void:
	var task := MusicImportTask.new()
	var root := ProjectSettings.globalize_path(ROOT.path_join("cancelled"))
	assert_true(task.start("res://src/ui/shared/assets/classic-media/music/playlist-01-outdoor.ogg", root, root.path_join("missing-helper")), "preparation starts asynchronously")
	task.cancel()
	while task.state == &"running":
		task.poll()
		await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(task.state == &"cancelled" and task.records.is_empty() and not FileAccess.file_exists(root.path_join("index.json")), "cancellation wins over preparation failure and never publishes partial tracks")
	task.close()
