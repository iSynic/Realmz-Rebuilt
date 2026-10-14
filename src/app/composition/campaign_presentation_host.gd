## Publishes prepared content and remembers only successfully entered adventures.
class_name CampaignPresentationHost
extends RefCounted

var _packages: PackageHostController
var _files: ApplicationCharacterFilesHost
var _storage: ApplicationAdventureStorageHost
var _media: PresentationMediaController
var _presentation: PresentationCoordinator
var _shell: GameShell
var _settings: PresentationSettings
var _settings_repository: SettingsRepository
var _set_content: Callable
var _invalidate_combat: Callable


func _init(packages: PackageHostController, files: ApplicationCharacterFilesHost, storage: ApplicationAdventureStorageHost, media: PresentationMediaController, presentation: PresentationCoordinator, shell: GameShell, settings: PresentationSettings, settings_repository: SettingsRepository, set_content: Callable, invalidate_combat: Callable) -> void:
	_packages = packages
	_files = files
	_storage = storage
	_media = media
	_presentation = presentation
	_shell = shell
	_settings = settings
	_settings_repository = settings_repository
	_set_content = set_content
	_invalidate_combat = invalidate_combat


func publish_setup(content: RealmzContent, media: MediaSource, path: String) -> void:
	_invalidate_combat.call()
	_set_content.call(content)
	_media.set_package_media(media)
	_presentation.refresh()
	_files.refresh_vault_views(content)
	_shell.navigator.setup_controller.campaign_library.select_prepared_package(path)
	_shell.status.set_status("Build your party now. Play will wait if the scenario is still preparing.")


func publish_adventure(prepared: PreparedPackage) -> void:
	_invalidate_combat.call()
	_set_content.call(prepared.content)
	_packages.promote(prepared)
	_settings.last_campaign_id = prepared.content.campaign_id
	_settings_repository.save_settings(_settings)
	_media.set_package_media(prepared.media)
	_presentation.refresh()
	_storage.refresh(prepared.content)
	_files.refresh_vault_views(prepared.content)


func publish_installed_setup(prepared: PreparedPackage, view: GameView, seed_value: int) -> String:
	_packages.promote(prepared)
	publish_setup(prepared.content, prepared.media, prepared.installed_path)
	_storage.refresh(prepared.content)
	var status := ApplicationStepStatusText.for_package(prepared.content, view, seed_value)
	_shell.status.set_status(status)
	return status
