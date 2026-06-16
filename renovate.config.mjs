/**
 * Merges renovate.json with .renovate/*.json fragments.
 * Required for --platform=local (local presets in extends are not supported).
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const readJson = (rel) =>
  JSON.parse(readFileSync(join(root, rel), "utf8"));

const base = readJson("renovate.json");
const { customManagers } = readJson(".renovate/customManagers.json");
const { packageRules: groupRules } = readJson(".renovate/groups.json");

const extendsPresets = (base.extends ?? []).filter(
  (preset) => !preset.startsWith(".renovate/"),
);

export default {
  ...base,
  extends: extendsPresets,
  customManagers,
  packageRules: [...(base.packageRules ?? []), ...groupRules],
};
