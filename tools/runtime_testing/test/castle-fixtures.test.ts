import { strict as assert } from "node:assert";
import { existsSync, promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { CastleFixtureManager, CASTLE_MAP_ID, CASTLE_RECIPE, type CastleFixtureEnvironment, type CastleFixtureLaunchRequest } from "../src/castle-fixtures.js";
import { CastleFixtureConfigSchema } from "../src/schemas.js";
import { FixtureError } from "../src/fixtures.js";

const castleSourceRoot = process.env.REALMZ_CASTLE_ROOT ?? path.resolve(process.cwd(), "../../.references/castle");

test("Castle launcher writes the exact nine-field config and uses no executable arguments", { skip: !existsSync(path.join(castleSourceRoot, "base/Realmz/Scenarios/Grilochs Revenge")) }, async () => {
  const repoRoot = path.resolve(process.cwd(), "..", "..");
  const castleRoot = castleSourceRoot;
  const sourceScenario = path.join(castleRoot, "base", "Realmz", "Scenarios", "Grilochs Revenge");
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "realmz-castle-fixture-test-"));
  const castleInstall = path.join(tempRoot, "Realmz Install");
  const castlePath = path.join(castleInstall, "Realmz.exe");
  const installedScenario = path.join(castleInstall, "Scenarios", "Grilochs Revenge");
  const environment: CastleFixtureEnvironment = { testingHome: path.join(tempRoot, "testing-home"), castlePath, castleRoot, rebuiltRoot: repoRoot };
  let launchRequest: CastleFixtureLaunchRequest | undefined;
  try {
    await fs.mkdir(path.dirname(castlePath), { recursive: true });
    await fs.writeFile(castlePath, "fake Castle executable");
    await fs.cp(sourceScenario, installedScenario, { recursive: true });
    const manager = new CastleFixtureManager(environment, (request) => { launchRequest = request; return { pid: 7331 }; });
    await assert.rejects(() => manager.create({ engine: "castle", recipe: CASTLE_RECIPE, source: { kind: "classic-starters", seed: 1, location: { mapId: CASTLE_MAP_ID, x: 7, y: 20 } } }, 10), (error: unknown) => error instanceof FixtureError && error.code === "fixture_timeout");
    assert.ok(launchRequest);
    assert.deepEqual(launchRequest.args, []);
    assert.equal(path.basename(launchRequest.configPath), "config.json");
    assert.equal(path.dirname(launchRequest.configPath), launchRequest.fixtureRoot);
    const raw = JSON.parse(await fs.readFile(launchRequest.configPath, "utf8")) as Record<string, unknown>;
    assert.deepEqual(Object.keys(raw).sort(), ["build", "discoveryRoot", "fixtureId", "identity", "kind", "location", "protocol", "scratchRoot", "seed"].sort());
    assert.equal(raw.kind, "castle-fixture");
    assert.equal((raw.location as Record<string, unknown>).mapId, CASTLE_MAP_ID);
    assert.equal((raw.location as Record<string, unknown>).x, 7);
    assert.equal((raw.identity as Record<string, unknown>).baseCommit, "491816ad60037394f92c428e99c004494d3c28b3");
    CastleFixtureConfigSchema.parse(raw);
    assert.equal(path.basename(launchRequest.stdoutLogPath), "stdout.log");
    const characterDirectory = path.join(launchRequest.fixtureRoot, "userdata", "Character Files");
    assert.deepEqual((await fs.readdir(characterDirectory)).sort(), ["Kevlar", "Lothlorian", "Silver Leaf", "Traskelion", "Trevor", "Vormale"].sort());
  } finally {
    await fs.rm(tempRoot, { recursive: true, force: true });
  }
});

test("Castle launcher accepts only the named Grilochs recipe and bounded baseline cell", async () => {
  const manager = new CastleFixtureManager({ testingHome: "C:/testing", castlePath: "C:/Realmz.exe", castleRoot: "C:/castle", rebuiltRoot: "C:/rebuilt" }, () => ({ pid: 1 }));
  await assert.rejects(() => manager.create({ engine: "castle", recipe: "other" as "native-griloch-starters", source: { kind: "classic-starters", seed: 1, location: { mapId: CASTLE_MAP_ID, x: 7, y: 20 } } }), (error: unknown) => error instanceof FixtureError && error.code === "unsupported_recipe");
  await assert.rejects(() => manager.create({ engine: "castle", source: { kind: "classic-starters", seed: 1, location: { mapId: CASTLE_MAP_ID, x: 6, y: 20 } } }), (error: unknown) => error instanceof FixtureError && error.code === "invalid_source");
});
