## Captures synthetic production-bound values for the editor-safe Builder projection.
extends SceneTree

const FIXTURES := preload("res://addons/realmz_builder/realmz_builder_preview_fixtures.gd")
const AUTHORING_SAMPLES := preload("res://addons/realmz_builder/realmz_builder_authoring_samples.gd")
const REGISTRY_PATH := "res://addons/realmz_builder/scene_previews.json"
const OUTPUT_PATH := "res://addons/realmz_builder/editor_samples.json.gz"
const MEDIA_ROOT := "res://addons/realmz_builder/editor_sample_media"
const SAMPLE_COMPONENTS := [
	"character_metric_row.tscn", "character_sheet_selector_button.tscn", "creature_library_row.tscn",
	"vault_character_card.tscn", "battle_initiative_panel.tscn", "battle_initiative_entry.tscn", "combat_spell_power_button.tscn",
	"inventory_character_button.tscn", "inventory_fact_row.tscn", "inventory_item_row.tscn",
	"journal_entry_row.tscn", "location_note_row.tscn", "player_map_menu_row.tscn",
	"classic_spell_selection_button.tscn", "money_character_row.tscn", "money_transfer_row.tscn",
	"shop_character_button.tscn", "shop_empty_label.tscn", "shop_item_row.tscn",
	"temple_character_row.tscn", "temple_service_row.tscn", "treasure_loot_cell.tscn",
	"treasure_recipient_row.tscn", "campaign_library_row.tscn", "party_import_candidate_row.tscn",
	"party_import_detail_label.tscn", "party_import_source_row.tscn", "party_setup_character_row.tscn",
	"pick_lock_tumbler_row.tscn", "save_slot_row.tscn", "interaction_hint.tscn",
]

var _pending_media: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	var check_only: bool = OS.get_cmdline_user_args().has("--check")
	if not check_only:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MEDIA_ROOT))
	var samples := {}
	for entry: Dictionary in registry["scenes"]:
		var surface_id := String(entry["id"])
		var scene := load("res://" + String(entry["scene"])) as PackedScene
		if scene == null:
			push_error("Missing Builder scene: %s" % surface_id)
			quit(1)
			return
		var authored_command_paths := _shell_command_paths(scene) if surface_id == "application-shell" else {}
		var profiles: Array = Array(registry["profiles"]).duplicate()
		if surface_id == "character-creation":
			profiles = ["Wide"]
		for profile: String in profiles:
			var dimensions := Vector2i(800, 600) if profile == "Compact" else Vector2i(1280, 720)
			var viewport := SubViewport.new()
			viewport.size = dimensions
			viewport.disable_3d = true
			root.add_child(viewport)
			var surface := scene.instantiate() as Control
			if surface_id == "loading-adventure":
				# Keep the production background request while pinning its editor sample.
				(surface as LoadingAdventureView).background_paths = PackedStringArray([
					"res://src/ui/shared/assets/main-menu/backgrounds/plate-05.png"])
			if is_equal_approx(surface.anchor_left, surface.anchor_right) and is_equal_approx(surface.anchor_top, surface.anchor_bottom):
				surface.size = dimensions
			viewport.add_child(surface)
			for settle_frame: int in 3:
				await process_frame
			var baseline := _capture(surface, profile == "Compact")
			if not FIXTURES.bind(surface, surface_id, profile):
				push_error("Builder binding failed: %s / %s" % [surface_id, profile])
				viewport.queue_free()
				quit(1)
				return
			if surface_id == "application-shell":
				_prepare_fixed_command_art(surface)
			for settle_frame: int in 3:
				await process_frame
			var bound := _capture(surface, profile == "Compact")
			if surface_id == "scrolling-text":
				for record: Dictionary in bound:
					var path := String(record["path"])
					if path == "ClassicScrollingTextSurface" or path.begins_with("ClassicScrollingTextSurface/"):
						record["path"] = path.replace("ClassicScrollingTextSurface", "ClassicScrollingTextWell")
			var sample_key := "%s/%s" % [surface_id, profile]
			var changes := _changes_from(baseline, bound, authored_command_paths)
			if not _validate_authored_paths(scene, changes, sample_key):
				viewport.queue_free()
				quit(1)
				return
			samples[sample_key] = changes
			viewport.queue_free()
			await process_frame
	if not _verify_media(samples, check_only):
		quit(1)
		return
	var encoded := JSON.stringify(samples, "", true)
	if check_only:
		var existing := FileAccess.open_compressed(OUTPUT_PATH, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
		var previous := existing.get_as_text() if existing != null else ""
		if previous != encoded:
			var first_mismatch := 0
			var shared_length := mini(previous.length(), encoded.length())
			while first_mismatch < shared_length and previous.substr(first_mismatch, 1) == encoded.substr(first_mismatch, 1):
				first_mismatch += 1
			var context_start := maxi(0, first_mismatch - 80)
			push_error("Realmz Builder editor samples drifted at byte %d: stored=%s generated=%s" % [
				first_mismatch, previous.substr(context_start, 180), encoded.substr(context_start, 180)])
			quit(1)
			return
		print("Checked %d production-bound Builder samples" % samples.size())
	else:
		var file := FileAccess.open_compressed(OUTPUT_PATH, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
		file.store_string(encoded)
		file.close()
		print("Captured %d production-bound Builder samples" % samples.size())
	quit()


func _validate_authored_paths(scene: PackedScene, records: Array[Dictionary], sample_key: String) -> bool:
	var authored := scene.instantiate() as Control
	var projection := AUTHORING_SAMPLES.new()
	projection.populate_snapshot(authored, records)
	var valid := true
	for record: Dictionary in records:
		var path := String(record["path"])
		if path != "." and authored.get_node_or_null(NodePath(path)) == null:
			push_error("Builder sample %s targets a missing authored path: %s" % [sample_key, path])
			valid = false
	projection.clear()
	authored.free()
	return valid


func _shell_command_paths(scene: PackedScene) -> Dictionary:
	var authored := scene.instantiate() as Control
	var paths := {}
	for node: Node in authored.find_children("*", "", true, false):
		if node.has_meta("shell_command_id"):
			var path := String(authored.get_path_to(node))
			if path.begins_with("BottomRegion/"):
				paths[String(node.get_meta("shell_command_id"))] = path
	authored.free()
	return paths


func _changes_from(baseline: Array[Dictionary], bound: Array[Dictionary], authored_command_paths: Dictionary) -> Array[Dictionary]:
	var authored := {}
	var authored_slots := {}
	var authored_instances := {}
	for record: Dictionary in baseline:
		var path := _authored_record_path(record, authored_command_paths)
		authored[path] = record["properties"]
		authored_slots[JSON.stringify(record["slot"])] = record
		authored_instances[record["instanceId"]] = path
	var result: Array[Dictionary] = []
	var sample_roots: Array[Dictionary] = []
	var templates := {}
	for record: Dictionary in bound:
		var path := _authored_record_path(record, authored_command_paths)
		path = String(authored_instances.get(record["instanceId"], path))
		var scene := String(record.get("sampleScene", ""))
		var sample_root := not authored.has(path) and scene.get_file() in SAMPLE_COMPONENTS
		if sample_root:
			sample_roots.append(record)
			templates[path] = load(scene).instantiate()
		var containing_root: Dictionary = {}
		var matched_sample_child := false
		if not sample_root:
			for root_record: Dictionary in sample_roots:
				if path.begins_with(String(root_record["path"]) + "/"):
					containing_root = root_record
		if not authored.has(path) and not containing_root.is_empty():
			var root_path := String(containing_root["path"])
			var relative_slots := Array(record["slot"]).slice(Array(containing_root["slot"]).size())
			var template_node := _node_at_indices(templates[root_path], relative_slots)
			if template_node is Control and template_node.get_class() == record["type"]:
				path = root_path + "/" + String(templates[root_path].get_path_to(template_node))
				matched_sample_child = true
		elif not authored.has(path) and not sample_root:
			var original: Dictionary = authored_slots.get(JSON.stringify(record["slot"]), {})
			if not original.is_empty() and original["type"] == record["type"]:
				path = String(original["path"])
		var inside_sample := sample_root or not containing_root.is_empty()
		if not authored.has(path) and inside_sample and not sample_root and not matched_sample_child:
			continue
		if not authored.has(path) and not inside_sample:
			continue
		record["path"] = path
		var changes := {}
		var before: Dictionary = authored.get(path, {})
		for property: String in record["properties"]:
			var value: Variant = record["properties"][property]
			if inside_sample or not before.has(property) or before[property] != value:
				changes[property] = value
		if changes.is_empty() and not sample_root and not record.has("editorIcon"):
			continue
		var changed: Dictionary = {"path": path, "properties": changes}
		if sample_root:
			changed["sampleScene"] = scene
		if record.has("editorIcon"):
			changed["editorIcon"] = record["editorIcon"]
		result.append(changed)
	for template: Node in templates.values():
		template.free()
	return result


func _authored_record_path(record: Dictionary, command_paths: Dictionary) -> String:
	var path := String(record["path"])
	if record.has("shellCommandId") and path.begins_with("BottomRegion/"):
		return String(command_paths.get(record["shellCommandId"], path))
	return path


func _node_at_indices(parent: Node, indices: Array) -> Node:
	var current := parent
	for index: int in indices:
		if index < 0 or index >= current.get_child_count():
			return null
		current = current.get_child(index)
	return current


func _prepare_fixed_command_art(surface: Control) -> void:
	for node: Node in surface.find_children("*", "ClassicBitmapButton", true, false):
		if not node.has_meta("shell_command_id") or String(node.get_meta("shell_command_id")).is_empty():
			continue
		var button := node as ClassicBitmapButton
		if button.has_visual_art():
			continue
		button.configure(ClassicCommandCatalog.command(StringName(node.get_meta("shell_command_id"))), 1)


func _capture(surface: Control, include_direct_placement: bool) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var nodes: Array[Node] = [surface]
	nodes.append_array(surface.find_children("*", "", true, false))
	for node: Node in nodes:
		if not node is Control:
			continue
		var ancestor := node
		var authored_or_sample := true
		while ancestor != surface:
			if ancestor.owner == null and ancestor.scene_file_path.get_file() not in SAMPLE_COMPONENTS:
				authored_or_sample = false
				break
			ancestor = ancestor.get_parent()
		if not authored_or_sample:
			continue
		var control := node as Control
		var path := "." if node == surface else String(surface.get_path_to(node))
		if path.begins_with("@") or path.contains("/@"):
			continue
		var record: Dictionary = {"path": path, "instanceId": node.get_instance_id()}
		if node.has_meta("shell_command_id"):
			record["shellCommandId"] = String(node.get_meta("shell_command_id"))
		var slot: Array[int] = []
		var cursor := node
		while cursor != surface:
			slot.push_front(cursor.get_index())
			cursor = cursor.get_parent()
		record["slot"] = slot
		record["type"] = node.get_class()
		if node != surface and node.owner == null and not node.scene_file_path.is_empty():
			record["sampleScene"] = node.scene_file_path
		var properties := {}
		for property: StringName in [&"visible", &"custom_minimum_size", &"size_flags_horizontal", &"size_flags_vertical", &"size_flags_stretch_ratio"]:
			properties[String(property)] = var_to_str(control.get(property))
		# Only Compact previews may reposition directly authored free-placement
		# panels. Geometry inside a container stays scene-owned; projecting it
		# before editor layout settles can accumulate anchor offsets on refresh.
		if node == surface or include_direct_placement and node.get_parent() == surface and not surface is Container:
			properties["position"] = var_to_str(control.position)
			properties["size"] = var_to_str(control.size)
		if node is Label or node is Button or node is LineEdit:
			properties["text"] = var_to_str(control.get("text"))
		if node is RichTextLabel:
			properties["text"] = var_to_str((node as RichTextLabel).get_parsed_text())
		if node is BaseButton:
			properties["disabled"] = var_to_str((node as BaseButton).disabled)
			properties["tooltip_text"] = var_to_str(control.tooltip_text)
			if (node as BaseButton).toggle_mode:
				properties["button_pressed"] = var_to_str((node as BaseButton).button_pressed)
		if node is Button and (node as Button).icon != null:
			properties["icon"] = _texture_reference((node as Button).icon)
		if node is GridContainer:
			properties["columns"] = var_to_str((node as GridContainer).columns)
		if node is BoxContainer:
			properties["vertical"] = var_to_str((node as BoxContainer).vertical)
		if node is Range:
			properties["value"] = var_to_str((node as Range).value)
		if node is TextureRect and (node as TextureRect).texture != null:
			properties["texture"] = _texture_reference((node as TextureRect).texture)
		var icon: Texture2D
		if node is ClassicBitmapButton:
			icon = node.get("_art_texture") as Texture2D
		elif node is ClassicSearchCommandButton:
			var atlas := node.get("_atlas") as Texture2D
			if atlas != null:
				icon = ImageTexture.create_from_image(atlas.get_image().get_region(Rect2i(0, 128, 32, 32)))
		elif node is ClassicTorchCommandButton:
			icon = node.get("_body_texture") as Texture2D
		if icon != null:
			var icon_path := _texture_reference(icon)
			if not icon_path.is_empty():
				record["editorIcon"] = icon_path.trim_prefix("resource:")
		record["properties"] = properties
		records.append(record)
	return records


func _texture_reference(texture: Texture2D) -> String:
	if texture.resource_path.begins_with("res://"):
		return "resource:" + texture.resource_path
	var image := texture.get_image()
	if image == null or image.is_empty() or image.get_width() > 128 or image.get_height() > 128:
		return ""
	var bytes := image.save_png_to_buffer()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	var digest := context.finish().hex_encode()
	var path := MEDIA_ROOT.path_join(digest + ".png")
	_pending_media[path] = bytes
	return "resource:" + path


func _verify_media(samples: Dictionary, check_only: bool) -> bool:
	var referenced: Dictionary = {}
	_collect_media(samples, referenced)
	var valid := true
	for path: String in referenced:
		if _pending_media.has(path) and not check_only:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				push_error("Could not write Builder sample art: " + path)
				valid = false
				continue
			file.store_buffer(_pending_media[path])
			file.close()
		if not FileAccess.file_exists(path):
			push_error("Missing Builder sample art: " + path)
			valid = false
		elif _pending_media.has(path) and FileAccess.get_file_as_bytes(path) != _pending_media[path]:
			push_error("Builder sample art differs from captured pixels: " + path)
			valid = false
	if check_only:
		for filename: String in DirAccess.get_files_at(MEDIA_ROOT):
			if filename.ends_with(".png") and not referenced.has(MEDIA_ROOT.path_join(filename)):
				push_error("Unused Builder sample art: " + filename)
				valid = false
	return valid


func _collect_media(value: Variant, referenced: Dictionary) -> void:
	if value is String:
		var path: String = String(value).trim_prefix("resource:")
		if path.begins_with(MEDIA_ROOT + "/"):
			referenced[path] = true
	elif value is Dictionary:
		for child: Variant in (value as Dictionary).values():
			_collect_media(child, referenced)
	elif value is Array:
		for child: Variant in value:
			_collect_media(child, referenced)
