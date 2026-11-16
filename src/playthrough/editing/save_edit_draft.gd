## One save editor draft over an immutable saved game state. Difficulty, monster set,
## party membership and ally changes form an ordered list replayed from the saved state,
## each with its own Undo. Every party member also has a `CharacterEditDraft` for their own
## character changes. `state` is always the complete replayed result.

class_name SaveEditDraft
extends RefCounted

const _ROSTER_KINDS: Array[StringName] = [&"difficulty", &"add_character", &"drop_character"]

var content: RealmzContent
var rules: RealmzRules
## The saved state with every listed change and character edit replayed onto it.
var state: GameState
var last_error := ""
## Why the current draft can't be saved, or "" (set when a character edit breaks a party rule).
var blocking_error := ""
var _base_data: Dictionary
var _members: Array[SaveEditMember] = []
var _operations: Array[Dictionary] = []
var _undo_reasons: Array[String] = []
## Undo reasons replay the draft once per change, so they are worked out only when asked for.
var _undo_reasons_stale := true
var _apply: SaveEditOperations
var _describe: SaveEditDescriber
var _ally_sequence := 0


func _init(saved_state: GameState, scenario: RealmzContent) -> void:
	content = scenario
	rules = RealmzRules.new(scenario != null and scenario.package_schema_version >= 7)
	_base_data = saved_state.to_data()
	_apply = SaveEditOperations.new(content, rules)
	_describe = SaveEditDescriber.new(content, saved_state)
	for character: CharacterState in saved_state.party.characters():
		_members.append(_new_member(SaveEditMember.SAVED, character))
	state = _replay(_operations)


func is_dirty() -> bool:
	return not _operations.is_empty() or _members.any(func(member: SaveEditMember) -> bool: return member.draft.is_dirty())


## Every member in party order, then members added in this draft; dropped members included.
func members() -> Array[SaveEditMember]:
	return _members.duplicate()


func member(character_id: String) -> SaveEditMember:
	for candidate: SaveEditMember in _members:
		if candidate.character_id == character_id:
			return candidate
	return null


## Replays after a member's character draft changed. False keeps the previous result and
## sets `blocking_error`, which disables saving until that change is undone.
func refresh() -> bool:
	var replayed := _replay(_operations)
	_undo_reasons_stale = true
	blocking_error = "" if replayed != null else "Undo the last character change: %s" % last_error
	if replayed == null:
		return false
	state = replayed
	_undo_reasons_stale = true
	return true


func set_difficulty(value: int) -> bool:
	return _set_scalar(&"difficulty", value, int(_base_data.get("difficulty", 0)))


func set_monster_set(value: int) -> bool:
	return _set_scalar(&"monster_set", value, int(_base_data.get("monsterSet", 0)))


## Adds a Character Files character, checked with the same admission rules as party setup.
func add_character(character: CharacterState, revision: String, source: ContentTransferCatalog, source_campaign_id: String) -> bool:
	last_error = ""
	if character == null or member(character.id) != null:
		return _refuse("That character is already part of this save.")
	var scope_error := PartyAdmissionRules.source_definition_error(source, content, character, source_campaign_id)
	if not scope_error.is_empty():
		return _refuse(scope_error)
	var added := _new_member(SaveEditMember.ADDED, character, revision)
	_members.append(added)
	var candidate: Array[Dictionary] = _operations.duplicate()
	candidate.append({"kind": &"add_character", "character_id": added.character_id})
	if _commit(candidate):
		return true
	_members.erase(added)
	return false


## Drops a member. A member added in this draft simply leaves; a saved member may also be
## kept in Character Files as a new character when the save is written.
func drop_character(character_id: String, keep_in_files: bool) -> bool:
	last_error = ""
	var target := member(character_id)
	if target == null or target.dropped:
		return _refuse("That character isn't in the party.")
	var candidate: Array[Dictionary] = _operations.duplicate()
	if target.origin == SaveEditMember.ADDED:
		candidate.assign(_operations.filter(func(operation: Dictionary) -> bool: return operation.get("character_id", "") != character_id))
	else:
		candidate.append({"kind": &"drop_character", "character_id": character_id, "keep": keep_in_files})
	return _commit(candidate)


func set_keep_in_files(character_id: String, keep: bool) -> bool:
	for index: int in _operations.size():
		var operation := _operations[index]
		if operation.kind == &"drop_character" and operation.character_id == character_id:
			var candidate: Array[Dictionary] = _operations.duplicate()
			var changed := operation.duplicate()
			changed["keep"] = keep
			candidate[index] = changed
			return _commit(candidate)
	return _refuse("That character hasn't been dropped.")


## Adds an ally rolled with `seed_value`, as the Classic add-ally operation builds one.
func add_ally(definition_id: String, seed_value: int) -> bool:
	# The ID carries the ally's own random seed, so an edited ally that later dies in play
	# can't have its identity reused by a later edit of the same adventure.
	_ally_sequence += 1
	var ally_id := "%s%08x.%d" % [SaveEditOperations.ALLY_PREFIX, seed_value & 0xffffffff, _ally_sequence]
	var candidate: Array[Dictionary] = _operations.duplicate()
	candidate.append({"kind": &"add_ally", "definition_id": definition_id, "seed": seed_value, "ally_id": ally_id})
	return _commit(candidate)


## Dismisses an ally. One added in this draft is simply not added.
func dismiss_ally(ally_id: String) -> bool:
	var candidate: Array[Dictionary] = _operations.duplicate()
	if _operations.any(func(operation: Dictionary) -> bool: return operation.kind == &"add_ally" and operation.ally_id == ally_id):
		candidate.assign(_operations.filter(func(operation: Dictionary) -> bool: return operation.get("ally_id", "") != ally_id))
	else:
		candidate.append({"kind": &"dismiss_ally", "ally_id": ally_id})
	return _commit(candidate)


func ally_candidates() -> Array[MonsterDefinition]:
	return _apply.ally_candidates(state)


## Undoes the listed party change at `index`. Undoing an added character also removes
## that character's own edits.
func undo(index: int) -> bool:
	last_error = ""
	if index < 0 or index >= _operations.size():
		return _refuse("That change is no longer listed.")
	var reasons := _reasons()
	if not reasons[index].is_empty():
		return _refuse(reasons[index])
	return _commit(_without(index))


## Listed party changes: label, detail, and whether (or why not) each can be undone.
## `with_undo` false skips working out which changes can be undone (canUndo is then true).
func changes(with_undo: bool = true) -> Array[Dictionary]:
	var reasons: Array[String] = []
	if with_undo:
		reasons = _reasons()
	var result: Array[Dictionary] = []
	for index: int in _operations.size():
		var row := _describe.describe(_operations[index], self)
		var reason := reasons[index] if with_undo else ""
		row.merge({"canUndo": reason.is_empty(), "undoReason": reason})
		result.append(row)
	return result


func _reasons() -> Array[String]:
	if _undo_reasons_stale:
		_undo_reasons = _compute_undo_reasons()
		_undo_reasons_stale = false
	return _undo_reasons


func discard() -> void:
	_members.assign(_members.filter(func(candidate: SaveEditMember) -> bool: return candidate.origin == SaveEditMember.SAVED))
	for candidate: SaveEditMember in _members:
		candidate.draft.discard()
	var none: Array[Dictionary] = []
	_commit(none)
	blocking_error = ""
	last_error = ""


## A carried-item identity unused anywhere in the party, its storage or any member draft.
func next_item_instance_id(character_id: String) -> String:
	var used := {}
	for instance_id: String in state.party.item_instance_ids():
		used[instance_id] = true
	for candidate: SaveEditMember in _members:
		for instance: ItemInstance in candidate.draft.base.inventory() + candidate.state().inventory():
			used[instance.id] = true
	var sequence := 1
	while used.has("%s.item.%d" % [character_id, sequence]):
		sequence += 1
	return "%s.item.%d" % [character_id, sequence]


## Dropped saved members to publish as new Character Files when the save is written.
func kept_characters() -> Array[CharacterState]:
	var result: Array[CharacterState] = []
	for candidate: SaveEditMember in _members:
		if candidate.dropped and candidate.keep_in_files:
			result.append(CharacterStateCodec.copy(candidate.state()))
	return result


func _new_member(origin: StringName, character: CharacterState, revision: String = "") -> SaveEditMember:
	var base := CharacterStateCodec.copy(character)
	return SaveEditMember.new(origin, CharacterEditDraft.new(base, CharacterEditContext.new(content, base)), revision)


func _set_scalar(kind: StringName, value: int, saved_value: int) -> bool:
	last_error = ""
	var candidate: Array[Dictionary] = []
	candidate.assign(_operations.filter(func(operation: Dictionary) -> bool: return operation.kind != kind))
	if value != saved_value:
		candidate.append({"kind": kind, "value": value})
	return _commit(candidate)


func _commit(candidate: Array[Dictionary]) -> bool:
	var replayed := _replay(candidate)
	if replayed == null:
		return false
	_operations = candidate
	state = replayed
	blocking_error = ""
	_sync_members()
	_undo_reasons_stale = true
	return true


## The saved state with every member's edited character, then each listed change in order.
func _replay(operations: Array[Dictionary]) -> GameState:
	last_error = ""
	var data := _base_data.duplicate(true)
	var party: Dictionary = data["party"]
	var characters: Array = []
	for candidate: SaveEditMember in _members:
		if candidate.origin == SaveEditMember.SAVED:
			characters.append(CharacterStateCodec.encode(candidate.state()))
	party["characters"] = characters
	var replayed := GameState.from_data(data)
	if replayed == null:
		last_error = "A character edit couldn't be applied to the save."
		return null
	var by_id: Dictionary[String, SaveEditMember] = {}
	for candidate: SaveEditMember in _members:
		by_id[candidate.character_id] = candidate
	for operation: Dictionary in operations:
		var error := _apply.apply(replayed, operation, by_id)
		if not error.is_empty():
			last_error = error
			return null
	# As in play, the rate is set when a party is formed: a roster or difficulty change re-forms it from
	# every member's current level. Member edits alone (Level Up included) keep the saved rate, as a
	# Level Up during play does.
	if operations.any(func(operation: Dictionary) -> bool: return operation.kind in _ROSTER_KINDS):
		replayed.experience_multiplier = LifecyclePartyWorkflow.party_experience_multiplier(replayed.party.characters(), replayed.difficulty, content.campaign)
	return replayed


## Drops added members no longer listed, and marks dropped and kept members.
func _sync_members() -> void:
	var added := {}
	var dropped := {}
	for operation: Dictionary in _operations:
		if operation.kind == &"add_character":
			added[operation.character_id] = true
		elif operation.kind == &"drop_character":
			dropped[operation.character_id] = bool(operation.keep)
	_members.assign(_members.filter(func(candidate: SaveEditMember) -> bool: return candidate.origin == SaveEditMember.SAVED or added.has(candidate.character_id)))
	for candidate: SaveEditMember in _members:
		candidate.dropped = dropped.has(candidate.character_id)
		candidate.keep_in_files = bool(dropped.get(candidate.character_id, false))


func _without(index: int) -> Array[Dictionary]:
	var candidate: Array[Dictionary] = _operations.duplicate()
	candidate.remove_at(index)
	return candidate


## A dry-run replay catches later changes that rely on this one, such as an ally added
## under the monster set being undone.
func _compute_undo_reasons() -> Array[String]:
	var reasons: Array[String] = []
	for index: int in _operations.size():
		var replayed := _replay(_without(index))
		reasons.append("" if replayed != null else "Can't undo this yet: %s" % last_error)
	last_error = ""
	return reasons


func _refuse(reason: String) -> bool:
	last_error = reason
	return false
