import { readdir } from "node:fs/promises";
import { spawnSync } from "node:child_process";
for (const dir of ["src", "public", "scripts", "sdk"])
  for (const file of await readdir(dir)) {
    if (!/\.(js|mjs)$/.test(file)) continue;
    const result = spawnSync(process.execPath, ["--check", `${dir}/${file}`], {
      stdio: "inherit",
    });
    if (result.status) process.exit(result.status);
  }
console.log(
  "All JavaScript syntax checks passed. Express serves public directly.",
);
