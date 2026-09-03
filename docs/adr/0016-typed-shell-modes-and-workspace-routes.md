# ADR 0016: Typed shell modes and workspace routes

## Status

Accepted.

## Context

The route catalog described Exploration and Combat with dictionaries pointing to one-node `ScreenFrame` scenes. Those nodes were hidden at runtime because both destinations are modes of the persistent application shell. The files made the route count uniform, but they looked like empty screens in Godot and could not truthfully represent the runtime composition.

## Decision

Routes are editor-authored `UiRouteDefinition` resources. Each definition declares its stable identity, label, shortcut, primary-menu status, description, and one of two presentation kinds. A `SHELL_MODE` reuses the persistent HUD and mounts no workspace. A `WORKSPACE` names an explicit `PackedScene` mounted by `ScreenNavigator`.

Exploration and Combat are shell modes. Their former marker scenes are removed. Character, Allies, Bestiary, Character Files, Inventory, Spells, Services, Maps and Notes, and System are workspaces. Route metadata remains editable in the Inspector without duplicating visible shell controls.

## Consequences

- The scene tree truthfully distinguishes a HUD mode from a replaceable workspace.
- Opening Exploration or Combat removes the previous workspace instead of retaining a hidden placeholder.
- New routes require a typed resource and an explicit presentation kind.
- Workflow inventory and presentation tests read the resource-backed registry rather than parsing dictionary literals.
