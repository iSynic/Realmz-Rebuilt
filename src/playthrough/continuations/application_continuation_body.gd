## Carries application hooks and character-library lifecycle handoffs.

class_name ApplicationContinuationBody
extends SessionContinuationBody

var hook: StringName
var program_id: String
var resume_kind: StringName
var service_id: String
var party_revived: bool
var suspended_vm: ScenarioVmSnapshot
var suspended_owner: SessionContinuation
var vm_handoff: ScenarioVmHandoff
var character_id: String
var remaining: int


func wire_payload(kind: StringName) -> Dictionary:
	if kind == &"character-spell-confirmation":
		return {"kind": String(kind), "characterId": character_id, "remaining": remaining}
	if kind == &"character-vault-publication":
		return {"kind": String(kind), "characterId": character_id}
	var data := {"kind": String(kind), "hook": String(hook), "programId": program_id, "resumeKind": String(resume_kind), "serviceId": service_id, "partyRevived": party_revived}
	if resume_kind == &"scenario-party-defeat":
		data["suspendedVm"] = {} if suspended_vm == null else suspended_vm.to_data()
		data["suspendedOwner"] = {} if suspended_owner == null else suspended_owner.to_data()
		data["vmHandoff"] = {} if vm_handoff == null else vm_handoff.to_data()
	return data
