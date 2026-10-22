## Translates recorded positions only; scripts, history, RNG and outcomes are never replayed.
class_name CompleteRecordStateUpdate
extends RefCounted

var last_error := ""
var _simple_slots: Dictionary
var _region_ids: Dictionary


func translate(original: SaveEnvelope, pair: Dictionary, new_hash: String) -> Dictionary:
	last_error = ""
	_simple_slots = pair.get("simpleSlots", {})
	_region_ids = pair.get("randomRegionIds", {})
	var data := original.to_data().duplicate(true)
	if data.gameState.combat != null:
		return _fail("Finish the battle in the original campaign before updating this save; its original signed monster routing identities were not recorded.")
	if not _world_regions(data.gameState.worldOverlays): return {}
	for continuation: Dictionary in [data.sessionContinuation, data.battleReturnContinuation]:
		if not _continuation(continuation, pair): return {}
	if not data.sessionInteraction.is_empty() and data.sessionInteraction.data.payload.has("regionId"):
		var region_id := _region_id(data.sessionInteraction.data.payload.regionId)
		if region_id.is_empty(): return {}
		data.sessionInteraction.data.payload.regionId = region_id
	var eliminated: Array[String] = []
	for key: String in data.gameState.eliminatedSimpleOptions:
		var pieces := key.split(":")
		if pieces.size() != 2: return _fail("An eliminated choice has no unambiguous native slot.")
		var slot := _slot(int(pieces[0]), int(pieces[1]))
		if slot < 0: return {}
		eliminated.append("%s:%d" % [pieces[0], slot])
	eliminated.sort()
	data.gameState.eliminatedSimpleOptions = eliminated
	var stock: Dictionary = {}
	for key: String in data.gameState.shopOverrides:
		var separator := key.rfind(":")
		var shop_id := key.left(separator)
		var classic_id := shop_id.trim_prefix("classic.shop.")
		var indexes: Array = pair.get("shopIndexes", {}).get(classic_id, [])
		var index := int(key.substr(separator + 1))
		if separator < 0 or not shop_id.begins_with("classic.shop.") or index < 0 or index >= indexes.size() or indexes[index] == null:
			return _fail("A recorded shop position cannot be mapped without guessing.")
		var translated_key := "%s:%d" % [shop_id, int(indexes[index])]
		if stock.has(translated_key): return _fail("Two recorded shop positions would collide.")
		stock[translated_key] = data.gameState.shopOverrides[key]
	data.gameState.shopOverrides = stock
	var vm: Dictionary = data.scenarioVm
	for frame: Dictionary in vm.frames:
		if not _context(frame.context): return {}
	var pending: Variant = vm.pendingContinuation
	if pending != null:
		var runtime: Dictionary = pending.data.runtime
		if runtime.kind in ["classic-opcode-death-macro", "classic-combat-death-macro", "safe-combat-death-macro", "classic-combat-macro", "safe-combat-macro"]:
			return _fail("Finish the nested monster macro in the original campaign before updating this save.")
		if runtime.kind == "classic-simple-encounter":
			var body: Dictionary = runtime.data
			var options: Variant = body.get("optionIndexes")
			if options == null:
				return _fail("This pending choice predates explicit response positions; finish it before updating.")
			var mapped: Array[int] = []
			for index: int in options:
				var slot := _slot(int(body.encounterId), index)
				if slot < 0: return {}
				mapped.append(slot)
			body.optionIndexes = mapped
	data.packageHash = new_hash
	return data


func _continuation(continuation: Dictionary, pair: Dictionary) -> bool:
	if continuation.is_empty(): return true
	var body: Dictionary = continuation.data
	if continuation.kind == "combat-death-macro":
		last_error = "Finish the nested monster macro in the original campaign before updating this save."
		return false
	if continuation.kind == "age-updates":
		return _continuation(body.resumeContinuation, pair)
	if continuation.kind in ["post-clock", "post-move"]:
		if not _region_continuation(body, pair): return false
	if continuation.kind == "post-clock":
		var positions: Array = pair.get("timerPositions", [])
		var index := int(body.timedEncounterIndex)
		if index < 0 or index >= positions.size() or positions[index] == null:
			last_error = "The pending timed-encounter position cannot be mapped without guessing."
			return false
		body.timedEncounterIndex = int(positions[index])
	return true


func _context(context: Dictionary) -> bool:
	if context.has("randomRegionId"):
		var region_id := _region_id(context.randomRegionId)
		if region_id.is_empty(): return false
		context.randomRegionId = region_id
	if context.get("encounterKind") != "simple" or not context.has("optionIndex"): return true
	var slot := _slot(int(context.get("encounterId", -1)), int(context.optionIndex))
	if slot < 0: return false
	if context.has("responseId") and context.responseId != "simple:%d:choice:%d" % [int(context.encounterId), slot]:
		last_error = "A pending response identity disagrees with its recorded position."
		return false
	context.optionIndex = slot
	return true


func _world_regions(world: Dictionary) -> bool:
	var seen: Dictionary = {}
	for region: Dictionary in world.randomRegions:
		var region_id := _region_id(region.id)
		if region_id.is_empty(): return false
		if seen.has(region_id):
			last_error = "Two recorded random regions would collide."
			return false
		seen[region_id] = true
		region.id = region_id
	world.randomRegions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.id < right.id)
	return true


func _region_continuation(body: Dictionary, pair: Dictionary) -> bool:
	if not body.randomRegionIds.is_empty() and not pair.get("randomPendingCompatibleByMap", {}).get(body.mapId, false):
		last_error = "Finish the pending random encounter in the original campaign before updating this save."
		return false
	var mapped: Array[String] = []
	for old_id: String in body.randomRegionIds:
		var region_id := _region_id(old_id)
		if region_id.is_empty(): return false
		mapped.append(region_id)
	body.randomRegionIds = mapped
	if not body.activeRandomRegionId.is_empty():
		var region_id := _region_id(body.activeRandomRegionId)
		if region_id.is_empty(): return false
		body.activeRandomRegionId = region_id
	return true


func _region_id(old_id: String) -> String:
	var value: Variant = _region_ids.get(old_id)
	if not value is String or value.is_empty():
		last_error = "A recorded random-region identity cannot be mapped without guessing."
		return ""
	return value


func _slot(encounter_id: int, index: int) -> int:
	var slots: Array = _simple_slots.get(str(encounter_id), [])
	if index < 0 or index >= slots.size() or slots[index] == null:
		last_error = "A recorded Simple Encounter choice cannot be mapped without guessing."
		return -1
	return int(slots[index])


func _fail(message: String) -> Dictionary:
	last_error = message
	return {}
