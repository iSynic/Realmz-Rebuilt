class_name PresentationCoordinator
extends Node

signal playback_step_settled(step: SessionStep)

const CombatPlaybackControllerScript := preload("res://src/presentation/combat_playback_controller.gd")

var _session_controller: GameSessionController
var _map_presenter: ClassicMapPresenter
var _battlefield_presenter: ClassicBattlefieldPresenter
var _dungeon_presenter: DungeonMap3DPresenter
var _interaction_presenter: InteractionPresenter
var _shell_presenter: ClassicApplicationShell
var _audio_presenter: ClassicAudioPresenter
var _media: ClassicMediaCatalog
var _package_media: MediaSource
var _character_media: MediaSource
var _application_media := ApplicationMediaCatalog.new()
var _stock_music := ClassicMusicCatalog.new()
var _active_route: StringName = &"exploration"
var _play_stage_visible := false
var _combat_playback: CombatPlaybackController
var _presented_view: GameView
var _deferred_step: SessionStep
var _deferred_view: GameView
var _reduced_motion: bool = false
var _dungeon_3d_enabled: bool = true


func bind(session_controller: GameSessionController, map_presenter: ClassicMapPresenter, battlefield_presenter: ClassicBattlefieldPresenter, dungeon_presenter: DungeonMap3DPresenter, interaction_presenter: InteractionPresenter, shell_presenter: ClassicApplicationShell, audio_presenter: ClassicAudioPresenter) -> void:
	assert(session_controller != null, "Presentation requires a session controller")
	assert(map_presenter != null, "Presentation requires an explicit map presenter")
	assert(battlefield_presenter != null, "Presentation requires an explicit battlefield presenter")
	assert(dungeon_presenter != null, "Presentation requires an explicit topology-derived dungeon presenter")
	assert(interaction_presenter != null, "Presentation requires an explicit interaction presenter")
	assert(shell_presenter != null, "Presentation requires an explicit Classic shell presenter")
	assert(audio_presenter != null, "Presentation requires an explicit audio presenter")
	_session_controller = session_controller
	_map_presenter = map_presenter
	_battlefield_presenter = battlefield_presenter
	_dungeon_presenter = dungeon_presenter
	_interaction_presenter = interaction_presenter
	_shell_presenter = shell_presenter
	_audio_presenter = audio_presenter
	_combat_playback = CombatPlaybackControllerScript.new()
	_combat_playback.frame_changed.connect(_on_combat_playback_frame_changed)
	_combat_playback.sound_requested.connect(_on_combat_playback_sound_requested)
	_combat_playback.playback_finished.connect(_on_combat_playback_finished)
	_session_controller.step_committed.connect(_on_step_committed)
	_shell_presenter.play_stage_visibility_changed.connect(set_play_stage_visible)
	_shell_presenter.presentation_sound_requested.connect(_on_presentation_sound_requested)
	_interaction_presenter.combat_spellbook_requested.connect(func(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void:
		_interaction_presenter.set_combat_spellbook_open(true)
		_shell_presenter.present_combat_spellbook(actor_id, options)
	)
	_interaction_presenter.combat_spellbook_closed.connect(func() -> void:
		_interaction_presenter.set_combat_spellbook_open(false)
		_shell_presenter.close_combat_spellbook()
	)
	_shell_presenter.combat_spell_cast_requested.connect(func(option: InteractionRequestValue.CastOption) -> void: _interaction_presenter.cast_combat_spell(option))
	_shell_presenter.combat_spellbook_back_requested.connect(func() -> void: _interaction_presenter.close_combat_spellbook())
	set_package_media(null)
	_present_current_view()
	set_process(false)


func _process(delta: float) -> void:
	if _combat_playback == null or not _combat_playback.is_active():
		set_process(false)
		return
	_combat_playback.advance(delta, _audio_presenter.is_blocking())


func _on_step_committed(step: SessionStep) -> void:
	var game_view := _session_controller.view()
	var treasure_transfer_captured := _has_event(step.events, &"reward_item_assigned") and _interaction_presenter.capture_treasure_transfer()
	if _combat_playback != null and _combat_playback.begin(_presented_view, step.events, game_view, _reduced_motion):
		_deferred_step = step
		_deferred_view = game_view
		_present_view(_combat_playback.base_view, false)
		_interaction_presenter.present_combat_playback_mask(_combat_playback.current_frame())
		set_process(true)
		return
	_present_committed_step(step, game_view, true)
	if treasure_transfer_captured:
		_interaction_presenter.begin_treasure_transfer(_reduced_motion)
	playback_step_settled.emit(step)


static func _has_event(events: Array[DomainEvent], kind: StringName) -> bool:
	return events.any(func(event: DomainEvent) -> bool: return event.kind == kind)


func _present_committed_step(step: SessionStep, game_view: GameView, include_audio: bool) -> void:
	_present_view(game_view, false, false)
	_shell_presenter.present_step(step)
	_shell_presenter.present_media_events(step.events, _media)
	if include_audio:
		_audio_presenter.present_events(step.events, _media)
	var passive_classic_text := ""
	var classic_flash_messages: Array[Dictionary] = []
	for event: DomainEvent in step.events:
		if event.kind == &"message_shown" and event.payload.has("classicClick") and not bool(event.payload.get("classicClick", false)):
			passive_classic_text = String(event.payload.get("text", ""))
		if event.kind == &"player_map_acquired" and event.payload.has("notificationText"):
			classic_flash_messages.append({"text": String(event.payload.get("notificationText", "")), "soundId": int(event.payload.get("notificationSoundId", 0))})
		elif event.kind == &"classic_notification_requested":
			classic_flash_messages.append({"text": String(event.payload.get("text", "")), "soundId": int(event.payload.get("soundId", 0))})
	_present_interaction(game_view)
	refresh_music()
	if game_view.pending_interaction == null and not passive_classic_text.is_empty():
		_interaction_presenter.present_passive_classic_text(passive_classic_text)
	if not classic_flash_messages.is_empty():
		_interaction_presenter.queue_classic_flash_messages(classic_flash_messages)


func _on_combat_playback_frame_changed(frame: CombatPlaybackFrame) -> void:
	_battlefield_presenter.present_playback_frame(frame)
	_interaction_presenter.update_combat_playback_frame(frame)


func _on_combat_playback_sound_requested(event: DomainEvent) -> void:
	_audio_presenter.present_events([event], _media)


func _on_combat_playback_finished() -> void:
	set_process(false)
	_battlefield_presenter.clear_playback_frame()
	var step := _deferred_step
	var game_view := _deferred_view
	_deferred_step = null
	_deferred_view = null
	if step != null and game_view != null:
		_present_committed_step(step, game_view, false)
		playback_step_settled.emit(step)


func _on_presentation_sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool) -> void:
	_audio_presenter.present_sound(sound_id, _media, wait_for_completion, stop_existing, reduced_sound_eligible)


func set_package_media(media: MediaSource) -> void:
	_package_media = media
	_media = ClassicMediaCatalog.new(media, _application_media, _character_media)
	_map_presenter.set_media_catalog(_media)
	_battlefield_presenter.set_media_catalog(_media)
	_shell_presenter.set_package_media(_media)
	refresh_music()


func set_application_character_media(media: MediaSource) -> void:
	_character_media = media
	set_package_media(_package_media)


func package_media() -> ClassicMediaCatalog:
	return _media


func set_active_route(route_id: StringName) -> void:
	_active_route = route_id
	# The router has already mounted and rendered the destination workspace when
	# it emits the route change. Re-presenting the complete view here caused a
	# nested second projection/presentation pass, most visibly on combat entry.
	if _session_controller != null:
		_update_spatial_visibility(_session_controller.view())
		refresh_music()


func refresh_music() -> void:
	if _audio_presenter == null or _shell_presenter == null:
		return
	var view := _session_controller.view() if _session_controller != null else _presented_view
	_audio_presenter.present_music_context(ClassicMusicContext.playlist_for(_active_route, view), _shell_presenter.presentation_settings(), _media, _stock_music)


func set_play_stage_visible(visible: bool) -> void:
	_play_stage_visible = visible
	if _session_controller != null:
		_update_spatial_visibility(_session_controller.view())


func set_dungeon_3d_enabled(enabled: bool) -> void:
	_dungeon_3d_enabled = enabled
	_sync_dungeon_view(_session_controller.view() if _session_controller != null else null)
	_present_current_view()


func toggle_dungeon_view() -> bool:
	var game_view := _session_controller.view() if _session_controller != null else null
	if game_view == null or game_view.map_view == null or game_view.map_view.level_type != &"dungeon":
		return false
	if not dungeon_view_toggle_available(game_view.map_view):
		_shell_presenter.set_status("This dungeon is locked to the 3D view. Wizard's Eye permits the overhead view.")
		return true
	_dungeon_3d_enabled = not _dungeon_presenter.is_active()
	_sync_dungeon_view(game_view)
	_update_spatial_visibility(game_view)
	return true


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if _dungeon_presenter != null:
		_dungeon_presenter.set_reduced_motion(enabled)
	if enabled and is_combat_playback_active():
		skip_combat_playback()


func set_exploration_speed_percent(percent: int) -> void:
	if _dungeon_presenter != null:
		_dungeon_presenter.set_speed_percent(percent)


func set_combat_playback_speed_percent(percent: int) -> void:
	if _combat_playback != null:
		_combat_playback.set_speed_percent(percent)


func is_combat_playback_active() -> bool:
	return _combat_playback != null and _combat_playback.is_active()


func skip_combat_playback() -> bool:
	return _combat_playback != null and _combat_playback.skip()


func refresh() -> void:
	_present_current_view()


func refresh_spatial_projection() -> void:
	if _session_controller == null:
		return
	var game_view := _session_controller.view()
	_map_presenter.present(game_view)
	_dungeon_presenter.present(game_view)
	_presented_view = game_view
	_sync_dungeon_view(game_view)
	_update_spatial_visibility(game_view)


func present_host_interaction(request: InteractionRequest) -> void:
	_present_request(request, _session_controller.view(), request)


func dismiss_host_interaction() -> void:
	present_host_interaction(null)
	_present_current_view()


func present_host_workflow(game_view: GameView, step: SessionStep = null) -> void:
	# Character Files creation is application-owned rather than a campaign
	# session, but it still consumes the same detached view and interaction
	# contracts as the ordinary creator.
	_present_view(game_view, false)
	if step != null:
		_shell_presenter.present_step(step)
	_present_interaction(game_view)


func _present_current_view(include_interaction: bool = true) -> void:
	if is_combat_playback_active():
		_present_view(_combat_playback.base_view, false)
		var frame := _combat_playback.current_frame()
		if frame != null:
			_battlefield_presenter.present_playback_frame(frame)
		_interaction_presenter.present_combat_playback_mask(frame)
		return
	var game_view := _session_controller.view()
	_present_view(game_view, include_interaction)


func _present_view(game_view: GameView, include_interaction: bool = true, refresh_music_context: bool = true) -> void:
	var previous := _presented_view
	if previous == null or previous.domain_revisions.exploration != game_view.domain_revisions.exploration:
		_map_presenter.present(game_view)
		_dungeon_presenter.present(game_view)
	if previous == null or previous.domain_revisions.combat != game_view.domain_revisions.combat:
		_battlefield_presenter.present(game_view)
	_shell_presenter.present(game_view)
	_sync_dungeon_view(game_view)
	_update_spatial_visibility(game_view)
	_presented_view = game_view
	if include_interaction:
		_present_interaction(game_view)
	if refresh_music_context:
		refresh_music()


func _update_spatial_visibility(game_view: GameView) -> void:
	var exploration_visible := should_show_exploration_stage(_active_route, game_view, _play_stage_visible)
	var battle_visible := should_show_battle_stage(_active_route, game_view, _play_stage_visible)
	_map_presenter.visible = exploration_visible and not _dungeon_presenter.is_active()
	_dungeon_presenter.visible = exploration_visible and _dungeon_presenter.is_active()
	_battlefield_presenter.visible = battle_visible


func _sync_dungeon_view(game_view: GameView) -> void:
	var map_view := game_view.map_view if game_view != null else null
	var forced_3d := map_view != null and map_view.level_type == &"dungeon" and not dungeon_view_toggle_available(map_view)
	_dungeon_presenter.set_enabled(_dungeon_3d_enabled or forced_3d)


static func dungeon_view_toggle_available(map_view: MapView) -> bool:
	return map_view != null and map_view.level_type == &"dungeon" and (map_view.dungeon_multiview or map_view.wizard_eye_active)


static func should_show_exploration_stage(active_route: StringName, game_view: GameView, play_stage_visible: bool) -> bool:
	return active_route in [&"exploration", &"spells"] and game_view != null and game_view.session_started and play_stage_visible


static func should_show_spatial_stage(active_route: StringName, game_view: GameView, play_stage_visible: bool) -> bool:
	return should_show_exploration_stage(active_route, game_view, play_stage_visible)


static func should_show_battle_stage(active_route: StringName, game_view: GameView, play_stage_visible: bool) -> bool:
	return active_route == &"combat" and game_view != null and game_view.session_started and game_view.combat_view != null and game_view.combat_view.battlefield != null and play_stage_visible


func _present_interaction(game_view: GameView) -> void:
	_present_request(game_view.active_interaction_request(), game_view, game_view.pending_interaction)


func _present_request(request: InteractionRequest, game_view: GameView, character_selection_request: InteractionRequest) -> void:
	var enables_spatial_cursor := request == null
	if not enables_spatial_cursor:
		_map_presenter.set_movement_cursor_enabled(false)
		_dungeon_presenter.set_navigation_cursor_enabled(false)
	_shell_presenter.present_character_selection(character_selection_request)
	_interaction_presenter.present(request, _shell_presenter.latest_classic_text(), game_view, _media)
	if enables_spatial_cursor:
		_map_presenter.set_movement_cursor_enabled(true)
		_dungeon_presenter.set_navigation_cursor_enabled(true)
