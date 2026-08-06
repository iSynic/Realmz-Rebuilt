# Infrastructure adapters contract

## Purpose

Own package loading, schema/hash validation, save persistence, migrations, and external host adapters.

## Ownership

- `.realmz2` ZIP verification and typed domain construction.
- `.r2save` repositories, validation, backup rotation, and pure migrations.
- Installed package discovery and capability/readiness reporting.

## Local Contracts

- Treat package and save data as untrusted until all structural, hash, reference, limit, topology, and capability checks pass.
- Validate Classic opcode support, Scenario Action namespaces, caller contexts, typed arguments, Safe bytecode limits, and every program/action reference before constructing content.
- Verify deterministic ZIP inventory/order, canonical manifest package hash, schema hash, and every file hash before parsing runtime documents.
- Runtime JSON dictionaries do not cross into the core; validating factories construct typed immutable content, including explicit topology edges/features, random regions, and cross-map transitions.
- Save only at committed session boundaries. Save the whole aggregate, including VM, interaction, clock, overlays, action state, and RNG.
- Write a temporary save, read and validate it, rotate one backup, then atomically replace the slot.
- Restore failure leaves the current session untouched.
- Save installation is temporary-write, typed readback, one-backup rotation, then same-volume rename; never expose a partially parsed envelope.
- Infrastructure may use Godot filesystem APIs; core and scenario code may not.

## Work Guidance

- Keep installed immutable content separate from mutable session state.
- Return typed validation errors suitable for readiness/error screens.

## Verification

- Contract tests cover hash/schema/reference rejection, package mismatch, corrupt saves, backup recovery, and migrations.

## Child DOX Index

- No child AGENTS.md files are currently required.
