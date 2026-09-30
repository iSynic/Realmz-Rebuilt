## Discovers all exact save-bound revisions independently of picker preferences.
class_name SavedPartyPackageCatalog
extends RefCounted

var _repository: PackageRepository
var _roots: Array[String]


func _init(repository: PackageRepository, roots: Array[String]) -> void:
	_repository = repository
	_roots = roots.duplicate()


func discover() -> Array[PackageDiscoveryResult]:
	return _repository.discover_packages(_roots)
