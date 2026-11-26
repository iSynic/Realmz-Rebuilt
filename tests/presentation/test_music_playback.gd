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
	assert_true(playlist != null and view.resolve("campaign.one", 12) == playlist, "a campaign inherits the global Outdoor playlist for Outdoor and Desert/Swamp/Snow")
	view.set_assignment("campaign.one", 1, "original")
	assert_true(view.resolve("campaign.one", 1) == null and view.resolve("campaign.one", 12) == null, "explicit Original suppresses the global Outdoor playlist")
	view.set_assignment("campaign.one", 1, "inherit")
	view.set_assignment("", 12, "original")
	assert_true(view.resolve("campaign.one", 1) == playlist and view.resolve("campaign.one", 12) == null, "Inherit restores global resolution while explicit Desert Original overrides Outdoor")
	var random := RandomNumberGenerator.new()
	random.seed = 42
	var queue := MusicPlaybackQueue.new(random)
	assert_true(queue.configure(playlist), "first assignment starts a queue")
	queue.position = 12.0
	assert_true(not queue.configure(playlist) and queue.position == 12.0, "view refresh retains the queue and playback position")
	for expected: String in ["a", "b", "c", "a"]:
		assert_equal(queue.current(), expected, "Repeat All follows ordered tracks and wraps")
		queue.advance()
	playlist.repeat = "one"
	queue.configure(playlist)
	queue.advance()
	var stayed_one := queue.current() == "a"
	queue.advance(true)
	assert_true(stayed_one and queue.current() == "b", "Repeat One keeps completed tracks and skips unavailable ones")
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
	var kept_exhausted := queue.exhausted
	queue.enter_context(PresentationSettings.MUSIC_RESTART_PLAYLIST)
	assert_true(kept_exhausted and not queue.exhausted and queue.current() == shuffled_first and random.state == shuffled_state, "song restart keeps exhaustion while playlist restart replays retained shuffle order")
	order.sort()
	playlist.tracks.assign(["a"])
	var before := random.state
	queue.configure(playlist)
	assert_true(order == ["a", "b", "c"] and random.state == before, "shuffle visits every track once and single-track shuffle consumes no RNG draw")


func _silence() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 8000
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var samples := PackedByteArray()
	samples.resize(160000)
	stream.data = samples
	return stream


func _test_transitions() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var stream := _silence()
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
		assert_true(presenter.current_music_title == expected and (channel.get_playback_position() >= 1.9 if transition == PresentationSettings.MUSIC_RESUME else channel.get_playback_position() < 0.3), "return from Battle applies the selected song and playback-position policy")
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
		assert_true(presenter.current_music_title == expected and (channel.get_playback_position() >= 2.9 if transition == PresentationSettings.MUSIC_RESUME else channel.get_playback_position() < 0.3), "return from Off applies the selected queue and playback-position policy")
		presenter.free()
	await tree.process_frame


func _test_playback() -> void:
	var presenter := ClassicAudioPresenter.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(presenter)
	var channel := presenter.get_node("ClassicMusicChannel") as AudioStreamPlayer
	var stream := _silence()
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
	var resumed := channel.get_playback_position() >= 1.9
	settings.set_music_mode(11, PresentationSettings.MUSIC_CONTINUE)
	presenter.present_music_context(11, settings, null, stock, "one")
	channel.finished.emit()
	assert_true(resumed and presenter.current_music_title == "B", "Outdoor resumes after Battle and Continue advances the playing queue")
	settings.set_music_mode(11, PresentationSettings.MUSIC_OFF)
	presenter.present_music_context(11, settings, null, stock, "one")
	var off_silent := not channel.playing
	presenter.present_music_context(1, settings, null, stock, "one")
	assert_true(off_silent and presenter.current_music_title == "B" and presenter.music.preview("c"), "Off suspends, return resumes, and library tracks preview")
	presenter.music.end_preview()
	assert_equal(presenter.current_music_title, "B", "ending preview restores ordinary playback")
	presenter.present_music_context(1, settings, null, stock, "two")
	var two_title := presenter.current_music_title
	presenter.present_music_context(1, settings, null, stock, "one")
	assert_true(two_title == "A" and presenter.current_music_title == "B", "each campaign owns and preserves an independent context queue")
	playlist.repeat = "none"
	presenter.music.set_library(library, func(_id: String) -> AudioStream: return stream)
	for index: int in 3:
		channel.stop()
		channel.finished.emit()
	presenter.present_music_context(1, settings, null, stock, "one")
	var stayed_silent := not channel.playing
	playlist.repeat = "all"
	presenter.music.set_library(library, func(_id: String) -> AudioStream: return null)
	var fallback_title := presenter.current_music_title
	presenter.music.set_library(library, func(_id: String) -> AudioStream: return stream, ["a"])
	assert_true(stayed_silent and fallback_title == stock.title(1) and presenter.current_music_title == "A", "exhaustion stays silent, unavailable playlists fall back to original, and repair retries them")
	presenter.music.preview("c")
	settings.music_enabled = false
	presenter.present_music_context(1, settings, null, stock, "one")
	assert_false(channel.playing, "disabling music also stops a preview")
	settings.music_enabled = true
	library.set_assignment("", 1, "stock", "stock:3")
	presenter.music.set_library(library, func(_id: String) -> AudioStream: return stream)
	presenter.present_music_context(1, settings, null, stock, "one")
	var swapped_and_previewed := presenter.current_music_title == stock.title(3) and presenter.music.preview("stock:11")
	presenter.music.end_preview()
	assert_true(swapped_and_previewed and presenter.current_music_title == stock.title(3), "direct stock track swaps Outdoor to Indoor and stock preview restores playback")
	presenter.present_music_context(12, settings, null, stock, "one")
	assert_equal(presenter.current_music_title, stock.title(3), "unassigned Desert follows Outdoor's custom stock track")
	presenter.free()
	await tree.process_frame
	await tree.process_frame
