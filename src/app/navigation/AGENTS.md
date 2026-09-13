# Application navigation contract

## Purpose

Translate Godot input into named application actions, typed session commands, and presentation-owned navigation without containing game rules.

## Ownership

- `ApplicationInputRouter` owns keyboard, pointer, and normalized controller dispatch priority.
- `UiInputActions` owns the stable named `InputMap` action vocabulary used by the host.
- `ControllerInputOwner` is the single active-pad owner. It resolves physical bindings into named actions, filters stick noise, applies dead-zone release hysteresis and UI repeat, clears held state at disconnect or focus loss, and requires neutral acknowledged input before resuming.

## Local Contracts

- Route, interaction, playback, debug, and exploration input keep their documented priority.
- Gameplay input becomes a typed intent or response before it crosses the session boundary.
- The router calls only public application, lifecycle, shell, and presentation operations.
- No navigation state enters saves or deterministic simulation.
- Raw joypad input is consumed by the controller owner before Godot's built-in UI navigation can also act on it.

## Work Guidance

- Add a named action before adding a physical shortcut.
- Keep repeat cadence and transient key state in presentation; never queue missed simulation steps.

## Verification

- Run the focused presentation and exploration workflow suites affected by an input change.
- Run `tools/verify_architecture.ps1` to preserve dependency direction.

## Child DOX Index
