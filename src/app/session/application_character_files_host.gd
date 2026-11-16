## Owns the application Character Files library, vault, and standalone creator.
class_name ApplicationCharacterFilesHost
extends RefCounted

var _package_host: PackageHostController
var _session: GameSessionController
var _presentation: PresentationCoordinator
var _presentation_media: PresentationMediaController
var _shell: GameShell
var _vault: CharacterVaultController
var _creator := CharacterCreationHostController.new()
var _library_content: RealmzContent
var _library_media: MediaSource
var _library_load_complete := false
var _art_host: ApplicationCharacterArtHost
## Reads the application's current campaign content; an editor draft can outlive a scenario change.
var _active_content_source: Callable


func _init(
	package_host: PackageHostController,
	session: GameSessionController,
	presentation: PresentationCoordinator,
	presentation_media: PresentationMediaController,
	shell: GameShell,
	vault: CharacterVaultController = null,
	art_host: ApplicationCharacterArtHost = null,
	active_content_source: Callable = Callable()
) -> void:
	_package_host = package_host
	_session = session
	_presentation = presentation
	_presentation_media = presentation_media
	_shell = shell
	_vault = vault if vault != null else CharacterVaultController.new()
	_art_host = art_host
	_active_content_source = active_content_source


func begin_library_load() -> void:
	if _package_host.start_bundled_load(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH):
		return
	_library_load_complete = true
	_shell.navigator.setup_controller.character_creation.set_standalone_character_creation_available(false, "The built-in Classic definitions could not start loading.")


func poll_library_load(active_content: RealmzContent) -> bool:
	if _library_load_complete or _package_host == null or _package_host.bundled_load_is_running():
		return false
	var prepared := _package_host.take_bundled_package(ApplicationLibraryIdentity.PATH)
	if prepared == null:
		return false
	_library_load_complete = true
	if not prepared.is_ok():
		_shell.navigator.setup_controller.character_creation.set_standalone_character_creation_available(false, prepared.error_message)
		_shell.status.set_status("Character Files creation unavailable • %s" % prepared.error_message, true)
		return true
	_library_content = prepared.content
	_library_media = prepared.media
	_package_host.set_application_content(_library_content, _library_media.assets())
	_presentation_media.set_application_character_media(_library_media)
	if _art_host != null:
		_art_host.set_stock_catalog(_library_content.characters)
	if active_content == null:
		_presentation_media.set_package_media(_library_media)
	_vault.seed_classic_starters_if_empty(CharacterVaultController.CLASSIC_STARTER_CATALOG_PATH, _library_content.package_hash, _library_content)
	_shell.navigator.setup_controller.character_creation.set_standalone_character_creation_available(true)
	refresh_vault_views(active_content)
	return true


func library_ready() -> bool:
	return _library_load_complete


func library_content() -> RealmzContent:
	return _library_content


func library_media() -> MediaSource:
	return _library_media


func creator_active() -> bool:
	return _creator.is_active()


func submit_creator_intent(intent: PlayerIntent) -> SessionStep:
	var step := _creator.submit(intent)
	_present_creator_step(step)
	return step


func respond_to_creator(response: InteractionResponse) -> void:
	_present_creator_step(_creator.respond(response))


func begin_creation(active_content: RealmzContent) -> void:
	if active_content != null or _session.view().session_started:
		_shell.status.set_status("Finish the current campaign setup before opening the general Character Files creator.", true)
		return
	if _library_content == null:
		_shell.status.set_status("Character Files creation is unavailable because the built-in Classic definitions did not load.", true)
		return
	var identity := _vault.next_character_file_identity()
	if identity == null:
		_shell.status.set_status("Character Files creation failed • %s" % _vault.last_error(), true)
		return
	var step := _creator.start(_library_content, identity)
	if step.state == SessionStep.State.FAILED:
		_shell.status.set_status("Character Files creation failed • %s" % step.error_message, true)
		return
	_presentation_media.set_package_media(_library_media)
	_presentation.present_host_workflow(_creator.view(), step)
	_shell.navigator.setup_controller.character_creation.begin_standalone_character_creation()
	_shell.status.set_status("Create a reusable character with the built-in Realmz races and classes.")


func cancel_creation(active_content: RealmzContent) -> void:
	if _creator.is_active():
		_finish_creation(active_content, "Character creation cancelled.")


func publish_campaign_character(active_content: RealmzContent, character_id: String) -> bool:
	if (_session.is_busy() or _session.resolution_failed):
		_shell.status.set_status("Combat resolution failed. Load a saved adventure or return to the main menu." if _session.resolution_failed else "Wait for combat resolution before publishing a character.", true)
		return false
	var snapshot := _session.session().snapshot()
	var source_character := snapshot.game_state.party.character_by_id(character_id) if snapshot != null and not character_id.is_empty() else null
	var character_name := _vault.publish_party_character(source_character, active_content, "character-creation")
	if character_name.is_empty():
		_shell.status.set_status("Vault publication failed • %s" % _vault.last_error(), true)
		return false
	refresh_vault_views(active_content)
	_shell.status.set_status("Published %s to the character vault" % character_name)
	return true


## The Character Files controller, shared with the save editor.
func vault() -> CharacterVaultController:
	return _vault


func vault_import_intent(character_id: String, revision_hash: String) -> PlayerIntent:
	if _art_host != null and not _art_host.install_bundle(_vault.artwork_bundle(character_id, revision_hash)):
		_shell.status.set_status("Character artwork could not be installed • %s" % _art_host.last_error, true)
		return null
	return _vault.import_intent(character_id, revision_hash)


func vault_error() -> String:
	return _vault.last_error()


func refresh_vault_views(active_content: RealmzContent) -> void:
	if _library_content != null:
		_vault.configure_rule_sources(_library_content, _package_host.saved_party_catalog.discover())
	var revisions := _vault.revisions(active_content, _library_content)
	if _art_host != null:
		for bundle: CharacterArtBundle in _vault.artwork_bundles():
			if not _art_host.install_bundle(bundle):
				_shell.status.set_status("Character artwork could not be installed • %s" % _art_host.last_error, true)
				break
	_shell.navigator.set_vault_revisions(revisions, _vault.unavailable_notice())


## Applies one player-confirmed Character Files change: archive, restore or delete.
func change_character(active_content: RealmzContent, operation: StringName, character_id: String, revision_hash: String) -> void:
	if operation == &"edit":
		_begin_edit(active_content, character_id, revision_hash)
		return
	if operation not in [&"archive", &"restore", &"delete"]:
		return
	if operation in [&"archive", &"delete"] and _in_party(character_id):
		_report_change("Character Files couldn't be changed • This character is in the party.", true)
		return
	var changed := _vault.change_character(operation, character_id, revision_hash)
	refresh_vault_views(active_content)
	if not changed:
		_report_change("Character Files couldn't be changed • %s" % _vault.last_error(), true)
		return
	var messages := {&"archive": "Character archived. Find it under Archived; every revision can be restored.", &"restore": "Character restored and active again.", &"delete": "Character deleted permanently."}
	_report_change(messages[operation], false)


## Opens the editor on the current revision against the stock library rules.
func _begin_edit(active_content: RealmzContent, character_id: String, revision_hash: String) -> void:
	if not library_ready():
		_report_change("The character editor opens once the stock character library has loaded.", true)
		return
	var edit := _vault.begin_edit(character_id, revision_hash, _library_content)
	if edit == null:
		_report_change("This character can't be edited • %s" % _vault.last_error(), true)
		return
	var editor := CharacterEditorSession.new(edit, _library_content)
	editor.closed.connect(func(message: String, is_error: bool) -> void:
		refresh_vault_views(_active_content_source.call() as RealmzContent if _active_content_source.is_valid() else active_content)
		_shell.navigator.content_presenter.characters.close_editor()
		if not message.is_empty():
			_report_change(message, is_error)
	)
	_shell.navigator.content_presenter.characters.present_editor(editor)


func _in_party(character_id: String) -> bool:
	for member: CharacterView in _session.view().party_members:
		if member.id == character_id:
			return true
	return false


func _report_change(text: String, is_error: bool) -> void:
	_shell.status.set_status(text, is_error)
	# The full-stage Character Files route hides the shell status line, so it shows its own notice.
	_shell.navigator.content_presenter.present_vault_status(text, is_error)


func request_maintenance(operation: StringName) -> void:
	if operation == &"cancel":
		_vault.cancel_repair_review()
	elif operation == &"open_backup":
		var path := _vault.repair_backup_path()
		if not path.is_empty() and OS.shell_open(path) != OK:
			_shell.status.set_status("Could not open the backup folder • %s" % path, true)
	elif not _vault.start_maintenance(operation):
		_shell.navigator.content_presenter.characters.present_repair(_vault.last_error(), false, false, false)


func poll_repair(active_content: RealmzContent) -> void:
	var result := _vault.poll_repair()
	if result.is_empty():
		return
	if not result.review: refresh_vault_views(active_content)
	_shell.navigator.content_presenter.characters.present_repair(result.details, result.review, result.canRepair, result.hasBackup)


func shutdown() -> void:
	_vault.shutdown_repair()


func _present_creator_step(step: SessionStep) -> void:
	if not _creator.is_active():
		return
	_presentation.present_host_workflow(_creator.view(), step)
	if step.state == SessionStep.State.FAILED:
		_shell.status.set_status("Character creation failed • %s" % step.error_message, true)
		return
	for event: DomainEvent in step.events:
		if event.kind == &"character_publication_requested":
			_publish_standalone_character()
			return


func _publish_standalone_character() -> void:
	var character := _creator.completed_character()
	if character == null:
		_shell.status.set_status("Character File publication failed • the completed character is unavailable.", true)
		return
	if not _vault.publish(character, _library_content.rules_version, "", _library_content.package_hash, "classic-application", _library_content):
		_shell.status.set_status("Character File publication failed • %s" % _vault.last_error(), true)
		return
	_creator.publication_committed()
	_finish_creation(null, "Created Character File for %s." % character.name)


func _finish_creation(active_content: RealmzContent, status: String) -> void:
	_creator.finish()
	_shell.navigator.setup_controller.character_creation.finish_standalone_character_creation()
	_presentation_media.set_package_media(_library_media)
	_presentation.refresh()
	refresh_vault_views(active_content)
	_shell.show_campaign_selection()
	_shell.status.set_status(status)
