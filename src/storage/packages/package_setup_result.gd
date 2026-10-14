## Returns independently decoded setup rules without claiming full package readiness.
class_name PackageSetupResult
extends RefCounted

var catalog: ScenarioSetupCatalog
var media: MediaSource
var source_path := ""
var error_message := ""


func is_ok() -> bool:
	return catalog != null and media != null and error_message.is_empty()
