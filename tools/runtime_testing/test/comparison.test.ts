import { strict as assert } from "node:assert";
import { test } from "node:test";
import { compareJourneyEvidence } from "../src/comparison.js";

function run() {
  const state = { party: { characters: [] }, questValues: { "0": -1 } };
  const rng = { generatorState: 17, drawCount: 0 };
  const observation = { campaignId: "synthetic", packageHash: "hash", rulesVersion: "classic", location: { mapId: "land:0", x: 1, y: 1 }, clock: { day: 1, hour: 0, minute: 0 }, fatigue: 4, party: [], pooledGold: 0, pendingInteraction: null, services: [], checkpointState: { rng, gameState: state }, rngTrace: [], scenarioTrace: [], traceLimitReached: false };
  return {
    format: "realmz-journey/1", completed: true, failure: null,
    baseline: { engine: "rebuilt", checkpoint: { format: "realmz2-save", formatVersion: 4, rng, gameState: state, viewRevision: 2 } }, initialObservation: observation,
    steps: [{ index: 0, command: "ui", mode: "ui-control-execution", requestedParams: { action: "click", controlLabel: "Shop" }, params: { action: "click", controlId: "first-process" }, beforeRevision: 3, afterRevision: 4, before: observation, after: structuredClone(observation), reply: { ok: true }, error: null }]
  };
}

test("comparison ignores process revisions and resolved UI IDs, but retains semantic selectors", () => {
  const a = run(), b = run();
  b.baseline.checkpoint.viewRevision = 90;
  b.steps[0]!.beforeRevision = 101;
  b.steps[0]!.afterRevision = 103;
  b.steps[0]!.params.controlId = "second-process";
  assert.equal(compareJourneyEvidence(a, b).equal, true);
  b.steps[0]!.requestedParams.controlLabel = "Done";
  assert.equal(compareJourneyEvidence(a, b).kind, "input");
});

test("comparison rejects different baseline RNG and hidden scenario state", () => {
  const a = run(), b = run();
  b.baseline.checkpoint.rng.generatorState = 18;
  assert.equal(compareJourneyEvidence(a, b).initialEquivalenceVerified, false);
  const c = run();
  c.baseline.checkpoint.gameState.questValues["0"] = 0;
  assert.equal(compareJourneyEvidence(a, c).initialEquivalenceVerified, false);
});

test("comparison identifies the earliest ordered RNG draw rather than array-key string order", () => {
  const a = run(), b = run();
  const values = Array.from({ length: 12 }, (_, drawIndex) => ({ drawIndex, raw: drawIndex, range: 100, result: drawIndex + 1 }));
  Object.assign(a.steps[0]!.after, { rngTrace: values });
  const changed = structuredClone(values);
  changed[2]!.result = 95;
  changed[10]!.result = 96;
  Object.assign(b.steps[0]!.after, { rngTrace: changed });
  const result = compareJourneyEvidence(a, b);
  assert.equal(result.kind, "rngTrace");
  assert.equal((result.firstDifference as { path: string }).path, "$.steps[0].rngTrace[2].result");
});

test("comparison cannot certify a missing baseline, saturated trace, or rejected step", () => {
  const a = run();
  assert.equal(compareJourneyEvidence({ ...a, baseline: null }, a).equal, false);
  const b = run();
  b.steps[0]!.after.traceLimitReached = true;
  assert.equal(compareJourneyEvidence(a, b).equal, false);
  const c = run();
  c.steps[0]!.reply.ok = false;
  assert.equal(compareJourneyEvidence(a, c).equal, false);
});
