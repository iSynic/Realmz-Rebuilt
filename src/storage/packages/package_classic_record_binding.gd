## Joins verified native presence and fixed slots to immutable operational catalogs.
class_name PackageClassicRecordBinding
extends RefCounted

const ProgramBinding := preload("res://src/storage/packages/package_classic_program_binding.gd")

static func bind(content: RealmzContent, records: ClassicRecordCatalog, assets: Array[MediaAsset]) -> String:
	var rule_error := PackageClassicRuleSelectionBinding.bind(content, records)
	if not rule_error.is_empty(): return rule_error
	for source: ClassicRecordCatalog.Source in records.sources():
		var found := false
		for asset: MediaAsset in assets:
			if asset.kind == &"classic-source" and asset.sha256 == source.sha256 and asset.byte_count == source.byte_length:
				found = true
				break
		if not found:
			return "Classic record source '%s' has no exact retained payload." % source.native_path
		for layout: ClassicRecordCatalog.Layout in source.layouts:
			for native_id: int in layout.complete_records:
				var error := _bind_record(content, records, source.native_path, layout.family, native_id)
				if not error.is_empty():
					return error
	var program_error := ProgramBinding.bind_program_bodies(content, records)
	if not program_error.is_empty(): return program_error
	var player_map_error := PackageClassicPlayerMapBinding.bind(content, records)
	if not player_map_error.is_empty(): return player_map_error
	var terrain_error := _bind_landlook_dependencies(content, records)
	if not terrain_error.is_empty(): return terrain_error
	content.classic_records = records
	content.scenario.classic_records = records
	return ""


static func _bind_landlook_dependencies(content: RealmzContent, records: ClassicRecordCatalog) -> String:
	for program_id: String in content.scenario.program_ids():
		var program := content.scenario.program_by_id(program_id)
		for index: int in program.instruction_count():
			var action: Variant = program.instruction_at(index)
			if not action is ClassicActionDefinition or action.opcode != 57 or action.extra_code.size() < 5: continue
			var look := RealmzArithmetic.new().signed_8(action.extra_code[0])
			if content.world.map_by_type_and_index(&"land", action.extra_code[2]) == null: continue
			var required := look in [0, 3, 4, 5, 9, 10]
			if look in [6, 7, 8]:
				var source := records.source_by_path("Data Custom %d BD" % (look - 5))
				required = source != null and source.effective_byte_length >= 8044
			if required and content.world.battle_terrain_set_by_landlook(look) == null:
				return "The compiler omitted opcode 57 landlook %d required by '%s' slot %d." % [look, program_id, action.slot]
	return ""


static func validate_source_receipt(archive: ZIPReader, records: ClassicRecordCatalog, assets: Array[MediaAsset]) -> String:
	var indexes: Array[MediaAsset] = []
	for asset: MediaAsset in assets:
		if asset.kind == &"classic-source-index": indexes.append(asset)
	if indexes.size() != 1:
		return "A v7 campaign requires one exact native source index."
	var receipt: Variant = JSON.parse_string(archive.read_file(indexes[0].path).get_string_from_utf8())
	if not receipt is Dictionary or receipt.get("kind") != "realmz2.classic-source-retention" or receipt.get("schemaVersion") != 1 or not receipt.get("sources") is Array:
		return "The native source index is malformed."
	var seen: Dictionary = {}
	for row: Variant in receipt.sources:
		if not row is Dictionary or not row.get("nativePath") is String or seen.has(row.nativePath):
			return "The native source index has malformed or duplicate paths."
		var source := records.source_by_path(row.nativePath)
		if source == null or row.get("sha256") != source.sha256 or row.get("blob") != "sha256:" + source.sha256 or row.get("byteLength") != source.byte_length:
			return "The native record catalog disagrees with its retained source index."
		var matched: MediaAsset
		for asset: MediaAsset in assets:
			if asset.path == row.get("assetPath") and asset.kind == &"classic-source" and asset.sha256 == source.sha256 and asset.byte_count == source.byte_length:
				if matched != null: return "The native source index has ambiguous payload identity."
				matched = asset
		if matched == null or not archive.file_exists(matched.path):
			return "The native source index names an unavailable payload."
		var original := archive.read_file(matched.path)
		if original.size() != source.byte_length or _sha256(original) != source.sha256:
			return "The retained native source payload failed its original identity check."
		if _is_resource_source(source.native_path) and not source.edits.is_empty():
			return "Resource-fork edits are unsupported by this package reader."
		var effective_result := _apply_source_edits(original, source)
		if not effective_result.error.is_empty(): return effective_result.error
		var effective: PackedByteArray = effective_result.bytes
		if effective.size() != source.effective_byte_length or _sha256(effective) != source.effective_sha256:
			return "The reconstructed native source failed its effective identity check."
		var fact_error := _verify_effective_record_facts(records, source, effective)
		if not fact_error.is_empty(): return fact_error
		var program_fact_error := ProgramBinding.verify_effective_source(records, source, effective)
		if not program_fact_error.is_empty(): return program_fact_error
		var player_map_error := PackageClassicPlayerMapBinding.verify_effective_source(records, source, effective)
		if not player_map_error.is_empty(): return player_map_error
		if source.native_path in ["Data RD", "Data RDD"] and not _bind_initial_darkness(records, source, effective):
			return "The effective native map source has invalid darkness-byte facts."
		seen[row.nativePath] = true
	return "" if seen.size() == records.sources().size() else "The native record catalog has undeclared source files."


static func _bind_initial_darkness(records: ClassicRecordCatalog, source: ClassicRecordCatalog.Source, effective: PackedByteArray) -> bool:
	var level_type := &"land" if source.native_path == "Data RD" else &"dungeon"
	var family := "land-random-levels" if level_type == &"land" else "dungeon-random-levels"
	for layout: ClassicRecordCatalog.Layout in source.layouts:
		if layout.family != family: continue
		if layout.record_bytes != 644 or layout.complete_records * 644 + layout.trailing_bytes != effective.size(): return false
		for index: int in layout.complete_records:
			records.set_verified_initial_map_darkness_byte(level_type, index, effective[index * 644 + 521])
		return true
	return false


static func _apply_source_edits(original: PackedByteArray, source: ClassicRecordCatalog.Source) -> Dictionary:
	var output := PackedByteArray()
	var cursor := 0
	for edit: ClassicRecordCatalog.Edit in source.edits:
		if edit.offset < cursor or edit.offset > original.size() or edit.offset + edit.before.size() > original.size():
			return {"bytes": PackedByteArray(), "error": "Classic source edit is outside the original payload."}
		var preimage := original.slice(edit.offset, edit.offset + edit.before.size())
		if preimage != _packed(edit.before):
			return {"bytes": PackedByteArray(), "error": "Classic source edit preimage differs from retained bytes."}
		output.append_array(original.slice(cursor, edit.offset))
		output.append_array(_packed(edit.after))
		cursor = edit.offset + edit.before.size()
	output.append_array(original.slice(cursor, original.size()))
	return {"bytes": output, "error": ""}


static func _verify_effective_record_facts(records: ClassicRecordCatalog, source: ClassicRecordCatalog.Source, effective: PackedByteArray) -> String:
	var family := ""
	var stride := 0
	match source.native_path:
		"Data ED":
			family = "simple-encounters"
			stride = 426
		"Data TD3":
			family = "timed-encounters"
			stride = 40
		"Data SD":
			family = "shop-records"
			stride = 3002
		_:
			return ""
	var layout: ClassicRecordCatalog.Layout
	for candidate: ClassicRecordCatalog.Layout in source.layouts:
		if candidate.family == family:
			layout = candidate
			break
	if layout == null or layout.record_bytes != stride:
		return "A full-fact source is missing its effective native layout."
	var encoded := PackedByteArray()
	for native_id: int in layout.complete_records:
		match family:
			"simple-encounters":
				var facts := records.simple_by_id(native_id)
				if facts == null: return "Simple Encounter facts do not cover effective native record %d." % native_id
				_encode_simple(encoded, facts)
			"timed-encounters":
				var facts := records.timed_by_id(native_id)
				if facts == null: return "Timed Encounter facts do not cover effective native record %d." % native_id
				for word: int in facts.words: append_signed_short(encoded, word)
			"shop-records":
				var facts := records.shop_by_id(native_id)
				if facts == null: return "Shop facts do not cover effective native record %d." % native_id
				for item_id: int in facts.item_ids: append_signed_short(encoded, item_id)
				for quantity: int in facts.quantities: encoded.append(quantity)
				append_signed_short(encoded, facts.inflation)
	var prefix_length := layout.complete_records * stride
	if encoded.size() != prefix_length or prefix_length + layout.trailing_bytes != source.effective_byte_length or effective.size() != source.effective_byte_length:
		return "Effective native record prefix and partial tail do not cover the reconstructed source."
	if effective.slice(0, prefix_length) != encoded:
		return "Native record facts differ from the reconstructed effective source bytes."
	return ""


static func _encode_simple(output: PackedByteArray, facts: ClassicRecordCatalog.SimpleFacts) -> void:
	for code: int in facts.codes: output.append(code & 0xff)
	for operand: int in facts.operands: append_signed_short(output, operand)
	for choice: int in facts.choice_results: output.append(choice & 0xff)
	output.append(facts.can_back_out_byte)
	output.append(facts.max_times & 0xff)
	output.append(facts.caste_success & 0xff)
	output.append(facts.reserved_byte)
	append_signed_short(output, facts.prompt_message_id)
	for text_slot: Array in facts.text_slots:
		for byte_value: int in text_slot: output.append(byte_value)


static func append_signed_short(output: PackedByteArray, value: int) -> void:
	output.append((value >> 8) & 0xff)
	output.append(value & 0xff)


static func _packed(values: Array[int]) -> PackedByteArray:
	var result := PackedByteArray()
	result.append_array(values)
	return result


static func _is_resource_source(path: String) -> bool:
	return path.ends_with(".rsrc") or path.ends_with(".rsf") or path.begins_with("._") or path.begins_with(".rsrc/") or "/.rsrc/" in path or "/._" in path


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if not bytes.is_empty() and context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


static func _bind_record(content: RealmzContent, records: ClassicRecordCatalog, path: String, family: String, native_id: int) -> String:
	match family:
		"land-action-points", "dungeon-action-points":
			if content.scenario.program_by_id("trigger:%s:%d:%d" % [path, native_id / 100, native_id % 100]) == null: return _omitted(path, native_id)
		"simple-encounters":
			var encounter := content.scenario_records.simple_encounter_by_id(native_id)
			var facts := records.simple_by_id(native_id)
			if encounter == null or facts == null:
				return _omitted(path, native_id)
			for slot: int in 4:
				var response := encounter.response_at(slot)
				if response == null or response.id != "simple:%d:choice:%d" % [native_id, slot] or response.result_program_id != "simple:%d:result:%d" % [native_id, facts.choice_results[slot] - 1]:
					return "Simple Encounter %d changed native choice slot %d." % [native_id, slot]
			encounter.native_facts = facts
			return _result_programs(content, "simple", native_id)
		"complex-encounters":
			if content.scenario_records.complex_encounter_by_id(native_id) == null:
				return _omitted(path, native_id)
			return _result_programs(content, "complex", native_id)
		"extra-action-points":
			if content.scenario.program_by_id("xap:%d" % native_id) == null:
				return _omitted(path, native_id)
		"timed-encounters":
			var encounter := content.scenario_records.timed_encounter_by_id(native_id)
			var facts := records.timed_by_id(native_id)
			if encounter == null or facts == null:
				return _omitted(path, native_id)
			var projected: Array[int] = [encounter.day, encounter.increment, encounter.chance_percent, encounter.classic_macro_id, encounter.required_level, encounter.required_random_rectangle, encounter.required_x, encounter.required_y, encounter.required_item_id, encounter.required_quest_id]
			if projected != facts.words.slice(0, 10) or encounter.program_id != "xap:%d" % facts.words[3]:
				return "Timed Encounter %d changed its signed native fields." % native_id
			encounter.native_facts = facts
		"shop-records":
			var shop := content.economy.shop_by_classic_id(native_id)
			var facts := records.shop_by_id(native_id)
			if shop == null or facts == null:
				return _omitted(path, native_id)
			if shop.inflation_percent != facts.inflation:
				return "Shop %d changed its native inflation." % native_id
			var stock_index := 0
			var items := shop.item_ids()
			for category: int in 5:
				for slot: int in range(category * 200, (category + 1) * 200):
					var item_id := facts.item_ids[slot]
					if item_id < 0: break
					if item_id == 0: continue
					if stock_index >= items.size() or shop.stock_slot(stock_index) != slot or items[stock_index] != "classic.item.%d" % item_id or shop.quantity(stock_index) != facts.quantities[slot]:
						return "Shop %d changed native stock slot %d." % [native_id, slot]
					stock_index += 1
			if stock_index != items.size(): return "Shop %d added stock outside its native categories." % native_id
			shop.native_facts = facts
		_:
			return _bind_catalog_record(content, path, family, native_id)
	return ""


static func _bind_catalog_record(content: RealmzContent, path: String, family: String, native_id: int) -> String:
	match family:
		"scenario-messages":
			if content.scenario_records.message_by_id(native_id) == null: return _omitted(path, native_id)
		"option-labels":
			if content.scenario_records.option_label_by_id(native_id) == null: return _omitted(path, native_id)
		"rogue-encounters":
			if content.scenario_records.thief_encounter_by_id(native_id) == null: return _omitted(path, native_id)
		"land-maps", "dungeon-maps":
			if content.world.map_by_id("%s:%d" % ["land" if family == "land-maps" else "dungeon", native_id]) == null: return _omitted(path, native_id)
		"battle-records":
			if content.combat.battle_by_classic_id(native_id) == null: return _omitted(path, native_id)
		"treasure-records":
			if content.economy.treasure_by_classic_id(native_id) == null: return _omitted(path, native_id)
		"scenario-monsters", "monster-variant-records", "mega-monster-variant-records":
			var set_id := -1 if path == "Data MD-1" else (1 if path == "Data MD1" else 0)
			var definition := content.combat.monster_by_classic_id_for_set(native_id, set_id)
			if definition == null: return _omitted(path, native_id)
			definition.native_complete_record = true
	return ""


static func _result_programs(content: RealmzContent, kind: String, native_id: int) -> String:
	for result: int in 4:
		if content.scenario.program_by_id("%s:%d:result:%d" % [kind, native_id, result]) == null:
			return "The compiler omitted %s %d result slot %d." % [kind, native_id, result]
	return ""


static func _omitted(path: String, native_id: int) -> String:
	return "The compiler omitted complete native record '%s' #%d." % [path, native_id]
