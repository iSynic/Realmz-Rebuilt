## Constructs the explicit adventure-owned rules command.
class_name AdventureRulesIntents
extends RefCounted


class Selection extends PlayerIntentPayload:
	var rules: AdventureRules

	func _init(selected: AdventureRules) -> void:
		rules = null if selected == null else selected.copy()


static func set_rules(rules: AdventureRules) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.SET_ADVENTURE_RULES, Selection.new(rules))
