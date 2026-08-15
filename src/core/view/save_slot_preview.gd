class_name SaveSlotPreview
extends RefCounted

const PRIMARY: StringName = &"primary"
const BACKUP: StringName = &"backup"
const VALID: StringName = &"valid"
const CORRUPT: StringName = &"corrupt"
const INCOMPATIBLE: StringName = &"incompatible"
const CAMPAIGN_MISMATCH: StringName = &"campaign-mismatch"
const PACKAGE_MISMATCH: StringName = &"package-mismatch"

var slot_id: String
var source: StringName
var status: StringName
var campaign_id: String = ""
var package_hash: String = ""
var rules_version: String = ""
var view_revision: int = 0
var modified_unix: int = 0
var realmz_day: int = 0
var realmz_hour: int = 0
var realmz_minute: int = 0
var map_id: String = ""
var coordinate: Vector2i = Vector2i.ZERO
var character_names: Array[String] = []
var error_message: String = ""
var can_load: bool = false


func _init(save_slot_id: String, save_source: StringName, save_status: StringName) -> void:
	slot_id = save_slot_id
	source = save_source
	status = save_status


func source_label() -> String:
	return "Backup" if source == BACKUP else "Current"


func status_label() -> String:
	match status:
		VALID:
			return "Identity verified"
		CORRUPT:
			return "Corrupt"
		INCOMPATIBLE:
			return "Incompatible save"
		CAMPAIGN_MISMATCH:
			return "Wrong campaign"
		PACKAGE_MISMATCH:
			return "Different package"
		_:
			return "Unavailable"
