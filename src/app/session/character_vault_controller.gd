## Coordinates character vault services at the application boundary.

class_name CharacterVaultController
extends RefCounted

const CLASSIC_STARTER_CATALOG_PATH := ClassicStarterCharacterCatalog.PATH

var _repository: CharacterVaultRepository
var _validated_records: Dictionary = {}
## Detached display views of immutable revisions for the current display package.
var _character_views: Dictionary = {}
var _views_package := ""
var _operation_error: String = ""
var _rule_sources: CharacterVaultRuleSources
var _active_content: RealmzContent
var _repair: CharacterVaultRepair
var _repair_thread: Thread
var _repair_operation: StringName
var _repair_cancelled := false
var _repair_packages: Array[PackageDiscoveryResult] = []
var _repair_application: RealmzContent
var _repair_prepared := false
var _starter_restore: ClassicStarterCharacterRestore


func _init(repository: CharacterVaultRepository = null) -> void:
	_repository = repository if repository != null else CharacterVaultRepository.new()


func import_intent(character_id: String, revision_hash: String) -> PlayerIntent:
	var admitted := _admission(character_id, revision_hash)
	if admitted == null:
		return null
	var record := admitted.record
	var detached_state := CharacterStateCodec.copy(record.state)
	return PartyIntents.import_vault_character(record.character_id, record.revision_hash, detached_state, record.source_campaign_id, record.source_package_hash, admitted.source_definitions) if detached_state != null else null


## A Character File revision and its rule source when it may join the active scenario, or null (see last_error).
func _admission(character_id: String, revision_hash: String) -> CharacterVaultAdmission:
	_operation_error = ""
	var cache_key := _cache_key(character_id, revision_hash)
	var record := _validated_records.get(cache_key) as CharacterVaultRecord
	if record == null:
		record = _repository.load_revision(character_id, revision_hash)
		if record != null:
			_validated_records[cache_key] = record
	if record == null:
		return null
	var source_definitions: ContentTransferCatalog
	if _rule_sources != null:
		if _active_content == null:
			_operation_error = "Choose a scenario before adding a Character File."
			return null
		source_definitions = _rule_sources.catalog(record, _active_content)
		_operation_error = _rule_sources.last_error if source_definitions == null else PartyAdmissionRules.source_definition_error(source_definitions, _active_content, record.state, record.source_campaign_id)
		if not _operation_error.is_empty():
			return null
	return CharacterVaultAdmission.new(record, source_definitions)


func configure_rule_sources(application: RealmzContent, packages: Array[PackageDiscoveryResult]) -> void:
	if _rule_sources == null:
		_rule_sources = CharacterVaultRuleSources.new()
	_rule_sources.configure(application, packages)
	_repair_application = application
	_repair_packages = packages.duplicate()


func start_maintenance(operation: StringName) -> bool:
	_operation_error = ""
	if _repair_thread != null or _repair_application == null:
		_operation_error = "Wait for the Character Files library to finish its current operation."
		return false
	if operation == &"restore_starters":
		return _start_starter_restore()
	if operation == &"review":
		_repair = CharacterVaultRepair.new(CharacterVaultRepository.new(_repository.directory_path()), _repair_application, _repair_packages)
	elif operation != &"repair" or not _repair_prepared or _repair == null or _repair.ready_names.is_empty():
		_operation_error = "Review the Character Files repair first."
		return false
	_repair_operation = operation
	_repair_prepared = false
	_repair_cancelled = false
	_repair_thread = Thread.new()
	var error := _repair_thread.start(_repair.prepare if operation == &"review" else _repair.execute)
	if error != OK:
		_repair_thread = null
		_operation_error = "Could not start Character Files repair."
		return false
	return true


func cancel_repair_review() -> void:
	_repair_prepared = false
	if _repair_operation == &"review": _repair_cancelled = true


func _start_starter_restore() -> bool:
	_repair_prepared = false
	_repair_cancelled = false
	_repair_operation = &"restore_starters"
	_starter_restore = ClassicStarterCharacterRestore.new(CharacterVaultRepository.new(_repository.directory_path()), _repair_application)
	_repair_thread = Thread.new()
	if _repair_thread.start(_starter_restore.execute) != OK:
		_repair_thread = null
		_operation_error = "Could not start starter-character restoration."
		return false
	return true


func poll_repair() -> Dictionary:
	if _repair_thread == null or _repair_thread.is_alive():
		return {}
	var success: bool = _repair_thread.wait_to_finish()
	_repair_thread = null
	if _repair_operation == &"restore_starters":
		_validated_records.clear()
		return {"details": _starter_restore.details(), "review": false, "canRepair": false, "hasBackup": _starter_restore.backup.complete}
	if _repair_cancelled:
		_repair = null
		return {}
	_repair_prepared = success and _repair_operation == &"review"
	_validated_records.clear()
	var details := ""
	if not success:
		details = _repair.last_error
	elif _repair_operation == &"review":
		details = "%d Character Files can be repaired.\n\n%s\n\nThe complete vault will be backed up before repair. New revisions preserve every original character field, and the originals remain in revision history." % [_repair.ready_names.size(), ", ".join(_repair.ready_names)] if not _repair.ready_names.is_empty() else "No Character Files need a repair that can be verified."
	else:
		details = "Repaired %d Character Files. Your original characters remain in revision history.\n\n%s" % [_repair.repaired_names.size(), ", ".join(_repair.repaired_names)]
	if _repair_operation == &"review" and _repair.ready_names.is_empty():
		details += "\n\nFor missing or older-format starter characters, use Restore starter characters in Character Files. Restoration adds fresh compatible copies; it does not convert old characters."
	if _repair.already_ready > 0:
		details += "\n\n%d Character Files already have their source identity." % _repair.already_ready
	if not _repair.issues.is_empty():
		details += "\n\nNeeds attention:\n" + "\n\n".join(_repair.issues)
	if _repair.backup.complete:
		details += "\n\nComplete vault backup:\n" + ProjectSettings.globalize_path(_repair.backup.path)
	return {"details": details, "review": success and _repair_operation == &"review", "canRepair": success and not _repair.ready_names.is_empty(), "hasBackup": _repair.backup.complete}


func repair_backup_path() -> String:
	if _repair_operation == &"restore_starters":
		return ProjectSettings.globalize_path(_starter_restore.backup.path) if _starter_restore != null and _starter_restore.backup.complete else ""
	return ProjectSettings.globalize_path(_repair.backup.path) if _repair != null and _repair.backup.complete else ""


func shutdown_repair() -> void:
	if _repair_thread != null:
		_repair_thread.wait_to_finish()
		_repair_thread = null


func publish(character: CharacterState, rules_version: String, source_campaign_id: String, source_package_hash: String, publication_source: String, source_content: RealmzContent = null, label: String = "") -> bool:
	_operation_error = ""
	if character == null:
		return false
	var record := CharacterVaultRecord.new(character.id, rules_version, source_campaign_id, source_package_hash, character)
	if source_content != null:
		if source_content.package_hash != source_package_hash or source_content.rules_version != rules_version or not source_campaign_id in ["", source_content.campaign_id]:
			_operation_error = "The character publication does not match its source rules."
			return false
		record.source_rules = CharacterVaultRuleIdentity.capture(source_content.transfer_catalog, character)
		if record.source_rules == null:
			_operation_error = "The character's source race and class could not be recorded."
			return false
	record.publication_metadata = {"name": character.name, "level": character.level, "source": publication_source}
	if not label.is_empty():
		record.publication_metadata["label"] = label
	var published := _repository.publish_new_character(record)
	if published:
		_validated_records.clear()
	return published


## Opens the current revision of an active character for editing, or null (see last_error).
func begin_edit(character_id: String, revision_hash: String, library: RealmzContent) -> CharacterVaultEdit:
	_operation_error = ""
	var record := _repository.load_revision(character_id, revision_hash)
	if record == null or library == null:
		_operation_error = "This revision can't be read."
		return null
	if _repository.current_revision_hash(character_id) != revision_hash:
		_operation_error = "Only the current revision of an active character can be edited."
		return null
	var custom_reason := ""
	var source := _rule_sources.catalog(record, library) if _rule_sources != null else null
	if source == null:
		custom_reason = "%s's race and class rules couldn't be resolved, so Items, Spells, age and Level Up are view-only. Repair Character Files may restore them." % record.state.name
	elif source.is_scenario_specific(&"races", record.state.race_id) or source.is_scenario_specific(&"castes", record.state.caste_id):
		custom_reason = "%s uses its scenario's own race or class rules, so Items, Spells, age and Level Up are view-only here." % record.state.name
	return CharacterVaultEdit.new(_repository, record, custom_reason)


## Publishes a copy of a party member as a new Character File and returns its name, or "" (see last_error).
## `identity` reserves the file's ID ahead of time (see SaveEditHolds); null takes the next unused one.
func publish_party_character(source_character: CharacterState, content: RealmzContent, publication_source: String, label: String = "", identity: CharacterFileIdentity = null) -> String:
	_operation_error = ""
	if content == null or source_character == null:
		_operation_error = "the character is unavailable"
		return ""
	# Campaign slot IDs belong to their playthrough, not to the reusable vault.
	if identity == null:
		identity = next_character_file_identity()
	if identity == null:
		_operation_error = last_error()
		return ""
	var character := CharacterStateCodec.copy_with_identity(source_character, identity.character_id)
	if character == null:
		_operation_error = "the character state is invalid"
		return ""
	if not publish(character, content.rules_version, content.campaign_id, content.package_hash, publication_source, content, label):
		_operation_error = last_error()
		return ""
	return character.name


func seed_if_empty(records: Array[CharacterVaultRecord]) -> bool:
	_operation_error = ""
	var seeded := _repository.seed_if_empty(records)
	if seeded:
		_validated_records.clear()
	return seeded


func seed_classic_starters_if_empty(catalog_path: String = CLASSIC_STARTER_CATALOG_PATH, application_library_hash: String = ApplicationLibraryIdentity.PACKAGE_HASH, application: RealmzContent = null) -> bool:
	var catalog := ClassicStarterCharacterCatalog.new()
	var records := catalog.load_records(catalog_path, application_library_hash, application)
	if records.is_empty():
		_operation_error = catalog.last_error
		push_warning("Starter characters were not installed: %s" % _operation_error)
		return false
	var seeded := seed_if_empty(records)
	if not seeded:
		push_warning("Starter characters were not installed: %s" % last_error())
	return seeded


func revisions(active_content: RealmzContent, fallback_content: RealmzContent = null) -> Array[CharacterVaultRevisionView]:
	_active_content = active_content
	_validated_records.clear()
	var result: Array[CharacterVaultRevisionView] = []
	var display_content := active_content if active_content != null else fallback_content
	var display_package := display_content.package_hash if display_content != null else ""
	if display_package != _views_package:
		_character_views.clear()
		_views_package = display_package
	for character_id: String in _repository.list_character_ids():
		var current_hash := _repository.current_revision_hash(character_id)
		var character_archived := current_hash.is_empty()
		for record: CharacterVaultRecord in _repository.list_revisions(character_id):
			_validated_records[_cache_key(record.character_id, record.revision_hash)] = record
			var eligibility := _repository.campaign_eligibility(record, active_content) if active_content != null else null
			if not _character_views.has(record.revision_hash):
				_character_views[record.revision_hash] = CharacterView.new(record.state, display_content)
			var revision := CharacterVaultRevisionView.from_record(record, eligibility, record.revision_hash == current_hash, character_archived, display_content, _character_views[record.revision_hash] as CharacterView)
			revision.last_current = character_archived and _repository.revision_is_archived(character_id, record.revision_hash)
			if _rule_sources != null and display_content != null:
				var source := _rule_sources.catalog(record, display_content)
				if source != null:
					if source.is_scenario_specific(&"races", record.state.race_id) or source.is_scenario_specific(&"castes", record.state.caste_id):
						revision.required_campaign_id = record.source_campaign_id
				var reason := _rule_sources.last_error if source == null else PartyAdmissionRules.source_definition_error(source, display_content, record.state, record.source_campaign_id)
				if not reason.is_empty():
					revision.eligible = false
					revision.eligibility_reasons.append(reason)
			result.append(revision)
	result.sort_custom(func(left: CharacterVaultRevisionView, right: CharacterVaultRevisionView) -> bool:
		var character_order := left.character_id.naturalnocasecmp_to(right.character_id)
		if character_order != 0:
			return character_order < 0
		if left.is_current != right.is_current:
			return left.is_current
		return left.revision_hash < right.revision_hash
	)
	return result


## The next unused identity, or null (see last_error) when deleted identities can't be read.
func next_character_file_identity() -> CharacterFileIdentity:
	var occupied: Dictionary = {}
	# Deleted characters' identities stay retired so an old save's party never matches a new character.
	var ledger_error := CharacterVaultDeletion.ledger_error(_repository.directory_path())
	if not ledger_error.is_empty():
		_operation_error = ledger_error
		return null
	for character_id: String in _repository.reserved_character_ids():
		occupied[character_id] = true
	var sequence := 1
	while occupied.has("realmz.character.%d" % sequence):
		sequence += 1
	return CharacterFileIdentity.new("realmz.character.%d" % sequence, sequence * 7919 + 1)


## Archives, restores or permanently deletes (archived only) one stored character.
func change_character(operation: StringName, character_id: String, revision_hash: String = "") -> bool:
	var changed := false
	match operation:
		&"archive": changed = _repository.archive_character(character_id)
		&"restore": changed = _repository.restore_revision(character_id, revision_hash)
		&"delete": changed = _repository.delete_archived_character(character_id)
	# Even a failed change may have moved files, so the next listing always rereads them.
	_validated_records.clear()
	return changed


func cached_revision_count() -> int:
	return _validated_records.size()


func artwork_bundles() -> Array[CharacterArtBundle]:
	var result: Array[CharacterArtBundle] = []
	for record: CharacterVaultRecord in _validated_records.values():
		result.append(record.character_art)
	return result


func artwork_bundle(character_id: String, revision_hash: String) -> CharacterArtBundle:
	var record := _validated_records.get(_cache_key(character_id, revision_hash)) as CharacterVaultRecord
	if record == null:
		record = _repository.load_revision(character_id, revision_hash)
	return record.character_art if record != null else null


func last_error() -> String:
	return _operation_error if not _operation_error.is_empty() else _repository.last_error


func unavailable_notice() -> String:
	return _repository.diagnostics().unavailable_notice()


static func _cache_key(character_id: String, revision_hash: String) -> String:
	return "%s:%s" % [character_id, revision_hash]
