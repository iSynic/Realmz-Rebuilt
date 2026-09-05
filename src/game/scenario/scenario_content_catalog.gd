## Indexes immutable campaign narration, triggers, and encounter definitions.

class_name ScenarioContentCatalog
extends RefCounted

var campaign: CampaignDefinition

var _messages: Dictionary = {}
var _option_labels: Dictionary = {}
var _triggers: Dictionary = {}
var _simple_encounters: Dictionary = {}
var _complex_encounters: Dictionary = {}
var _thief_encounters: Dictionary = {}
var _timed_encounters: Dictionary = {}


func _init(
		campaign_definition: CampaignDefinition,
		messages: Array[MessageDefinition],
		triggers: Array[TriggerDefinition],
		simple_encounters: Array[SimpleEncounterDefinition] = [],
		complex_encounters: Array[ComplexEncounterDefinition] = [],
		thief_encounters: Array[ThiefEncounterDefinition] = [],
		timed_encounters: Array[TimedEncounterDefinition] = [],
		option_labels: Array[OptionLabelDefinition] = []) -> void:
	campaign = campaign_definition
	_index_by_id(_messages, messages)
	_index_by_id(_option_labels, option_labels)
	_index_by_id(_triggers, triggers)
	_index_by_id(_simple_encounters, simple_encounters)
	_index_by_id(_complex_encounters, complex_encounters)
	_index_by_id(_thief_encounters, thief_encounters)
	_index_by_id(_timed_encounters, timed_encounters)


func message_by_id(message_id: int) -> MessageDefinition:
	return _messages.get(message_id) as MessageDefinition


func option_label_by_id(option_label_id: int) -> OptionLabelDefinition:
	return _option_labels.get(option_label_id) as OptionLabelDefinition


func has_option_labels() -> bool:
	return not _option_labels.is_empty()


func trigger_by_id(trigger_id: String) -> TriggerDefinition:
	return _triggers.get(trigger_id) as TriggerDefinition


func trigger_by_map_record(map_id: String, record_index: int) -> TriggerDefinition:
	for value: Variant in _triggers.values():
		var trigger := value as TriggerDefinition
		if trigger.map_id == map_id and trigger.classic_record_index == record_index:
			return trigger
	return null


func simple_encounter_by_id(encounter_id: int) -> SimpleEncounterDefinition:
	return _simple_encounters.get(encounter_id) as SimpleEncounterDefinition


func complex_encounter_by_id(encounter_id: int) -> ComplexEncounterDefinition:
	return _complex_encounters.get(encounter_id) as ComplexEncounterDefinition


func thief_encounter_by_id(encounter_id: int) -> ThiefEncounterDefinition:
	return _thief_encounters.get(encounter_id) as ThiefEncounterDefinition


func timed_encounter_by_id(encounter_id: int) -> TimedEncounterDefinition:
	return _timed_encounters.get(encounter_id) as TimedEncounterDefinition


func timed_encounters() -> Array[TimedEncounterDefinition]:
	var result: Array[TimedEncounterDefinition] = []
	var ids: Array = _timed_encounters.keys()
	ids.sort()
	for id: Variant in ids:
		result.append(_timed_encounters[id] as TimedEncounterDefinition)
	return result


static func _index_by_id(target: Dictionary, records: Array) -> void:
	for record: Variant in records:
		target[record.id] = record
