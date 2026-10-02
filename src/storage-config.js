import path from "node:path";
import { fileURLToPath } from "node:url";
export const APP_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
export function assertPrivateDirectory(directory, { appRoot = APP_ROOT } = {}) {
  const resolved = path.resolve(directory),
    relative = path.relative(appRoot, resolved);
  if (
    resolved === path.resolve(appRoot) ||
    (!relative.startsWith(".." + path.sep) &&
      relative !== ".." &&
      !path.isAbsolute(relative))
  )
    throw Error(
      "DATA_DIR must be outside the application/deployment directory",
    );
  if (
    resolved
      .split(path.sep)
      .some((p) =>
        [
          "public_html",
          "hbuilds",
          "public",
          "build",
          "dist",
          "node_modules",
        ].includes(p),
      )
  )
    throw Error(
      "DATA_DIR cannot be inside public_html, hbuilds, public, build, dist or node_modules",
    );
  return resolved;
}
export function storageConfig(env = process.env, { appRoot = APP_ROOT } = {}) {
  const driver = env.DATABASE_DRIVER || (env.MYSQL_HOST ? "mysql" : "sqlite");
  if (!["sqlite", "mysql"].includes(driver))
    throw Error("DATABASE_DRIVER must be sqlite or mysql");
  if (driver === "mysql") {
    if (!env.MYSQL_HOST)
      throw Error("MYSQL_HOST is required for the mysql database driver");
    return { driver };
  }
  const production = env.NODE_ENV === "production";
  if (!production && !env.DATA_DIR)
    return {
      driver,
      filename: env.SQLITE_PATH || path.join(appRoot, "zelon.sqlite"),
    };
  let directory = env.DATA_DIR;
  if (!directory) {
    const match = appRoot.match(
      /^(\/home\/[^/]+\/domains\/[^/]+)\/(?:hbuilds|nodejs|public_html)(?:\/|$)/,
    );
    if (match) directory = path.join(match[1], "zelon-data");
  }
  if (!directory)
    throw Error(
      "Set DATA_DIR to an absolute private persistent directory outside the deployed application",
    );
  if (!path.isAbsolute(directory))
    throw Error("DATA_DIR must be an absolute path");
  directory = assertPrivateDirectory(directory, { appRoot });
  return { driver, directory, filename: path.join(directory, "zelon.sqlite") };
}
