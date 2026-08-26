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

  writeFileSync(userConfig, "");

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
