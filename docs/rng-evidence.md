# Realmz randomness evidence

`RealmzRng` separates three facts that the modern Castle port no longer combines.

## Source/control-flow evidence

At Castle commit `491816ad60037394f92c428e99c004494d3c28b3`, `src/realmz_orig/share-movecost-dialog.c:44` implements `Rand(range)` by calling QuickDraw `Random()`, taking the absolute signed result, and returning `1 + (raw * range) / 32768`. Positive ranges produce Realmz's inclusive 1…range scaling. The signed-short parameter also permits zero and negative authored/effective ranges; those still consume a draw and use C integer truncation toward zero.

The same commit's `src/MemoryManager.cpp:286` documents the original signed range but deliberately supplies host random bytes in the SDL port. Castle therefore remains evidence for scaling and draw order, not for a deterministic historical seed sequence.

## Macintosh algorithm evidence

Apple's *develop* Issue 21 states that QuickDraw updates the unsigned 32-bit `randSeed` with `randSeed = (randSeed * 16807) mod 2147483647` and returns a signed 16-bit number. [Archived issue text](https://preserve.mactech.com/articles/develop/issue_21/21macqaa.html)

*Inside Macintosh: Operating System Utilities* specifies that `Random` is determined solely by `randSeed`, initializes from seed 1, and returns uniformly from -32767 through 32767. [Archived Apple reference](https://dev.os9.ca/techpubs/mac/OSUtilities/OSUtilities-63.html)

The recovered QuickDraw routine returns the signed low word of the updated seed and maps low word `0x8000` to zero, preserving the documented exclusion of -32768. Runtime-unit vectors starting with seed 1 observe seed states `16807`, `282475249`, and `1622650073`; the corresponding signed raw values begin `16807`, `15089`, and `-21287`. Castle scaling at range 100 yields 52, 47, and 65.

## Runtime contract

- The host supplies one seed; normalization maps zero to QuickDraw's default seed 1.
- State and draw count are session-owned and saved.
- Every trace entry records draw index, semantic tag, range, raw value, and result.
- `ScriptedRng` accepts signed raw values for branch-equivalent source/oracle fixtures.
- `draw_classic` preserves Castle's signed-short range formula for source paths where zero or negative effective values are legal; the ordinary `draw` API continues to reject invalid positive-die ranges.
- `draw_between_classic` additionally preserves the signed-short conversion of `high - low + 1` before applying Castle's inclusive offset. This admits source-authored inverted endpoints without sorting them and exposes their exact selectable bounds to package validation.
- No core code may call Godot randomness or derive a seed from wall-clock time.

Evidence labels: the Castle function and Macintosh references are `source-control-flow`; the seed/scaling vectors are `runtime-unit`. A separate `castle-runtime` fixture is still required before claiming an original Mac executable sequence observation.
