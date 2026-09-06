## Identifies the immutable Providence-built stock application library.

class_name ApplicationLibraryIdentity
extends RefCounted

const PATH := "res://src/storage/characters/realmz-classic-character-library.realmz2"
const CAMPAIGN_ID := "realmz-classic-character-library"
const PACKAGE_HASH := "c7e093f46bcca49d2382d68c2995ae5ff90c0e706dbd538682b613af9b80e0bd"


static func load(repository: PackageRepository) -> PackageLoadResult:
	return repository.load_bundled_package(PATH, CAMPAIGN_ID, PACKAGE_HASH)
