class_name ScenarioApplicationHookWorkflow
extends RefCounted

const RESUME_KINDS: Array[StringName] = [
	&"begin-adventure",
	&"service",
	&"end-adventure",
	&"end-adventure-close",
	&"party-defeat",
	&"scenario-party-defeat",
]


static func continuation(content: RealmzContent, hook: StringName, resume_kind: StringName, service_id: String, suspended: SessionContinuation.ApplicationBody = null) -> SessionContinuation:
	if resume_kind not in RESUME_KINDS:
		return null
	var body := suspended if suspended != null else SessionContinuation.ApplicationBody.new()
	body.hook = hook
	body.program_id = content.scenario.application_hook_program_id(hook)
	body.resume_kind = resume_kind
	body.service_id = service_id
	return SessionContinuation.new(&"application-hook", body)


static func start_context(hook: StringName, service_id: String) -> ScenarioExecutionContext:
	return ScenarioExecutionContext.calling(&"lifecycle").set_application_hook(hook, service_id)


static func completion_event(body: SessionContinuation.ApplicationBody) -> DomainEvent:
	return DomainEvent.new(&"application_hook_completed", {"hook": String(body.hook), "programId": body.program_id})
