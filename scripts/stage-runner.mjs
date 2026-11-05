import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const targetTriple = execFileSync("rustc", ["--print", "host-tuple"], { encoding: "utf8" }).trim();

execFileSync("cargo", ["build", "--release", "-p", "agentflow-runner", "-p", "agentflow-mock-cli"], {
  cwd: root,
  stdio: "inherit",
});

const destinationDirectory = join(root, "src-tauri", "binaries");
mkdirSync(destinationDirectory, { recursive: true });
for (const binary of ["agentflow-runner", "agentflow-mock-cli"]) {
  const source = join(root, "target", "release", `${binary}.exe`);
  const destination = join(destinationDirectory, `${binary}-${targetTriple}.exe`);
  copyFileSync(source, destination);
  console.log(`Staged sidecar: ${destination}`);
}
