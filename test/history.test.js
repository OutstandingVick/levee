import test from "node:test";
import assert from "node:assert/strict";
import { loadSnapshotFile, replaySnapshots, SnapshotError } from "../src/history.js";
import { mandate } from "../examples/scenario.js";

const fixtureUrl = new URL("../examples/history.demo.json", import.meta.url);

test("historical replay warms up before deriving volatility", async () => {
  const dataset = await loadSnapshotFile(fixtureUrl);
  const replay = replaySnapshots(mandate, dataset.snapshots);
  assert.equal(replay.summary.warmupSnapshots, 2);
  assert.equal(replay.summary.evaluatedSnapshots, 3);
});

test("every replayed plan preserves reserve and stress invariants", async () => {
  const dataset = await loadSnapshotFile(fixtureUrl);
  const replay = replaySnapshots(mandate, dataset.snapshots);
  for (const frame of replay.frames.filter((item) => item.status === "EVALUATED")) {
    assert.ok(frame.plan.summary.actualReserveUsd >= mandate.reserveFloorUsd);
    assert.ok(frame.plan.summary.projectedStressLossPercent <= mandate.maximumStressLossPercent);
  }
});

test("replay rejects the volatile boosted pool despite high APY", async () => {
  const dataset = await loadSnapshotFile(fixtureUrl);
  const replay = replaySnapshots(mandate, dataset.snapshots);
  for (const frame of replay.frames.filter((item) => item.status === "EVALUATED")) {
    const boosted = frame.plan.decisions.find((item) => item.poolId.includes("BOOSTED"));
    assert.equal(boosted.status, "REJECTED");
  }
});

test("rejects non-chronological snapshot data", () => {
  const pool = { id: "p", spotPriceUsd: 1, grossApyPercent: 1, tvlUsd: 1 };
  assert.throws(
    () => replaySnapshots(mandate, [
      { timestamp: "2026-01-02T00:00:00Z", pools: [pool] },
      { timestamp: "2026-01-01T00:00:00Z", pools: [pool] },
    ]),
    SnapshotError,
  );
});
