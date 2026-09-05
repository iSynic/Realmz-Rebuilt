# Shared game contracts

`src/game/shared` is the deliberately narrow common vocabulary of the pure game layer. It is not a general utilities folder. A value belongs here only when at least three features consume it or when it defines one stable boundary between gameplay and a host adapter.

Follow a random decision through `RealmzRng`. The active `GameSession` owns one generator and passes it by reference through `SessionContext`; saves retain only generator state and draw count. Every source-backed or improved-AI draw uses that generator, so a restore resumes the same sequence. `ScriptedRng` supplies explicit oracle values in tests without creating a second production algorithm.

`RealmzArithmetic` names the signed 16-bit and 32-bit conversions needed to reproduce Castle calculations. `DomainEvent` carries an already committed gameplay fact outward. `ViewChangeSet` names the detached read-model domains that presentation must refresh, while `ActionAvailabilityView` and `DefinitionOptionView` carry reusable player-visible choices without granting mutation access.

Media follows a port-and-adapter boundary. `MediaAsset` identifies immutable content; `MediaSource` is the read-only byte-source port. Package and application adapters perform archive or filesystem work. The `PresentationSettings` record is likewise pure, but host-owned: it can remember stable display and audio choices plus the last successfully started campaign identity, and it never enters `GameSession` or an adventure save.

`interactions/` owns the stable pure `InteractionRequest` and `InteractionResponse` envelopes used by scenario execution, playthrough, persistence, and UI. It also owns neutral bodies and strict wire decoding. Character, combat, economy, and scenario bodies stay with their game feature, so the shared folder defines the protocol without becoming the owner of every decision.

When adding a new concept, start in the feature that gives it meaning. Promote it here only after the cross-feature contract is clear. The thin `GameState` root, reusable `ConditionSet`, and interaction envelope are deliberate boundary values; never place feature-specific state, rules, commands, or continuations in this folder. Use `test_realmz_rng.gd` for generator behavior, `test_game_session.gd` and `test_session_persistence.gd` for transaction boundaries, `test_package_repository.gd` for media ports, and `test_classic_ui_system.gd` for presentation settings.
