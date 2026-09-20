## Binds detached character facts to the editable Classic roster record.
class_name PartyRosterMemberRow
extends PanelContainer

var _compact_layout := false


func _ready() -> void:
	$Character/Details/Record.minimum_size_changed.connect(_update_height)
	_apply_layout()


func current_marker() -> ColorRect:
	return $Character/CurrentCharacterMarker as ColorRect


func character_button() -> Button:
	return $Character as Button


func selection_number() -> Label:
	return $Character/SelectionNumber as Label


func auto_toggle() -> Button:
	return $Character/CombatAuto as Button


func set_compact_layout(compact: bool) -> void:
	_compact_layout = compact
	if is_node_ready():
		_apply_layout()


func set_selected(selected: bool) -> void:
	$SelectionOutline.visible = selected


func bind_character(character: CharacterView, current_health: int, state_text: String) -> void:
	var spell_points := "%d/%d" % [character.spell_points, character.maximum_spell_points] if character.maximum_spell_points > 0 else "—"
	var summary := "%s\nHP %d/%d • SP %s • ATK %s • AR %d\n%s / %s" % [
		character.name, current_health, character.maximum_health, spell_points,
		character.attacks_per_round, character.armor, character.race_name, character.caste_name,
	]
	character_button().text = summary
	character_button().accessibility_name = "%s. Level %d. Movement %d/%d. %s" % [
		summary, character.level, character.movement, character.maximum_movement, state_text,
	]
	$Character/Details/Record/IdentityCell/Identity/CharacterName.text = character.name
	$Character/Details/Record/IdentityCell/Identity/ArmorCell/Armor/Value.text = str(character.armor)
	$Character/Details/Record/CharacterRoleCell/CharacterRole.text = "%s / %s" % [character.race_name, character.caste_name]
	$Character/Details/Record/Vitals/HealthCell/Health/Value.text = "%d/%d" % [current_health, character.maximum_health]
	$Character/Details/Record/Vitals/HealthCell/Health/Value.modulate = Color("e66e6d") if current_health * 2 < character.maximum_health else Color.WHITE
	$Character/Details/Record/Vitals/SpellPointsCell/SpellPoints/Value.text = spell_points
	$Character/Details/Record/Actions/AttacksCell/Attacks/Value.text = character.attacks_per_round
	$Character/Details/Record/Actions/MovementCell/Movement/Value.text = "%d/%d" % [character.movement, character.maximum_movement]


func _apply_layout() -> void:
	$Character/Details/Record/IdentityCell/Identity.vertical = _compact_layout
	$Character/Details/Record/Vitals.columns = 1 if _compact_layout else 2
	$Character/Details/Record/Actions.columns = 1 if _compact_layout else 2
	_update_height()


func _update_height() -> void:
	custom_minimum_size.y = maxf(76.0, $Character/Details/Record.get_combined_minimum_size().y + 2.0)
