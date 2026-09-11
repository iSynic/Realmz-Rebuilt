import { createHash } from "node:crypto";
import { promises as fs } from "node:fs";

type Fields = Record<string, unknown>;
type Difference = { path: string; left: unknown; right: unknown };
const CAP = 256 * 1024 * 1024;
const GRILOCH_PACKAGE = "bfd9f8a1fb60bd18dbd3bb5475e9c316ce356f7d2846bcdcd26629fd80e28867";
const APPLICATION_PACKAGE = "35dd24b24879e6e4aa8e3eb54672dfba99ba6c1538a3b6760898fcd4a91e8589";
const CASTLE_BASE = "491816ad60037394f92c428e99c004494d3c28b3";
// Sorted name:sha256 lines, joined with LF and no terminal newline. These
// source identities are reviewed with the bounded recipe in docs/runtime-testing.md.
const SCENARIO_FILES = "4d76e476008b561e2598ddbf3bd51de7348b8ff67bf8326f70fcc3f6bed60d0a";
const STARTER_FILES = "3afc0e5146fd87c84eaff55d91a684897e7653950114e18ba08dfe46b0e893ba";
const VOLATILE = new Set(["requestId", "viewRevision", "gameRevision", "revision", "expectedRevision", "beforeRevision", "afterRevision"]);

function object(value: unknown): Fields {
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw new Error("required observation object is missing");
  return value as Fields;
}
function list(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw new Error("required observation array is missing");
  return value;
}
function integer(value: unknown): number {
  if (!Number.isSafeInteger(value)) throw new Error("required observation integer is missing");
  return value as number;
}
function boolean(value: unknown): boolean {
  if (typeof value !== "boolean") throw new Error("required observation boolean is missing");
  return value;
}
function string(value: unknown): string {
  if (typeof value !== "string") throw new Error("required observation string is missing");
  return value;
}

function stable(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") return Object.fromEntries(Object.entries(object(value)).filter(([key]) => !VOLATILE.has(key)).sort(([a], [b]) => a.localeCompare(b)).map(([key, entry]) => [key, stable(entry)]));
  return value;
}

function difference(left: unknown, right: unknown, path = "$"): Difference | null {
  if (JSON.stringify(left) === JSON.stringify(right)) return null;
  if (left === null || right === null || typeof left !== "object" || typeof right !== "object" || Array.isArray(left) !== Array.isArray(right)) return { path, left: left ?? null, right: right ?? null };
  if (Array.isArray(left) && Array.isArray(right)) {
    for (let i = 0; i < Math.max(left.length, right.length); i++) { const result = difference(left[i], right[i], `${path}[${i}]`); if (result) return result; }
  } else {
    const a = object(left), b = object(right);
    for (const key of [...new Set([...Object.keys(a), ...Object.keys(b)])].sort()) { const result = difference(a[key], b[key], `${path}.${key}`); if (result) return result; }
  }
  return { path, left, right };
}

function sourceHash(value: unknown): string {
  const lines = list(value).map((entry) => { const file = object(entry); return `${string(file.name)}:${string(file.sha256)}`; });
  if (new Set(lines.map((line) => line.split(":")[0])).size !== lines.length) throw new Error("duplicate source identity");
  return createHash("sha256").update(lines.sort().join("\n")).digest("hex");
}

function validateProfile(initial: Fields, engine: string): void {
  const identity = object(initial.identity);
  if (engine === "castle") {
    if (identity.baseCommit !== CASTLE_BASE || sourceHash(identity.scenarioFiles) !== SCENARIO_FILES || sourceHash(identity.characters) !== STARTER_FILES) throw new Error("Castle source identities do not match the pinned Griloch profile");
    if (object(initial.scenarioState).profile !== "griloch-ap52/1") throw new Error("Castle relevant-scenario observation is unavailable");
  } else if (initial.campaignId !== "scenario-grilochs-revenge" || initial.packageHash !== GRILOCH_PACKAGE || identity.applicationPackageHash !== APPLICATION_PACKAGE) {
    throw new Error("Rebuilt content identities do not match the pinned Griloch profile");
  }
  if (list(initial.party).length !== 6) throw new Error("Griloch profile requires the complete six-character party");
  const location = object(initial.location);
  if (location.mapId !== "land:0" || ![7, 8].includes(integer(location.x)) || location.y !== 20) throw new Error("Griloch profile baseline is outside the bounded approach");
}

function classicId(value: unknown, prefix: string): number {
  const id = string(value);
  if (!id.startsWith(prefix) || !/^\d+$/.test(id.slice(prefix.length))) throw new Error("unsupported Classic identity");
  return integer(Number(id.slice(prefix.length)));
}

function party(value: unknown, native: boolean): unknown {
  return list(value).map((entry) => {
    const p = object(entry);
    const conditions = list(p.conditions).map(integer);
    if (conditions.length !== 40) throw new Error("complete Classic conditions are required");
    return {
      name: string(p.name), race: native ? integer(p.raceId) : classicId(p.raceId, "classic.race."), caste: native ? integer(p.casteId) : classicId(p.casteId, "classic.caste."), level: integer(p.level),
      stamina: integer(native ? p.stamina : p.health), staminaMax: integer(native ? p.staminaMax : p.maximumHealth), spellPoints: integer(p.spellPoints), spellPointsMax: integer(native ? p.spellPointsMax : p.maximumSpellPoints), load: integer(p.load), loadMax: integer(native ? p.loadMax : p.maximumLoad), conditions,
      money: native ? list(p.money).map(integer) : [integer(p.gold), integer(p.gems), integer(p.jewelry)],
      items: list(p.items).map((item) => { const i = object(item); return { id: integer(native ? i.itemId : i.classicId), equipped: boolean(i.equipped), identified: boolean(i.identified), charges: integer(i.charges) }; })
    };
  });
}

function wealth(value: unknown): number[] {
  const w = object(value);
  return [integer(w.gold), integer(w.gems), integer(w.jewelry)];
}

function scenario(initial: Fields, native: boolean): Fields {
  if (native) {
    const s = object(initial.scenarioState);
    const quests = list(initial.questValues).map(integer);
    if (quests.length !== 128 || quests.slice(100).some((value) => value !== 0)) throw new Error("nonzero native quest slots outside Rebuilt's supported 0..99 range");
    return { quests: quests.slice(0, 100), actionPointChance: integer(s.actionPointChance), banked: list(s.bankedWealth).map(integer), bankAvailable: boolean(s.bankAvailable), templeAvailable: boolean(s.templeAvailable), partyInBoat: boolean(s.partyInBoat), partyCamping: boolean(s.partyCamping), randomEncountersEnabled: boolean(s.randomEncountersEnabled), shopAcceptRanges: s.shopAcceptRanges === null ? null : list(s.shopAcceptRanges).map(integer) };
  }
  const s = object(object(initial.checkpointState).gameState), overlays = object(s.worldOverlays);
  const values = object(s.questValues);
  if (Object.keys(values).some((key) => !/^\d+$/.test(key) || Number(key) >= 100)) throw new Error("unsupported quest identity");
  const target = list(initial.nearbyTargets).map(object).find((entry) => entry.id === "Data DD:0:52");
  if (!target) throw new Error("the exact AP 52 baseline was not observed");
  const overrides = object(overlays.triggerChances);
  const disabled = list(overlays.disabledTriggers).includes("Data DD:0:52");
  const chance = disabled ? 0 : overrides["Data DD:0:52"] ?? (target.authoredActive === true ? target.chancePercent : 0);
  return { quests: Array.from({ length: 100 }, (_, i) => integer(values[String(i)] ?? 0)), actionPointChance: integer(chance), banked: wealth(object(s.party).bankedWealth), bankAvailable: boolean(s.bankAvailable), templeAvailable: boolean(s.templeAvailable), partyInBoat: boolean(s.partyInBoat), partyCamping: boolean(s.partyCamping), randomEncountersEnabled: boolean(s.randomEncountersEnabled), shopAcceptRanges: s.activeShopId === "" ? null : list(s.shopAcceptRanges).map(integer) };
}

function sharedObservation(value: unknown, engine: string): unknown {
  const o = object(value), native = engine === "castle";
  const rng = native ? object(o.rng) : object(object(o.checkpointState).rng);
  const pending = o.pendingInteraction === null ? null : object(o.pendingInteraction);
  if (pending && pending.kind !== "shop_action") throw new Error("interaction normalization is unsupported outside the Griloch shop");
  return stable({ location: o.location, clock: o.clock, fatigue: integer(o.fatigue), party: party(o.party, native), pool: native ? list(o.pool).map(integer) : wealth(object(object(object(o.checkpointState).gameState).party).pooledWealth),
    rng: { state: integer(native ? rng.state : rng.generatorState), drawCount: integer(rng.drawCount) }, scenario: scenario(o, native),
    services: list(o.services).map((entry) => { const s = object(entry); if (s.kind !== "shop") throw new Error("unsupported service"); return { kind: "shop", id: native ? integer(s.shopId) : classicId(s.serviceId, "classic.shop.") }; }),
    pending: pending ? { kind: "shop_action", shopId: native ? integer(pending.shopId) : classicId(object(object(pending.data).payload).shopId, "classic.shop.") } : null });
}

function rebuiltObservation(value: unknown): unknown {
  const o = object(value);
  for (const key of ["campaignId", "packageHash", "rulesVersion", "location", "clock", "party", "pooledGold", "pendingInteraction", "rngTrace", "scenarioTrace"]) if (!(key in o)) throw new Error(`missing Rebuilt semantics: ${key}`);
  return stable(Object.fromEntries(["campaignId", "packageHash", "rulesVersion", "location", "clock", "fatigue", "party", "pooledGold", "pendingInteraction", "services", "checkpointState", "rngTrace", "scenarioTrace"].map((key) => [key, o[key]])));
}

function trace(value: unknown, engine: string, kind: "rngTrace" | "scenarioTrace"): unknown {
  const entries = list(object(value)[kind]).map(object);
  if (kind === "rngTrace") return entries.map((e) => ({ drawIndex: integer(e.drawIndex), raw: integer(e.raw), range: integer(e.range), result: integer(e.result) }));
  return entries.filter((e) => engine === "castle" ? e.rawOpcode !== 0 : e.event === "execute-classic").map((e) => ({ programId: string(e.programId), slot: integer(e.slot), rawOpcode: integer(e.rawOpcode), id: integer(e.id) }));
}

function validateEvidence(value: unknown): { evidence: Fields; baseline: Fields; initial: Fields; engine: string; steps: Fields[] } {
  const evidence = object(value);
  if (evidence.format !== "realmz-journey/1" || typeof evidence.completed !== "boolean") throw new Error("invalid journey evidence format");
  const baseline = object(evidence.baseline), initial = object(evidence.initialObservation), checkpoint = object(baseline.checkpoint);
  const engine = string(baseline.engine);
  if (!["rebuilt", "castle"].includes(engine)) throw new Error("unsupported engine normalization");
  if (engine === "rebuilt" && (checkpoint.format !== "realmz2-save" || checkpoint.formatVersion !== 4 || !checkpoint.rng || !checkpoint.gameState)) throw new Error("validated Rebuilt baseline checkpoint is missing");
  if (engine === "rebuilt") {
    integer(object(checkpoint.rng).generatorState);
    integer(object(checkpoint.rng).drawCount);
    const captured = object(initial.checkpointState);
    if (difference(stable(checkpoint.rng), stable(captured.rng)) || difference(stable(checkpoint.gameState), stable(captured.gameState))) throw new Error("initial observation does not match the captured baseline state");
  }
  if (engine === "castle" && (checkpoint.kind !== "native-observation" || checkpoint.restorable !== false)) throw new Error("native baseline checkpoint is missing");
  const steps = list(evidence.steps).map(object);
  if (initial.traceLimitReached === true) throw new Error("baseline trace is incomplete");
  for (const [index, step] of steps.entries()) {
    if (step.index !== index || !["act", "respond", "ui", "invoke"].includes(string(step.command))) throw new Error("invalid journey step order or command");
    object(step.before);
    if (step.after !== null) object(step.after);
    if (object(step.before).traceLimitReached === true || (step.after !== null && object(step.after).traceLimitReached === true)) throw new Error("journey trace is incomplete");
    if (evidence.completed && (step.after === null || step.reply === null || object(step.reply).ok !== true || step.error !== null)) throw new Error("completed evidence contains an incomplete or rejected step");
  }
  return { evidence, baseline, initial, engine, steps };
}

export function compareJourneyEvidence(leftValue: unknown, rightValue: unknown): Fields {
  let initialEquivalenceVerified = false;
  try {
    const left = validateEvidence(leftValue), right = validateEvidence(rightValue);
    const crossEngine = left.engine !== right.engine;
    if (left.engine === "castle" || right.engine === "castle") { validateProfile(left.initial, left.engine); validateProfile(right.initial, right.engine); }
    const normalize = crossEngine || left.engine === "castle" ? sharedObservation : rebuiltObservation;
    if (!crossEngine && left.engine === "rebuilt") {
      const checkpointDifference = difference(stable(left.baseline.checkpoint), stable(right.baseline.checkpoint), "$.baseline");
      if (checkpointDifference) return { initialEquivalenceVerified: false, equal: false, reason: "initial_checkpoint_difference", firstDifference: checkpointDifference };
    }
    const initialDifference = difference(normalize(left.initial, left.engine), normalize(right.initial, right.engine), "$.initial");
    if (initialDifference) return { initialEquivalenceVerified: false, equal: false, reason: "initial_state_difference", firstDifference: initialDifference };
    initialEquivalenceVerified = true;
    for (let index = 0; index < Math.min(left.steps.length, right.steps.length); index++) {
      const a = left.steps[index]!, b = right.steps[index]!;
      const input = (s: Fields): unknown => stable({ command: s.command, mode: s.mode, params: s.requestedParams ?? s.params });
      const inputs = difference(input(a), input(b), `$.steps[${index}].input`);
      if (inputs) return { initialEquivalenceVerified, equal: false, kind: "input", stepIndex: index, firstDifference: inputs };
      for (const kind of ["rngTrace", "scenarioTrace"] as const) {
        if (a.after === null || b.after === null) break;
        const compared = crossEngine ? difference(trace(a.after, left.engine, kind), trace(b.after, right.engine, kind), `$.steps[${index}].${kind}`) : difference(stable(object(a.after)[kind]), stable(object(b.after)[kind]), `$.steps[${index}].${kind}`);
        if (compared) return { initialEquivalenceVerified, equal: false, kind, stepIndex: index, firstDifference: compared };
      }
      const error = difference(stable(a.error), stable(b.error), `$.steps[${index}].error`);
      if (error) return { initialEquivalenceVerified, equal: false, kind: "error", stepIndex: index, firstDifference: error };
      const state = difference(a.after === null ? null : normalize(a.after, left.engine), b.after === null ? null : normalize(b.after, right.engine), `$.steps[${index}].state`);
      if (state) return { initialEquivalenceVerified, equal: false, kind: "state", stepIndex: index, firstDifference: state };
    }
    const incomplete = !left.evidence.completed || !right.evidence.completed || left.evidence.failure !== null || right.evidence.failure !== null || !left.steps.length || !right.steps.length;
    if (incomplete) return { initialEquivalenceVerified, equal: false, reason: "evidence_incomplete", firstDifference: difference(stable(left.evidence.failure), stable(right.evidence.failure), "$.failure") };
    const stepCount = difference(left.steps.length, right.steps.length, "$.steps.length");
    return { initialEquivalenceVerified, equal: stepCount === null, firstDifference: stepCount, steps: Math.min(left.steps.length, right.steps.length), profile: crossEngine || left.engine === "castle" ? "griloch-ap52/1" : "rebuilt-save-v4" };
  } catch (error) {
    return { initialEquivalenceVerified, equal: false, reason: "normalization_unavailable", firstDifference: null, error: error instanceof Error ? error.message : "invalid comparison evidence" };
  }
}

export async function compareJourneyRuns(leftPath: string, rightPath: string): Promise<Fields> {
  try {
    const read = async (file: string): Promise<unknown> => {
      const stat = await fs.lstat(file);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > CAP) throw new Error("comparison requires regular evidence files within the 256 MiB bound");
      return JSON.parse(await fs.readFile(file, "utf8"));
    };
    return compareJourneyEvidence(await read(leftPath), await read(rightPath));
  } catch (error) {
    return { initialEquivalenceVerified: false, equal: false, reason: "invalid_evidence", firstDifference: null, error: error instanceof Error ? error.message : "evidence could not be read" };
  }
}
