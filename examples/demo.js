import { buildAllocationPlan } from "../src/engine.js";
import { candidatePools, mandate } from "./scenario.js";

const plan = buildAllocationPlan(mandate, candidatePools);

console.log("\nLEVEE — allocation decision\n");
for (const decision of plan.decisions) {
  const icon = decision.status === "ACCEPTED" ? "✓" : "✗";
  console.log(`${icon} ${decision.status.padEnd(8)} ${decision.poolId}`);
  for (const reason of decision.reasons) console.log(`  ${reason.code}: ${reason.detail}`);
}
console.log("\nPortfolio summary");
console.table(plan.summary);
