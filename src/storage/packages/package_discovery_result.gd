class_name PackageDiscoveryResult
extends RefCounted

var path: String
var campaign_id: String
var package_hash: String
var rules_version: String
var display_name: String
var ready: bool
var error_message: String


func _init(package_path: String, is_ready: bool, loaded_campaign_id: String = "", loaded_package_hash: String = "", loaded_rules_version: String = "", readiness_error: String = "", loaded_display_name: String = "") -> void:
	path = package_path
	ready = is_ready
	campaign_id = loaded_campaign_id
	package_hash = loaded_package_hash
	rules_version = loaded_rules_version
	error_message = readiness_error
	display_name = loaded_display_name
