## Carries detached save slot preview data from gameplay into presentation.

class_name SaveSlotPreview
extends RefCounted

const PRIMARY: StringName = &"primary"
const SCENARIO_SLOTS := "ABCDEFGHIJ"
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
var can_update: bool = false
var map_preview_jpeg: PackedByteArray = PackedByteArray()


func _init(save_slot_id: String, save_source: StringName, save_status: StringName) -> void:
	slot_id = save_slot_id
	source = save_source
	status = save_status


## The player-facing name of a slot: "Slot A", "Quick Save 1", or "Slot A, earlier copy" for a
## copy the game set aside (named "<slot>-earlier-<hash>" or "<slot>-programs-<hash>" on disk).
static func title_for(id: String) -> String:
	if id.length() == 1 and SCENARIO_SLOTS.contains(id): return "Slot %s" % id
	if id == "quick": return "Quick Save 1"
	if id == "quick-2": return "Quick Save 2"
	for marker: String in ["-earlier-", "-backup-programs-", "-programs-"]:
		var at := id.rfind(marker)
		if at > 0: return "%s, %s" % [title_for(id.left(at)), "earlier copy" if marker == "-earlier-" else "before an update"]
	return id


## "Latest save" for the slot's own file, "Backup" for the one it replaced.
func source_label() -> String:
	return "Backup" if source == BACKUP else "Latest save"


func status_label() -> String:
	match status:
		VALID:
			return "Ready to load"
		CORRUPT:
			return "Damaged save"
		INCOMPATIBLE:
			return "Can't be opened by this version"
		CAMPAIGN_MISMATCH:
			return "From another scenario"
		PACKAGE_MISMATCH:
			return "Different scenario version"
		_:
			return "Unavailable"
