## Prepares explicit rule-identity repair and preserves originals behind a verified backup.
class_name CharacterVaultRepair
extends RefCounted

var ready_names: Array[String] = []
var issues: Array[String] = []
var repaired_names: Array[String] = []
var already_ready := 0
var last_error := ""
var backup := CharacterVaultBackup.new()
var _repository: CharacterVaultRepository
var _application: RealmzContent
var _sources := CharacterVaultRuleSources.new()
var _recovery := CharacterVaultRecoveryCatalog.new()
var _original: Dictionary = {}
var _plan: Array[Dictionary] = []


func _init(repository: CharacterVaultRepository, application: RealmzContent, packages: Array[PackageDiscoveryResult]) -> void:
	_repository = repository
	_application = application
	_sources.configure(application, packages)


func prepare() -> bool:
	_original = backup.snapshot(_repository.directory_path())
	if not backup.last_error.is_empty():
		return _fail(backup.last_error)
	if not _recovery.load_catalog():
		return _fail(_recovery.last_error)
	for record: CharacterVaultRecord in _repository.list_current_records():
		if record.source_rules != null:
			already_ready += 1
			continue
		var source := _sources.catalog(record, _application)
		var identity := CharacterVaultRuleIdentity.capture(source, record.state) if source != null else _recovery.resolve(record)
		if identity == null:
			issues.append("%s: install its exact source scenario revision (%s, %s), then try Repair again." % [record.state.name, record.source_campaign_id, record.source_package_hash])
			continue
		ready_names.append(record.state.name)
		_plan.append({"id": record.character_id, "revision": record.revision_hash, "identity": identity})
	var diagnostics: Variant = _repository.diagnostics()
	if diagnostics.incompatible_current_count > 0:
		issues.append("%d older-format Character Files are preserved. This action repairs current-format files only." % diagnostics.incompatible_current_count)
	if diagnostics.invalid_current_count > 0:
		issues.append("%d damaged Character Files are preserved and require separate recovery." % diagnostics.invalid_current_count)
	return backup.matches(_repository.directory_path(), _original) or _fail(backup.last_error)


func execute() -> bool:
	if _plan.is_empty():
		return _fail("No Character Files are ready for repair.")
	if not backup.create(_repository.directory_path(), _original):
		return _fail(backup.last_error)
	if not _receipt("prepared"):
		return _fail("Could not write the backup receipt. No characters were changed.")
	var touched: Array[String] = []
	for item: Dictionary in _plan:
		touched.append(item.id)
		if not _repository.repair_rule_identity(item.id, item.revision, item.identity):
			var failure := _repository.last_error
			var restored := backup.restore_indices(_repository.directory_path(), touched, _original)
			repaired_names.clear()
			_receipt("rolled-back" if restored else "recovery-required")
			return _fail("Repair stopped: %s %s" % [failure, "Original selections were restored." if restored else "Some selections could not be restored; use the complete backup."])
		repaired_names.append(ready_names[repaired_names.size()])
	if not _receipt("complete"):
		return _fail("Characters were repaired, but the completion receipt could not be updated. The complete original backup is preserved.")
	return true


func _receipt(status: String) -> bool:
	var file := FileAccess.open(backup.path.path_join("repair-receipt.json"), FileAccess.WRITE)
	if file == null:
		return false
	var revisions: Array[Dictionary] = []
	for item: Dictionary in _plan:
		revisions.append({"characterId": item.id, "originalRevision": item.revision, "currentRevision": _repository.current_revision_hash(item.id)})
	file.store_string(CanonicalJson.encode({"version": 1, "status": status, "originalFiles": _original, "revisions": revisions}))
	file.flush()
	file.close()
	return true


func _fail(message: String) -> bool:
	last_error = message
	return false
