## Validates the converter's explicit Classic rule-selection requirement.
class_name ClassicRuleSelectionRequirement
extends RefCounted

var field: String
var minimum: int
var maximum: int
var application_minimum: int
var application_maximum: int
var scenario_minimum: int
var scenario_maximum: int
var origin: String


static func from_data(value: Variant) -> ClassicRuleSelectionRequirement:
	if not value is Dictionary or value.size() != 6:
		return null
	if value.get("field") != "nativeMenuSelection" or value.get("origin") != "explicit-intended-selection":
		return null
	var application: Variant = value.get("applicationRules")
	var scenario: Variant = value.get("scenarioFirst")
	if not application is Dictionary or application.size() != 2 or not scenario is Dictionary or scenario.size() != 2:
		return null
	var bounds: Array = [value.get("minimum"), value.get("maximum"), application.get("minimum"), application.get("maximum"), scenario.get("minimum"), scenario.get("maximum")]
	for index: int in bounds.size():
		var bound: Variant = bounds[index]
		if not (bound is int or bound is float) or not is_finite(float(bound)) or float(bound) != floorf(float(bound)) or bound < 1 or bound > 32767:
			return null
		bounds[index] = int(bound)
	if bounds != [1, 32767, 1, 19, 20, 32767]:
		return null
	var result := ClassicRuleSelectionRequirement.new()
	result.field = value.field
	result.minimum = int(bounds[0])
	result.maximum = int(bounds[1])
	result.application_minimum = int(bounds[2])
	result.application_maximum = int(bounds[3])
	result.scenario_minimum = int(bounds[4])
	result.scenario_maximum = int(bounds[5])
	result.origin = value.origin
	return result
