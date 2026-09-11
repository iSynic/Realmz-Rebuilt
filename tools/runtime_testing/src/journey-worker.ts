import { runWorkerFromCommandLine } from "./journeys.js";

runWorkerFromCommandLine().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
