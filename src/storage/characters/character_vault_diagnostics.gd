## Summarizes preserved Character Files that the current codec can and cannot load.

class_name CharacterVaultDiagnostics
extends RefCounted

var valid_current_count: int = 0
var incompatible_current_count: int = 0
var invalid_current_count: int = 0
var stored_identity_count: int = 0


func unavailable_notice() -> String:
	var unavailable := incompatible_current_count + invalid_current_count
	if unavailable == 0:
		return ""
	var noun := "Character File" if unavailable == 1 else "Character Files"
	if incompatible_current_count > 0 and invalid_current_count == 0:
		return "%d existing %s use an incompatible older format. They were preserved and cannot be loaded by this build. Starter Character Files were not installed because the vault is not empty." % [unavailable, noun]
	if invalid_current_count > 0 and incompatible_current_count == 0:
		return "%d existing %s could not be validated. They were preserved and cannot be loaded. Starter Character Files were not installed because the vault is not empty." % [unavailable, noun]
	return "%d existing Character Files cannot be loaded: %d use an incompatible older format and %d failed validation. They were preserved. Starter Character Files were not installed because the vault is not empty." % [unavailable, incompatible_current_count, invalid_current_count]
