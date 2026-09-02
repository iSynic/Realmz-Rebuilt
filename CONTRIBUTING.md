# Contributing to Realmz Rebuilt

Thank you for helping improve Realmz Rebuilt.

## Before opening a change

- Use Godot 4.7.1 and Git LFS.
- Keep gameplay deterministic and independent of scene nodes, wall-clock time, filesystem access, and Godot randomness.
- Treat Castle source or a controlled Castle runtime fixture as the authority for Classic-visible behavior. Clearly label intentional fidelity corrections.
- Keep Providence as the authoring/compiler boundary and `.realmz2` packages as immutable runtime inputs.
- Do not add proprietary, commercial, user-owned, or unlicensed scenarios, saves, characters, captures, or extracted data.
- Preserve nearest-filtered Classic pixels and the Mobile-renderer/OpenGL-fallback contract.

## Verification

Start with the narrow affected tests. Before requesting review, run:

```powershell
./tools/verify.ps1
git diff --check
```

For export or package changes, also verify a native export and its adjacent PCK or macOS archive. Report the exact checks that ran and any platform validation that remains outstanding.

## Changes and review

Keep changes focused and explain the user-visible behavior, source evidence, package/save impact, and verification. Avoid generated editor state, local paths, logs, captures, `.godot`, `dist`, or personal tool configuration. Pull requests should be suitable for squash or rebase merge; merge commits are not used.

Security-sensitive findings should not include credentials, private saves, or unlicensed content in a public issue. Contact the repository owner privately when disclosure could put users or data at risk.
