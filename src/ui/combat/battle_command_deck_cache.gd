## Prepares one unbound battle command deck across idle presentation frames.
class_name BattleCommandDeckCache
extends RefCounted

var _prepared: BattleInteraction
var _preparing := false
var _released := false


func prepare(host: Node) -> void:
	if _released or _prepared != null or _preparing or not is_instance_valid(host) or not host.is_inside_tree(): return
	_preparing = true
	var tree := host.get_tree()
	await tree.process_frame
	_preparing = false
	if _released: return
	_prepared = (load(InteractionComponentFactory.BATTLE_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as BattleInteraction
	var deck := _prepared
	var profile := BattleCommandScaleController.standalone_profile(1.0)
	for group: String in ["BattleInspectionCommandsInset", "BattlePrimaryCommandsInset", "BattleTurnCommandsInset"]:
		await tree.process_frame
		if _released or _prepared != deck: return
		var panel := deck.find_child(group, true, false) as Control
		UiSizing.apply(panel, profile)
		panel.remove_meta(UiSizing.PROFILE)
	await tree.process_frame
	if not _released and _prepared == deck: UiSizing.apply(deck, profile)


func take() -> BattleInteraction:
	var deck := _prepared
	_prepared = null
	if deck != null and deck.has_meta(UiSizing.PROFILE): deck.remove_meta(UiSizing.PROFILE)
	return deck


func release() -> void:
	_released = true
	if _prepared != null: _prepared.free()
	_prepared = null
