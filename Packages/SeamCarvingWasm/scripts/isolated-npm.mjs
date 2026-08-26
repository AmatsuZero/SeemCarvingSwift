import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * Creates an npm environment for external-consumer checks that cannot inherit
 * the developer's user-level npm configuration.
 */
export function createIsolatedNpmEnvironment(baseEnvironment = process.env) {
  const configDirectory = mkdtempSync(join(tmpdir(), "seemcarving-npm-config-"));
  const userConfig = join(configDirectory, "npmrc");

  // Block dependency lifecycle scripts during arbitrary tarball installation;
  // explicit `npm run` commands still execute normally.
  writeFileSync(userConfig, "ignore-scripts=true\n");

  const environment = Object.fromEntries(
    Object.entries(baseEnvironment).filter(([name]) => !name.toLowerCase().startsWith("npm_config_")),
  );
  environment.NPM_CONFIG_USERCONFIG = userConfig;

  return {
    env: environment,
    userConfig,
    cleanup() {
      rmSync(configDirectory, { force: true, recursive: true });
    },
  };
}
