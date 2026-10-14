# ADR 0023: Responsive scenario preparation and exact-revision loading

Status: Accepted

## Decision

Scenario selection prepares a detached typed setup catalog before constructing the world and scenario program. The catalog uses the ordinary package decoders and application-library composition rules. It contains the campaign restrictions, character rules, creation items and spells, appearance references, and party choices needed by the existing preparation transactions.

The existing cancellable package worker publishes setup readiness and full readiness separately. It retains at most one full candidate; a newer selection supersedes work and stale results cannot publish. A full result already available at the next frame may supply setup directly.

`PartyPreparationState` owns the ordinary character state and serialized RNG while world construction continues. Activation verifies exact package, application-library, and setup-rule identities, then attaches the fully validated content without regenerating characters or equipment. Scenario execution starts only through the ordinary Begin Adventure transaction. Setup-only sessions cannot save an adventure.

Setup caches are derived data, bound to archive, package, schema, decoder, and application-library identities. Bundled sidecars are reproducible release inputs. Missing or stale installed caches regenerate on the package worker. Before publishing cached rules, the reader verifies the source archive entries and compares their setup projection; a cache checksum alone does not establish trust. Full package validation remains mandatory before gameplay.

Saved-adventure browsing discovers previews independently of a loaded session. The selected save resolves to its exact installed package revision, including when other saves in the same scenario use different revisions. Missing revisions remain explicit errors. Approved Update Save operations remain separate verified-copy actions; ordinary loading never rebinds a save.

Settings and saved-adventure browsing are application workspaces available without a session. An explicit Begin Adventure or Load request shows a cancellable loading surface only while preparation is pending. Cancel removes the pending entry request while preserving the party draft or selected save. A later completion cannot enter gameplay. Preparation or restore failures retain those choices and permit retry or Back.

## Consequences

- Package, save, and Character Files formats and identities are unchanged.
- Character creation, vault admission, saved-party admission, and party options share the existing rules during preparation.
- Stable controls remain scene-authored; the application workflow owns package orchestration and presentation owns the loading background choice.
- The remembered campaign changes only after successful adventure entry or restore.
- Bundled preparation verifies sidecars with `tools/generate_setup_catalogs.gd -- --check`; cache bytes never replace source validation.
- Seeded fast/slow setup comparisons must preserve the complete snapshot and initial gameplay state. UI acceptance separately covers cancellation, exact revisions, fresh Settings, compact layouts, and native exports.
