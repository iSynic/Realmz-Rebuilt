## Persists and validates character vault eligibility data at the Character Files boundary.

class_name CharacterVaultEligibility
extends RefCounted

var eligible: bool = false
var reasons: Array[String] = []


func to_data() -> Dictionary:
	return {"eligible": eligible, "reasons": reasons.duplicate()}
