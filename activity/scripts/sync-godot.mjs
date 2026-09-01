import { createHash } from "node:crypto";
import { access, cp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const activityDirectory = path.resolve(scriptDirectory, "..");
const repositoryDirectory = path.resolve(activityDirectory, "..");
const godotExportDirectory = path.join(repositoryDirectory, "build", "web");
const publicGameDirectory = path.join(activityDirectory, "public", "game");
const godotEntryPoint = path.join(godotExportDirectory, "index.html");

try {
  await access(godotEntryPoint, constants.R_OK);
} catch {
  throw new Error(
    `Godot web export not found at ${godotEntryPoint}. ` +
      "Run scripts/export_web.ps1 or export the Web preset there first.",
  );
}

const godotShell = await readFile(godotEntryPoint, "utf8");
if (!godotShell.includes('"experimentalVK":true')) {
  throw new Error("The Godot Web export must enable mobile virtual-keyboard support.");
}

async function hashDirectory(directory, relativeDirectory = "", hash = createHash("sha256")) {
  const entries = await readdir(directory, { withFileTypes: true });
  entries.sort((left, right) => left.name.localeCompare(right.name));
  for (const entry of entries) {
    if (entry.name.endsWith(".import")) continue;
    const relativePath = path.posix.join(relativeDirectory, entry.name);
    const absolutePath = path.join(directory, entry.name);
    hash.update(relativePath);
    if (entry.isDirectory()) await hashDirectory(absolutePath, relativePath, hash);
    else if (entry.isFile()) hash.update(await readFile(absolutePath));
    else throw new Error(`The Godot export contains an unsupported entry: ${relativePath}`);
  }
  return hash;
}

const buildId = (await hashDirectory(godotExportDirectory)).digest("hex").slice(0, 16);
const versionDirectory = path.join(publicGameDirectory, buildId);

const expectedGameDirectory = path.resolve(activityDirectory, "public", "game");
if (publicGameDirectory !== expectedGameDirectory) {
  throw new Error(`Refusing to replace unexpected directory: ${publicGameDirectory}`);
}

await rm(publicGameDirectory, { recursive: true, force: true });
await mkdir(versionDirectory, { recursive: true });
await cp(godotExportDirectory, versionDirectory, {
  recursive: true,
  force: true,
  filter: (source) => !source.endsWith(".import"),
});

const versionEntryPoint = path.join(versionDirectory, "index.html");
const generatedViewport =
  '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">';
const activityViewport =
  '<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover, interactive-widget=resizes-content">';
let versionShell = await readFile(versionEntryPoint, "utf8");
if (versionShell.includes(generatedViewport)) {
  versionShell = versionShell.replace(generatedViewport, activityViewport);
} else if (!versionShell.includes(activityViewport)) {
  throw new Error("The Godot Web export has an unexpected viewport declaration.");
}
await writeFile(versionEntryPoint, versionShell, "utf8");

await writeFile(
  path.join(activityDirectory, "public", "game-manifest.json"),
  `${JSON.stringify({ buildId, entry: `/game/${buildId}/index.html` })}\n`,
  "utf8",
);

console.log(`Staged Godot web build ${buildId} for the Activity shell.`);
