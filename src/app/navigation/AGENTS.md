# Application navigation contract

## Purpose

Translate Godot input into named application actions, typed session commands, and presentation-owned navigation without containing game rules.

## Ownership

- `ApplicationInputRouter` owns keyboard and pointer dispatch priority.
- `UiInputActions` owns the stable named `InputMap` action vocabulary used by the host.

## Local Contracts

- Route, interaction, playback, debug, and exploration input keep their documented priority.
- Gameplay input becomes a typed intent or response before it crosses the session boundary.
- The router calls only public application, lifecycle, shell, and presentation operations.
- No navigation state enters saves or deterministic simulation.

## Work Guidance

- Add a named action before adding a physical shortcut.
- Keep repeat cadence and transient key state in presentation; never queue missed simulation steps.

## Verification

- Run the focused presentation and exploration workflow suites affected by an input change.
- Run `tools/verify_architecture.ps1` to preserve dependency direction.

## Child DOX Index
