import { buildAllocationPlan } from "../src/engine.js";
import { contentHash } from "../src/provenance.js";

export class LeveeAgent {
  constructor({ mandate, simulator, attestor, executor, clock = () => new Date() }) {
    this.mandate = mandate;
    this.simulator = simulator;
    this.attestor = attestor;
    this.executor = executor;
    this.clock = clock;
  }

  async runCycle(candidatePools) {
    const observedAt = this.clock().toISOString();
    const inputHash = contentHash({ mandate: this.mandate, candidatePools, observedAt });
    const plan = buildAllocationPlan(this.mandate, candidatePools, { observedAt, inputHash });
    const selected = plan.allocations[0];
    if (!selected) return { status: "NO_ACTION", observedAt, inputHash, plan };

    const proposal = {
      mandateId: this.mandate.id,
      mandateVersion: plan.mandateVersion,
      modelVersion: plan.modelVersion,
      poolId: selected.poolId,
      amountUsd: selected.amountUsd,
      projectedStressLossPercent: plan.summary.projectedStressLossPercent,
      observedAt,
      inputHash,
    };
    const simulation = await this.simulator.simulate(proposal);
    if (!simulation.success) {
      return { status: "SIMULATION_REJECTED", proposal, simulation, plan };
    }
    const assessment = await this.attestor.attest({ proposal, simulation });
    const receipt = await this.executor.execute({ proposal, simulation, assessment });
    return { status: "EXECUTED", proposal, simulation, assessment, receipt, plan };
  }
}

export function createHttpAttestor(url, fetchImpl = fetch) {
  return {
    async attest(payload) {
      const response = await fetchImpl(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (!response.ok) throw new Error(`attestor returned HTTP ${response.status}`);
      return response.json();
    },
  };
}
