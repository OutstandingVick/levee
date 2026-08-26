const EPSILON = 1e-9;
export const MODEL_VERSION = "levee-risk-v1.0.0";

export class MandateError extends Error {}

export function validateMandate(mandate) {
  const required = [
    "capitalUsd",
    "reserveFloorUsd",
    "minimumNetApyPercent",
    "maximumStressLossPercent",
    "maximumPoolAllocationPercent",
  ];

  for (const field of required) {
    if (!Number.isFinite(mandate[field])) {
      throw new MandateError(`${field} must be a finite number`);
    }
  }

  if (mandate.capitalUsd <= 0) throw new MandateError("capitalUsd must be positive");
  if (mandate.reserveFloorUsd < 0 || mandate.reserveFloorUsd > mandate.capitalUsd) {
    throw new MandateError("reserveFloorUsd must be between zero and total capital");
  }
  for (const field of [
    "minimumNetApyPercent",
    "maximumStressLossPercent",
    "maximumPoolAllocationPercent",
  ]) {
    if (mandate[field] < 0 || mandate[field] > 100) {
      throw new MandateError(`${field} must be between 0 and 100`);
    }
  }
  if (!Array.isArray(mandate.approvedAssets) || mandate.approvedAssets.length === 0) {
    throw new MandateError("approvedAssets must not be empty");
  }
  if (!Array.isArray(mandate.approvedProtocols) || mandate.approvedProtocols.length === 0) {
    throw new MandateError("approvedProtocols must not be empty");
  }
  if (!Array.isArray(mandate.priceShocksPercent) || mandate.priceShocksPercent.length === 0) {
    throw new MandateError("priceShocksPercent must not be empty");
  }
}

// Loss versus holding the same 50/50 assets outside a constant-product LP.
export function impermanentLossPercent(priceRatio) {
  if (!Number.isFinite(priceRatio) || priceRatio <= 0) {
    throw new RangeError("priceRatio must be positive");
  }
  return (1 - (2 * Math.sqrt(priceRatio)) / (1 + priceRatio)) * 100;
}

// Conservative loss from initial USD value. For upside shocks, IL remains a real
// opportunity loss even though the LP's nominal USD value increases.
export function positionStressLossPercent(shockPercent) {
  const ratio = 1 + shockPercent / 100;
  if (ratio <= 0) return 100;
  const capitalLoss = Math.max(0, 1 - Math.sqrt(ratio)) * 100;
  return Math.max(capitalLoss, impermanentLossPercent(ratio));
}

function poolIdentity(pool) {
  return `${pool.protocol}:${pool.pair}`;
}

function staticRejections(pool, mandate) {
  const reasons = [];
  if (!mandate.approvedProtocols.includes(pool.protocol)) {
    reasons.push({ code: "PROTOCOL_NOT_APPROVED", detail: `${pool.protocol} is not approved` });
  }
  const unapproved = pool.assets.filter((asset) => !mandate.approvedAssets.includes(asset));
  if (unapproved.length) {
    reasons.push({ code: "ASSET_NOT_APPROVED", detail: `Unapproved assets: ${unapproved.join(", ")}` });
  }
  if (pool.tvlUsd < mandate.minimumPoolTvlUsd) {
    reasons.push({ code: "TVL_TOO_LOW", detail: `$${pool.tvlUsd.toLocaleString()} TVL is below the $${mandate.minimumPoolTvlUsd.toLocaleString()} floor` });
  }
  if (pool.ageDays < mandate.minimumPoolAgeDays) {
    reasons.push({ code: "POOL_TOO_NEW", detail: `${pool.ageDays} days old is below the ${mandate.minimumPoolAgeDays}-day floor` });
  }
  if (pool.dataQualityReasons) reasons.push(...pool.dataQualityReasons);
  return reasons;
}

function netApyPercent(pool, allocationUsd, mandate) {
  const gasDrag = allocationUsd > 0 ? (pool.annualGasCostUsd / allocationUsd) * 100 : Infinity;
  const volatilityPenalty = pool.annualizedVolatilityPercent * mandate.volatilityPenaltyFactor;
  const feeApy = pool.feeApyPercent ?? pool.grossApyPercent;
  const incentiveApy = pool.incentiveApyPercent ?? 0;
  const persistence = Math.min(1, (pool.incentiveDaysRemaining ?? 0) / 365);
  const slippageDrag = (pool.slippageBps ?? 0) / 100;
  const repositionDrag = allocationUsd > 0 ? ((pool.repositionCostUsd ?? 0) / allocationUsd) * 100 : Infinity;
  return feeApy + incentiveApy * persistence - gasDrag - slippageDrag - repositionDrag - volatilityPenalty;
}

export function concentratedPositionStressLossPercent(shockPercent, rangeLowerRatio, rangeUpperRatio) {
  if (!(rangeLowerRatio > 0 && rangeLowerRatio < 1 && rangeUpperRatio > 1)) {
    throw new RangeError("range must straddle the entry-price ratio of 1");
  }
  const value = (price) => {
    const bounded = Math.min(rangeUpperRatio, Math.max(rangeLowerRatio, price));
    const token0 = 1 / Math.sqrt(bounded) - 1 / Math.sqrt(rangeUpperRatio);
    const token1 = Math.sqrt(bounded) - Math.sqrt(rangeLowerRatio);
    return token0 * price + token1;
  };
  const ratio = Math.max(0, 1 + shockPercent / 100);
  const initialValue = value(1);
  const shockedValueRatio = value(ratio) / initialValue;
  const token0Initial = 1 - 1 / Math.sqrt(rangeUpperRatio);
  const token1Initial = 1 - Math.sqrt(rangeLowerRatio);
  const heldValueRatio = (token0Initial * ratio + token1Initial) / initialValue;
  const capitalLoss = Math.max(0, 1 - shockedValueRatio) * 100;
  const relativeLoss = heldValueRatio > 0
    ? Math.max(0, 1 - shockedValueRatio / heldValueRatio) * 100
    : 100;
  return Math.max(capitalLoss, relativeLoss);
}

function poolStressLossPercent(pool, shock) {
  if (pool.rangeLowerRatio && pool.rangeUpperRatio) {
    return concentratedPositionStressLossPercent(shock, pool.rangeLowerRatio, pool.rangeUpperRatio);
  }
  return positionStressLossPercent(shock);
}

function worstPortfolioStressPercent(allocations, pools, mandate) {
  let worst = 0;
  for (const shock of mandate.priceShocksPercent) {
    let lossUsd = 0;
    for (const allocation of allocations) {
      const pool = pools.get(allocation.poolId);
      lossUsd += allocation.amountUsd * poolStressLossPercent(pool, shock) / 100 * pool.riskyAssetWeight;
    }
    worst = Math.max(worst, (lossUsd / mandate.capitalUsd) * 100);
  }
  return worst;
}

export function buildAllocationPlan(mandate, candidatePools, context = {}) {
  validateMandate(mandate);
  const deployableUsd = mandate.capitalUsd - mandate.reserveFloorUsd;
  const maxPerPoolUsd = deployableUsd * mandate.maximumPoolAllocationPercent / 100;
  const pools = new Map(candidatePools.map((pool) => [poolIdentity(pool), pool]));
  const decisions = [];

  const ranked = candidatePools
    .map((pool) => {
      const poolId = poolIdentity(pool);
      const proposedUsd = Math.min(maxPerPoolUsd, deployableUsd);
      const projectedNetApyPercent = netApyPercent(pool, proposedUsd, mandate);
      return { pool, poolId, proposedUsd, projectedNetApyPercent };
    })
    .sort((a, b) => b.projectedNetApyPercent - a.projectedNetApyPercent);

  const allocations = [];
  let remainingUsd = deployableUsd;

  for (const candidate of ranked) {
    const reasons = staticRejections(candidate.pool, mandate);
    const amountUsd = Math.min(candidate.proposedUsd, remainingUsd);
    if (candidate.projectedNetApyPercent + EPSILON < mandate.minimumNetApyPercent) {
      reasons.push({
        code: "NET_APY_TOO_LOW",
        detail: `${candidate.projectedNetApyPercent.toFixed(2)}% net APY is below the ${mandate.minimumNetApyPercent}% floor`,
      });
    }

    const trial = [...allocations, { poolId: candidate.poolId, amountUsd }];
    const trialStress = worstPortfolioStressPercent(trial, pools, mandate);
    if (trialStress > mandate.maximumStressLossPercent + EPSILON) {
      reasons.push({
        code: "STRESS_LOSS_LIMIT",
        detail: `${trialStress.toFixed(2)}% projected portfolio loss exceeds the ${mandate.maximumStressLossPercent}% limit`,
      });
    }

    if (amountUsd <= EPSILON) {
      reasons.push({ code: "NO_CAPACITY", detail: "Deployable capital is already allocated" });
    }

    if (reasons.length === 0) {
      allocations.push({
        poolId: candidate.poolId,
        amountUsd,
        projectedNetApyPercent: candidate.projectedNetApyPercent,
      });
      remainingUsd -= amountUsd;
      decisions.push({ poolId: candidate.poolId, status: "ACCEPTED", reasons: [] });
    } else {
      decisions.push({ poolId: candidate.poolId, status: "REJECTED", reasons });
    }
  }

  const reserveUsd = mandate.reserveFloorUsd + remainingUsd;
  return {
    mandateId: mandate.id,
    mandateVersion: mandate.version ?? "1",
    modelVersion: MODEL_VERSION,
    observedAt: context.observedAt ?? null,
    inputHash: context.inputHash ?? null,
    allocations,
    decisions,
    summary: {
      capitalUsd: mandate.capitalUsd,
      mandatedReserveFloorUsd: mandate.reserveFloorUsd,
      actualReserveUsd: reserveUsd,
      deployedUsd: mandate.capitalUsd - reserveUsd,
      projectedStressLossPercent: worstPortfolioStressPercent(allocations, pools, mandate),
    },
  };
}
