/**
 * Sends the API to neurex.ps/haya over FTP.
 *
 *   node tools/deploy.mjs --list            # show the remote tree, send nothing
 *   node tools/deploy.mjs --dry-run         # say what would go
 *   node tools/deploy.mjs --paths=app       # a subtree
 *   node tools/deploy.mjs                   # the API
 *
 * ---------------------------------------------------------------------------
 * WHY THIS IS NOT A COPY OF schools/tools/deploy.mjs.
 *
 * That one skips a file whose remote size already matches the local one, which
 * is the right trade for eight thousand vendor files and a trap for everything
 * else: a same-length edit — `min:8` → `min:6` is the same eight bytes — is
 * silently skipped, and the deploy reports success. This one compares content,
 * by reading the remote file back, and only sends what actually differs. The
 * API is a few hundred small files; correctness is worth the read.
 *
 * It never deletes. `public_html` on this host carries /system, /garage, /dura
 * and /_leads beside /haya, and a mirroring deploy would take them with it.
 */

import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, posix, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "basic-ftp";
import { Writable } from "node:stream";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));

const args = process.argv.slice(2);
const listOnly = args.includes("--list");
const dryRun = args.includes("--dry-run");
const only = args.find((a) => a.startsWith("--paths="))?.split("=")[1]?.split(",");

const fail = (message) => {
  console.error(`\n  ${message}\n`);
  process.exit(1);
};

/* --------------------------------------------------------------- config */

const CONFIG = join(ROOT, ".env.deploy");
if (!existsSync(CONFIG)) fail("no .env.deploy — I do not have the host, and I will not guess it.");

const config = {};
for (const line of readFileSync(CONFIG, "utf8").split(/\r?\n/)) {
  const match = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
  if (match) config[match[1]] = match[2].replace(/^["']|["']$/g, "");
}
for (const key of ["FTP_HOST", "FTP_USER", "FTP_PASS", "REMOTE_DIR"]) {
  if (!config[key]) fail(`.env.deploy is missing ${key}`);
}

const base = posix.join(config.FTP_PATH || "/", config.REMOTE_DIR);

/*
 * What lives where on the server, from README «النشر»:
 *   public_html/haya/_app/   the Laravel application
 *   public_html/haya/api/    its public directory, front controller patched
 */
const NEVER = [
  /(^|\/)\.env$/,          // the server's own, with its database password
  /(^|\/)storage\//,       // logs, caches and uploads the server writes
  /(^|\/)database\/.*\.sqlite$/,
  /(^|\/)bootstrap\/cache\//,
  /(^|\/)\.git/,
  /(^|\/)tests?\//,
  /(^|\/)node_modules\//,
];

const walk = (dir, out = []) => {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const rel = relative(join(ROOT, "api"), full).split("\\").join("/");
    if (NEVER.some((p) => p.test(rel))) continue;
    statSync(full).isDirectory() ? walk(full, out) : out.push({ full, rel });
  }
  return out;
};

const sha = (buf) => createHash("sha256").update(buf).digest("hex");

/* ----------------------------------------------------------------- run */

const client = new Client(30_000);
client.ftp.verbose = false;

try {
  await client.access({
    host: config.FTP_HOST,
    user: config.FTP_USER,
    password: config.FTP_PASS,
    port: Number(config.FTP_PORT || 21),
    secure: config.FTP_SECURE === "true",
    secureOptions: { rejectUnauthorized: false },
  });

  if (listOnly) {
    console.log(`\n  ${base}\n`);
    for (const entry of await client.list(base)) {
      console.log(`    ${entry.isDirectory ? "d" : "-"} ${entry.name}`);
    }
    process.exit(0);
  }

  let files = walk(join(ROOT, "api"));
  if (only) files = files.filter((f) => only.some((p) => f.rel === p || f.rel.startsWith(`${p}/`)));

  console.log(`\n  api   ${files.length} files  →  ${base}/_app\n`);

  let sent = 0;
  let same = 0;

  for (const file of files) {
    const local = readFileSync(file.full);
    const remote = posix.join(base, "_app", file.rel);

    // Read the remote copy and compare content. A missing file throws, which
    // is simply "not there yet".
    let unchanged = false;
    try {
      const chunks = [];
      await client.downloadTo(
        new Writable({
          write(chunk, _enc, done) {
            chunks.push(chunk);
            done();
          },
        }),
        remote,
      );
      unchanged = sha(Buffer.concat(chunks)) === sha(local);
    } catch {
      unchanged = false;
    }

    if (unchanged) {
      same++;
      continue;
    }

    if (!dryRun) {
      await client.ensureDir(posix.dirname(remote));
      await client.uploadFrom(file.full, remote);
    }
    sent++;
    console.log(`    ${dryRun ? "would send" : "sent"}  ${file.rel}`);
  }

  console.log(
    `\n  ${dryRun ? "would send" : "sent"} ${sent}, ${same} already identical. Nothing was deleted.\n`,
  );
} catch (error) {
  fail(error.message);
} finally {
  client.close();
}
