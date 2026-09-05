## Owns the application Character Files library, vault, and standalone creator.
class_name ApplicationCharacterFilesHost
extends RefCounted

const LIBRARY_PATH := "res://src/storage/characters/realmz-classic-character-library.realmz2"
const LIBRARY_ID := "realmz-classic-character-library"
const LIBRARY_HASH := "c7e093f46bcca49d2382d68c2995ae5ff90c0e706dbd538682b613af9b80e0bd"

var _package_host: PackageHostController
var _session: GameSessionController
var _presentation: PresentationCoordinator
var _presentation_media: PresentationMediaController
var _shell: GameShell
var _vault := CharacterVaultController.new()
var _creator := CharacterCreationHostController.new()
var _library_content: RealmzContent
var _library_media: MediaSource
var _library_load_complete := false


func _init(
	package_host: PackageHostController,
	session: GameSessionController,
	presentation: PresentationCoordinator,
	presentation_media: PresentationMediaController,
	shell: GameShell
) -> void:
	_package_host = package_host
	_session = session
	_presentation = presentation
	_presentation_media = presentation_media
	_shell = shell


func begin_library_load() -> void:
	if _package_host.start_bundled_load(LIBRARY_PATH, LIBRARY_ID, LIBRARY_HASH):
		return
	_library_load_complete = true
	_shell.navigator.setup_controller.character_creation.set_standalone_character_creation_available(false, "The built-in Classic definitions could not start loading.")


func poll_library_load(active_content: RealmzContent) -> bool:
	if _library_load_complete or _package_host == null or _package_host.bundled_load_is_running():
		return false
	var prepared := _package_host.take_bundled_package(LIBRARY_PATH)
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
	_presentation_media.set_package_media(_library_media)
	_vault.seed_classic_starters_if_empty()
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
	var step := _creator.start(_library_content, _vault.next_character_file_identity())
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
	var character_name := _vault.publish_from_snapshot(_session.session().snapshot(), active_content, character_id)
	if character_name.is_empty():
		_shell.status.set_status("Vault publication failed • %s" % _vault.last_error(), true)
		return false
	refresh_vault_views(active_content)
	_shell.status.set_status("Published %s to the character vault" % character_name)
	return true


func vault_import_intent(character_id: String, revision_hash: String) -> PlayerIntent:
	return _vault.import_intent(character_id, revision_hash)


func vault_error() -> String:
	return _vault.last_error()


func refresh_vault_views(active_content: RealmzContent) -> void:
	_shell.navigator.set_vault_revisions(_vault.revisions(active_content, _library_content))


func archive_character(active_content: RealmzContent, character_id: String) -> void:
	if not _vault.archive(character_id):
		_shell.status.set_status("Vault archive failed • %s" % _vault.last_error(), true)
		return
	refresh_vault_views(active_content)
	_shell.status.set_status("Character archived • immutable revisions remain recoverable")


func restore_character(active_content: RealmzContent, character_id: String, revision_hash: String) -> void:
	if not _vault.restore(character_id, revision_hash):
		_shell.status.set_status("Vault restore failed • %s" % _vault.last_error(), true)
		return
	refresh_vault_views(active_content)
	_shell.status.set_status("Character revision restored as current")


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
	if not _vault.publish(character, _library_content.rules_version, "", _library_content.package_hash, "classic-application"):
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
