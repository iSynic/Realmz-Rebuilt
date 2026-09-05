# ADR 0017: Lazy workspace route scenes

## Status

Accepted.

## Context

ADR 0016 made every route an editor-authored `UiRouteDefinition` and stored each workspace as a `PackedScene`. Building the persistent menu reads every route definition. Godot therefore loaded all nine major workspace dependency graphs before the front door became ready, even though the player had not opened them.

The scenes were correctly editable, but their eager dependency cost violated the startup performance boundary and the rule that route work happens at route transitions.

## Decision

Keep the typed route resources and their Inspector editing. A workspace route stores an `@export_file("*.tscn")` scene path instead of an embedded `PackedScene`. `UiRouteDefinition` loads that scene on first use, and `ScreenNavigator` instantiates it only when the route opens. Shell-mode routes keep an empty path; Godot's ordinary resource cache supplies reuse without a statically retained scene graph.

## Consequences

- Menu construction reads route metadata without loading every workspace hierarchy.
- Maintainers still select and navigate to the owning scene through the Godot Inspector.
- A workspace pays its load cost when first opened, and subsequent visits may reuse Godot's cached scene resource.
- Route tests validate both the declared path and its `PackedScene` resource type.
- ADR 0016 remains authoritative for the shell-mode/workspace distinction; this decision replaces only its eager `PackedScene` storage detail.
