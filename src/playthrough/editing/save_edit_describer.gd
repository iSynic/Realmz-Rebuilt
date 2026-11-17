## Words for each listed save editor party change.

class_name SaveEditDescriber
extends RefCounted

var _content: RealmzContent
## Saved ally names by ally ID, so a dismissed ally keeps its name in the change list.
var _saved_allies := {}
var _saved_difficulty := 0
var _saved_monster_set := 0


func _init(content: RealmzContent, saved_state: GameState) -> void:
	_content = content
	_saved_difficulty = saved_state.difficulty
	_saved_monster_set = saved_state.monster_set
	for ally: MonsterState in saved_state.party.allies():
		_saved_allies[ally.id] = ally.name


## `label` and `detail` for one party change in `draft`.
func describe(operation: Dictionary, draft: SaveEditDraft) -> Dictionary:
	var kind: StringName = operation.kind
	match kind:
		&"difficulty":
			var difficulty: int = operation.value
			return _row("Difficulty", "%s → %s" % [PartySetupView.difficulty_name(_saved_difficulty), PartySetupView.difficulty_name(difficulty)])
		&"monster_set":
			var monster_set: int = operation.value
			return _row("Monsters", "%s → %s" % [PartySetupView.monster_set_name(_saved_monster_set), PartySetupView.monster_set_name(monster_set)])
		&"add_character":
			var added_id: String = operation.character_id
			return _row("Added %s" % _member_name(draft, added_id), "Joins from Character Files")
		&"drop_character":
			var keep: bool = operation.keep
			var dropped_id: String = operation.character_id
			return _row("Dropped %s" % _member_name(draft, dropped_id), "Kept in Character Files as a new character" if keep else "Leaves this save")
		&"add_ally":
			var definition_id: String = operation.definition_id
			var definition := _content.combat.monster_by_id(definition_id)
			return _row("Added ally %s" % (definition.name if definition != null else "creature"), "Travels with the party")
		&"dismiss_ally":
			var ally_id: String = operation.ally_id
			var ally_name: String = _saved_allies.get(ally_id, "an ally")
			return _row("Dismissed %s" % ally_name, "Leaves the party")
	return _row("Change", "")


static func _member_name(draft: SaveEditDraft, character_id: String) -> String:
	var target := draft.member(character_id)
	return target.state().name if target != null else "a character"


static func _row(label: String, detail: String) -> Dictionary:
	return {"label": label, "detail": detail}
