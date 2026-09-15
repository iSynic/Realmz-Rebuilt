# Monster macro spell reachability

This evidence separates stored opcode-17 rows from static calls originating at authored negative battle macros and positive monster death macros. Static call reachability does not establish controlled execution or ordinary-route reachability.

## Reproduction

Run:

```powershell
./tools/audit_macro_spell_reachability.ps1 src/storage/packages/bundled_campaigns -OutputPath "$env:TEMP/realmz-macro-audit.json"
```

The audit reads the application spell library before applying scenario spell overrides. It follows direct XAP calls and the opcode-specific branch modes and inline Encounter results represented by the compiled programs. It does not treat arbitrary Extra Code integers as program identities.

Application archive SHA-256: `bf1ff5de1d6fc5bd1d5ffff8d582797dfab885acfd9b20b4e02ce9040421e150`.

## Bundled corpus result

| Scenario | Stored opcode 17 | Statically reachable | Immediate | Queued field | Repeated target | Other target | Missing called program |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Assault on Giant Mountain | 7 | 4 | 0 | 4 | 0 | 0 | `xap:165`, `xap:169` |
| Castle in the Clouds | 12 | 3 | 2 | 0 | 1 | 0 | — |
| City of Bywater | 4 | 4 | 1 | 1 | 0 | 2 | — |
| Destroy the Necronomicon | 5 | 5 | 1 | 4 | 0 | 0 | — |
| Griloch's Revenge | 2 | 0 | 0 | 0 | 0 | 0 | — |
| Half Truth | 7 | 7 | 2 | 5 | 0 | 0 | — |
| Mithril Vault | 14 | 9 | 1 | 5 | 1 | 2 | — |
| Prelude to Pestilence | 0 | 0 | 0 | 0 | 0 | 0 | — |
| Trouble in the Sword Lands | 14 | 5 | 3 | 1 | 1 | 0 | — |
| Twin Sands of Time | 0 | 0 | 0 | 0 | 0 | 0 | — |
| War in the Sword Lands | 50 | 10 | 3 | 7 | 0 | 0 | — |
| White Dragon | 16 | 10 | 4 | 5 | 0 | 1 | `xap:9363` |
| Wrath of the Mind Lords | 26 | 11 | 7 | 4 | 0 | 0 | — |
| **Total** | **157** | **68** | **24** | **36** | **3** | **5** | **3 identities** |

The 36 queued rows use fixed or power-area spell signatures and are now executable through the source-anchored macro field path. The controlled VM case uses the application-owned Noxious Cloud signature: it applies the immediate area resolution, creates the persistent field at the retained macro source, preserves the active activation and resource totals, and continues the issuing program.

The three repeated-target rows and five other-target rows remain explicit compatibility work. Castle passes the macro source coordinate directly into `spelltargets`, whose target-type-zero and target-type-one interpretation aliases that coordinate as a combatant selector; ray target type six bypasses its normal `cast` traversal. Those results require controlled Castle fixtures before Rebuilt assigns intentional corrected semantics.

The three missing calls are not one defect. `xap:165` and `xap:169` fall within AOGM's emitted XAP extent. Direct pinned-source inspection finds both nonempty authored rows, and a clean current Providence vNext import resolves both from the death-macro references on normal and variant monster rows 73 and 83. Their omission is stale bundled-package lineage; a fresh package remains blocked by the independent reachable message-30002 reference and therefore has not replaced the bundle.

White Dragon's `xap:9363` lies beyond every emitted program. Exact raw-byte inspection proves that the aligned row presented as battle 143 contains the signed `-9363` value and repeated monster 109 cells inside a foreign suffix. Current Providence vNext preserves those source bytes but rejects the dangling reference rather than emitting an invented program or silently treating the row as valid gameplay. An explicit source correction remains required before White Dragon can be regenerated. Neither case is a runtime spell-family gap.

## Evidence limits

- The bundled scenario archives are the exact packages validated by `verify_bundled_scenarios.ps1`; the audit records each archive SHA-256 in its JSON output.
- Audit schema 2 reports the greatest emitted XAP identity plus missing calls inside and beyond that extent. This structural classification is not by itself evidence that an in-range row is authored or an out-of-range row is invalid; the AOGM and White Dragon conclusions above additionally use exact pinned-source and current Providence readiness evidence.
- No campaign is promoted by this audit. Ordinary-route proof remains absent.
- Third-party coverage remains limited to packages that Providence can compile. The current intake has two loadable packages, but their retained archives were not reused for this audit; the ten conversion-blocked sources cannot yet enter package-level call analysis.
