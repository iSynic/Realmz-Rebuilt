## Binds one selected Character Files entry to the scene-authored detail pane and revision rows.
class_name VaultDetailBinder
extends RefCounted

const GOLD := &"VaultStatusGold"
const MUTED := &"VaultStatusMuted"
const GOOD := &"VaultStatusGood"
const BAD := &"VaultStatusBad"

signal inspect_requested(revision_hash: String)
signal character_requested(operation: StringName, character_id: String, revision_hash: String)


static func status_for(entry: VaultEntry, view: GameView) -> Dictionary:
	if in_party(entry, view):
		return {"text": "In party", "variation": GOLD}
	if entry.archived:
		return {"text": "Archived", "variation": MUTED}
	if not has_scenario(view):
		return {"text": "Not checked", "variation": MUTED}
	return {"text": "Eligible", "variation": GOOD} if entry.display.eligible else {"text": "Not eligible", "variation": BAD}


static func has_scenario(view: GameView) -> bool:
	return view != null and view.campaign_summary != null


static func in_party(entry: VaultEntry, view: GameView) -> bool:
	if view == null:
		return false
	for member: CharacterView in view.party_members:
		if member.id == entry.character_id:
			return true
	return false


## Eligibility heading, reasons and status variation for one inspected revision.
static func revision_eligibility(revision: CharacterVaultRevisionView, view: GameView) -> Dictionary:
	if not has_scenario(view):
		return {"text": "Not checked • Choose a scenario in party setup to see whether %s can join." % revision.name, "variation": MUTED}
	var scenario := view.campaign_summary.title
	if revision.eligible:
		return {"text": "Eligible for %s" % scenario, "variation": GOOD}
	var reasons := ""
	for reason: String in revision.eligibility_reasons:
		reasons += "\n•  %s" % reason
	return {"text": "Not eligible for %s%s" % [scenario, reasons], "variation": BAD}


static func identity_text(revision: CharacterVaultRevisionView) -> String:
	var character := revision.character
	var race := character.race_name if character != null else revision.race_id
	var caste := character.caste_name if character != null else revision.caste_id
	return "Level %d %s %s" % [revision.level, race, caste]


func bind(screen: VaultScreen, entry: VaultEntry, view: GameView, textures: Dictionary) -> void:
	var revision := entry.display
	var character := revision.character
	var portrait: Texture2D = textures.get(revision.portrait_id)
	_bind_texture(screen.detail_portrait, portrait, Vector2(44, 44))
	var tactical_icon: Texture2D = textures.get(character.combat_icon_id) if character != null else null
	_bind_texture(screen.detail_tactical_icon, tactical_icon, Vector2(32, 32))
	screen.detail_name.text = revision.name
	var count := entry.revisions.size()
	screen.detail_identity.text = "%s  •  %d %s" % [identity_text(revision), count, "revision" if count == 1 else "revisions"]
	screen.detail_identity.tooltip_text = "Realmz character file" if revision.source_campaign_id.is_empty() else "First saved from %s" % revision.source_campaign_id
	_bind_stats(screen, character)
	_bind_eligibility(screen, entry, view)
	_bind_actions(screen, entry, view)
	_bind_revisions(screen, entry)
	screen.manage_strip.visible = entry.archived
	# A party member keeps every file; the host refuses the same change.
	var party_member := in_party(entry, view)
	screen.delete_button.disabled = party_member
	screen.delete_button.tooltip_text = "%s is in the party." % revision.name if party_member else "Permanently remove this character and every revision."


func _bind_texture(target: TextureRect, texture: Texture2D, fallback: Vector2) -> void:
	target.texture = texture
	# Portraits and tactical icons always render at their native source size.
	target.custom_minimum_size = texture.get_size() if texture != null else fallback


func _bind_stats(screen: VaultScreen, character: CharacterView) -> void:
	if character == null:
		for tile: String in ["StaminaTile", "SpellPointsTile", "ArmorTile", "LoadTile"]:
			screen.stat_value(tile).text = "—"
		return
	screen.stat_value("StaminaTile").text = "%d / %d" % [character.current_health, character.maximum_health]
	screen.stat_value("SpellPointsTile").text = "—" if character.maximum_spell_points <= 0 else "%d / %d" % [character.spell_points, character.maximum_spell_points]
	screen.stat_value("ArmorTile").text = str(character.armor)
	screen.stat_value("LoadTile").text = "%d / %d" % [character.carried_load, character.maximum_load]


func _bind_eligibility(screen: VaultScreen, entry: VaultEntry, view: GameView) -> void:
	var revision := entry.display
	var scenario := view.campaign_summary.title if has_scenario(view) else ""
	var heading := ""
	var variation := MUTED
	var reasons: Array[String] = []
	var blocked := has_scenario(view) and not revision.eligible
	if entry.archived:
		heading = "Archived"
		reasons.append("Restore a revision to use %s in a party again." % revision.name)
	elif not has_scenario(view):
		heading = "Not checked"
		reasons.append("Choose a scenario in party setup to see whether %s can join." % revision.name)
	elif in_party(entry, view):
		heading = "In your party for %s" % scenario
		variation = GOLD
	elif revision.eligible:
		heading = "Eligible for %s" % scenario
		variation = GOOD
	else:
		heading = "Not eligible for %s" % scenario
		variation = BAD
	if blocked and not entry.archived:
		for reason: String in revision.eligibility_reasons:
			reasons.append("•  %s" % reason)
	screen.eligibility_heading.text = heading
	screen.eligibility_heading.theme_type_variation = variation
	var reasons_label := screen.eligibility_reasons
	reasons_label.text = "\n".join(reasons)
	reasons_label.visible = not reasons.is_empty()
	# Reasons use the error colour only when they actually block this scenario.
	reasons_label.theme_type_variation = BAD if blocked and not entry.archived else MUTED


func _bind_actions(screen: VaultScreen, entry: VaultEntry, view: GameView) -> void:
	var add := screen.add_to_party_button
	var reason := add_reason(entry, view)
	add.visible = not entry.archived
	screen.add_group.visible = not entry.archived
	add.disabled = not reason.is_empty()
	add.tooltip_text = reason if add.disabled else "Add %s to the party for this scenario." % entry.display.name
	var setup_reason := screen.setup_reason
	setup_reason.visible = add.visible and add.disabled and not reason.is_empty()
	setup_reason.text = reason
	var sheet := screen.full_sheet_button
	sheet.disabled = entry.display.character == null
	sheet.tooltip_text = "Open the complete character record." if not sheet.disabled else "This revision has no readable character record."
	var edit := screen.edit_button
	edit.visible = not entry.archived
	edit.disabled = entry.display.character == null
	edit.tooltip_text = "Change this character and save the result as a new revision. Parties and saved adventures keep their own copies." if not edit.disabled else "This revision has no readable character record."
	screen.restore_archived_button.visible = entry.archived
	var archive := screen.archive_button
	archive.visible = not entry.archived
	# A party member stays active; the host refuses the same change.
	archive.disabled = in_party(entry, view)
	archive.tooltip_text = "%s is in the party, so they stay active." % entry.display.name if archive.disabled else "Hide this character from party setup. Every revision is kept."


static func add_reason(entry: VaultEntry, view: GameView) -> String:
	if entry.archived:
		return "Restore this character before adding it to a party."
	if view == null or not view.session_started or not has_scenario(view):
		return "Choose a scenario in party setup before adding characters."
	if in_party(entry, view):
		return "%s is in the party, so they can't be added again or archived." % entry.display.name
	var availability := view.availability(&"import_vault_character")
	if not availability.enabled:
		return availability.reason
	if not entry.display.eligible:
		return "%s can't join this scenario." % entry.display.name
	return ""


func _bind_revisions(screen: VaultScreen, entry: VaultEntry) -> void:
	var parent := screen.revision_rows
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	for revision: CharacterVaultRevisionView in entry.revisions:
		var row := screen.revision_row_scene.instantiate() as PanelContainer
		row.name = "Revision_%s" % revision.revision_hash.validate_node_name()
		var title := row.get_node("RevisionContent/Summary/Title") as Label
		var label := "" if revision.publication_label in ["", revision.name] else "  •  %s" % revision.publication_label
		title.text = "Level %d%s" % [revision.level, label]
		(row.get_node("RevisionContent/Summary/Detail") as Label).text = "Revision %s" % revision.revision_hash.left(8)
		var tag := row.get_node("RevisionContent/CurrentTag") as Label
		tag.visible = revision.is_current or revision.last_current
		tag.text = "Current" if revision.is_current else "Last active"
		var inspect := row.get_node("RevisionContent/Inspect") as Button
		inspect.disabled = revision.character == null
		inspect.tooltip_text = "Open this revision's complete character sheet." if not inspect.disabled else "This revision has no readable character record."
		if not inspect.disabled:
			inspect.pressed.connect(inspect_requested.emit.bind(revision.revision_hash))
		var restore := row.get_node("RevisionContent/Restore") as Button
		restore.visible = entry.archived
		if entry.archived:
			restore.pressed.connect(character_requested.emit.bind(&"restore", revision.character_id, revision.revision_hash))
		parent.add_child(row)
