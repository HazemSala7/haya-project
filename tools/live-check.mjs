/**
 * Checks the deployed academy — the things that must still be true on the
 * real server, not on a laptop.
 *
 *   node tools/live-check.mjs [https://neurex.ps/haya]
 *
 * Read-only apart from one login per role. It never publishes, never edits a
 * report and never writes to a child's file: this runs against the academy's
 * actual records, and a smoke test that leaves rows behind in a live case file
 * is worse than no smoke test.
 */

const BASE = (process.argv[2] ?? "https://neurex.ps/haya").replace(/\/$/, "");
const API = `${BASE}/api`;

let pass = 0;
let fail = 0;
const failures = [];

function check(label, condition, detail = "") {
  if (condition) {
    pass++;
    console.log(`  ok   ${label}`);
  } else {
    fail++;
    failures.push(label);
    console.log(`  FAIL ${label} ${detail}`);
  }
}

async function call(path, { method = "GET", body, token } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      Accept: "application/json",
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    /* a PHP fatal or an HTML error page — the status is what matters */
  }

  return { status: res.status, json, text };
}

async function page(path) {
  const res = await fetch(`${BASE}${path}`);
  return { status: res.status, html: await res.text() };
}

console.log(`\n-- ${BASE} --\n`);

/* ---- the static dashboard ------------------------------------------- */

console.log("-- the dashboard is served --");

const home = await page("/");
check("the app loads", home.status === 200);
check("it is the academy's build", home.html.includes("أكاديمية الحياة"));
check(
  "assets are mounted under /haya, not the domain root",
  home.html.includes("/haya/_next/"),
  "basePath was not baked into this build",
);

const login = await page("/login/");
check("the login screen is exported", login.status === 200);

/* ---- the API is reachable and mounted right ------------------------- */

console.log("\n-- the API answers --");

const health = await fetch(`${BASE}/api/up`);
check("the health endpoint responds", health.status === 200);

const guarded = await call("/students");
check("an unauthenticated call is refused", guarded.status === 401);
check("and refused as JSON, not an HTML redirect", guarded.json !== null);

const missing = await call("/students/99999999", { token: null });
check("a missing record does not leak a stack trace", !missing.text.includes("vendor"));

/* ---- .env is not on the web ----------------------------------------- */

console.log("\n-- the application directory is closed --");

for (const path of ["/_app/.env", "/_app/composer.json", "/api/../_app/.env"]) {
  const res = await fetch(`${BASE}${path}`);
  check(
    `${path} is not served`,
    res.status === 403 || res.status === 404,
    `got ${res.status}`,
  );
}

const storage = await fetch(`${BASE}/_app/storage/app/private/sessions/1`);
check(
  "session photos are not reachable by path",
  storage.status === 403 || storage.status === 404,
  `got ${storage.status}`,
);

/*
 * The deploy archive must not be left lying next to what it unpacked.
 *
 * `_app/` is closed by its .htaccess — but the zip sits *beside* it, not
 * inside it, so nothing protects it. On the first deploy of this system it
 * stayed there and served 200 with 7.8MB of application, `.env` and the
 * database password included, to anyone who guessed the name.
 */
for (const archive of ["_app.zip", "haya.zip", "haya-backend.zip", "backup.zip", "_app.tar.gz"]) {
  const res = await fetch(`${BASE}/${archive}`);
  check(
    `no deploy archive left at /${archive}`,
    res.status === 403 || res.status === 404,
    `got ${res.status} — delete it now, it contains .env`,
  );
}

// Same for the one-shot installer, if one was used.
const installers = await Promise.all(
  ["install.php", "_install.php", "setup.php", "deploy.php"].map((f) =>
    fetch(`${BASE}/${f}`).then((r) => ({ f, status: r.status })),
  ),
);
check(
  "no installer script left behind",
  installers.every((i) => i.status === 403 || i.status === 404),
  installers.filter((i) => i.status < 400).map((i) => i.f).join(", "),
);

/* ---- the three roles still sign in ---------------------------------- */

console.log("\n-- the accounts work --");

async function login_as(email) {
  const res = await call("/auth/login", {
    method: "POST",
    body: { email, password: process.env.HAYA_PASSWORD ?? "password" },
  });
  return res.json?.token ?? null;
}

const admin = await login_as("admin@haya.test");
const specialist = await login_as("rana@haya.test");
const guardian = await login_as("sanaa@haya.test");

check("the director signs in", Boolean(admin));
check("a specialist signs in", Boolean(specialist));
check("a parent signs in", Boolean(guardian));

if (!admin || !guardian) {
  console.log("\nno session — the checks below need one\n");
  process.exit(1);
}

/* ---- the boundaries hold on the real data --------------------------- */

console.log("\n-- the boundaries hold --");

const asAdmin = await call("/students?per_page=100", { token: admin });
const asParent = await call("/students?per_page=100", { token: guardian });

check("the office sees the roll", asAdmin.json.meta.total > 0);
check(
  "a parent sees fewer children than the office does",
  asParent.json.meta.total < asAdmin.json.meta.total,
  `parent ${asParent.json?.meta?.total} vs office ${asAdmin.json?.meta?.total}`,
);

const parentSessions = await call("/sessions?per_page=100", { token: guardian });

check(
  "no private note reaches a parent",
  parentSessions.json.data.every((s) => s.private_notes === undefined),
);
check(
  "no draft report reaches a parent",
  parentSessions.json.data.every(
    (s) => s.report_status === "published" || ["absent", "excused", "cancelled"].includes(s.status),
  ),
);

const staffOnly = await call("/staff", { token: specialist });
check("a specialist cannot list accounts", staffOnly.status === 403);

const parentWrite = await call("/students", {
  method: "POST",
  token: guardian,
  body: { name: "x", birth_date: "2020-01-01", gender: "male", enrolled_at: "2026-01-01" },
});
check("a parent cannot register a child", parentWrite.status === 403);

/* ---- the office's own alarms are wired ------------------------------ */

console.log("\n-- the office screen is computing --");

const dash = await call("/dashboard", { token: admin });
check("the director's dashboard answers", dash.json?.data?.kind === "admin");
check(
  "it counts unwritten reports",
  typeof dash.json.data.stats.unwritten === "number",
);
check(
  "it counts unanswered parents",
  typeof dash.json.data.stats.unanswered === "number",
);
check(
  "it looks for families who stopped reading",
  Array.isArray(dash.json.data.silent_families),
);

/* ---------------------------------------------------------------------- */

console.log(`\n${pass} passed, ${fail} failed\n`);

if (fail) {
  console.log("failing:");
  failures.forEach((f) => console.log(`  - ${f}`));
  process.exit(1);
}
