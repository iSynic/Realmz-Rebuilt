class_name RealmzApplication
extends Control

const GameSessionControllerScript := preload("res://src/app/game_session_controller.gd")
const PresentationCoordinatorScript := preload("res://src/presentation/presentation_coordinator.gd")
const PackageRepositoryScript := preload("res://src/infrastructure/packages/package_repository.gd")
const PackageInstallTaskScript := preload("res://src/infrastructure/packages/package_install_task.gd")
const PackageOperationStatusScript := preload("res://src/infrastructure/packages/package_operation_status.gd")
const SaveRepositoryScript := preload("res://src/infrastructure/saves/save_repository.gd")
const CharacterVaultRepositoryScript := preload("res://src/infrastructure/characters/character_vault_repository.gd")
const SettingsRepositoryScript := preload("res://src/infrastructure/settings/settings_repository.gd")
const DungeonMap3DPresenterScript := preload("res://src/presentation/dungeon_map_3d_presenter.gd")
const ApplicationLifecycleScript := preload("res://src/app/application_lifecycle.gd")

@onready var _status_label: Label = $ClassicShell/BottomRegion/BottomRow/NarrativeWell/NarrativeColumn/Facts/Status
@onready var _smoke_button: Button = $ClassicShell/SmokeAction
@onready var _map_presenter: ClassicMapPresenter = %ExplorationMap
@onready var _battlefield_presenter: ClassicBattlefieldPresenter = %BattlefieldMap
@onready var _interaction_presenter: InteractionPresenter = %InteractionPanel
@onready var _shell_presenter: ClassicApplicationShell = $ClassicShell
@onready var _classic_shell: ClassicApplicationShell = $ClassicShell
@onready var _audio_presenter: ClassicAudioPresenter = %ClassicAudio

var session_controller: GameSessionController
var presentation_coordinator: PresentationCoordinator
var package_repository: PackageRepository
var save_repository: SaveRepository
var character_vault_repository: CharacterVaultRepository
var settings_repository: SettingsRepository
var _active_content: RealmzContent
var _presentation_settings: PresentationSettings
var _dungeon_presenter: DungeonMap3DPresenter
var _host_interaction: InteractionRequest
var _package_install_task: RefCounted
var _pending_package_seed: int = 1
var _last_package_operation_key: String = ""


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	UiInputActions.ensure_defaults()
	package_repository = PackageRepositoryScript.new()
	_package_install_task = PackageInstallTaskScript.new()
	save_repository = SaveRepositoryScript.new()
	character_vault_repository = CharacterVaultRepositoryScript.new()
	settings_repository = SettingsRepositoryScript.new()
	_presentation_settings = settings_repository.load_settings()
	session_controller = GameSessionControllerScript.new()
	presentation_coordinator = PresentationCoordinatorScript.new()
	_dungeon_presenter = DungeonMap3DPresenterScript.new()
	add_child(session_controller)
	add_child(presentation_coordinator)
	add_child(_dungeon_presenter)
	presentation_coordinator.bind(session_controller, _map_presenter, _battlefield_presenter, _dungeon_presenter, _interaction_presenter, _shell_presenter, _audio_presenter)
	_interaction_presenter.response_submitted.connect(_on_interaction_response_submitted)
	_interaction_presenter.presentation_action_requested.connect(_on_combat_presentation_action_requested)
	_map_presenter.movement_requested.connect(_on_map_movement_requested)
	_battlefield_presenter.tactical_action_requested.connect(_on_battlefield_action_requested)
	_battlefield_presenter.combatant_inspected.connect(_on_battlefield_combatant_inspected)
	_shell_presenter.start_package_requested.connect(_begin_package_start)
	_shell_presenter.cancel_package_requested.connect(_cancel_package_start)
	_shell_presenter.refresh_campaigns_requested.connect(_refresh_campaigns)
	_shell_presenter.intent_submitted.connect(_submit_intent)
	_shell_presenter.save_requested.connect(save_active_session)
	_shell_presenter.load_requested.connect(load_active_session)
	_shell_presenter.load_backup_requested.connect(load_backup_session)
	_shell_presenter.refresh_saves_requested.connect(_refresh_save_previews)
	_shell_presenter.end_adventure_requested.connect(_on_end_adventure_requested)
	_shell_presenter.quit_requested.connect(_on_quit_requested)
	_shell_presenter.topology_debug_changed.connect(_on_topology_debug_changed)
	_shell_presenter.dungeon_3d_changed.connect(_on_dungeon_3d_changed)
	_shell_presenter.master_volume_changed.connect(_on_master_volume_changed)
	_shell_presenter.text_scale_changed.connect(_on_text_scale_changed)
	_shell_presenter.ui_scale_mode_changed.connect(_on_ui_scale_mode_changed)
	_shell_presenter.window_mode_changed.connect(_on_window_mode_changed)
	_shell_presenter.reduced_motion_changed.connect(_on_reduced_motion_changed)
	_shell_presenter.layout_changed.connect(_on_shell_layout_changed)
	_shell_presenter.route_changed.connect(presentation_coordinator.set_active_route)
	_shell_presenter.vault_archive_requested.connect(_archive_vault_character)
	_shell_presenter.vault_restore_requested.connect(_restore_vault_revision)
	_shell_presenter.apply_settings(_presentation_settings)
	_apply_application_theme(_presentation_settings.text_scale)
	_interaction_presenter.set_text_scale(_presentation_settings.text_scale)
	_apply_window_mode(_presentation_settings.window_mode)
	_audio_presenter.set_master_volume(_presentation_settings.master_volume)
	_on_topology_debug_changed(_presentation_settings.topology_debug)
	_on_dungeon_3d_changed(_presentation_settings.dungeon_3d)
	_status_label.text = "Pure session boundary online"
	_refresh_campaigns()
	_refresh_vault_views()
	set_process(true)


func _process(_delta: float) -> void:
	if _package_install_task == null:
		return
	var operation: RefCounted = _package_install_task.snapshot()
	var operation_key := "%s:%s:%d:%d:%s" % [operation.state, operation.phase, operation.completed, operation.total, operation.message]
	if operation_key != _last_package_operation_key:
		_last_package_operation_key = operation_key
		_shell_presenter.set_package_operation(operation)
		_shell_presenter.set_status(operation.message, operation.state == PackageOperationStatusScript.FAILED)
	if operation.is_running() or operation.state == PackageOperationStatusScript.IDLE:
		return
	var installation: PackageInstallResult = _package_install_task.take_result()
	_shell_presenter.set_package_operation(PackageOperationStatusScript.new())
	_last_package_operation_key = ""
	if operation.state == PackageOperationStatusScript.CANCELLED:
		_shell_presenter.set_status("Package validation cancelled.")
		return
	_complete_package_install(installation, _pending_package_seed)


func _exit_tree() -> void:
	if _package_install_task != null:
		_package_install_task.shutdown()


func _on_smoke_action_pressed() -> void:
	_smoke_button.release_focus()
	if not session_controller.view().session_started:
		_status_label.text = "MCP input verified • no package loaded"
		return
	var step := _submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	if step.state == SessionStep.State.FAILED:
		return
	var roll: int = step.events[0].payload.get("roll", 0)
	var current_view := session_controller.view()
	_status_label.text = "Search committed • roll %d • day %d %02d:%02d" % [roll, current_view.realmz_day, current_view.realmz_hour, current_view.realmz_minute]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_quit_requested()


func _on_quit_requested() -> void:
	if _host_interaction != null:
		return
	var current_view := session_controller.view()
	var combat_view := current_view.combat_view
	var in_combat := combat_view != null and combat_view.outcome == &"active"
	_host_interaction = ApplicationLifecycleScript.quit_application_request(current_view.session_started, in_combat)
	presentation_coordinator.present_host_interaction(_host_interaction)
	_shell_presenter.set_status("Confirm whether to quit Realmz 2.")


func _on_end_adventure_requested() -> void:
	if not session_controller.view().session_started:
		_shell_presenter.show_campaign_selection()
		return
	var pending := session_controller.view().pending_interaction
	if pending != null and pending.kind != InteractionRequest.COMBAT:
		_shell_presenter.set_status("Resolve the current interaction before ending the adventure.", true)
		return
	if _host_interaction != null:
		return
	var combat_view := session_controller.view().combat_view
	var in_combat := combat_view != null and combat_view.outcome == &"active"
	_host_interaction = ApplicationLifecycleScript.end_adventure_request(in_combat)
	presentation_coordinator.present_host_interaction(_host_interaction)
	_shell_presenter.set_status("Choose how to end the active adventure.")


func start_package(package_path: String, initial_seed: int) -> SessionStep:
	if session_controller.view().session_started:
		return SessionStep.failed(session_controller.view().revision, &"session_already_started", "End the active adventure before starting another campaign.")
	var installation := package_repository.install_package(package_path)
	return _complete_package_install(installation, initial_seed)


func _begin_package_start(package_path: String, initial_seed: int) -> void:
	if session_controller.view().session_started:
		_shell_presenter.set_status("End the active adventure before starting another campaign.", true)
		return
	if _package_install_task.snapshot().is_running():
		return
	_pending_package_seed = initial_seed
	if not _package_install_task.start(package_path):
		_shell_presenter.set_status(_package_install_task.snapshot().message, true)
		return
	_shell_presenter.set_package_operation(_package_install_task.snapshot())
	_shell_presenter.set_status("Preparing package validation…")


func _cancel_package_start() -> void:
	if _package_install_task != null:
		_package_install_task.cancel()


func _complete_package_install(installation: PackageInstallResult, initial_seed: int) -> SessionStep:
	if installation == null:
		_status_label.text = "Package rejected • package operation returned no result"
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(0, &"package_operation_failed", "Package operation returned no result.")
	if not installation.is_ok():
		_status_label.text = "Package rejected • %s" % installation.error_message
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(0, installation.error_code, installation.error_message)
	var package_result := installation.package
	var step := session_controller.start(package_result.content, initial_seed)
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Session start failed • %s" % step.error_message
		_shell_presenter.set_status(_status_label.text, true)
		return step
	_active_content = package_result.content
	presentation_coordinator.set_package_media(package_result.media)
	presentation_coordinator.refresh()
	_refresh_save_previews()
	_refresh_vault_views()
	_smoke_button.text = "Search area"
	var current_view := session_controller.view()
	_status_label.text = "Loaded %s • %s %d,%d • seed %d" % [_active_content.campaign_id, current_view.party_map_id, current_view.party_coordinate.x, current_view.party_coordinate.y, initial_seed]
	_shell_presenter.set_status(_status_label.text)
	_refresh_campaigns()
	return step


func _input(event: InputEvent) -> void:
	var pending := session_controller.view().pending_interaction
	var combat_pending := pending != null and pending.kind == InteractionRequest.COMBAT
	if combat_pending and event.is_action_pressed(&"realmz_inspect_movement"):
		_battlefield_presenter.set_movement_costs_visible(true)
		get_viewport().set_input_as_handled()
		return
	if combat_pending and event.is_action_released(&"realmz_inspect_movement"):
		_battlefield_presenter.set_movement_costs_visible(false)
		get_viewport().set_input_as_handled()
		return
	if not event.is_pressed():
		return
	if combat_pending and _battlefield_presenter.dismiss_reveal_friends():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"realmz_back"):
		if _interaction_presenter.has_blocking_request():
			_shell_presenter.set_status("Choose a response before leaving this interaction.")
			get_viewport().set_input_as_handled()
			return
		if _interaction_presenter.dismiss_passive_text() or _shell_presenter.handle_back():
			get_viewport().set_input_as_handled()
			return
	if _host_interaction != null:
		return
	if pending != null:
		if pending.kind == InteractionRequest.COMBAT:
			var combat_direction := UiInputActions.movement_direction(event)
			if combat_direction != Vector2i.ZERO and _interaction_presenter.accepts_combat_spatial_input() and _battlefield_presenter.submit_movement_direction(combat_direction):
				get_viewport().set_input_as_handled()
		return
	if _shell_presenter.handle_route_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	if not session_controller.view().session_started:
		return
	if not _shell_presenter.accepts_exploration_input():
		return
	if event.is_action_pressed(&"realmz_search"):
		_submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"realmz_camp"):
		_submit_intent(PlayerIntent.camp())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"realmz_rest"):
		_submit_intent(PlayerIntent.rest())
		get_viewport().set_input_as_handled()
		return
	var direction := UiInputActions.movement_direction(event)
	if direction != Vector2i.ZERO:
		_submit_movement(direction)
		get_viewport().set_input_as_handled()


func _on_map_movement_requested(direction: Vector2i) -> void:
	_submit_movement(direction)


func _on_battlefield_action_requested(payload: Dictionary) -> void:
	if _interaction_presenter.accepts_combat_spatial_input():
		_interaction_presenter.submit_active_payload(payload)


func _on_battlefield_combatant_inspected(combatant_id: String) -> void:
	_interaction_presenter.inspect_combatant(combatant_id)


func _on_combat_presentation_action_requested(action: StringName, payload: Dictionary) -> void:
	match action:
		&"focus_combatant":
			var combatant_id := String(payload.get("combatantId", ""))
			_battlefield_presenter.focus_combatant(combatant_id)
			_interaction_presenter.inspect_combatant(combatant_id)
			if bool(payload.get("playSound", false)):
				_audio_presenter.present_sound(147, presentation_coordinator.package_media())
		&"toggle_reveal_friends":
			_battlefield_presenter.toggle_reveal_friends()
			_audio_presenter.present_sound(137, presentation_coordinator.package_media())


func _submit_movement(direction: Vector2i) -> void:
	if not _shell_presenter.accepts_exploration_input() or not session_controller.view().session_started or session_controller.view().pending_interaction != null:
		return
	var map_view := session_controller.view().map_view
	if MapTopology.is_diagonal_direction(direction) and (map_view == null or map_view.level_type != &"land"):
		return
	_submit_intent(PlayerIntent.move(direction))


func _submit_intent(intent: PlayerIntent) -> SessionStep:
	if intent != null and intent.kind == PlayerIntent.Kind.IMPORT_VAULT_CHARACTER:
		var record := character_vault_repository.load_revision(intent.target_id, intent.revision_hash)
		if record == null:
			var failed := SessionStep.failed(session_controller.view().revision, &"vault_load_failed", character_vault_repository.last_error if not character_vault_repository.last_error.is_empty() else "The requested vault revision is unavailable.")
			_present_step_status(failed)
			return failed
		intent = PlayerIntent.import_vault_character(record.character_id, record.revision_hash, record.state.to_data(), record.source_campaign_id, record.source_package_hash)
	var step := session_controller.submit_intent(intent)
	_present_step_status(step)
	return step


func _on_interaction_response_submitted(response: InteractionResponse) -> void:
	if _host_interaction != null:
		_respond_host_interaction(response)
		return
	var step := session_controller.respond(response)
	_present_step_status(step)


func _respond_host_interaction(response: InteractionResponse) -> void:
	var action := ApplicationLifecycleScript.response_action(_host_interaction, response)
	if action.is_empty():
		_shell_presenter.set_status("The lifecycle response was invalid.", true)
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	var operation := StringName(_host_interaction.payload.get("operation", &""))
	if operation == &"quit-application":
		_respond_quit_interaction(action)
		return
	if operation != &"end-adventure":
		_shell_presenter.set_status("The lifecycle operation was invalid.", true)
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	var result := ApplicationLifecycleScript.execute_end_adventure(
		action,
		func() -> bool: return save_active_session("quick"),
		func() -> SessionStep: return session_controller.close()
	)
	var result_state := StringName(result.get("state", &"invalid"))
	if result_state == &"cancelled":
		_host_interaction = null
		presentation_coordinator.refresh()
		_shell_presenter.set_status("Adventure continues.")
		return
	if result_state == &"save-failed":
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	if result_state == &"close-failed":
		var failed_step: SessionStep = result.get("step")
		var error_message := failed_step.error_message if failed_step != null else "The session close operation is unavailable."
		_shell_presenter.set_status("End Adventure failed • %s" % error_message, true)
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	if result_state == &"pending":
		_host_interaction = null
		var pending_step: SessionStep = result.get("step")
		_present_step_status(pending_step)
		return
	if result_state != &"closed":
		_shell_presenter.set_status("The lifecycle response was invalid.", true)
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	_complete_closed_session()


func _respond_quit_interaction(action: StringName) -> void:
	var has_active_session := session_controller.view().session_started
	var result_state := ApplicationLifecycleScript.execute_quit(
		action,
		func() -> bool: return save_active_session("quick") if has_active_session else false,
		_quit_application
	)
	if result_state == &"cancelled":
		_host_interaction = null
		presentation_coordinator.refresh()
		_shell_presenter.set_status("Quit cancelled.")
		return
	if result_state == &"save-failed":
		presentation_coordinator.present_host_interaction(_host_interaction)
		return
	if result_state != &"quit-requested":
		_shell_presenter.set_status("Quit failed • the application remains open.", true)
		presentation_coordinator.present_host_interaction(_host_interaction)


func _quit_application() -> void:
	if _package_install_task != null:
		_package_install_task.shutdown()
	get_tree().quit()


func _complete_closed_session() -> void:
	_host_interaction = null
	_active_content = null
	presentation_coordinator.set_package_media(null)
	_refresh_save_previews()
	_refresh_vault_views()
	_refresh_campaigns()
	_shell_presenter.show_campaign_selection()
	_status_label.text = "Adventure ended • choose a campaign"
	_shell_presenter.set_status(_status_label.text)


func _present_step_status(step: SessionStep) -> void:
	if step.state == SessionStep.State.FAILED:
		_status_label.text = "Action failed • %s" % step.error_message
		_shell_presenter.set_status(_status_label.text, true)
		return
	for event: DomainEvent in step.events:
		if event.kind == &"session_ended":
			_complete_closed_session()
			return
		match event.kind:
			&"character_draft_generated":
				_status_label.text = "Classic character roll ready for review"
			&"character_draft_spells_changed":
				_status_label.text = "%d starting-spell points remain" % event.payload.get("remaining", 0)
			&"character_spell_confirmation_requested":
				_status_label.text = "%d starting-spell points remain • confirm acceptance" % event.payload.get("remaining", 0)
			&"character_spell_confirmation_declined":
				_status_label.text = "Choose more starting spells or accept the remaining points"
			&"character_draft_cancelled":
				_status_label.text = "Character creation cancelled"
			&"character_finalized":
				_status_label.text = "Character added to party setup"
			&"character_vault_confirmation_requested":
				_status_label.text = "Character added • choose whether to publish a reusable vault revision"
			&"character_publication_requested":
				_publish_character_revision(String(event.payload.get("characterId", "")))
			&"character_publication_declined":
				_status_label.text = "Character kept in this campaign party only"
			&"vault_character_imported":
				_status_label.text = "Vault character added to party setup"
			&"party_member_removed":
				_status_label.text = "Character removed from party setup"
			&"party_created":
				_status_label.text = "Party assembled • the adventure begins"
			&"character_age_changed":
				_status_label.text = "%s entered a new age group" % event.payload.get("characterName", "A party member")
			&"message_shown":
				_status_label.text = "Scenario text" if event.payload.has("classicClick") else event.payload.get("text", "Message")
			&"map_transitioned":
				_status_label.text = "Entered %s" % event.payload.get("targetMapId", "map")
			&"movement_blocked":
				_status_label.text = "Blocked • %s" % event.payload.get("reason", "unknown")
	if step.state == SessionStep.State.WAITING_FOR_INTERACTION:
		if step.interaction.kind == &"acknowledge" and step.interaction.payload.get("presentation") == "classic-textbox":
			_status_label.text = "Scenario text • continue when ready"
		else:
			_status_label.text = String(step.interaction.payload.get("prompt", "Choose an option"))


func _publish_character_revision(character_id: String) -> bool:
	if _active_content == null or character_id.is_empty():
		_status_label.text = "Vault publication failed • no active character or campaign"
		return false
	var boundary := session_controller.session().snapshot()
	if boundary == null:
		_status_label.text = "Vault publication failed • the session is not at a committed boundary"
		return false
	var source_character := boundary.game_state.party.character_by_id(character_id)
	if source_character == null:
		_status_label.text = "Vault publication failed • the character is unavailable"
		return false
	var character := CharacterState.from_data(source_character.to_data())
	if character == null:
		_status_label.text = "Vault publication failed • the character state is invalid"
		return false
	var record := CharacterVaultRecord.new(character.id, _active_content.rules_version, _active_content.campaign_id, _active_content.package_hash, character)
	record.publication_metadata = {"name": character.name, "level": character.level, "source": "character-creation"}
	if not character_vault_repository.publish_revision(record):
		_status_label.text = "Vault publication failed • %s" % character_vault_repository.last_error
		return false
	_refresh_vault_views()
	_status_label.text = "Published %s to the character vault" % character.name
	return true


func _refresh_vault_views() -> void:
	var revisions: Array[CharacterVaultRevisionView] = []
	for character_id: String in character_vault_repository.list_character_ids():
		var current_hash := character_vault_repository.current_revision_hash(character_id)
		var character_archived := current_hash.is_empty()
		for record: CharacterVaultRecord in character_vault_repository.list_revisions(character_id):
			var eligibility := character_vault_repository.campaign_eligibility(record, _active_content) if _active_content != null else null
			revisions.append(CharacterVaultRevisionView.from_record(record, eligibility, record.revision_hash == current_hash, character_archived, _active_content))
	revisions.sort_custom(func(left: CharacterVaultRevisionView, right: CharacterVaultRevisionView) -> bool:
		var character_order := left.character_id.naturalnocasecmp_to(right.character_id)
		if character_order != 0:
			return character_order < 0
		if left.is_current != right.is_current:
			return left.is_current
		return left.revision_hash < right.revision_hash
	)
	_classic_shell.set_vault_revisions(revisions)


func _archive_vault_character(character_id: String) -> void:
	if not character_vault_repository.archive_character(character_id):
		_status_label.text = "Vault archive failed • %s" % character_vault_repository.last_error
		_shell_presenter.set_status(_status_label.text, true)
		return
	_refresh_vault_views()
	_status_label.text = "Character archived • immutable revisions remain recoverable"
	_shell_presenter.set_status(_status_label.text)


func _restore_vault_revision(character_id: String, revision_hash: String) -> void:
	if not character_vault_repository.restore_revision(character_id, revision_hash):
		_status_label.text = "Vault restore failed • %s" % character_vault_repository.last_error
		_shell_presenter.set_status(_status_label.text, true)
		return
	_refresh_vault_views()
	_status_label.text = "Character revision restored as current"
	_shell_presenter.set_status(_status_label.text)


func save_active_session(slot_id: String) -> bool:
	if _active_content == null:
		_status_label.text = "Save failed • no package loaded"
		_shell_presenter.set_status(_status_label.text, true)
		return false
	var saved := save_repository.save(_active_content.campaign_id, slot_id, session_controller.session().snapshot())
	_status_label.text = "Saved %s" % slot_id if saved else "Save failed • %s" % save_repository.last_error
	_shell_presenter.set_status(_status_label.text, not saved)
	if saved:
		_refresh_save_previews()
	return saved


func load_active_session(slot_id: String) -> SessionStep:
	return _load_session_record(slot_id, false)


func load_backup_session(slot_id: String) -> SessionStep:
	return _load_session_record(slot_id, true)


func _load_session_record(slot_id: String, backup: bool) -> SessionStep:
	if _active_content == null:
		_status_label.text = "Load failed • no package loaded"
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(0, "no_package_loaded", "Load a package before restoring a save.")
	var envelope := save_repository.load_backup(_active_content.campaign_id, slot_id, _active_content.package_hash) if backup else save_repository.load(_active_content.campaign_id, slot_id, _active_content.package_hash)
	if envelope == null:
		_status_label.text = "Load failed • %s" % save_repository.last_error
		_shell_presenter.set_status(_status_label.text, true)
		return SessionStep.failed(session_controller.view().revision, "save_load_failed", save_repository.last_error)
	var step := session_controller.restore(_active_content, envelope)
	_status_label.text = "Loaded %s %s" % ["backup" if backup else "save", slot_id] if step.state != SessionStep.State.FAILED else "Load failed • %s" % step.error_message
	_shell_presenter.set_status(_status_label.text, step.state == SessionStep.State.FAILED)
	return step


func _refresh_save_previews() -> void:
	var previews: Array = []
	if _active_content != null:
		previews = save_repository.list_previews(_active_content.campaign_id, _active_content.package_hash)
	_shell_presenter.set_save_previews(previews)


func _refresh_campaigns() -> void:
	if _package_install_task != null and _package_install_task.snapshot().is_running():
		return
	_shell_presenter.set_campaigns(package_repository.discover_campaigns(["user://packages"]))


func _on_topology_debug_changed(enabled: bool) -> void:
	_map_presenter.show_debug_facts = enabled
	_map_presenter.queue_redraw()
	if _presentation_settings != null:
		_presentation_settings.topology_debug = enabled
		settings_repository.save_settings(_presentation_settings)


func _on_dungeon_3d_changed(enabled: bool) -> void:
	presentation_coordinator.set_dungeon_3d_enabled(enabled)
	if _presentation_settings != null:
		_presentation_settings.dungeon_3d = enabled
		settings_repository.save_settings(_presentation_settings)


func _on_master_volume_changed(value: float) -> void:
	_audio_presenter.set_master_volume(value)
	_presentation_settings.master_volume = value
	settings_repository.save_settings(_presentation_settings)


func _on_text_scale_changed(value: float) -> void:
	_presentation_settings.text_scale = value
	_apply_application_theme(value)
	_interaction_presenter.set_text_scale(value)
	_shell_presenter.apply_settings(_presentation_settings)
	settings_repository.save_settings(_presentation_settings)


func _on_ui_scale_mode_changed(value: String) -> void:
	_presentation_settings.ui_scale_mode = value
	_shell_presenter.apply_settings(_presentation_settings)
	settings_repository.save_settings(_presentation_settings)


func _on_window_mode_changed(value: String) -> void:
	_presentation_settings.window_mode = value
	_apply_window_mode(value)
	settings_repository.save_settings(_presentation_settings)


func _apply_window_mode(value: String) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if value == PresentationSettings.BORDERLESS_FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func _apply_application_theme(text_scale: float) -> void:
	var base_theme := load("res://src/presentation/classic_ui_theme.tres") as Theme
	var application_theme := base_theme.duplicate(true) as Theme
	application_theme.default_font_size = int(round(15.0 * text_scale))
	theme = application_theme


func _on_shell_layout_changed(workspace_rect: Rect2, _profile: UiLayoutProfile) -> void:
	var inset := 8.0
	var content_rect := workspace_rect.grow(-inset)
	_map_presenter.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_map_presenter.position = content_rect.position
	_map_presenter.size = content_rect.size
	_battlefield_presenter.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_battlefield_presenter.position = content_rect.position
	_battlefield_presenter.size = content_rect.size
	if _dungeon_presenter != null:
		_dungeon_presenter.position = content_rect.position
		_dungeon_presenter.size = content_rect.size
	var textbox_rect := classic_textbox_rect(workspace_rect, _profile.bottom_height)
	_interaction_presenter.set_classic_regions(content_rect, textbox_rect, classic_combat_rect(size, _profile.bottom_height))


static func classic_textbox_rect(workspace_rect: Rect2, bottom_height: float) -> Rect2:
	return Rect2(workspace_rect.position.x, workspace_rect.end.y, workspace_rect.size.x, bottom_height)


static func classic_combat_rect(viewport_size: Vector2, bottom_height: float) -> Rect2:
	return Rect2(0.0, maxf(0.0, viewport_size.y - bottom_height), viewport_size.x, minf(bottom_height, viewport_size.y))


func _on_reduced_motion_changed(enabled: bool) -> void:
	_presentation_settings.reduced_motion = enabled
	settings_repository.save_settings(_presentation_settings)
