extends "res://tests/presentation/classic_ui_test_support.gd"

## The modular combat HUD: the battle deck floating as separate pieces over a full-window battlefield.


func run() -> void:
	await _test_battle_floating_deck()


func _test_battle_floating_deck() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var request := _fixture_request("battle.commands", InteractionRequest.COMBAT, {"actions": ["finish", "defend"]})
	var presenter := (load("res://src/ui/shared/interactions/interaction_presenter.tscn") as PackedScene).instantiate() as InteractionPresenter
	tree.root.add_child(presenter)
	await tree.process_frame
	UiSizing.apply(presenter, UiLayoutProfile.for_viewport(Vector2(1280.0, 720.0), PresentationSettings.UI_SCALE_AUTO))
	var strip := Rect2(0.0, 530.0, 1280.0, 190.0)
	var area := Rect2(0.0, 0.0, 1280.0, 720.0)
	var placed := HudPreferences.new()
	placed.place(7, Vector2(1.0, 0.0), &"")
	BattleCommandScaleController.modular = true
	BattleDeckLayout.preferences = placed
	BattleDeckLayout.area = area
	presenter.set_classic_regions(area.grow(-8.0), strip, strip)
	presenter.present(request)
	await tree.process_frame
	await tree.process_frame
	var deck := presenter.find_child("BattleOverview", true, false).get_parent() as BattleInteraction
	var pieces: Array[Control] = [deck.find_child("ActiveCombatant", true, false), deck.get_node("%BattleInitiativeHost"), deck.find_child("BattleInspectionCommandsInset", true, false), deck.get_node("%BattlePrimaryCommandsInset"), deck.find_child("BattleTurnCommandsInset", true, false)]
	var free := area.grow(-8.0)
	assert_true(deck.deck_layout.parked() and pieces.all(func(piece: Control) -> bool: return piece.top_level and free.encloses(Rect2(piece.position, piece.size))), "the modular combat HUD stands the combatant card, turn order and each command group inside the window, free of the command region")
	assert_true(presenter.position.y >= area.end.y, "the emptied command region waits below the window so the battlefield is uncovered")
	assert_true(is_equal_approx(pieces[0].position.x, free.position.x) and is_equal_approx(pieces[0].position.y, free.position.y) and absf(pieces[1].get_rect().get_center().x - free.get_center().x) <= 1.0 and is_equal_approx(pieces[2].get_rect().end.y, free.end.y) and is_equal_approx(pieces[4].get_rect().end.x, free.end.x), "unplaced pieces rest at the card's top-left corner, the turn order's top centre and the lower edge")
	assert_true(is_equal_approx(pieces[3].get_rect().end.x, free.end.x) and is_equal_approx(pieces[3].position.y, free.position.y), "a piece the combat HUD preferences place stands at its saved fraction of the free space")
	assert_true(pieces[2].size.y < pieces[3].size.y, "a folded command group is only as tall as its tab")
	var floating_turn := pieces[1].find_child("BattleInitiativeOrder", true, false).get_child(0) as Button
	floating_turn.text = "NOW"
	floating_turn.icon = GradientTexture1D.new()
	deck.deck_layout.place()
	await tree.process_frame
	assert_true(floating_turn.custom_minimum_size.x >= 64.0 and floating_turn.size.x >= 64.0 and free.encloses(Rect2(pieces[1].position, pieces[1].size)), "a floating turn entry keeps room for its combatant's portrait beside the label")
	var saved: Array[HudPreferences] = []
	BattleDeckLayout.save = func(value: HudPreferences) -> void: saved.append(value)
	var grab := InputEventMouseButton.new()
	grab.button_index = MOUSE_BUTTON_LEFT
	grab.pressed = true
	grab.ctrl_pressed = true
	grab.position = pieces[3].get_rect().get_center()
	var slide := InputEventMouseMotion.new()
	slide.position = free.get_center()
	var drop := InputEventMouseButton.new()
	drop.button_index = MOUSE_BUTTON_LEFT
	drop.position = free.get_center()
	assert_true(deck.deck_layout.handle_input(grab) and deck.deck_layout.handle_input(slide) and deck.deck_layout.handle_input(drop) and saved.size() == 1 and saved[0].extra_panels[0].custom_position and absf(saved[0].extra_panels[0].position.x - 0.5) < 0.1 and HudPreferences.from_data(saved[0].to_data()).extra_panels[0].custom_position and absf(pieces[3].get_rect().get_center().x - free.get_center().x) <= 2.0, "Ctrl+drag moves a floating battle piece and saves its place in the combat HUD preferences once, on release")
	var plain := InputEventMouseButton.new()
	plain.button_index = MOUSE_BUTTON_LEFT
	plain.pressed = true
	plain.position = pieces[3].get_rect().get_center()
	assert_true(not deck.deck_layout.handle_input(plain) and saved.size() == 1, "an ordinary click on a piece is left to its commands")
	var context := InputEventMouseButton.new()
	context.button_index = MOUSE_BUTTON_RIGHT
	context.pressed = true
	context.position = pieces[3].get_rect().get_center()
	var piece_menu := deck.get_node("%DeckPieceMenu") as PopupMenu
	assert_true(deck.deck_layout.handle_input(context) and piece_menu.visible, "a right-click on a floating piece opens its menu instead of reaching the battlefield")
	piece_menu.hide()
	piece_menu.id_pressed.emit(1)
	assert_true(saved.size() == 2 and not saved[1].extra_panels[0].custom_position and is_equal_approx(pieces[4].get_rect().end.x, free.end.x) and absf(pieces[3].get_rect().get_center().x - free.get_center().x) <= 1.0, "the piece menu's reset returns every piece to its resting place and saves that")
	# The plain resting arrangement at the combat sizes; a new profile's own default layout is covered in test_ui_themes.
	var enlarged := HudPreferences.new(); enlarged.panels[HudPreferences.PanelId.ROSTER].auto_hide = true; enlarged.adopt_combat_scales()
	BattleDeckLayout.preferences = enlarged
	deck.deck_layout.place()
	var heading_size := (pieces[3].find_child("Heading", true, false) as Label).get_theme_font_size(&"font_size")
	assert_true(pieces.all(func(piece: Control) -> bool: return piece.scale == Vector2.ONE and free.grow(1.0).encloses(Rect2(piece.position, piece.size))) and is_equal_approx(UiSizing.profile_for(pieces[0]).ui_scale, 1.25) and is_equal_approx(UiSizing.profile_for(pieces[1]).ui_scale, 1.25) and is_equal_approx(UiSizing.profile_for(pieces[2]).ui_scale, 1.5) and is_equal_approx(UiSizing.profile_for(pieces[4]).ui_scale, 1.5) and heading_size == 18 and pieces[3].size.x > 300.0 and absf(pieces[4].get_rect().end.x - free.end.x) <= 1.0, "at the combat default the card and turn order are laid out a quarter larger and the command groups half as large again, with text set at that size and not stretched, all inside the window")
	var turn_order := pieces[1].find_child("BattleInitiativeOrder", true, false) as BoxContainer
	var across := pieces[1].size
	context.position = pieces[1].get_rect().get_center()
	assert_true(not turn_order.vertical and deck.deck_layout.handle_input(context), "the turn order runs across the screen until asked otherwise")
	piece_menu.hide()
	piece_menu.id_pressed.emit(4)
	await tree.process_frame
	assert_true(turn_order.vertical and saved[-1].orientation_of(2) == "vertical" and pieces[1].size.y > across.y and pieces[1].size.x < across.x, "Vertical turn order on its menu stacks the turns down the screen and saves the choice")
	piece_menu.id_pressed.emit(4)
	await tree.process_frame
	assert_true(not turn_order.vertical, "choosing it again returns the turn order to a row")
	context.position = pieces[3].position + pieces[3].size * 0.75
	assert_true(deck.deck_layout.handle_input(context), "the enlarged piece answers a right-click anywhere in the space it takes on screen")
	piece_menu.hide()
	piece_menu.id_pressed.emit(3)
	assert_true(is_equal_approx(saved[-1].extra_panels[0].scale, 1.25) and is_equal_approx(UiSizing.profile_for(pieces[3]).ui_scale, 1.25) and is_equal_approx(UiSizing.profile_for(pieces[2]).ui_scale, 1.5), "Smaller on a piece's menu steps that piece alone and saves it")
	BattleDeckLayout.save = Callable()
	BattleDeckLayout.obscured = func() -> bool: return true
	deck.deck_layout.poll_obscured()
	assert_true(pieces.all(func(piece: Control) -> bool: return not piece.visible) and not deck.deck_layout.handle_input(context), "while the pause menu or Combat Log stands over the battle the floating pieces step aside, so they cannot take its clicks")
	BattleDeckLayout.obscured = Callable()
	deck.deck_layout.poll_obscured()
	assert_true(pieces[0].visible and pieces[3].visible, "the pieces return when the battle is uncovered")
	var shown := deck.find_child("InspectedCombatant", true, false) as Control
	deck.inspect_combatant("monster")
	await tree.process_frame
	assert_true(shown.visible and not pieces[0].visible and shown.position == pieces[0].position, "inspecting another combatant swaps the single card to it in place")
	deck.inspect_combatant("hero")
	await tree.process_frame
	assert_true(pieces[0].visible and not shown.visible, "returning to the acting combatant restores its summary on the single card")
	BattleDeckLayout.area = Rect2()
	presenter.set_classic_regions(Rect2(0.0, 28.0, 992.0, 502.0), strip, strip)
	await tree.process_frame
	assert_true(not deck.deck_layout.floating and pieces.all(func(piece: Control) -> bool: return not piece.top_level) and shown.visible and presenter.position == strip.position, "leaving the modular combat layout returns every piece to the docked deck in its command region")
	BattleCommandScaleController.modular = false
	BattleDeckLayout.preferences = null
	presenter.free()
