import { LeveeAgent } from "./service.js";
import { candidatePools, mandate } from "../examples/scenario.js";

const agent = new LeveeAgent({
  mandate,
  simulator: { simulate: async () => ({ success: true, gasEstimate: 240_000 }) },
  attestor: { attest: async () => ({ signature: "0xdemo", expiresInSeconds: 300 }) },
  executor: { execute: async () => ({ dryRun: true, transactionHash: null }) },
  clock: () => new Date("2026-08-26T12:00:00Z"),
});

console.dir(await agent.runCycle(candidatePools), { depth: 4 });
