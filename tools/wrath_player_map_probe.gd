## Probes Wrath's exact player-map marker media through the Journal presenter.
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var valid_shape := arguments.size() == 2 or arguments.size() == 3 and arguments[2] == "--visual" or arguments.size() == 4 and arguments[2] == "--visual" and arguments[3].begins_with("--capture-dir=")
	if not valid_shape or not arguments[0].begins_with("--package-path=") or not arguments[1].begins_with("--package-hash="):
		printerr("USAGE: --script res://tools/wrath_player_map_probe.gd -- --package-path=<archive> --package-hash=<sha256> [--visual [--capture-dir=<outside-Git-directory>]]")
		quit(2)
		return
	var visual := arguments.size() >= 3
	var capture_dir := arguments[3].substr("--capture-dir=".length()) if arguments.size() == 4 else ""
	var package_path := arguments[0].substr("--package-path=".length())
	var expected_hash := arguments[1].substr("--package-hash=".length())
	if package_path.is_empty() or expected_hash.length() != 64:
		printerr("INVALID_PACKAGE_IDENTITY")
		quit(2)
		return
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not application.is_ok():
		printerr("APPLICATION_ERROR ", application.error_code)
		quit(1)
		return
	repository.set_application_content(application.content, application.media.assets())
	var package := repository.load_package(package_path)
	if not package.is_ok():
		printerr("PACKAGE_ERROR ", package.error_code)
		quit(1)
		return
	var content: RealmzContent = package.content
	if content.package_hash != expected_hash or content.campaign_id != "scenario-wrath-of-the-mind-lords":
		printerr("PACKAGE_IDENTITY_CHANGED ", content.package_hash)
		quit(1)
		return
	var media := ClassicMediaCatalog.new(package.media, ApplicationMediaCatalog.new(), application.media)
	var marker_count := 0
	for definition: PlayerMapDefinition in content.world.player_maps():
		for marker: PlayerMapMarkerDefinition in definition.markers():
			var asset := media.asset_by_id(marker.icon_asset_id)
			var exact := media.asset_by_resource("cicn", marker.classic_icon_id)
			if asset == null or exact == null or asset != exact or media.image_texture(asset) == null:
				printerr("MARKER_UNAVAILABLE ", definition.id, " ", marker.classic_icon_id, " ", marker.icon_asset_id)
				quit(1)
				return
			marker_count += 1
	if marker_count != 44 or content.world.player_maps().size() != 19:
		printerr("MARKER_INVENTORY_INCOMPLETE ", marker_count)
		quit(1)
		return
	var session := GameSession.new()
	if session.start(content, 1).state != SessionStep.State.COMPLETED:
		printerr("SESSION_START_FAILED")
		quit(1)
		return
	var snapshot := session.snapshot()
	for map_id in [2, 13, 14, 17]:
		var definition := content.world.player_map_by_classic_id(map_id)
		if definition == null:
			printerr("PLAYER_MAP_MISSING ", map_id)
			quit(1)
			return
		snapshot.game_state.world.exploration.acquire_map(definition.id)
	if session.restore(content, snapshot).state != SessionStep.State.COMPLETED:
		printerr("MAP_FIXTURE_RESTORE_FAILED")
		quit(1)
		return
	var view := session.view()
	var body := VBoxContainer.new()
	body.name = "ISOLATED_WRATH_PLAYER_MAP_FIXTURE"
	body.size = Vector2(1280, 720)
	root.add_child(body)
	var controller := MapsJournalScreenController.new()
	controller.present(body, view, media)
	var chooser := body.find_child("AcquiredMapChooser", true, false)
	if chooser == null:
		printerr("MAP_CHOOSER_MISSING")
		quit(1)
		return
	for map_id in [2, 13, 14, 17]:
		var definition := content.world.player_map_by_classic_id(map_id)
		var button: Button
		for node: Node in chooser.find_children("*", "Button", true, false):
			if String(node.get_meta("player_map_id", "")) == definition.id:
				button = node as Button
				break
		if button == null or button.disabled:
			printerr("MAP_SELECTION_UNAVAILABLE ", definition.id)
			quit(1)
			return
		button.pressed.emit()
		var canvas := body.find_child("PlayerMapCanvas", true, false) as PlayerMapCanvas
		var selected := canvas.get("_view") as PlayerMapView if canvas != null else null
		if selected == null or selected.id != definition.id or selected.cells.is_empty() or selected.markers.size() != definition.markers().size():
			printerr("MAP_PRESENTATION_MISMATCH ", definition.id)
			quit(1)
			return
		for marker: PlayerMapMarkerDefinition in selected.markers:
			if canvas._texture_for(marker.icon_asset_id) == null:
				printerr("MARKER_NOT_DRAWABLE ", definition.id, " ", marker.icon_asset_id)
				quit(1)
				return
		print("PRESENTED ", JSON.stringify({"id": definition.id, "cells": selected.cells.size(), "markers": selected.markers.size()}))
	await process_frame
	await process_frame
	print("WRATH_PLAYER_MAP_PROBE_PASS ", JSON.stringify({"packageHash": content.package_hash, "playerMaps": content.world.player_maps().size(), "markers": marker_count}))
	if visual:
		DisplayServer.window_set_title("ISOLATED Wrath player-map fixture")
		var controls := HBoxContainer.new()
		var label := Label.new()
		label.text = "ISOLATED TEST FIXTURE — Wrath player maps 2, 13, 14, 17"
		controls.add_child(label)
		var close_button := Button.new()
		close_button.text = "Close fixture"
		close_button.pressed.connect(func() -> void: quit(0))
		controls.add_child(close_button)
		if not capture_dir.is_empty():
			var capture_button := Button.new()
			capture_button.text = "Capture fixture"
			capture_button.pressed.connect(func() -> void: _capture_fixture(body, capture_dir))
			controls.add_child(capture_button)
		body.add_child(controls)
		body.move_child(controls, 0)
		print("VISUAL_FIXTURE_READY")
		return
	body.queue_free()
	quit(0)


func _capture_fixture(body: VBoxContainer, output_dir: String) -> void:
	await process_frame
	var canvas := body.find_child("PlayerMapCanvas", true, false) as PlayerMapCanvas
	var selected := canvas.get("_view") as PlayerMapView if canvas != null else null
	if selected == null or DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("CAPTURE_UNAVAILABLE")
		return
	var path := output_dir.path_join("wrath-" + selected.id.replace(".", "-") + "-" + str(Time.get_ticks_usec()) + ".png")
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		printerr("CAPTURE_FAILED ", error)
		return
	print("CAPTURED ", JSON.stringify({"playerMapId": selected.id, "path": path, "sha256": FileAccess.get_sha256(path)}))
