## Loads a scenario package against the pinned application catalog for performance and capability probes.
extends RefCounted

const PACKAGE_REPOSITORY := preload("res://src/storage/packages/package_repository.gd")
const APPLICATION_PACKAGE_PATH := ApplicationLibraryIdentity.PATH
const APPLICATION_PACKAGE_ID := ApplicationLibraryIdentity.CAMPAIGN_ID
const APPLICATION_PACKAGE_HASH := ApplicationLibraryIdentity.PACKAGE_HASH


static func load_application() -> PackageLoadResult:
	return PACKAGE_REPOSITORY.new().load_bundled_package(
		APPLICATION_PACKAGE_PATH,
		APPLICATION_PACKAGE_ID,
		APPLICATION_PACKAGE_HASH
	)


static func load_scenario(package_path: String, application: PackageLoadResult = null) -> PackageLoadResult:
	if application == null:
		application = load_application()
	if not application.is_ok():
		return application
	var repository := PACKAGE_REPOSITORY.new()
	repository.set_application_content(application.content, application.media.assets())
	return repository.load_package(package_path)
