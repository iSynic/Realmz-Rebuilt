## Verifies Classic program facts against retained source and normalized package programs.
extends RefCounted


static func verify_effective_source(records: ClassicRecordCatalog, source: ClassicRecordCatalog.Source, effective: PackedByteArray) -> String:
	var family := ""
	var stride := 0
	match source.native_path:
		"Data DD":
			family = "land-action-points"
			stride = 40
		"Data DDD":
			family = "dungeon-action-points"
			stride = 40
		"Data ED3":
			family = "extra-action-points"
			stride = 40
		"Data ED2":
			family = "complex-encounters"
			stride = 520
		"Data EDCD":
			family = "extra-codes"
			stride = 10
		_: return ""
	var layout := _layout(source, family)
	if layout == null or layout.record_bytes != stride:
		return "A full program-fact source is missing its effective native layout."
	var encoded := PackedByteArray()
	for native_id: int in layout.complete_records:
		if family == "extra-codes":
			var extra := records.extra_code_by_id(native_id)
			if extra == null: return "Extra Code facts do not cover effective native row %d." % native_id
			for value: int in extra.values: PackageClassicRecordBinding.append_signed_short(encoded, value)
		else:
			var facts := records.program_by_path_and_id(source.native_path, native_id)
			if facts == null: return "Program facts do not cover effective native record '%s' #%d." % [source.native_path, native_id]
			for value: int in facts.prefix: encoded.append(value)
			for value: int in facts.codes:
				if source.native_path == "Data ED2": encoded.append(value & 0xff)
				else: PackageClassicRecordBinding.append_signed_short(encoded, value)
			for value: int in facts.operands: PackageClassicRecordBinding.append_signed_short(encoded, value)
			for value: int in facts.suffix: encoded.append(value)
	var prefix_length := layout.complete_records * stride
	if encoded.size() != prefix_length or prefix_length + layout.trailing_bytes != source.effective_byte_length or effective.size() != source.effective_byte_length:
		return "Effective native program prefix and partial tail do not cover the reconstructed source."
	if effective.slice(0, prefix_length) != encoded:
		return "Typed program facts differ from the reconstructed effective native source bytes."
	return ""


static func bind_program_bodies(content: RealmzContent, records: ClassicRecordCatalog) -> String:
	var expected_program_ids: Array[String] = []
	for source: ClassicRecordCatalog.Source in records.sources():
		var layout_family := ""
		match source.native_path:
			"Data DD": layout_family = "land-action-points"
			"Data DDD": layout_family = "dungeon-action-points"
			"Data ED3": layout_family = "extra-action-points"
			"Data ED2": layout_family = "complex-encounters"
			"Data ED": layout_family = "simple-encounters"
			_: continue
		var layout := _layout(source, layout_family)
		if layout == null: return "A required Classic program layout is unavailable for '%s'." % source.native_path
		for native_id: int in layout.complete_records:
			if source.native_path in ["Data DD", "Data DDD", "Data ED3"]:
				var facts := records.program_by_path_and_id(source.native_path, native_id)
				if facts == null: return "The compiler omitted complete native program '%s' #%d." % [source.native_path, native_id]
				var program_id := "xap:%d" % native_id if source.native_path == "Data ED3" else "trigger:%s:%d:%d" % [source.native_path, int(native_id / 100), native_id % 100]
				var owner_kind: StringName = &"extra-action-point" if source.native_path == "Data ED3" else &"trigger"
				var owner_id := "Data ED3:macro:%d" % native_id if source.native_path == "Data ED3" else "%s:%d:%d" % [source.native_path, int(native_id / 100), native_id % 100]
				expected_program_ids.append(program_id)
				var error := _verify_program(content, records, program_id, facts.codes, facts.operands, owner_kind, owner_id)
				if not error.is_empty(): return error
			elif source.native_path == "Data ED2":
				var facts := records.program_by_path_and_id(source.native_path, native_id)
				if facts == null: return "The compiler omitted complete native program record 'Data ED2' #%d." % native_id
				for result_index: int in 4:
					var start := result_index * 8
					var program_id := "complex:%d:result:%d" % [native_id, result_index]
					expected_program_ids.append(program_id)
					var error := _verify_program(content, records, program_id, facts.codes.slice(start, start + 8), facts.operands.slice(start, start + 8), &"complex-encounter-result", str(native_id))
					if not error.is_empty(): return error
			else:
				var facts := records.simple_by_id(native_id)
				if facts == null: return "The compiler omitted complete Simple Encounter program record #%d." % native_id
				for result_index: int in 4:
					var start := result_index * 8
					var program_id := "simple:%d:result:%d" % [native_id, result_index]
					expected_program_ids.append(program_id)
					var error := _verify_program(content, records, program_id, facts.codes.slice(start, start + 8), facts.operands.slice(start, start + 8), &"simple-encounter-result", str(native_id))
					if not error.is_empty(): return error
	expected_program_ids.sort()
	if expected_program_ids != content.scenario.program_ids():
		return "The compiled program inventory differs from the complete native source families."
	return ""


static func _verify_program(content: RealmzContent, records: ClassicRecordCatalog, program_id: String, codes: Array, operands: Array, owner_kind: StringName, owner_id: String) -> String:
	var program := content.scenario.program_by_id(program_id)
	if program == null: return "The compiler omitted complete native program '%s'." % program_id
	if program.owner_kind != owner_kind or program.owner_id != owner_id:
		return "Native program '%s' changed its source owner or caller context." % program_id
	var expected_slots: Array[int] = []
	for slot: int in codes.size():
		var raw_opcode: int = codes[slot]
		var operand: int = operands[slot]
		if raw_opcode == 0 and operand == 0: continue
		expected_slots.append(slot)
	if program.instruction_count() != expected_slots.size():
		return "Native program '%s' has %d normalized instructions; expected %d." % [program_id, program.instruction_count(), expected_slots.size()]
	for instruction_index: int in expected_slots.size():
		var slot: int = expected_slots[instruction_index]
		var raw_opcode: int = codes[slot]
		var action: Variant = program.instruction_at(instruction_index)
		if not action is ClassicActionDefinition:
			return "Native program '%s' contains a non-Classic instruction at slot %d." % [program_id, slot]
		var gosub := raw_opcode < 0 and raw_opcode not in [-14, -23]
		var normalized := ClassicOpcodeCatalog.normalize(raw_opcode)
		if action.slot != slot or action.raw_opcode != raw_opcode or action.opcode != normalized or action.gosub != gosub or action.operand_id != int(operands[slot]):
			return "Native program '%s' changed source instruction slot %d." % [program_id, slot]
		if ClassicOpcodeCatalog.reads_extra_code(action.opcode):
			var expected_extra: Array[int] = []
			var primary := records.extra_code_by_id(action.operand_id)
			if primary != null:
				expected_extra.append_array(primary.values)
				if action.opcode == 92:
					var companion := records.extra_code_by_id(action.operand_id + 1)
					if companion != null: expected_extra.append_array(companion.values)
			if action.extra_code != expected_extra:
				return "Native program '%s' Extra Code differs from typed source row for signed operand %d." % [program_id, action.operand_id]
	return ""


static func _layout(source: ClassicRecordCatalog.Source, family: String) -> ClassicRecordCatalog.Layout:
	for candidate: ClassicRecordCatalog.Layout in source.layouts:
		if candidate.family == family:
			return candidate
	return null
