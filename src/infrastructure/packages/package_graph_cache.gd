class_name PackageGraphCache
extends RefCounted

var _active_key: String = ""
var _active_result: PackageLoadResult
var _candidate_key: String = ""
var _candidate_result: PackageLoadResult


func get_result(key: String) -> PackageLoadResult:
	if key == _active_key:
		return _active_result
	if key == _candidate_key:
		return _candidate_result
	return null


func retain_candidate(key: String, result: PackageLoadResult) -> void:
	if key.is_empty() or result == null or not result.is_ok():
		return
	if key == _active_key:
		_active_result = result
		return
	_candidate_key = key
	_candidate_result = result


func promote(key: String) -> void:
	if key.is_empty() or key == _active_key:
		return
	if key != _candidate_key:
		return
	_active_key = _candidate_key
	_active_result = _candidate_result
	_candidate_key = ""
	_candidate_result = null


func clear_candidate() -> void:
	_candidate_key = ""
	_candidate_result = null


func clear() -> void:
	_active_key = ""
	_active_result = null
	clear_candidate()


func retained_count() -> int:
	var count := 0
	if _active_result != null:
		count += 1
	if _candidate_result != null:
		count += 1
	return count
