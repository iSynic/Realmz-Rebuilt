## Carries a detached, validated source save for importing its party.

class_name SavePartySource
extends RefCounted

var campaign_id: String = ""
var package_hash: String = ""
var rules_version: String = ""
var source_file_hash: String = ""
var slot_id: String = ""
var source_kind: StringName = &""
var modified_unix: int = 0
var party_names: Array[String] = []
var error: String = ""
var envelope: SaveEnvelope = null

## Opaque repository selector. Callers retain this record and pass it back to storage.
var _storage_selector: String = ""


func is_valid() -> bool:
	return envelope != null and error.is_empty()
