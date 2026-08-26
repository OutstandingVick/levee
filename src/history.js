import { readFile } from "node:fs/promises";
import { buildAllocationPlan } from "./engine.js";
import { contentHash } from "./provenance.js";
import { assessDataQuality } from "./quality.js";

export class SnapshotError extends Error {}

export async function loadSnapshotFile(path) {
  const parsed = JSON.parse(await readFile(path, "utf8"));
  if (!Array.isArray(parsed.snapshots)) {
    throw new SnapshotError("snapshot file must contain a snapshots array");
  }
  validateSnapshots(parsed.snapshots);
  return parsed;
}

export function validateSnapshots(snapshots) {
  let previousTime = -Infinity;
  for (const snapshot of snapshots) {
    const time = Date.parse(snapshot.timestamp);
    if (!Number.isFinite(time) || time <= previousTime) {
      throw new SnapshotError("snapshot timestamps must be valid and strictly increasing");
    }
    previousTime = time;
    if (!Array.isArray(snapshot.pools) || snapshot.pools.length === 0) {
      throw new SnapshotError(`${snapshot.timestamp} must contain at least one pool`);
    }
    const ids = new Set();
    for (const pool of snapshot.pools) {
      if (!pool.id || ids.has(pool.id)) throw new SnapshotError("pool ids must be unique per snapshot");
      ids.add(pool.id);
      for (const field of ["spotPriceUsd", "grossApyPercent", "tvlUsd"]) {
        if (!Number.isFinite(pool[field]) || pool[field] <= 0) {
          throw new SnapshotError(`${pool.id}.${field} must be positive`);
        }
      }
    }
  }
}

export function annualizedVolatilityPercent(observations) {
  if (observations.length < 3) {
    throw new SnapshotError("at least three price observations are required");
  }
  const returns = [];
  const intervalsYears = [];
  for (let index = 1; index < observations.length; index += 1) {
    const previous = observations[index - 1];
    const current = observations[index];
    const intervalMs = Date.parse(current.timestamp) - Date.parse(previous.timestamp);
    if (intervalMs <= 0) throw new SnapshotError("price observations must be chronological");
    returns.push(Math.log(current.price / previous.price));
    intervalsYears.push(intervalMs / (365.25 * 24 * 60 * 60 * 1000));
  }
  const mean = returns.reduce((sum, value) => sum + value, 0) / returns.length;
  const variance = returns.reduce((sum, value) => sum + (value - mean) ** 2, 0)
    / (returns.length - 1);
  const averageIntervalYears = intervalsYears.reduce((sum, value) => sum + value, 0)
    / intervalsYears.length;
  return Math.sqrt(variance / averageIntervalYears) * 100;
}

export function replaySnapshots(mandate, snapshots, options = {}) {
  validateSnapshots(snapshots);
  const windowSize = options.volatilityWindowSize ?? 5;
  const histories = new Map();
  const frames = [];

  for (const snapshot of snapshots) {
    for (const pool of snapshot.pools) {
      const history = histories.get(pool.id) ?? [];
      history.push({ timestamp: snapshot.timestamp, price: pool.spotPriceUsd });
      histories.set(pool.id, history.slice(-windowSize));
    }

    const eligiblePools = snapshot.pools.flatMap((pool) => {
      const history = histories.get(pool.id);
      if (history.length < 3) return [];
      return [{
        ...pool,
        annualizedVolatilityPercent: annualizedVolatilityPercent(history),
        dataQualityReasons: assessDataQuality(
          { ...pool, observedAt: pool.observedAt ?? snapshot.timestamp },
          mandate,
          new Date(snapshot.timestamp),
        ),
      }];
    });

    if (eligiblePools.length === 0) {
      frames.push({
        timestamp: snapshot.timestamp,
        status: "WARMUP",
        reason: "At least three observations are required to estimate volatility",
      });
      continue;
    }

    const plan = buildAllocationPlan(mandate, eligiblePools, {
      observedAt: snapshot.timestamp,
      inputHash: contentHash({ mandate, snapshot }),
    });
    frames.push({ timestamp: snapshot.timestamp, status: "EVALUATED", plan });
  }

  return {
    mandateId: mandate.id,
    volatilityWindowSize: windowSize,
    frames,
    summary: summarizeReplay(frames),
  };
}

function summarizeReplay(frames) {
  const evaluated = frames.filter((frame) => frame.status === "EVALUATED");
  let allocationChanges = 0;
  let previous = null;
  let turnoverUsd = 0;
  let estimatedGasUsd = 0;
  let estimatedFeeIncomeUsd = 0;
  let previousAllocations = new Map();
  const rejectionCounts = {};

  for (const frame of evaluated) {
    const current = frame.plan.allocations.map((item) => item.poolId).sort().join("|");
    if (previous !== null && current !== previous) allocationChanges += 1;
    previous = current;
    const currentAllocations = new Map(frame.plan.allocations.map((item) => [item.poolId, item.amountUsd]));
    const poolIds = new Set([...previousAllocations.keys(), ...currentAllocations.keys()]);
    let frameTurnover = 0;
    for (const poolId of poolIds) {
      frameTurnover += Math.abs((currentAllocations.get(poolId) ?? 0) - (previousAllocations.get(poolId) ?? 0));
    }
    turnoverUsd += frameTurnover;
    if (frameTurnover > 0) estimatedGasUsd += 35;
    estimatedFeeIncomeUsd += frame.plan.allocations.reduce(
      (sum, allocation) => sum + allocation.amountUsd * allocation.projectedNetApyPercent / 100 / 365,
      0,
    );
    previousAllocations = currentAllocations;
    for (const decision of frame.plan.decisions) {
      for (const reason of decision.reasons) {
        rejectionCounts[reason.code] = (rejectionCounts[reason.code] ?? 0) + 1;
      }
    }
  }

  return {
    totalSnapshots: frames.length,
    evaluatedSnapshots: evaluated.length,
    warmupSnapshots: frames.length - evaluated.length,
    allocationChanges,
    rejectionCounts,
    maximumProjectedStressLossPercent: evaluated.reduce(
      (maximum, frame) => Math.max(maximum, frame.plan.summary.projectedStressLossPercent),
      0,
    ),
    turnoverUsd,
    estimatedGasUsd,
    estimatedNetIncomeUsd: estimatedFeeIncomeUsd - estimatedGasUsd,
  };
}
