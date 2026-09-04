# Interaction request payload contract

## Purpose

Own the feature-level typed payloads carried by `InteractionRequest`.

## Ownership

- Detached request bodies and their exact `to_data()` representation.
- Request-specific equality helpers used by restore validation.

## Local Contracts

- Bodies extend `InteractionRequestBody` and remain pure values.
- Serialized kinds, fields, versions, and optional-field presence remain unchanged.
- Request decoding remains strict and rejects unknown or mixed fields.
- Bodies never retain session state, Nodes, repositories, media bytes, or live continuations.
- New callers use the top-level payload class directly; do not add nested compatibility aliases to `InteractionRequest`.

## Work Guidance

- Move one coherent request family with its production callers and tests.
- Keep the central request class limited to kind registration, construction, and codec dispatch.

## Verification

- Run the owning gameplay, restore, scenario, and presentation suites for a moved family.
- Run `tools/verify.ps1` before committing a completed family migration.

## Child DOX Index
