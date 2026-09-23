/**
 * End-to-end check of the academy API.
 *
 * Runs against a live server and exercises the places where being wrong costs
 * something that cannot be taken back: does a guardian ever see what a
 * specialist wrote for herself, can a report a mother has already read be
 * quietly rewritten, does a curve start where the child started, and can one
 * family reach another family's child.
 *
 *   cd api && php artisan serve --port=8020
 *   node tools/smoke-test.mjs [http://127.0.0.1:8020/api]
 */

const API = (process.argv[2] ?? "http://127.0.0.1:8020/api").replace(/\/$/, "");

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
    /* some checks only want the status */
  }

  return { status: res.status, json };
}

async function login(email, password = "password") {
  const res = await call("/auth/login", { method: "POST", body: { email, password } });
  return res.json?.token;
}

/* ---------------------------------------------------------------------- */

console.log("\n-- signing in --");

const admin = await login("admin@haya.test");
const rana = await login("rana@haya.test");   // speech therapist
const aya = await login("aya@haya.test");     // occupational therapist
const mom = await login("sanaa@haya.test");   // Yousef's mother
const other = await login("raghad@haya.test"); // Layan's mother

check("the director can sign in", Boolean(admin));
check("a specialist can sign in", Boolean(rana));
check("a parent can sign in", Boolean(mom));

const ranaId = (await call("/auth/me", { token: rana })).json.data.id;

const wrong = await call("/auth/login", {
  method: "POST",
  body: { email: "admin@haya.test", password: "nope" },
});
check("a wrong password is refused", wrong.status === 422);

const unknown = await call("/auth/login", {
  method: "POST",
  body: { email: "nobody@haya.test", password: "password" },
});
check(
  "an unknown address gives the same answer as a wrong password",
  unknown.status === 422 &&
    unknown.json?.errors?.email?.[0] === wrong.json?.errors?.email?.[0],
);

const anonymous = await call("/students");
check("no token means no data", anonymous.status === 401);

/*
 * The same refusal, from a client that does not announce it wants JSON.
 *
 * This is the one bug in the system that could not be seen locally. The
 * Authenticate middleware builds its exception like this:
 *
 *     $request->expectsJson() ? null : $this->redirectTo($request)
 *
 * and Laravel's default `redirectTo` is `fn () => route('login')`. With no
 * such route, that throws while the AuthenticationException is still being
 * constructed — so no exception handler ever sees it and the caller gets a
 * 500 with "Route [login] not defined" in the log, which describes nothing
 * that is actually wrong. Fixed by `redirectGuestsTo(fn () => null)` in
 * bootstrap/app.php.
 *
 * Every request the frontend makes carries the Accept header, so the app was
 * fine; it was anything else — a browser opened straight at an endpoint, a
 * monitor, a curl by hand — that got the 500.
 */
const plain = await fetch(`${API}/students`);
check(
  "an unauthenticated request without an Accept header is also a clean 401",
  plain.status === 401,
  `got ${plain.status}`,
);
check(
  "and it answers JSON, not an HTML error page",
  (plain.headers.get("content-type") ?? "").includes("json"),
);

/* ---------------------------------------------------------------------- */

console.log("\n-- who can see which child --");

const adminList = await call("/students", { token: admin });
const specialistList = await call("/students", { token: rana });
const momList = await call("/students", { token: mom });

check("the office sees every child", adminList.json.meta.total === 8);
check(
  "a specialist sees every child too (she covers for colleagues)",
  specialistList.json.meta.total === 8,
);
check("a parent sees only her own", momList.json.meta.total === 1);

const yousef = momList.json.data[0];
check("and it is her own child", yousef.name.startsWith("يوسف"));

const otherList = await call("/students", { token: other });
const layan = otherList.json.data[0];

const trespass = await call(`/students/${layan.id}`, { token: mom });
check("another family's child is not found, not forbidden", trespass.status === 404);

/* ---------------------------------------------------------------------- */

console.log("\n-- what a specialist writes for herself --");

const staffSessions = await call(
  `/sessions?student_id=${yousef.id}&report_status=published&per_page=50`,
  { token: rana },
);
const withNotes = staffSessions.json.data.find((s) => s.has_private_note);

check("a published session list comes back for staff", staffSessions.json.data.length > 0);
check(
  "the list flags which sessions carry private notes, without carrying the text",
  Boolean(withNotes) && staffSessions.json.data.every((s) => s.private_notes === undefined),
);

if (withNotes) {
  const asStaff = await call(`/sessions/${withNotes.id}`, { token: rana });
  const asParent = await call(`/sessions/${withNotes.id}`, { token: mom });

  check("the specialist reads her own private notes", Boolean(asStaff.json.data.private_notes));
  check(
    "the parent never sees them",
    asParent.status === 200 && asParent.json.data.private_notes === undefined,
  );
  check(
    "and the report itself still reaches her",
    Boolean(asParent.json?.data?.activities),
  );
}

const parentList = await call(`/sessions?student_id=${yousef.id}&per_page=100`, { token: mom });
check(
  "no private notes leak through the list endpoint either",
  parentList.json.data.every((s) => s.private_notes === undefined),
);

/* ---------------------------------------------------------------------- */

console.log("\n-- a draft is not a shy report --");

const drafts = await call("/sessions?unwritten=1&per_page=50", { token: admin });
check("the office can see what has not been written up", drafts.json.data.length > 0);

const draft = drafts.json.data.find((s) => s.student_id === yousef.id);

if (draft) {
  const parentSees = await call(`/sessions/${draft.id}`, { token: mom });
  check("a parent cannot open an unpublished session", parentSees.status === 404);

  const inParentList = parentList.json.data.some((s) => s.id === draft.id);
  check("nor does it appear in her timeline", !inParentList);
} else {
  console.log("  --   no draft for this child, skipping two checks");
}

const absent = parentList.json.data.find((s) => s.status === "absent");
check("but an absence IS shown to the family — silence reads as neglect", Boolean(absent));

/* ---------------------------------------------------------------------- */

console.log("\n-- publishing --");

// Her own unwritten sessions — the list shows everybody's, because a
// specialist covering for a colleague needs to see them.
const mine = await call(`/sessions?unwritten=1&specialist_id=${ranaId}&per_page=50`, {
  token: rana,
});
const target = mine.json.data[0];

if (target) {
  // Strip the report back to nothing, then try to send it.
  await call(`/sessions/${target.id}`, {
    method: "PUT",
    token: rana,
    body: { activities: "", home_plan: "" },
  });

  const empty = await call(`/sessions/${target.id}/publish`, { method: "POST", token: rana });
  check("an empty report cannot be sent", empty.status === 422);

  await call(`/sessions/${target.id}`, {
    method: "PUT",
    token: rana,
    body: { activities: "اشتغلنا على بطاقات الصور." },
  });

  const noPlan = await call(`/sessions/${target.id}/publish`, { method: "POST", token: rana });
  check(
    "nor one with nothing for the family to do at home",
    noPlan.status === 422,
    noPlan.json?.message ?? "",
  );

  await call(`/sessions/${target.id}`, {
    method: "PUT",
    token: rana,
    body: { home_plan: "كرّروا التمرين ٥ دقايق يومياً." },
  });

  const sent = await call(`/sessions/${target.id}/publish`, { method: "POST", token: rana });
  check("a complete report goes out", sent.status === 200);
  check("and it is stamped with the moment it went", Boolean(sent.json?.data?.published_at));

  const again = await call(`/sessions/${target.id}/publish`, { method: "POST", token: rana });
  check("it cannot be sent twice", again.status === 422);

  const rewrite = await call(`/sessions/${target.id}`, {
    method: "PUT",
    token: rana,
    body: { activities: "شيء مختلف تماماً." },
  });
  check("and it cannot be rewritten after the family has it", rewrite.status === 422);

  const correction = await call(`/sessions/${target.id}/addendum`, {
    method: "POST",
    token: rana,
    body: { body: "تصحيح: الجلسة كانت ٤٥ دقيقة وليس ٣٠." },
  });
  check("a correction is added underneath instead", correction.status === 200);
  check(
    "and the original text is still there",
    correction.json?.data?.activities === "اشتغلنا على بطاقات الصور.",
  );

  const deletion = await call(`/sessions/${target.id}`, { method: "DELETE", token: rana });
  check("a published report cannot be deleted", deletion.status === 422);
} else {
  console.log("  --   no unwritten session for this specialist, skipping publish checks");
}

/* ---------------------------------------------------------------------- */

console.log("\n-- who may write --");

const anySession = staffSessions.json.data[0];

const parentWrite = await call(`/sessions/${anySession.id}`, {
  method: "PUT",
  token: mom,
  body: { activities: "أنا كتبت هذا." },
});
check("a parent cannot write a report", parentWrite.status === 403);

const parentPublish = await call(`/sessions/${anySession.id}/publish`, {
  method: "POST",
  token: mom,
});
check("nor publish one", parentPublish.status === 403);

const wrongSpecialist = await call(`/sessions/${anySession.id}`, {
  method: "PUT",
  token: aya,
  body: { activities: "أنا مش أخصائية هذا الملف." },
});
check(
  "a specialist cannot write on a colleague's session",
  wrongSpecialist.status === 403,
);

const officeCan = await call(`/sessions/${anySession.id}/addendum`, {
  method: "POST",
  token: admin,
  body: { body: "مراجعة إدارية." },
});
check("but the director can — she is clinically responsible", officeCan.status === 200);

/* ---------------------------------------------------------------------- */

console.log("\n-- goals are measured, not described --");

const goals = await call(`/goals?student_id=${yousef.id}&per_page=50`, { token: rana });
check("the child has goals", goals.json.data.length > 0);

const goal = goals.json.data[0];
const curve = await call(`/goals/${goal.id}`, { token: rana });

check("a goal opens as a curve", curve.status === 200);
check(
  "which starts at the baseline, not at the first session",
  curve.json.data.baseline_point?.level === curve.json.data.goal.baseline,
);
check("with a point per session scored", curve.json.data.points.length > 0);
check(
  "every point is on the five-step scale",
  curve.json.data.points.every((p) => p.level >= 0 && p.level <= 4),
);
check(
  "no point claims more successes than attempts",
  curve.json.data.points.every((p) => p.trials === null || p.successes <= p.trials),
);

/*
 * The list and the curve have to agree about where the child is now.
 *
 * They did not: both called the newest rating "the last one by created_at",
 * and a whole session's goals are written in the same second — so the tie-break
 * was whatever the database felt like, and a goal reading 3 on its own screen
 * read 1 in the list beside it. Ratings now carry `measured_at`, copied off the
 * session, and everything orders by that.
 *
 * Checked across every goal rather than one, because the broken version was
 * right about a third of the time.
 */
console.log("\n-- the screens agree with each other --");

let agree = 0;
let disagree = 0;

for (const g of goals.json.data) {
  const c = await call(`/goals/${g.id}`, { token: rana });
  const listSays = g.trend?.latest ?? null;
  const curveSays = c.json.data.summary.latest ?? null;

  if (listSays === curveSays) agree++;
  else {
    disagree++;
    console.log(`       "${g.title}": list ${listSays}, curve ${curveSays}`);
  }
}

check(
  `every goal reads the same in the list as on its curve (${agree} checked)`,
  disagree === 0,
);

const ordered = await call(`/goals/${goal.id}`, { token: rana });
check(
  "and the curve's points are in date order",
  ordered.json.data.points.every(
    (p, i, all) => i === 0 || new Date(all[i - 1].date) <= new Date(p.date),
  ),
);

const parentCurve = await call(`/goals/${goal.id}`, { token: mom });
check("the family can read the curve too", parentCurve.status === 200);

const otherCurve = await call(`/goals/${goal.id}`, { token: other });
check("another family cannot", otherCurve.status === 404);

if (target) {
  const foreignGoal = await call(`/goals?student_id=${layan.id}&per_page=5`, { token: rana });

  if (foreignGoal.json.data.length) {
    const rateForeign = await call(`/sessions/${target.id}/ratings`, {
      method: "POST",
      token: rana,
      body: { ratings: [{ goal_id: foreignGoal.json.data[0].id, level: 3 }] },
    });
    check("a goal belonging to another child cannot be scored here", rateForeign.status === 422);
  }
}

const draftForRating = mine.json.data.find((s) => s.id !== target?.id);

if (draftForRating) {
  const badCount = await call(`/sessions/${draftForRating.id}/ratings`, {
    method: "POST",
    token: rana,
    body: { ratings: [{ goal_id: goal.id, level: 3, trials: 5, successes: 9 }] },
  });
  check("9 successes out of 5 attempts is refused", badCount.status === 422);

  const badLevel = await call(`/sessions/${draftForRating.id}/ratings`, {
    method: "POST",
    token: rana,
    body: { ratings: [{ goal_id: goal.id, level: 7 }] },
  });
  check("a level off the scale is refused", badLevel.status === 422);
}

/* ---------------------------------------------------------------------- */

console.log("\n-- read receipts --");

const unread = staffSessions.json.data.find((s) => s.report_status === "published");

const beforeStaff = await call(`/sessions/${unread.id}`, { token: rana });
const staffReads = beforeStaff.json.data.read_by?.length ?? 0;

await call(`/sessions/${unread.id}`, { token: rana });
const afterStaff = await call(`/sessions/${unread.id}`, { token: rana });

check(
  "a specialist opening a report is not a read receipt",
  (afterStaff.json.data.read_by?.length ?? 0) === staffReads,
);

await call(`/sessions/${unread.id}`, { token: mom });
const afterParent = await call(`/sessions/${unread.id}`, { token: rana });

check(
  "a parent opening it is",
  (afterParent.json.data.read_by?.length ?? 0) >= staffReads,
);
check(
  "and it names who read it",
  afterParent.json.data.read_by?.some((r) => r.name?.includes("سناء")),
);

/* ---------------------------------------------------------------------- */

console.log("\n-- the office --");

const staffOnly = await call("/staff", { token: rana });
check("a specialist cannot list accounts", staffOnly.status === 403);

const parentStaff = await call("/staff", { token: mom });
check("nor can a parent", parentStaff.status === 403);

const staffList = await call("/staff", { token: admin });
check("the director can", staffList.status === 200);

const mismatch = await call("/staff", {
  method: "POST",
  token: admin,
  body: {
    name: "تجربة",
    email: `t${Date.now()}@haya.test`,
    role: "specialist",
    specialty: null,
  },
});
check("a specialist without a specialty is refused", mismatch.status === 422);

const guardianWithSpecialty = await call("/staff", {
  method: "POST",
  token: admin,
  body: {
    name: "تجربة٢",
    email: `t2${Date.now()}@haya.test`,
    role: "guardian",
    specialty: "speech",
  },
});
check("a parent with a specialty is refused", guardianWithSpecialty.status === 422);

const created = await call("/staff", {
  method: "POST",
  token: admin,
  body: { name: "ولي أمر تجريبي", email: `p${Date.now()}@haya.test`, role: "guardian" },
});
check("a guardian account is created", created.status === 201);
check(
  "with a password handed back exactly once",
  Boolean(created.json?.meta?.generated_password),
);

const newId = created.json?.data?.id;

if (newId) {
  const off = await call(`/staff/${newId}`, {
    method: "PUT",
    token: admin,
    body: { is_active: false },
  });
  check("an account can be switched off", off.status === 200);
}

/* ---------------------------------------------------------------------- */

console.log("\n-- switching someone off takes effect now --");

const victim = await call("/staff", {
  method: "POST",
  token: admin,
  body: { name: "أخصائية مؤقتة", email: `v${Date.now()}@haya.test`, role: "guardian" },
});

const victimPassword = victim.json.meta.generated_password;
const victimToken = await login(victim.json.data.email, victimPassword);

check("the new account can sign in", Boolean(victimToken));

await call(`/staff/${victim.json.data.id}`, {
  method: "PUT",
  token: admin,
  body: { is_active: false },
});

const afterOff = await call("/dashboard", { token: victimToken });
check("and its live token stops working the moment it is switched off", afterOff.status === 401);

/* ---------------------------------------------------------------------- */

console.log("\n-- enrolments --");

const enrollments = await call("/enrollments", { token: admin });
check("programmes list", enrollments.status === 200);
check("and the unassigned queue is counted", enrollments.json.meta.unassigned >= 1);

const clash = await call("/enrollments", {
  method: "POST",
  token: admin,
  body: {
    student_id: yousef.id,
    specialty: "speech",
    started_at: "2026-08-01",
  },
});
check("a second live programme of the same kind is refused", clash.status === 422);

const badSpecialist = await call("/enrollments", {
  method: "POST",
  token: admin,
  body: {
    student_id: layan.id,
    specialty: "occupational",
    specialist_id: (await call("/staff?role=specialist&specialty=speech", { token: admin }))
      .json.data[0].id,
    started_at: "2026-08-01",
  },
});
check(
  "a speech therapist cannot be put on an occupational case",
  badSpecialist.status === 422,
);

/* ---------------------------------------------------------------------- */

console.log("\n-- messages --");

const thread = await call(`/students/${yousef.id}/messages`, { token: mom });
check("a parent reads the thread about her child", thread.status === 200);
check("which has something in it", thread.json.data.length > 0);

const foreignThread = await call(`/students/${layan.id}/messages`, { token: mom });
check("but not another family's thread", foreignThread.status === 404);

const posted = await call(`/students/${yousef.id}/messages`, {
  method: "POST",
  token: mom,
  body: { body: "سؤال من الاختبار الآلي." },
});
check("she can ask a question", posted.status === 201);

const foreignSession = (await call(`/sessions?student_id=${layan.id}&per_page=1`, { token: admin }))
  .json.data[0];

if (foreignSession) {
  const misattached = await call(`/students/${yousef.id}/messages`, {
    method: "POST",
    token: mom,
    body: { body: "محاولة ربط بجلسة طفل آخر.", therapy_session_id: foreignSession.id },
  });
  check("a question cannot be pinned to another child's session", misattached.status === 422);
}

/* ---------------------------------------------------------------------- */

console.log("\n-- the first screen --");

for (const [who, token, kind] of [
  ["the director", admin, "admin"],
  ["a specialist", rana, "specialist"],
  ["a parent", mom, "guardian"],
]) {
  const dash = await call("/dashboard", { token });
  check(`${who} gets her own dashboard`, dash.json?.data?.kind === kind);
}

const adminDash = (await call("/dashboard", { token: admin })).json.data;
check("the office is told what has not been written up", adminDash.stats.unwritten >= 0);
check("and which programmes have nobody on them", adminDash.stats.unassigned >= 1);
check(
  "and which families have gone quiet",
  Array.isArray(adminDash.silent_families) && adminDash.silent_families.length >= 1,
);

const momDash = (await call("/dashboard", { token: mom })).json.data;
check("a parent's screen leads with her children", momDash.children.length === 1);
check(
  "each carrying an attendance figure",
  momDash.children[0].summary.attendance.rate !== undefined,
);
check(
  "and a count of what she has not opened",
  typeof momDash.children[0].unread_reports === "number",
);

/* ---------------------------------------------------------------------- */

console.log(`\n${pass} passed, ${fail} failed\n`);

if (fail) {
  console.log("failing:");
  failures.forEach((f) => console.log(`  - ${f}`));
  process.exit(1);
}
