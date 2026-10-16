import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    globalSetup: ["tests/integration/global-setup.ts"],
    testTimeout: 30_000,
    hookTimeout: 60_000,
    // Les tests d'intégration partagent la même base locale : exécution séquentielle.
    fileParallelism: false,
  },
});
