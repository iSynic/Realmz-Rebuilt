class_name CharacterVaultEligibility
extends RefCounted

var eligible: bool = false
var reasons: Array[String] = []


func to_data() -> Dictionary:
	return {"eligible": eligible, "reasons": reasons.duplicate()}
