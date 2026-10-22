## Immutable typed projection of the native facts retained by Providence.
class_name ClassicRecordCatalog
extends RefCounted

enum Availability { ABSENT, COMPLETE, PARTIAL }
const SOURCE_LAYOUTS := {
	"Data LD": {"family": "land-maps", "stride": 16200},
	"Data DL": {"family": "dungeon-maps", "stride": 16200},
	"Layout": {"family": "land-layout", "stride": 256},
	"Data RD": {"family": "land-random-levels", "stride": 644},
	"Data RDD": {"family": "dungeon-random-levels", "stride": 644},
	"Data DD": {"family": "land-action-points", "stride": 40},
	"Data DDD": {"family": "dungeon-action-points", "stride": 40},
	"Data EDCD": {"family": "extra-codes", "stride": 10},
	"Data ED": {"family": "simple-encounters", "stride": 426},
	"Data ED2": {"family": "complex-encounters", "stride": 520},
	"Data ED3": {"family": "extra-action-points", "stride": 40},
	"Data TD2": {"family": "rogue-encounters", "stride": 118},
	"Data TD3": {"family": "timed-encounters", "stride": 40},
	"Data SD": {"family": "shop-records", "stride": 3002},
	"Data TD": {"family": "treasure-records", "stride": 48},
	"Data BD": {"family": "battle-records", "stride": 346},
	"Data MD": {"family": "scenario-monsters", "stride": 210},
	"Data MD1": {"family": "monster-variant-records", "stride": 210},
	"Data MD-1": {"family": "mega-monster-variant-records", "stride": 210},
	"Data DES": {"family": "monster-descriptions", "stride": 256},
	"Data Race": {"family": "race-rules", "stride": 408},
	"Data Caste": {"family": "caste-rules", "stride": 576},
	"Data S": {"family": "standard-spell-definitions", "stride": 30},
	"Data Spell": {"family": "scenario-spell-definitions", "stride": 30},
	"Data NI": {"family": "scenario-item-definitions", "stride": 100},
	"Data ID": {"family": "item-definitions", "stride": 100},
	"Data SD2": {"family": "scenario-messages", "stride": 256},
	"Data OD": {"family": "option-labels", "stride": 25},
	"Data MD2": {"family": "player-maps", "stride": 340},
	"Global": {"family": "global-macro-hooks", "stride": 60},
	"Data CI": {"family": "scenario-contact-info", "stride": 4608},
	"Data CS": {"family": "scenario-security-backup", "stride": 316},
	"Data RI": {"family": "scenario-restrictions", "stride": 320},
	"Scenario": {"family": "scenario-support", "stride": 600},
	"Data Solids": {"family": "special-land-solidity", "stride": 1024},
	"Data Custom 1 BD": {"family": "custom-landlook-metadata", "stride": 40},
	"Data Custom 2 BD": {"family": "custom-landlook-metadata", "stride": 40},
	"Data Custom 3 BD": {"family": "custom-landlook-metadata", "stride": 40},
}

class ByteRange extends RefCounted:
	var start: int
	var end: int
	func _init(p_start: int, p_end: int) -> void:
		start = p_start
		end = p_end

class Layout extends RefCounted:
	var family: String
	var record_bytes: int
	var complete_records: int
	var trailing_bytes: int
	var owned_byte_ranges: Array[ByteRange] = []
	func _init(p_family: String, stride: int, complete: int, tail: int, ranges: Array[ByteRange]) -> void:
		family = p_family
		record_bytes = stride
		complete_records = complete
		trailing_bytes = tail
		owned_byte_ranges = ranges.duplicate()

class Edit extends RefCounted:
	var offset: int
	var before: Array[int] = []
	var after: Array[int] = []
	func _init(p_offset: int, p_before: Array[int], p_after: Array[int]) -> void:
		offset = p_offset
		before = p_before.duplicate()
		after = p_after.duplicate()

class Source extends RefCounted:
	var native_path: String
	var sha256: String
	var byte_length: int
	var effective_sha256: String
	var effective_byte_length: int
	var edits: Array[Edit] = []
	var layouts: Array[Layout] = []
	func _init(path: String, digest: String, length: int, effective_digest: String, effective_length: int, edit_values: Array[Edit], values: Array[Layout]) -> void:
		native_path = path
		sha256 = digest
		byte_length = length
		effective_sha256 = effective_digest
		effective_byte_length = effective_length
		edits = edit_values.duplicate()
		layouts = values.duplicate()

class Lookup extends RefCounted:
	var availability: Availability
	var native_path: String
	var family: String
	var native_index: int
	var byte_start: int
	var byte_end: int
	var available_bytes: int
	func _init(state: Availability, path: String, record_family: String, index: int, start: int, finish: int, available: int) -> void:
		availability = state
		native_path = path
		family = record_family
		native_index = index
		byte_start = start
		byte_end = finish
		available_bytes = available

class SimpleFacts extends RefCounted:
	var id: int
	var codes: Array[int] = []
	var operands: Array[int] = []
	var choice_results: Array[int] = []
	var can_back_out_byte: int
	var max_times: int
	var caste_success: int
	var reserved_byte: int
	var prompt_message_id: int
	var text_slots: Array[Array] = []

class TimedFacts extends RefCounted:
	var id: int
	var words: Array[int] = []

class ShopFacts extends RefCounted:
	var id: int
	var item_ids: Array[int] = []
	var quantities: Array[int] = []
	var inflation: int

class PlayerMapFacts extends RefCounted:
	var id: int
	var words: Array[int] = []
	var note_bytes: Array[int] = []
	func can_project() -> bool:
		# PICT uses the map identity only for its optional current-party marker.
		return id < 20 and (words[35] < 0 or words[34] > 0 and (words[33] != 0 or words[32] >= 0))

class ProgramFacts extends RefCounted:
	var native_path: String
	var id: int
	var prefix: Array[int] = []
	var codes: Array[int] = []
	var operands: Array[int] = []
	var suffix: Array[int] = []
	func _init(path: String, native_id: int, prefix_bytes: Array[int], native_codes: Array[int], native_operands: Array[int], suffix_bytes: Array[int]) -> void:
		native_path = path
		id = native_id
		prefix = prefix_bytes.duplicate()
		codes = native_codes.duplicate()
		operands = native_operands.duplicate()
		suffix = suffix_bytes.duplicate()

class ProjectionDigest extends RefCounted:
	var sha256: String
	func _init(value: String) -> void:
		sha256 = value

class RuleProjection extends RefCounted:
	var family: StringName
	var id: String
	var digest: ProjectionDigest
	func _init(kind: StringName, identity: String, commitment: ProjectionDigest) -> void:
		family = kind
		id = identity
		digest = commitment

class RuleSelection extends RefCounted:
	var native_menu_selection: int
	var captured_source_set_sha256: String
	var race_source: StringName
	var caste_source: StringName
	var projected_rules: Array[RuleProjection] = []

class ExtraCodeFacts extends RefCounted:
	var id: int
	var values: Array[int] = []
	func _init(native_id: int, native_values: Array[int]) -> void:
		id = native_id
		values = native_values.duplicate()

class ResourceFacts extends RefCounted:
	var native_path: String
	var resource_type_bytes: PackedByteArray
	var resource_id: int
	var occurrence: int
	var sha256: String
	var byte_length: int
	func _init(path: String, type_bytes: PackedByteArray, id: int, ordinal: int, digest: String, length: int) -> void:
		native_path = path
		resource_type_bytes = type_bytes.duplicate()
		resource_id = id
		occurrence = ordinal
		sha256 = digest
		byte_length = length

var _sources: Array[Source] = []
var _source_by_path: Dictionary = {}
var _simple_by_id: Dictionary = {}
var _timed_by_id: Dictionary = {}
var _shop_by_id: Dictionary = {}
var _player_map_by_id: Dictionary = {}
var _program_by_key: Dictionary = {}
var _extra_code_by_id: Dictionary = {}
var _resource_facts: Array[ResourceFacts] = []
var _undecodable_resource_sources: Array[String] = []
var _native_races: Array[RaceDefinition] = []
var _native_castes: Array[CasteDefinition] = []
var rule_selection: RuleSelection

var resource_facts: Array[ResourceFacts]:
	get:
		return _resource_facts.duplicate()

var undecodable_resource_source_paths: Array[String]:
	get:
		return _undecodable_resource_sources.duplicate()


func _init(source_values: Array[Source] = [], simple_values: Array[SimpleFacts] = [], timed_values: Array[TimedFacts] = [], shop_values: Array[ShopFacts] = [], program_values: Array[ProgramFacts] = [], extra_code_values: Array[ExtraCodeFacts] = [], resource_values: Array[ResourceFacts] = [], undecodable_paths: Array[String] = [], player_map_values: Array[PlayerMapFacts] = [], selection: RuleSelection = null, native_race_values: Array[RaceDefinition] = [], native_caste_values: Array[CasteDefinition] = []) -> void:
	rule_selection = selection
	_native_races = native_race_values.duplicate()
	_native_castes = native_caste_values.duplicate()
	for value: Source in source_values:
		_add_source(value)
	for value: SimpleFacts in simple_values:
		_add_simple(value)
	for value: TimedFacts in timed_values:
		_add_timed(value)
	for value: ShopFacts in shop_values:
		_add_shop(value)
	for value: ProgramFacts in program_values:
		_add_program(value)
	for value: ExtraCodeFacts in extra_code_values:
		_add_extra_code(value)
	for value: PlayerMapFacts in player_map_values:
		_player_map_by_id[value.id] = value
	_resource_facts = resource_values.duplicate()
	_undecodable_resource_sources = undecodable_paths.duplicate()

func source_by_path(native_path: String) -> Source:
	return _source_by_path.get(native_path)

func simple_by_id(record_id: int) -> SimpleFacts:
	return _simple_by_id.get(record_id)

func timed_by_id(record_id: int) -> TimedFacts:
	return _timed_by_id.get(record_id)

func shop_by_id(record_id: int) -> ShopFacts:
	return _shop_by_id.get(record_id)

func player_map_by_id(record_id: int) -> PlayerMapFacts:
	return _player_map_by_id.get(record_id)

func program_by_path_and_id(native_path: String, record_id: int) -> ProgramFacts:
	return _program_by_key.get("%s:%d" % [native_path, record_id])

func extra_code_by_id(record_id: int) -> ExtraCodeFacts:
	return _extra_code_by_id.get(record_id)

func sources() -> Array[Source]:
	return _sources.duplicate()


func native_races() -> Array[RaceDefinition]:
	return _native_races.duplicate()


func native_castes() -> Array[CasteDefinition]:
	return _native_castes.duplicate()

func can_prove_resource_absence(resource_type: String, resource_id: int) -> bool:
	if resource_type.length() != 4:
		return false
	var query_bytes := resource_type.to_utf8_buffer()
	if query_bytes.size() != 4:
		return false
	for byte_value: int in query_bytes:
		if byte_value > 0x7f:
			return false
	for facts: ResourceFacts in _resource_facts:
		if facts.resource_type_bytes == query_bytes and facts.resource_id == resource_id:
			return false
	return _undecodable_resource_sources.is_empty()

func lookup(native_path: String, native_index: int, family: String = "") -> Lookup:
	var source := source_by_path(native_path)
	if source == null or native_index < 0:
		return Lookup.new(Availability.ABSENT, native_path, family, native_index, 0, 0, 0)
	for layout: Layout in source.layouts:
		if not family.is_empty() and layout.family != family:
			continue
		var start := native_index * layout.record_bytes
		if start >= source.effective_byte_length:
			continue
		var available := mini(layout.record_bytes, source.effective_byte_length - start)
		if available == layout.record_bytes and native_index < layout.complete_records:
			return Lookup.new(Availability.COMPLETE, native_path, layout.family, native_index, start, start + layout.record_bytes, layout.record_bytes)
		if available < layout.record_bytes:
			return Lookup.new(Availability.PARTIAL, native_path, layout.family, native_index, start, start + available, available)
	return Lookup.new(Availability.ABSENT, native_path, family, native_index, 0, 0, 0)

func _add_source(value: Source) -> void:
	_sources.append(value)
	_source_by_path[value.native_path] = value

func _add_simple(value: SimpleFacts) -> void:
	_simple_by_id[value.id] = value

func _add_timed(value: TimedFacts) -> void:
	_timed_by_id[value.id] = value

func _add_shop(value: ShopFacts) -> void:
	_shop_by_id[value.id] = value

func _add_program(value: ProgramFacts) -> void:
	_program_by_key["%s:%d" % [value.native_path, value.id]] = value

func _add_extra_code(value: ExtraCodeFacts) -> void:
	_extra_code_by_id[value.id] = value
