# 0020: Exclusive combat session worker

Status: Accepted

Combat Auto and ordinary commands can resolve a complete enemy phase before returning. Running those synchronous rules on the application thread prevents input and drawing during the decision.

The application retains one dedicated worker and transfers exclusive access to the existing `GameSession`, rules, RNG, VM and lazy content caches for each combat job. The pure session transaction API remains synchronous. The worker completes the command and its detached view; the main thread validates job identity, session generation and starting revision before publishing exactly once. No scene operation or presentation timing enters gameplay.

Queue acceptance is a typed `CombatSubmission`, separate from a completed `SessionStep`. While busy the host exposes only its last committed view. Navigation, snapshots, diagnostics and other live queries cannot read the worker-owned session. Projection changes and replacement wait for a boundary. An incomplete result quarantines the session rather than exposing possibly partial state; a saved adventure may replace it. Shutdown joins the worker.

Escape and roster toggles acknowledge immediately and coalesce by character identity. At the boundary, the worker applies those ordinary toggle commands in sorted-ID order and publishes their combined ordered events with one final view. Auto-off commands share a projection; a batch ends at its first Auto-on command because enabling the active character can execute an activation. Escape includes accepted in-flight enables as well as committed and queued toggles. Persistent Auto cannot start another activation before these changes complete. Lifecycle confirmation remains visible; accepted close, load and quit requests run before subsequent automatic work.

Decision-local spell and geometry reuse and guarded reuse of the first pursuit step preserve tactical choices, ordering and RNG draws. No Fast or historical Castle policy is introduced. Verification compares complete state, events and traces, separately measures computation and native responsiveness, and retains cold/warm and renderer evidence in `runtime-performance.md`.
