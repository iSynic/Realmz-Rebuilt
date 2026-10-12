## Names player-imported artwork independently of Classic resource identities.
class_name CharacterArtIdentity
extends RefCounted

const PREFIX := "character-art:"


static func make(kind: String, digest: String) -> String:
	return PREFIX + kind + ":" + digest


static func is_valid(id: String, kind: String) -> bool:
	if kind not in [CharacterAppearanceDefinition.PORTRAIT, CharacterAppearanceDefinition.COMBAT_ICON]:
		return false
	var prefix := PREFIX + kind + ":"
	if not id.begins_with(prefix):
		return false
	var digest := id.trim_prefix(prefix)
	if digest.length() != 64:
		return false
	for character: String in digest:
		if not character in "0123456789abcdef":
			return false
	return true


static func is_imported(id: String) -> bool:
	return id.begins_with(PREFIX)
