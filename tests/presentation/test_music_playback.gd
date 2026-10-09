extends RealmzTestCase


func run() -> void:
	_test_resolution_and_queue()
	await _test_transitions()
	await _test_playback()


func _library() -> MusicLibraryView:
	var view := MusicLibraryView.new()
	for id: String in ["a", "b", "c"]:
		var track := MusicLibraryView.Track.new()
		track.id = id
		track.title = id.to_upper()
		view.tracks[id] = track
	var playlist := view.add_playlist("Journey")
	playlist.tracks.assign(["a", "b", "c"])
	view.set_assignment("", 1, "playlist", playlist.id)
	return view


func _test_resolution_and_queue() -> void:
	var view := _library()
	var playlist := view.resolve("campaign.one", 1)
	assert_not_null(playlist, "a campaign inherits the global playlist")
	view.set_assignment("campaign.one", 1, "original")
	assert_equal(view.resolve("campaign.one", 1), null, "explicit Original suppresses the global playlist")
	view.set_assignment("campaign.one", 1, "inherit")
	assert_equal(view.resolve("campaign.one", 1), playlist, "Inherit restores global resolution")
	var random := RandomNumberGenerator.new()
	random.seed = 42
	var queue := MusicPlaybackQueue.new(random)
	assert_true(queue.configure(playlist), "first assignment starts a queue")
	queue.position = 12.0
	assert_false(queue.configure(playlist), "view refresh retains the queue")
	assert_equal(queue.position, 12.0, "view refresh retains the playback position")
	for expected: String in ["a", "b", "c", "a"]:
		assert_equal(queue.current(), expected, "Repeat All follows ordered tracks and wraps")
		queue.advance()
	playlist.repeat = "one"
	queue.configure(playlist)
	queue.advance()
	assert_equal(queue.current(), "a", "Repeat One keeps the completed track")
	queue.advance(true)
	assert_equal(queue.current(), "b", "an unavailable Repeat One track can be skipped")
	playlist.repeat = "none"
	queue.configure(playlist)
	for index: int in 3:
		queue.advance()
	assert_true(queue.exhausted and queue.current().is_empty(), "no repeat has an explicit silent terminal state")
	playlist.shuffle = true
	queue.configure(playlist)
	var order: Array[String] = []
	for index: int in 3:
		order.append(queue.current())
		queue.advance()
	var shuffled_first := order[0]
	var shuffled_state := random.state
	queue.enter_context(PresentationSettings.MUSIC_RESTART_SONG)
	assert_true(queue.exhausted, "an exhausted no-repeat playlist has no current song to restart")
	queue.enter_context(PresentationSettings.MUSIC_RESTART_PLAYLIST)
	assert_equal([queue.exhausted, queue.current(), random.state], [false, shuffled_first, shuffled_state], "playlist restart replays the retained shuffled order without another shuffle draw")
	order.sort()
	assert_equal(order, playlist.tracks, "shuffle traverses every track once before exhaustion")
	playlist.tracks.assign(["a"])
	var before := random.state
	queue.configure(playlist)
	assert_equal(random.state, before, "a one-track shuffle consumes no random draw")


func _test_transitions() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 8000
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var samples := PackedByteArray()
	samples.resize(160000)
	stream.data = samples
	for transition: String in PresentationSettings.MUSIC_TRANSITIONS:
		var presenter := ClassicAudioPresenter.new()
		tree.root.add_child(presenter)
		var channel := presenter.get_node("ClassicMusicChannel") as AudioStreamPlayer
		var settings := PresentationSettings.new()
		settings.music_transition = transition
		var stock := ClassicMusicCatalog.new()
		presenter.music.set_library(_library(), func(_id: String) -> AudioStream: return stream)
		presenter.present_music_context(1, settings, null, stock, "one")
		channel.finished.emit()
		channel.seek(2.0)
		await tree.process_frame
		presenter.present_music_context(11, settings, null, stock, "one")
		presenter.present_music_context(1, settings, null, stock, "one")
		var expected := "A" if transition == PresentationSettings.MUSIC_RESTART_PLAYLIST else "B"
		assert_equal(presenter.current_music_title, expected, "return from Battle applies the selected playlist/song identity policy")
		assert_true(channel.get_playback_position() >= 1.9 if transition == PresentationSettings.MUSIC_RESUME else channel.get_playback_position() < 0.3, "return from Battle applies the selected playback-position policy")
		channel.seek(3.0)
		await tree.process_frame
		presenter.present_music_context(1, settings, null, stock, "one")
		assert_true(channel.get_playback_position() >= 2.9, "ordinary view refresh never restarts music")
		presenter.music.preview("c")
		presenter.music.end_preview()
		assert_true(presenter.current_music_title == expected and channel.get_playback_position() >= 2.9, "preview restores the exact interrupted song and position under every policy")
		settings.set_music_mode(11, PresentationSettings.MUSIC_CONTINUE)
		presenter.present_music_context(11, settings, null, stock, "one")
		presenter.present_music_context(1, settings, null, stock, "one")
		assert_true(channel.get_playback_position() >= 2.9, "Continue preserves uninterrupted playback through both context boundaries")
		settings.set_music_mode(11, PresentationSettings.MUSIC_OFF)
		presenter.present_music_context(11, settings, null, stock, "one")
		presenter.present_music_context(1, settings, null, stock, "one")
		assert_equal(presenter.current_music_title, expected, "return from an Off context applies the same queue policy")
		assert_true(channel.get_playback_position() >= 2.9 if transition == PresentationSettings.MUSIC_RESUME else channel.get_playback_position() < 0.3, "return from Off applies the selected playback-position policy")
		presenter.free()
	await tree.process_frame


func _test_playback() -> void:
	var presenter := ClassicAudioPresenter.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(presenter)
	var channel := presenter.get_node("ClassicMusicChannel") as AudioStreamPlayer
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 8000
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var samples := PackedByteArray()
	samples.resize(160000)
	stream.data = samples
	var library := _library()
	var playlist := library.resolve("one", 1)
	var settings := PresentationSettings.new()
	settings.music_transition = PresentationSettings.MUSIC_RESUME
	var stock := ClassicMusicCatalog.new()
	presenter.music.set_library(library, func(_id: String) -> AudioStream: return stream)
	presenter.present_music_context(1, settings, null, stock, "one")
	assert_equal(presenter.current_music_title, "A", "custom music replaces the resolved stock context")
	channel.seek(2.0)
	await tree.process_frame
	presenter.present_music_context(11, settings, null, stock, "one")
	presenter.present_music_context(1, settings, null, stock, "one")
	assert_true(channel.get_playback_position() >= 1.9, "Outdoor resumes its position after Battle")
	settings.set_music_mode(11, PresentationSettings.MUSIC_CONTINUE)
	presenter.present_music_context(11, settings, null, stock, "one")
	channel.finished.emit()
	assert_equal(presenter.current_music_title, "B", "Continue lets the inherited playing queue advance")
	settings.set_music_mode(11, PresentationSettings.MUSIC_OFF)
	presenter.present_music_context(11, settings, null, stock, "one")
	assert_false(channel.playing, "Off suspends the retained queue")
	presenter.present_music_context(1, settings, null, stock, "one")
	assert_equal(presenter.current_music_title, "B", "returning from Off resumes the current queue entry")
	assert_true(presenter.music.preview("c"), "a library track can be previewed")
	presenter.music.end_preview()
	assert_equal(presenter.current_music_title, "B", "ending preview restores ordinary playback")
	presenter.present_music_context(1, settings, null, stock, "two")
	assert_equal(presenter.current_music_title, "A", "another campaign owns an independent context queue")
	presenter.present_music_context(1, settings, null, stock, "one")
	assert_equal(presenter.current_music_title, "B", "switching campaigns preserves the previous queue")
	playlist.repeat = "none"
	presenter.music.set_library(library, func(_id: String) -> AudioStream: return stream)
	for index: int in 3:
		channel.stop()
		channel.finished.emit()
	presenter.present_music_context(1, settings, null, stock, "one")
	assert_false(channel.playing, "normal no-repeat exhaustion stays silent across view refresh")
	playlist.repeat = "all"
	presenter.music.set_library(library, func(_id: String) -> AudioStream: return null)
	assert_equal(presenter.current_music_title, stock.title(1), "an entirely unavailable playlist falls back to original music")
	presenter.music.set_library(library, func(_id: String) -> AudioStream: return stream, ["a"])
	assert_equal(presenter.current_music_title, "A", "repairing an unavailable track retries the playlist without changing its assignment")
	presenter.music.preview("c")
	settings.music_enabled = false
	presenter.present_music_context(1, settings, null, stock, "one")
	assert_false(channel.playing, "disabling music also stops a preview")
	presenter.free()
	await tree.process_frame
	await tree.process_frame
