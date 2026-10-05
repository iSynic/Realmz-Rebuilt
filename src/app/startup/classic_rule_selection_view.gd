## Detaches validated converter requirements from their storage representation.
class_name ClassicRuleSelectionView
extends RefCounted

var field: String
var minimum: int
var maximum: int
var application_minimum: int
var application_maximum: int
var scenario_minimum: int
var scenario_maximum: int
var origin: String


static func from_requirement(requirement: ClassicRuleSelectionRequirement) -> ClassicRuleSelectionView:
	if requirement == null:
		return null
	var result := ClassicRuleSelectionView.new()
	result.field = requirement.field
	result.minimum = requirement.minimum
	result.maximum = requirement.maximum
	result.application_minimum = requirement.application_minimum
	result.application_maximum = requirement.application_maximum
	result.scenario_minimum = requirement.scenario_minimum
	result.scenario_maximum = requirement.scenario_maximum
	result.origin = requirement.origin
	return result
