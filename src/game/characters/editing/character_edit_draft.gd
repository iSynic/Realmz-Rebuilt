## One Character Files editor draft: an ordered list of operations replayed from the
## immutable base revision. Every listed change can be undone individually; a later
## Level Up keeps the values its dice read until it is undone.

class_name CharacterEditDraft
extends RefCounted

const _SCALAR_KINDS: Array[StringName] = [&"field", &"save", &"skill", &"condition", &"name", &"gender", &"portrait", &"icon", &"age"]
const _ITEM_KINDS: Array[StringName] = [&"add_item", &"remove_item", &"equip", &"identify"]

var base: CharacterState
var state: CharacterState
var context: CharacterEditContext
var last_error := ""
var _operations: Array[Dictionary] = []
var _effects: Array[Dictionary] = []
var _undo_reasons: Array[String] = []
var _apply: CharacterEditOperations
var _describe: CharacterEditDescriber


func _init(base_state: CharacterState, edit_context: CharacterEditContext) -> void:
	base = CharacterStateCodec.copy(base_state)
	context = edit_context
	_apply = CharacterEditOperations.new(context)
	_describe = CharacterEditDescriber.new(context)
	state = CharacterStateCodec.copy(base)


func is_dirty() -> bool:
	return not _operations.is_empty()


func has_level_up() -> bool:
	return _operations.any(func(operation: Dictionary) -> bool: return operation.kind == &"level_up")


## The rolled gains of the latest Level Up, or an empty dictionary.
func last_level_result() -> Dictionary:
	for index: int in range(_operations.size() - 1, -1, -1):
		if _operations[index].kind == &"level_up":
			var result: Dictionary = _operations[index].get("result", {})
			return result.duplicate()
	return {}


## Why `field` can't change right now, or "".
func lock_reason(field: StringName) -> String:
	if (field in CharacterEditLimits.LEVEL_UP_INPUTS or field == &"age") and has_level_up():
		return "Undo Level Up to change %s; its rolls read it." % ("age" if field == &"age" else CharacterEditLimits.LABELS[field])
	return ""


## Applies one operation; returns false with `last_error` when it is refused.
func apply(operation: Dictionary) -> bool:
	last_error = ""
	var lock_field: StringName = &"age" if operation.kind == &"age" else operation.get("field", &"")
	var lock := lock_reason(lock_field)
	if not lock.is_empty():
		return _refuse(lock)
	var candidate: Array[Dictionary] = _operations.duplicate()
	if operation.kind in _ITEM_KINDS and not operation.has("definition_id"):
		var instance_id: String = operation.get("instance_id", "")
		var carried := _carried(instance_id)
		operation["definition_id"] = carried.definition_id if carried != null else ""
		operation["identified"] = carried == null or carried.identified
	if operation.kind == &"level_up":
		# Level Up resets experience, so earlier experience edits would only list a lost change.
		candidate.assign(candidate.filter(func(other: Dictionary) -> bool: return other.get("field", &"") != &"experience"))
	var appended: Array[Dictionary] = candidate.duplicate()
	appended.append(operation)
	# Folding is only a tidier list: it must produce exactly the appended result, so a
	# later age, item or Level Up that read the earlier value is never reordered.
	if _merge(candidate, operation) and _same_result(candidate, appended):
		return _commit(candidate)
	return _commit(appended)


## Undoes the listed change at `index` together with anything that depends on it.
func undo(index: int) -> bool:
	last_error = ""
	if index < 0 or index >= _operations.size():
		return _refuse("That change is no longer listed.")
	var reason := undo_reason(index)
	if not reason.is_empty():
		return _refuse(reason)
	return _commit(_without(index))


## Undoes the most recent Level Up and its spell choice.
func undo_level_up() -> bool:
	for index: int in range(_operations.size() - 1, -1, -1):
		if _operations[index].kind == &"level_up":
			return undo(index)
	return _refuse("There is no Level Up to undo.")


## The operations left when the change at `index` and its dependents are undone.
func _without(index: int) -> Array[Dictionary]:
	var operation := _operations[index]
	var candidate: Array[Dictionary] = []
	for position: int in _operations.size():
		var other := _operations[position]
		var depends: bool = operation.kind == &"add_item" and other.get("instance_id", "") == operation.instance_id
		# Only the latest Level Up can be undone, so every later spell choice is its own.
		depends = depends or (operation.kind == &"level_up" and other.kind == &"level_spells" and position > index)
		if position != index and not depends:
			candidate.append(other)
	return candidate


## Why the change at `index` can't be undone on its own, or "", computed once per commit.
func undo_reason(index: int) -> String:
	return _undo_reasons[index] if index >= 0 and index < _undo_reasons.size() else ""


## A dry-run replay catches later changes that rely on this one, such as gold spent
## from a raised load limit.
func _compute_undo_reason(index: int) -> String:
	var reason := _ordering_reason(index)
	if not reason.is_empty():
		return reason
	var error := _replay_error(_without(index))
	return "" if error.is_empty() else "Can't undo this yet: %s" % error


func _ordering_reason(index: int) -> String:
	var operation := _operations[index]
	var later := _operations.slice(index + 1)
	if operation.kind == &"level_up" and later.any(func(other: Dictionary) -> bool: return other.kind == &"level_up"):
		return "Undo the later Level Up first."
	if operation.kind == &"level_spells":
		return "Undo the Level Up to change this choice."
	var field: StringName = &"age" if operation.kind == &"age" else operation.get("field", &"")
	if (field in CharacterEditLimits.LEVEL_UP_INPUTS or field == &"age") and later.any(func(other: Dictionary) -> bool: return other.kind == &"level_up"):
		return "Undo Level Up first; its rolls read this value."
	return ""


func discard() -> void:
	_operations.clear()
	_effects.clear()
	_undo_reasons.clear()
	state = CharacterStateCodec.copy(base)


## Listed changes: label, detail, and whether (or why not) each can be undone.
func changes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in _operations.size():
		var reason := undo_reason(index)
		result.append({"label": _effects[index].label, "detail": _effects[index].detail, "canUndo": reason.is_empty(), "undoReason": reason})
	return result


## A carried-item identity unused by the base revision and every draft operation.
func next_item_instance_id() -> String:
	var used := {}
	for instance: ItemInstance in base.inventory() + state.inventory():
		used[instance.id] = true
	for operation: Dictionary in _operations:
		used[operation.get("instance_id", "")] = true
	var sequence := base.inventory().size() + 1
	while used.has("%s.item.%d" % [base.id, sequence]):
		sequence += 1
	return "%s.item.%d" % [base.id, sequence]


## Folds a repeated edit of the same value, a re-toggle, or removing an item added
## in this draft into the earlier operation. Returns false when it must be appended;
## `apply` keeps a fold only when it replays to exactly the appended result.
func _merge(candidate: Array[Dictionary], operation: Dictionary) -> bool:
	var key := _key(operation)
	for index: int in range(candidate.size() - 1, -1, -1):
		var earlier := candidate[index]
		if operation.kind == &"remove_item" and earlier.kind == &"add_item" and earlier.instance_id == operation.instance_id:
			candidate.assign(candidate.filter(func(other: Dictionary) -> bool: return other.get("instance_id", "") != operation.instance_id))
			return true
		# A Level Up and its spell choice read everything before them; never fold across.
		if earlier.kind in [&"level_up", &"level_spells"]:
			return false
		if key.is_empty() or _key(earlier) != key:
			continue
		if operation.kind in [&"spell", &"equip"]:
			if earlier.get("known", earlier.get("equipped")) != operation.get("known", operation.get("equipped")):
				candidate.remove_at(index)
				return true
			return false
		candidate[index] = operation
		return true
	return false


func _commit(candidate: Array[Dictionary]) -> bool:
	var replayed := CharacterStateCodec.copy(base)
	var effects: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	for operation: Dictionary in candidate:
		var before: Variant = _describe.value(replayed, operation)
		# Scalar edits apply to a trial so a dropped no-op leaves no side effect behind.
		var target := CharacterStateCodec.copy(replayed) if operation.kind in _SCALAR_KINDS else replayed
		var error := _apply.apply(target, operation)
		if not error.is_empty():
			return _refuse(error)
		var after: Variant = _describe.value(target, operation)
		if operation.kind in _SCALAR_KINDS and before == after:
			continue
		replayed = target
		kept.append(operation)
		effects.append(_describe.effect(operation, before, after))
	_operations = kept
	_effects = effects
	state = replayed
	_undo_reasons.clear()
	for index: int in _operations.size():
		_undo_reasons.append(_compute_undo_reason(index))
	return true


func _replay_error(candidate: Array[Dictionary]) -> String:
	var replayed := CharacterStateCodec.copy(base)
	for operation: Dictionary in candidate:
		var error := _apply.apply(replayed, operation.duplicate(true))
		if not error.is_empty():
			return error
	return ""


func _same_result(left: Array[Dictionary], right: Array[Dictionary]) -> bool:
	var results: Array[Dictionary] = []
	for candidate: Array[Dictionary] in [left, right]:
		var replayed := CharacterStateCodec.copy(base)
		for operation: Dictionary in candidate:
			if not _apply.apply(replayed, operation.duplicate(true)).is_empty():
				return false
		results.append(CharacterStateCodec.encode(replayed))
	return results[0] == results[1]


func _key(operation: Dictionary) -> String:
	var kind: StringName = operation.kind
	match kind:
		&"field": return "field:%s" % operation.field
		&"save", &"skill", &"condition": return "%s:%d" % [operation.kind, operation.index]
		&"name", &"gender", &"portrait", &"icon", &"age": return String(kind)
		&"spell": return "spell:%s" % operation.spell_id
		&"equip": return "equip:%s" % operation.instance_id
	return ""


func _carried(instance_id: String) -> ItemInstance:
	for instance: ItemInstance in state.inventory():
		if instance.id == instance_id:
			return instance
	return null


func _refuse(reason: String) -> bool:
	last_error = reason
	return false
