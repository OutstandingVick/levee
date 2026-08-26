import test from "node:test";
import assert from "node:assert/strict";
import { assessDataQuality } from "../src/quality.js";
import { mandate } from "../examples/scenario.js";

test("fails closed on stale and conflicting market data", () => {
  const reasons = assessDataQuality({
    observedAt: "2026-01-01T00:00:00Z", spotPriceUsd: 100, secondaryPriceUsd: 90,
    tvlUsd: 500_000, previousTvlUsd: 1_000_000, feeApyPercent: 150,
  }, mandate, new Date("2026-01-03T00:00:00Z"));
  const codes = reasons.map((reason) => reason.code);
  assert.ok(codes.includes("STALE_DATA"));
  assert.ok(codes.includes("PRICE_DISAGREEMENT"));
  assert.ok(codes.includes("ABNORMAL_TVL_CHANGE"));
  assert.ok(codes.includes("APY_OUTLIER"));
});
