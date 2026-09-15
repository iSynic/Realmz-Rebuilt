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

The three missing called program identities are compiler/content diagnostics, not proof that an opcode-17 row executes. They remain separate from runtime spell-family support.

## Evidence limits

- The bundled scenario archives are the exact packages validated by `verify_bundled_scenarios.ps1`; the audit records each archive SHA-256 in its JSON output.
- No campaign is promoted by this audit. Ordinary-route proof remains absent.
- Third-party coverage remains limited to packages that Providence can compile. The current intake has two loadable packages, but their retained archives were not reused for this audit; the ten conversion-blocked sources cannot yet enter package-level call analysis.
