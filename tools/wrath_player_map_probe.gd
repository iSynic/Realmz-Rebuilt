## Probes Wrath's exact player-map marker media through the Journal presenter.
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2 or not arguments[0].begins_with("--package-path=") or not arguments[1].begins_with("--package-hash="):
		printerr("USAGE: --script res://tools/wrath_player_map_probe.gd -- --package-path=<archive> --package-hash=<sha256>")
		quit(2)
		return
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
	for map_id in [13, 14, 15]:
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
	for map_id in [13, 14, 15]:
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
	body.queue_free()
	print("WRATH_PLAYER_MAP_PROBE_PASS ", JSON.stringify({"packageHash": content.package_hash, "playerMaps": content.world.player_maps().size(), "markers": marker_count}))
	quit(0)
