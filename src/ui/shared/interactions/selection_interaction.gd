## Binds character-target context and surviving-allies requests to one authored scene.

class_name SelectionInteraction
extends InteractionComponent

const GOLD := Color("e0bc53")
const MUTED := Color("9ca3ad")

@export var ally_candidate_scene: PackedScene
@export var spell_target_badge_scene: PackedScene

var _checks: Array[CheckButton] = []
var _media: ClassicMediaCatalog
var _game_view: GameView
var _ally_summary: Label
var _ally_maximum := 0


func _ready() -> void:
	(%AllySelectionContinue as Button).pressed.connect(_submit_allies)


func configure(media: ClassicMediaCatalog, game_view: GameView = null) -> void:
	_media = media
	_game_view = game_view


func build(request: InteractionRequest) -> void:
	_checks.clear()
	(%CharacterSelectionMode as Control).visible = request.kind == &"character_selection"
	(%AllySelectionMode as Control).visible = request.kind == &"ally_selection"
	if request.kind == &"character_selection":
		_build_character_selection(request)
	else:
		_build_ally_selection(request)


func _build_character_selection(request: InteractionRequest) -> void:
	var body := request.body as CharacterSelectionRequestBody
	if body == null:
		return
	var context_panel := %SpellTargetContext as PanelContainer
	context_panel.visible = body.spell_context != null
	if body.spell_context != null:
		_bind_spell_target_context(body.spell_context)
	(%CharacterSelectionHint as Label).text = "Choose %d party member%s from the Party roster." % [body.count, "" if body.count == 1 else "s"]


func _bind_spell_target_context(context: InteractionRequestValue.SpellTargetContext) -> void:
	var panel := %SpellTargetContext as PanelContainer
	panel.tooltip_text = context.description
	var icon := %SpellContextIcon as TextureRect
	icon.texture = _spell_icon(context)
	icon.visible = icon.texture != null
	(%SpellContextName as Label).text = context.spell_name
	var source_label: String = String({&"field-spell": "Memorized spell", &"scroll-use": "Scroll", &"item-use": "Item magic"}.get(context.source_kind, "Spell"))
	var cost_label := " • Cost %d SP" % context.spell_point_cost if context.spell_point_cost > 0 else ""
	(%SpellContextSource as Label).text = "%s • Power %d%s" % [source_label, context.power, cost_label]
	(%SpellContextTarget as Label).text = "%s • %d target%s" % [_target_label(context.target_type), context.target_count, "" if context.target_count == 1 else "s"]
	var badge_host := %SpellTargetBadgeHost as HBoxContainer
	_clear_children(badge_host)
	var target_badge := spell_target_badge_scene.instantiate() as ClassicSpellTargetBadge
	if target_badge.present(context.target_type, context.target_size, _target_label(context.target_type), Vector2(48.0, 48.0)):
		badge_host.add_child(target_badge)
	else:
		target_badge.free()


func _spell_icon(context: InteractionRequestValue.SpellTargetContext) -> Texture2D:
	if _media == null or context.icon_id <= 0:
		return null
	return _media.image_texture(_media.asset_by_resource(context.icon_resource_type, context.icon_id))


static func _target_label(target_type: int) -> String:
	return {0: "Up to power", 1: "Party member", 3: "Fixed area", 4: "Power-sized area", 5: "Caster", 7: "Party state", 9: "All friendly", 10: "All enemies", 12: "Everybody"}.get(target_type, "Classic target type %d" % target_type)


func _build_ally_selection(request: InteractionRequest) -> void:
	var body := request.body as SelectionRequestBody
	if body == null:
		return
	_ally_maximum = body.maximum
	_ally_summary = %AllySelectionSummary as Label
	(%AllySelectionCapacity as Label).text = "Keep up to %d" % body.maximum
	var grid := %AllyCandidateGrid as GridContainer
	_clear_children(grid)
	(%AllySelectionEmpty as Control).visible = body.candidates.is_empty()
	for entry: InteractionRequestValue.SelectionCandidate in body.candidates:
		var required := body.required_ids.has(entry.id)
		var check := ally_candidate_scene.instantiate() as CheckButton
		check.call("bind_candidate", entry, required or body.selected_ids.has(entry.id), required, _ally_icon(entry.id))
		check.toggled.connect(_refresh_ally_selection.unbind(1))
		grid.add_child(check)
		_checks.append(check)
	_refresh_ally_selection()


func _submit_allies() -> void:
	var ids := _selected_ids()
	if ids.size() > _ally_maximum:
		_ally_summary.text = "Choose no more than %d allies." % _ally_maximum
		return
	response_body_submitted.emit(InteractionResponse.AllySelectionBody.new(ids))


func _refresh_ally_selection() -> void:
	if _ally_summary == null:
		return
	var selected := _selected_ids()
	_ally_summary.text = "%d of %d selected" % [selected.size(), _ally_maximum]
	for check: CheckButton in _checks:
		var required := bool(check.get_meta(&"required", false))
		check.disabled = required or not check.button_pressed and selected.size() >= _ally_maximum


func _selected_ids() -> Array[String]:
	var ids: Array[String] = []
	for check: CheckButton in _checks:
		if check.button_pressed:
			ids.append(String(check.get_meta(&"character_id")))
	return ids


func _ally_icon(ally_id: String) -> Texture2D:
	if _game_view == null or _media == null:
		return null
	if _game_view.combat_view != null:
		for ally: MonsterView in _game_view.combat_view.monsters:
			if ally.id == ally_id and ally.icon_id > 0:
				return _media.image_texture(_media.asset_by_resource(ally.icon_resource_type, ally.icon_id))
	for ally: MonsterView in _game_view.party_allies:
		if ally.id == ally_id and ally.icon_id > 0:
			return _media.image_texture(_media.asset_by_resource(ally.icon_resource_type, ally.icon_id))
	return null


static func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.free()
