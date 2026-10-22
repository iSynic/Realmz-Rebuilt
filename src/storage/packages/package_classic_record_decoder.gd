## Strictly converts schema-v7 Classic record facts into typed game values.
class_name PackageClassicRecordDecoder
extends PackageDecoderBase

const SOURCE_FIELDS: Array[String] = ["nativePath", "sha256", "byteLength", "effectiveSha256", "effectiveByteLength", "edits", "layouts"]
const EDIT_FIELDS: Array[String] = ["offset", "before", "after"]
const LAYOUT_FIELDS: Array[String] = ["family", "recordBytes", "completeRecords", "trailingBytes", "ownedByteRanges"]
const RANGE_FIELDS: Array[String] = ["start", "end"]
const SIMPLE_FIELDS: Array[String] = ["id", "codes", "operands", "choiceResults", "canBackOutByte", "maxTimes", "casteSuccess", "reservedByte", "promptMessageId", "textSlots"]
const TIMED_FIELDS: Array[String] = ["id", "words"]
const SHOP_FIELDS: Array[String] = ["id", "itemIds", "quantities", "inflation"]
const PLAYER_MAP_FIELDS: Array[String] = ["id", "words", "noteBytes"]
const PROGRAM_FIELDS: Array[String] = ["nativePath", "id", "prefix", "codes", "operands", "suffix"]
const EXTRA_CODE_FIELDS: Array[String] = ["id", "values"]
const RESOURCE_FIELDS: Array[String] = ["nativePath", "resourceTypeBytes", "resourceId", "occurrence", "sha256", "byteLength"]
const RECORDS_FIELDS: Array[String] = ["sources", "resources", "undecodableResourceSources", "simple", "timed", "shops", "programs", "extraCodes", "playerMaps", "ruleSelection", "races", "castes"]

func decode(value: Variant) -> ClassicRecordCatalog:
	clear_error()
	if not value is Dictionary or not _exact_fields(value, RECORDS_FIELDS):
		_reject("content.classicRecords has invalid top-level fields.")
		return null
	var setup := decode_setup({"sources": value.sources, "ruleSelection": value.ruleSelection})
	if setup == null: return null
	var source_rows := setup.sources()
	var rule_decoder := PackageCharacterContentDecoder.new(_diagnostic)
	var races: Variant = rule_decoder.decode_races(value.races, true, true)
	var castes: Variant = rule_decoder.decode_castes(value.castes, true, true)
	if races == null or castes == null or not _rule_facts_cover_source(setup, "Data Race", races, 408) or not _rule_facts_cover_source(setup, "Data Caste", castes, 576):
		return null
	var source_index: Dictionary = {}
	for source: ClassicRecordCatalog.Source in source_rows: source_index[source.native_path] = source
	var simple: Variant = _decode_simple(value.simple)
	var timed: Variant = _decode_timed(value.timed)
	var shops: Variant = _decode_shops(value.shops)
	var player_maps: Variant = _decode_player_maps(value.playerMaps)
	var programs: Variant = _decode_programs(value.programs)
	var extra_codes: Variant = _decode_extra_codes(value.extraCodes)
	var resources: Variant = _decode_resources(value.resources, source_index)
	var undecodable_paths: Variant = _decode_undecodable_sources(value.undecodableResourceSources, source_index)
	if simple == null or timed == null or shops == null or player_maps == null or programs == null or extra_codes == null or resources == null or undecodable_paths == null:
		return null
	if not _facts_cover_source(source_index, "Data ED", "simple-encounters", _record_ids(simple)):
		return null
	if not _facts_cover_source(source_index, "Data TD3", "timed-encounters", _record_ids(timed)):
		return null
	if not _facts_cover_source(source_index, "Data SD", "shop-records", _record_ids(shops)):
		return null
	if not _facts_cover_source(source_index, "Data MD2", "player-maps", _record_ids(player_maps)):
		return null
	if not _program_facts_cover_sources(source_index, programs):
		return null
	if not _extra_code_facts_cover_source(source_index, extra_codes):
		return null
	return ClassicRecordCatalog.new(source_rows, simple, timed, shops, programs, extra_codes, resources, undecodable_paths, player_maps, setup.rule_selection, races, castes)


func _rule_facts_cover_source(records: ClassicRecordCatalog, path: String, rows: Array, stride: int) -> bool:
	var source := records.source_by_path(path)
	var count := 0 if source == null else mini(30, int(source.effective_byte_length / stride))
	if rows.size() != count:
		return _reject("Native rule facts do not cover every supplied complete '%s' record." % path)
	for index: int in count:
		if rows[index].classic_id != index + 1:
			return _reject("Native rule facts changed their fixed source identities.")
	return true


func decode_setup(value: Variant) -> ClassicRecordCatalog:
	clear_error()
	if not value is Dictionary or not _exact_fields(value, ["sources", "ruleSelection"]) or not value.sources is Array:
		_reject("Classic setup facts must contain only source inventory and rule selection.")
		return null
	var sources: Array[ClassicRecordCatalog.Source] = []
	var seen: Dictionary = {}
	for row: Variant in value.sources:
		var source := _decode_source(row)
		if source == null: return null
		if seen.has(source.native_path):
			_reject("Classic source paths must be unique.")
			return null
		seen[source.native_path] = true
		sources.append(source)
	var selection_decoder := PackageClassicRuleSelectionDecoder.new(_diagnostic)
	var selection := selection_decoder.decode(value.ruleSelection)
	if not selection_decoder.error_message().is_empty():
		_reject(selection_decoder.error_message())
		return null
	return ClassicRecordCatalog.new(sources, [], [], [], [], [], [], [], [], selection)

func _decode_player_maps(value: Variant) -> Variant:
	if not value is Array:
		_reject("Classic player-map facts must be an array.")
		return null
	var result: Array[ClassicRecordCatalog.PlayerMapFacts] = []
	var ids: Dictionary = {}
	for row: Variant in value:
		if not row is Dictionary or not _exact_fields(row, PLAYER_MAP_FIELDS):
			_reject("Classic player-map facts have invalid fields.")
			return null
		var record_id := _bounded_integer(row.id, 0, 2147483647, "Classic player-map id")
		var words: Variant = _integer_array_range(row.words, 42, -32768, 32767, "player-map words")
		var note: Variant = _integer_array_range(row.noteBytes, 256, 0, 255, "player-map noteBytes")
		if record_id < 0 or ids.has(record_id) or words == null or note == null or not error_message().is_empty():
			if error_message().is_empty(): _reject("Classic player-map facts are duplicated or malformed.")
			return null
		var record := ClassicRecordCatalog.PlayerMapFacts.new()
		record.id = record_id
		record.words = words
		record.note_bytes = note
		ids[record_id] = true
		result.append(record)
	return result

func _decode_programs(value: Variant) -> Variant:
	if not value is Array:
		_reject("Classic program facts must be an array.")
		return null
	var result: Array[ClassicRecordCatalog.ProgramFacts] = []
	var seen: Dictionary = {}
	for row: Variant in value:
		if not row is Dictionary or not _exact_fields(row, PROGRAM_FIELDS) or not row.nativePath is String or row.nativePath not in ["Data DD", "Data DDD", "Data ED3", "Data ED2"]:
			_reject("Classic program facts have invalid fields or native path.")
			return null
		var record_id := _bounded_integer(row.id, 0, 2147483647, "Classic program id")
		var prefix: Variant = _integer_array_range(row.prefix, _program_prefix_size(row.nativePath), 0, 255, "program prefix")
		var code_minimum := -32768 if row.nativePath != "Data ED2" else -128
		var code_maximum := 32767 if row.nativePath != "Data ED2" else 127
		var codes: Variant = _integer_array_range(row.codes, 32 if row.nativePath == "Data ED2" else 8, code_minimum, code_maximum, "program codes")
		var operands: Variant = _integer_array_range(row.operands, 32 if row.nativePath == "Data ED2" else 8, -32768, 32767, "program operands")
		var suffix: Variant = _integer_array_range(row.suffix, _program_suffix_size(row.nativePath), 0, 255, "program suffix")
		var key := "%s:%d" % [row.nativePath, record_id]
		if record_id < 0 or seen.has(key) or prefix == null or codes == null or operands == null or suffix == null or not error_message().is_empty():
			if error_message().is_empty(): _reject("Classic program facts are duplicated or malformed.")
			return null
		seen[key] = true
		result.append(ClassicRecordCatalog.ProgramFacts.new(row.nativePath, record_id, prefix, codes, operands, suffix))
	return result

func _program_prefix_size(path: String) -> int:
	return 0 if path == "Data ED2" else 8

func _program_suffix_size(path: String) -> int:
	return 424 if path == "Data ED2" else 0

func _decode_extra_codes(value: Variant) -> Variant:
	if not value is Array:
		_reject("Classic Extra Code facts must be an array.")
		return null
	var result: Array[ClassicRecordCatalog.ExtraCodeFacts] = []
	var seen: Dictionary = {}
	for row: Variant in value:
		if not row is Dictionary or not _exact_fields(row, EXTRA_CODE_FIELDS):
			_reject("Classic Extra Code facts have invalid fields.")
			return null
		var record_id := _bounded_integer(row.id, 0, 2147483647, "Extra Code id")
		var values: Variant = _integer_array_range(row.values, 5, -32768, 32767, "Extra Code values")
		if record_id < 0 or seen.has(record_id) or values == null or not error_message().is_empty():
			if error_message().is_empty(): _reject("Classic Extra Code facts are duplicated or malformed.")
			return null
		seen[record_id] = true
		result.append(ClassicRecordCatalog.ExtraCodeFacts.new(record_id, values))
	return result

func _program_facts_cover_sources(sources: Dictionary, programs: Array[ClassicRecordCatalog.ProgramFacts]) -> bool:
	var facts_by_path: Dictionary = {}
	for facts: ClassicRecordCatalog.ProgramFacts in programs:
		var rows: Dictionary = facts_by_path.get(facts.native_path, {})
		rows[facts.id] = true
		facts_by_path[facts.native_path] = rows
	for definition: Array in [["Data DD", "land-action-points", 40], ["Data DDD", "dungeon-action-points", 40], ["Data ED3", "extra-action-points", 40], ["Data ED2", "complex-encounters", 520]]:
		var path: String = definition[0]
		var family: String = definition[1]
		var stride: int = definition[2]
		var row_ids: Dictionary = facts_by_path.get(path, {})
		if not sources.has(path):
			if not row_ids.is_empty(): return _reject("Classic program facts exist without source '%s'." % path)
			continue
		var source: ClassicRecordCatalog.Source = sources[path]
		var layout: ClassicRecordCatalog.Layout
		for candidate: ClassicRecordCatalog.Layout in source.layouts:
			if candidate.family == family:
				layout = candidate
				break
		if layout == null or layout.record_bytes != stride or row_ids.size() != layout.complete_records:
			return _reject("Classic program facts do not cover every complete '%s' source record." % path)
		for record_id: int in layout.complete_records:
			if not row_ids.has(record_id): return _reject("Classic program facts omit '%s' #%d." % [path, record_id])
	return true

func _extra_code_facts_cover_source(sources: Dictionary, extra_codes: Array[ClassicRecordCatalog.ExtraCodeFacts]) -> bool:
	var ids: Array[int] = []
	for facts: ClassicRecordCatalog.ExtraCodeFacts in extra_codes: ids.append(facts.id)
	return _facts_cover_source(sources, "Data EDCD", "extra-codes", ids)

func _decode_resources(value: Variant, sources: Dictionary) -> Variant:
	if not value is Array:
		_reject("Classic resources must be an array.")
		return null
	var result: Array[ClassicRecordCatalog.ResourceFacts] = []
	var occurrences: Dictionary = {}
	for row: Variant in value:
		if not row is Dictionary or not _exact_fields(row, RESOURCE_FIELDS):
			_reject("Classic resource facts have invalid fields.")
			return null
		if not row.nativePath is String or not sources.has(row.nativePath):
			_reject("Classic resource facts reference an undeclared source.")
			return null
		var resource_type_values: Variant = _integer_array_range(row.resourceTypeBytes, 4, 0, 255, "resourceTypeBytes")
		if resource_type_values == null or not _is_sha256(row.sha256):
			_reject("Classic resource type bytes or SHA-256 are invalid.")
			return null
		var resource_type_bytes := PackedByteArray()
		for byte_value: int in resource_type_values:
			resource_type_bytes.append(byte_value)
		var resource_id := _bounded_integer(row.resourceId, -32768, 32767, "Classic resourceId")
		var occurrence := _bounded_integer(row.occurrence, 0, 2147483647, "Classic resource occurrence")
		var byte_length := _bounded_integer(row.byteLength, 0, 2147483647, "Classic resource byteLength")
		if resource_id < -32768 or occurrence < 0 or byte_length < 0 or not error_message().is_empty():
			return null
		var path_occurrences: Dictionary = occurrences.get(row.nativePath, {})
		var occurrence_key := "%s:%d:%d" % [resource_type_bytes.hex_encode(), resource_id, occurrence]
		if path_occurrences.has(occurrence_key):
			_reject("Classic resource occurrences must be unique for each exact key within a source.")
			return null
		path_occurrences[occurrence_key] = true
		occurrences[row.nativePath] = path_occurrences
		result.append(ClassicRecordCatalog.ResourceFacts.new(row.nativePath, resource_type_bytes, resource_id, occurrence, row.sha256, byte_length))
	return result

func _decode_undecodable_sources(value: Variant, sources: Dictionary) -> Variant:
	if not value is Array:
		_reject("undecodableResourceSources must be an array.")
		return null
	var result: Array[String] = []
	var seen: Dictionary = {}
	for path: Variant in value:
		if not path is String or not sources.has(path) or seen.has(path):
			_reject("Undecodable resource source paths must be unique declared sources.")
			return null
		seen[path] = true
		result.append(path)
	return result

func _decode_source(value: Variant) -> ClassicRecordCatalog.Source:
	if not value is Dictionary or not _exact_fields(value, SOURCE_FIELDS) or not value.nativePath is String or value.nativePath.is_empty() or not _is_sha256(value.sha256) or not _is_sha256(value.effectiveSha256):
		_reject("Classic source facts have invalid fields, path, or SHA-256.")
		return null
	var length := _bounded_integer(value.byteLength, 0, 2147483647, "Classic source byteLength")
	var effective_length := _bounded_integer(value.effectiveByteLength, 0, 2147483647, "Classic source effectiveByteLength")
	if length < 0 or effective_length < 0 or not value.layouts is Array:
		return null
	var edits: Variant = _decode_edits(value.edits, length, effective_length)
	if edits == null:
		return null
	var layouts: Array[ClassicRecordCatalog.Layout] = []
	var seen_families: Dictionary = {}
	for row: Variant in value.layouts:
		if not row is Dictionary or not _exact_fields(row, LAYOUT_FIELDS) or not row.family is String or row.family.is_empty() or seen_families.has(row.family):
			_reject("Classic source layouts require unique families and exact fields.")
			return null
		seen_families[row.family] = true
		var stride := _bounded_integer(row.recordBytes, 1, 2147483647, "Classic recordBytes")
		var complete := _bounded_integer(row.completeRecords, 0, 2147483647, "Classic completeRecords")
		var tail := _bounded_integer(row.trailingBytes, 0, 2147483647, "Classic trailingBytes")
		if stride < 1 or complete < 0 or tail < 0 or tail >= stride or complete * stride + tail != effective_length:
			_reject("Classic source layout does not match its declared byte length.")
			return null
		var ranges: Variant = _decode_ranges(row.ownedByteRanges, stride)
		if ranges == null:
			return null
		layouts.append(ClassicRecordCatalog.Layout.new(row.family, stride, complete, tail, ranges))
	var expected_layout: Dictionary = ClassicRecordCatalog.SOURCE_LAYOUTS.get(value.nativePath, {})
	if not expected_layout.is_empty() and (layouts.size() != 1 or layouts[0].family != expected_layout.family or layouts[0].record_bytes != expected_layout.stride):
		_reject("Classic source '%s' must use its registered family and stride." % value.nativePath)
		return null
	return ClassicRecordCatalog.Source.new(value.nativePath, value.sha256, length, value.effectiveSha256, effective_length, edits, layouts)

func _decode_edits(value: Variant, original_length: int, effective_length: int) -> Variant:
	if not value is Array or value.size() > 100000:
		_reject("Classic source edits must be a bounded array.")
		return null
	var result: Array[ClassicRecordCatalog.Edit] = []
	var previous_offset := -1
	var previous_end := 0
	var computed_length := original_length
	for row: Variant in value:
		if not row is Dictionary or not _exact_fields(row, EDIT_FIELDS):
			_reject("Classic source edits require exact offset, before, and after fields.")
			return null
		var offset := _bounded_integer(row.offset, 0, original_length, "Classic source edit offset")
		var before: Variant = _edit_byte_array(row.before, "Classic source edit before")
		var after: Variant = _edit_byte_array(row.after, "Classic source edit after")
		if offset < 0 or before == null or after == null:
			return null
		if offset < previous_offset or offset < previous_end or offset + before.size() > original_length:
			_reject("Classic source edits must be sorted, disjoint, and within the original payload.")
			return null
		if before == after:
			_reject("Classic source edits must change their declared span.")
			return null
		previous_offset = offset
		previous_end = offset + before.size()
		computed_length += after.size() - before.size()
		result.append(ClassicRecordCatalog.Edit.new(offset, before, after))
	if computed_length != effective_length:
		_reject("Classic source edit lengths do not produce effectiveByteLength.")
		return null
	return result

func _edit_byte_array(value: Variant, label: String) -> Variant:
	if not value is Array or value.size() > 2147483647:
		_reject("%s must be a byte array." % label)
		return null
	var result: Array[int] = []
	for item: Variant in value:
		if not _is_integer(item):
			_reject("%s contains a non-integer byte." % label)
			return null
		var byte_value := _integer(item)
		if byte_value < 0 or byte_value > 255:
			_reject("%s contains a byte outside [0, 255]." % label)
			return null
		result.append(byte_value)
	return result

func _decode_ranges(value: Variant, stride: int) -> Variant:
	if not value is Array:
		_reject("Classic ownedByteRanges must be an array.")
		return null
	var result: Array[ClassicRecordCatalog.ByteRange] = []
	for row: Variant in value:
		if not row is Dictionary or not _exact_fields(row, RANGE_FIELDS):
			_reject("Classic byte ranges require exact start and end fields.")
			return null
		var start := _bounded_integer(row.start, 0, stride, "Classic byte range start")
		var finish := _bounded_integer(row.end, 0, stride, "Classic byte range end")
		if start < 0 or finish <= start:
			_reject("Classic owned byte range must be nonempty and within its record.")
			return null
		result.append(ClassicRecordCatalog.ByteRange.new(start, finish))
	return result

func _decode_simple(value: Variant) -> Variant:
	if not value is Array:
		_reject("Classic simple facts must be an array.")
		return null
	var result: Array[ClassicRecordCatalog.SimpleFacts] = []
	var ids: Dictionary = {}
	for row: Variant in value:
		if not row is Dictionary or not _exact_fields(row, SIMPLE_FIELDS):
			_reject("Classic simple facts have invalid fields.")
			return null
		var record_id := _bounded_integer(row.id, 0, 2147483647, "Classic simple id")
		if record_id < 0 or ids.has(record_id):
			_reject("Classic simple IDs must be unique nonnegative integers.")
			return null
		var record := ClassicRecordCatalog.SimpleFacts.new()
		record.id = record_id
		var codes: Variant = _integer_array_range(row.codes, 32, -128, 127, "simple codes")
		var operands: Variant = _integer_array_range(row.operands, 32, -32768, 32767, "simple operands")
		var choices: Variant = _integer_array_range(row.choiceResults, 4, -128, 127, "simple choiceResults")
		var text_slots: Variant = _byte_slots(row.textSlots, 4, 80, "simple textSlots")
		if codes == null or operands == null or choices == null or text_slots == null or not error_message().is_empty():
			return null
		record.codes = codes
		record.operands = operands
		record.choice_results = choices
		record.text_slots = text_slots
		record.can_back_out_byte = _bounded_integer(row.canBackOutByte, 0, 255, "canBackOutByte")
		record.max_times = _bounded_integer(row.maxTimes, -128, 127, "maxTimes")
		record.caste_success = _bounded_integer(row.casteSuccess, -128, 127, "casteSuccess")
		record.reserved_byte = _bounded_integer(row.reservedByte, 0, 255, "reservedByte")
		record.prompt_message_id = _bounded_integer(row.promptMessageId, -32768, 32767, "promptMessageId")
		if not error_message().is_empty() or record.can_back_out_byte < 0 or record.max_times < -128 or record.caste_success < -128 or record.reserved_byte < 0 or record.prompt_message_id < -32768:
			return null
		ids[record_id] = true
		result.append(record)
	return result

func _decode_timed(value: Variant) -> Variant:
	return _decode_fixed_records(value, TIMED_FIELDS, "timed", 20, -32768, 32767)

func _decode_shops(value: Variant) -> Variant:
	if not value is Array:
		_reject("Classic shop facts must be an array.")
		return null
	var result: Array[ClassicRecordCatalog.ShopFacts] = []
	var ids: Dictionary = {}
	for row: Variant in value:
		if not row is Dictionary or not _exact_fields(row, SHOP_FIELDS):
			_reject("Classic shop facts have invalid fields.")
			return null
		var record_id := _bounded_integer(row.id, 0, 2147483647, "Classic shop id")
		var item_ids: Variant = _integer_array_range(row.itemIds, 1000, -32768, 32767, "shop itemIds")
		var quantities: Variant = _integer_array_range(row.quantities, 1000, 0, 255, "shop quantities")
		var inflation := _bounded_integer(row.inflation, -32768, 32767, "shop inflation")
		if record_id < 0 or ids.has(record_id) or item_ids == null or quantities == null or inflation < -32768 or not error_message().is_empty():
			if error_message().is_empty(): _reject("Classic shop values are out of range or duplicated.")
			return null
		var record := ClassicRecordCatalog.ShopFacts.new()
		record.id = record_id
		record.item_ids = item_ids
		record.quantities = quantities
		record.inflation = inflation
		ids[record_id] = true
		result.append(record)
	return result

func _decode_fixed_records(value: Variant, fields: Array[String], label: String, count: int, minimum: int, maximum: int) -> Variant:
	if not value is Array:
		_reject("Classic %s facts must be an array." % label)
		return null
	var result: Array[ClassicRecordCatalog.TimedFacts] = []
	var ids: Dictionary = {}
	for row: Variant in value:
		if not row is Dictionary or not _exact_fields(row, fields):
			_reject("Classic %s facts have invalid fields." % label)
			return null
		var record_id := _bounded_integer(row.id, 0, 2147483647, "Classic %s id" % label)
		var words: Variant = _integer_array_range(row.words, count, minimum, maximum, "%s words" % label)
		if record_id < 0 or ids.has(record_id) or words == null or not error_message().is_empty():
			return null
		var record := ClassicRecordCatalog.TimedFacts.new()
		record.id = record_id
		record.words = words
		ids[record_id] = true
		result.append(record)
	return result

func _integer_array_range(value: Variant, size: int, minimum: int, maximum: int, label: String) -> Variant:
	var result: Variant = _integer_array(value, size, label)
	if result == null:
		return null
	if not _array_values_in_range(result, minimum, maximum):
		_reject("%s contains a value outside [%d, %d]." % [label, minimum, maximum])
		return null
	return result

func _byte_slots(value: Variant, slots: int, width: int, label: String) -> Variant:
	if not value is Array or value.size() != slots:
		_reject("%s must contain %d fixed byte slots." % [label, slots])
		return null
	var result: Array[Array] = []
	for slot: Variant in value:
		var bytes: Variant = _integer_array_range(slot, width, 0, 255, label)
		if bytes == null:
			return null
		result.append(bytes)
	return result

func _facts_cover_source(sources: Dictionary, path: String, family: String, ids: Array[int]) -> bool:
	if not sources.has(path):
		if ids.is_empty():
			return true
		return _reject("Classic facts exist without source '%s'." % path)
	var source: ClassicRecordCatalog.Source = sources[path]
	var layout: ClassicRecordCatalog.Layout
	for candidate: ClassicRecordCatalog.Layout in source.layouts:
		if candidate.family == family:
			layout = candidate
			break
	if layout == null or ids.size() != layout.complete_records:
		return _reject("Classic facts do not cover every complete '%s' source record." % path)
	var found: Dictionary = {}
	for record_id: int in ids:
		if record_id < 0 or record_id >= layout.complete_records or found.has(record_id):
			return _reject("Classic fact IDs do not exactly cover '%s'." % path)
		found[record_id] = true
	return true

func _record_ids(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(value.id)
	return result

func _bounded_integer(value: Variant, minimum: int, maximum: int, label: String) -> int:
	if not _is_integer(value):
		_reject("%s must be an integer." % label)
		return -1
	var parsed := _integer(value)
	if parsed < minimum or parsed > maximum:
		_reject("%s is outside [%d, %d]." % [label, minimum, maximum])
		return -1
	return parsed
