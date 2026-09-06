## Loads a scenario package against the pinned application catalog for performance and capability probes.
extends RefCounted

const PACKAGE_REPOSITORY := preload("res://src/storage/packages/package_repository.gd")
const APPLICATION_PACKAGE_PATH := ApplicationLibraryIdentity.PATH
const APPLICATION_PACKAGE_ID := ApplicationLibraryIdentity.CAMPAIGN_ID
const APPLICATION_PACKAGE_HASH := ApplicationLibraryIdentity.PACKAGE_HASH


static func load_scenario(package_path: String) -> PackageLoadResult:
	var repository := PACKAGE_REPOSITORY.new()
	var application := repository.load_bundled_package(
		APPLICATION_PACKAGE_PATH,
		APPLICATION_PACKAGE_ID,
		APPLICATION_PACKAGE_HASH
	)
	if not application.is_ok():
		return application
	repository.set_application_content(application.content, application.media.assets())
	return repository.load_package(package_path)
