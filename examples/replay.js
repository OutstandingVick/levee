import { loadSnapshotFile, replaySnapshots } from "../src/history.js";
import { mandate } from "./scenario.js";

const fixtureUrl = new URL("./history.demo.json", import.meta.url);
const dataset = await loadSnapshotFile(fixtureUrl);
const replay = replaySnapshots(mandate, dataset.snapshots);

console.log(`\nLEVEE — historical replay (${dataset.metadata.source})\n`);
console.log(dataset.metadata.warning);
for (const frame of replay.frames) {
  if (frame.status === "WARMUP") {
    console.log(`· ${frame.timestamp.slice(0, 10)} WARMUP — ${frame.reason}`);
    continue;
  }
  const accepted = frame.plan.allocations.map((item) => item.poolId).join(", ") || "reserve only";
  const rejected = frame.plan.decisions.filter((item) => item.status === "REJECTED").length;
  console.log(`✓ ${frame.timestamp.slice(0, 10)} ${accepted}; ${rejected} rejected`);
}
console.log("\nReplay summary");
console.dir(replay.summary, { depth: null });
