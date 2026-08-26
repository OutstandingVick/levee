import test from "node:test";
import assert from "node:assert/strict";
import {
  buildAllocationPlan,
  concentratedPositionStressLossPercent,
  impermanentLossPercent,
  MandateError,
  validateMandate,
} from "../src/engine.js";
import { candidatePools, mandate } from "../examples/scenario.js";

test("impermanent loss is zero at the entry price", () => {
  assert.equal(impermanentLossPercent(1), 0);
});

test("impermanent loss is symmetric for reciprocal price moves", () => {
  assert.ok(Math.abs(impermanentLossPercent(2) - impermanentLossPercent(0.5)) < 1e-10);
});

test("rejects an invalid reserve floor", () => {
  assert.throws(
    () => validateMandate({ ...mandate, reserveFloorUsd: 10_001 }),
    MandateError,
  );
});

test("preserves the reserve floor", () => {
  const plan = buildAllocationPlan(mandate, candidatePools);
  assert.ok(plan.summary.actualReserveUsd >= mandate.reserveFloorUsd);
  assert.equal(
    plan.summary.capitalUsd,
    plan.summary.actualReserveUsd + plan.summary.deployedUsd,
  );
});

test("rejects the tempting boosted pool with explicit risk signals", () => {
  const plan = buildAllocationPlan(mandate, candidatePools);
  const decision = plan.decisions.find((item) => item.poolId.includes("BOOSTED"));
  assert.equal(decision.status, "REJECTED");
  assert.ok(decision.reasons.some((reason) => reason.code === "TVL_TOO_LOW"));
  assert.ok(decision.reasons.some((reason) => reason.code === "POOL_TOO_NEW"));
  assert.ok(decision.reasons.some((reason) => reason.code === "STRESS_LOSS_LIMIT"));
});

test("never returns a plan above the stress-loss mandate", () => {
  const plan = buildAllocationPlan(mandate, candidatePools);
  assert.ok(plan.summary.projectedStressLossPercent <= mandate.maximumStressLossPercent);
});

test("concentrated liquidity has greater downside risk in a narrow range", () => {
  const narrow = concentratedPositionStressLossPercent(-30, 0.9, 1.1);
  const wide = concentratedPositionStressLossPercent(-30, 0.5, 2);
  assert.ok(narrow > wide);
});

test("randomized plans always preserve reserve and stress limits", () => {
  let seed = 42;
  const random = () => ((seed = seed * 1664525 + 1013904223 >>> 0) / 2 ** 32);
  for (let iteration = 0; iteration < 250; iteration += 1) {
    const randomMandate = {
      ...mandate,
      reserveFloorUsd: 1_000 + random() * 7_000,
      maximumStressLossPercent: 2 + random() * 18,
      maximumPoolAllocationPercent: 10 + random() * 90,
    };
    const randomPools = Array.from({ length: 6 }, (_, index) => ({
      ...candidatePools[index % candidatePools.length],
      pair: `RANDOM-${iteration}-${index}`,
      grossApyPercent: random() * 100,
      annualizedVolatilityPercent: random() * 150,
      tvlUsd: random() * 30_000_000,
      ageDays: Math.floor(random() * 800),
      riskyAssetWeight: 0.5 + random() * 1.5,
    }));
    const plan = buildAllocationPlan(randomMandate, randomPools);
    assert.ok(plan.summary.actualReserveUsd + 1e-8 >= randomMandate.reserveFloorUsd);
    assert.ok(plan.summary.projectedStressLossPercent <= randomMandate.maximumStressLossPercent + 1e-8);
  }
});

test("candidate input order cannot change the safety outcome", () => {
  const forward = buildAllocationPlan(mandate, candidatePools);
  const reverse = buildAllocationPlan(mandate, [...candidatePools].reverse());
  assert.equal(forward.summary.projectedStressLossPercent, reverse.summary.projectedStressLossPercent);
  assert.deepEqual(forward.allocations, reverse.allocations);
});
