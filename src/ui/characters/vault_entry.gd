## Groups one stored character's detached revisions for the Character Files list.
class_name VaultEntry
extends RefCounted

var character_id: String
var archived: bool
var display: CharacterVaultRevisionView
var revisions: Array[CharacterVaultRevisionView] = []


## Groups revisions by character. The current revision represents an active character; an
## archived one is represented by the revision it was archived from, so Restore brings back
## its latest state, then by level.
static func group(source: Array[CharacterVaultRevisionView]) -> Array[VaultEntry]:
	var by_id: Dictionary = {}
	var result: Array[VaultEntry] = []
	for revision: CharacterVaultRevisionView in source:
		var entry := by_id.get(revision.character_id) as VaultEntry
		if entry == null:
			entry = VaultEntry.new()
			entry.character_id = revision.character_id
			entry.archived = revision.archived
			by_id[revision.character_id] = entry
			result.append(entry)
		entry.revisions.append(revision)
		if entry.display == null or _rank(revision) > _rank(entry.display):
			entry.display = revision
	result.sort_custom(func(left: VaultEntry, right: VaultEntry) -> bool: return left.display.name.naturalnocasecmp_to(right.display.name) < 0)
	return result


static func _rank(revision: CharacterVaultRevisionView) -> int:
	return (2000 if revision.is_current else 0) + (1000 if revision.last_current else 0) + revision.level


func matches(query: String) -> bool:
	if query.is_empty():
		return true
	var character := display.character
	var haystack := "%s %s %s" % [display.name, character.race_name if character != null else display.race_id, character.caste_name if character != null else display.caste_id]
	return haystack.to_lower().contains(query.to_lower())
