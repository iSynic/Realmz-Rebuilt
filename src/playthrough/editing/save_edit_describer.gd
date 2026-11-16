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
	match StringName(operation.kind):
		&"difficulty":
			return _row("Difficulty", "%s → %s" % [PartySetupView.difficulty_name(_saved_difficulty), PartySetupView.difficulty_name(int(operation.value))])
		&"monster_set":
			return _row("Monsters", "%s → %s" % [PartySetupView.monster_set_name(_saved_monster_set), PartySetupView.monster_set_name(int(operation.value))])
		&"add_character":
			return _row("Added %s" % _member_name(draft, String(operation.character_id)), "Joins from Character Files")
		&"drop_character":
			var detail := "Kept in Character Files as a new character" if bool(operation.keep) else "Leaves this save"
			return _row("Dropped %s" % _member_name(draft, String(operation.character_id)), detail)
		&"add_ally":
			var definition := _content.combat.monster_by_id(String(operation.definition_id))
			return _row("Added ally %s" % (definition.name if definition != null else "creature"), "Travels with the party")
		&"dismiss_ally":
			return _row("Dismissed %s" % String(_saved_allies.get(String(operation.ally_id), "an ally")), "Leaves the party")
	return _row("Change", "")


static func _member_name(draft: SaveEditDraft, character_id: String) -> String:
	var target := draft.member(character_id)
	return target.state().name if target != null else "a character"


static func _row(label: String, detail: String) -> Dictionary:
	return {"label": label, "detail": detail}
