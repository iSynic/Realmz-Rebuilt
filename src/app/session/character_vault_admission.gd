## One Character File revision cleared to join the active scenario's party, with its rule source.

class_name CharacterVaultAdmission
extends RefCounted

var record: CharacterVaultRecord
## Null when no rule-source catalog is configured.
var source_definitions: ContentTransferCatalog


func _init(admitted: CharacterVaultRecord, definitions: ContentTransferCatalog) -> void:
	record = admitted
	source_definitions = definitions
