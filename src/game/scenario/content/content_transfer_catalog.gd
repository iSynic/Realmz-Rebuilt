## Retains package-decoded definition identity and ownership for explicit transfers.
class_name ContentTransferCatalog
extends RefCounted

var _fingerprints: Dictionary = {}
var _scenario_owned: Dictionary = {}
var _application_fingerprints: Dictionary = {}
var _projection_fingerprints: Dictionary = {}


func record(kind: StringName, id: String, fingerprint: String, scenario_owned: bool) -> void:
	var key := "%s:%s" % [kind, id]
	_fingerprints[key] = fingerprint
	if scenario_owned:
		_scenario_owned[key] = true


func inherit_application(application: ContentTransferCatalog) -> void:
	if application != null:
		_fingerprints = application._fingerprints.duplicate()
		_application_fingerprints = application._fingerprints.duplicate()
		_projection_fingerprints = application._projection_fingerprints.duplicate()


func record_projection(kind: StringName, id: String, digest: String) -> void:
	_projection_fingerprints["%s:%s" % [kind, id]] = digest


func exclude_definition(kind: StringName, id: String) -> void:
	var key := "%s:%s" % [kind, id]
	_fingerprints.erase(key)
	_scenario_owned.erase(key)
	_projection_fingerprints.erase(key)


func projection_fingerprint(kind: StringName, id: String) -> String:
	return _projection_fingerprints.get("%s:%s" % [kind, id], "")


func is_scenario_specific(kind: StringName, id: String) -> bool:
	var key := "%s:%s" % [kind, id]
	return _scenario_owned.has(key) and _fingerprints.get(key, "") != _application_fingerprints.get(key, "")


func is_scenario_owned(kind: StringName, id: String) -> bool:
	return _scenario_owned.has("%s:%s" % [kind, id])


func matches(other: ContentTransferCatalog, kind: StringName, id: String) -> bool:
	var key := "%s:%s" % [kind, id]
	return other != null and _fingerprints.has(key) and _fingerprints[key] == other._fingerprints.get(key, "")


func fingerprint(kind: StringName, id: String) -> String:
	return _fingerprints.get("%s:%s" % [kind, id], "")
