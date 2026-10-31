/**
 * Drives the academy's monthly subscription end to end.
 *
 *   node tools/billing-smoke-test.mjs                     # local :8020
 *
 * It WRITES: it prices a child, issues a month, takes money and takes it back.
 * Run it against the development database, never against the live academy.
 *
 * Issuing a month is one click that creates a debt against every family in
 * the building, so most of what is tested here is the second click and the
 * edges around it: a month issued twice, a child with no agreed fee, a
 * payment larger than what is owed, and whether a parent can read another
 * family's account by changing the id.
 */

const API = process.argv[2] ?? process.env.HAYA_API ?? 'http://127.0.0.1:8020/api';

let pass = 0;
let fail = 0;

function check(label, ok, detail = '') {
  if (ok) {
    pass++;
    console.log(`  ok   ${label}`);
  } else {
    fail++;
    console.log(`  FAIL ${label} ${detail}`);
  }
}

async function call(path, { method = 'GET', body, token } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    /* not json */
  }
  return { status: res.status, json, data: json?.data, text: text.slice(0, 300) };
}

const login = async (email, password = 'password') =>
  (await call('/auth/login', { method: 'POST', body: { email, password } })).json?.token;

const near = (a, b) => Math.abs(Number(a) - Number(b)) < 0.005;

/* ------------------------------------------------------------------ setup */

const admin = await login('admin@haya.test');
if (!admin) {
  console.error('admin login failed — is the dev database seeded?');
  process.exit(1);
}

const students = (await call('/students?per_page=5', { token: admin })).json?.data ?? [];
if (students.length < 2) {
  console.error('needs at least two children on file');
  process.exit(1);
}

const [priced, unpriced] = students;

// A month far enough back that the academy is not working on it.
const when = new Date();
when.setMonth(when.getMonth() - 8);
const period = `${when.getFullYear()}-${String(when.getMonth() + 1).padStart(2, '0')}-01`;

/*
 * Through the dedicated endpoint, which is how both screens price a child:
 * the billing screen has only a name and an id in hand, and a PUT to
 * /students would have to send the whole file back to pass its validation.
 */
const setFee = (student, fee) =>
  call(`/students/${student.id}/fee`, {
    method: 'PUT',
    token: admin,
    body: { monthly_fee: fee },
  });

let r = await setFee(priced, 400);
check('a monthly fee can be set', r.status === 200 && near(r.data?.monthly_fee, 400), r.text);

r = await setFee(unpriced, null);
check('and cleared', r.status === 200 && !r.data?.monthly_fee, r.text);

// Zero is not a fee. It would read as "settled" on every screen and hide the
// child from the one list that would have caught them.
r = await setFee(unpriced, 0);
check('a fee of zero is stored as no fee at all', r.status === 200 && !r.data?.monthly_fee, r.text);

// The whole-file route still accepts it, because the child's own form has the
// field too — and the two must not disagree about what empty means.
r = await call(`/students/${priced.id}`, {
  method: 'PUT',
  token: admin,
  body: {
    name: priced.name,
    birth_date: priced.birth_date,
    gender: priced.gender,
    enrolled_at: priced.enrolled_at,
    status: 'active',
    monthly_fee: 400,
  },
});
check("the child's own form sets the same field", r.status === 200 && near(r.data?.monthly_fee, 400), r.text);

console.log(`\n${priced.name} at 400/month · ${unpriced.name} unpriced · ${period}\n`);

/* ------------------------------------------------------------ issuing it */

console.log('issuing the month');

/*
 * Where this child stood before the test touched anything.
 *
 * The academy's development database is also somebody's sandbox, so the child
 * picked here may already carry months from a run that was interrupted or from
 * a walk through the screens. Asserting an absolute balance would make this
 * test a report on the state of that database; asserting the change this run
 * caused is a test of the code.
 */
const opening = (await call(`/billing/students/${priced.id}`, { token: admin })).data?.balance;

r = await call('/billing/summary?period=' + period, { token: admin });
check('the summary says what the button would do', r.status === 200 && r.data?.pending > 0, JSON.stringify(r.data));
check(
  'and names the children it would skip',
  (r.data?.unpriced_students ?? []).some((s) => s.name === unpriced.name),
  JSON.stringify(r.data?.unpriced_students),
);

const willCharge = r.data.pending;
const willTotal = r.data.pending_total;

r = await call('/billing/issue', { method: 'POST', token: admin, body: { period } });
check('issued', r.status === 201, r.text);
check('somebody was charged', r.data?.created >= 1, JSON.stringify(r.data));
// The screen showed a count and a total before the button was pressed. If they
// are not what actually happened, the office was asked to approve a figure
// that was never real.
check(
  'exactly as many as the summary promised',
  r.data?.created === willCharge && near(r.data?.total, willTotal),
  `promised ${willCharge}/${willTotal}, got ${r.data?.created}/${r.data?.total}`,
);
check(
  'and the unpriced child was skipped by name',
  (r.data?.skipped ?? []).some((s) => s.student === unpriced.name && s.why.includes('بلا اشتراك')),
  JSON.stringify(r.data?.skipped),
);

const mine = ((await call(`/billing/invoices?student_id=${priced.id}&period=${period}`, { token: admin })).json?.data ?? [])[0];
check('the invoice is for the agreed fee', near(mine?.total, 400), JSON.stringify(mine));
check('due on the first of the month', mine?.due_on?.startsWith(period.slice(0, 7)), mine?.due_on);
check('and labelled by its month', Boolean(mine?.period_label), mine?.period_label);

/* ------------------------------------------------- the second click */

console.log('\nthe second click');

const before = (await call(`/billing/invoices?period=${period}`, { token: admin })).json?.meta?.total;

r = await call('/billing/issue', { method: 'POST', token: admin, body: { period } });
check('creates nothing', r.data?.created === 0, JSON.stringify(r.data));
check('and names who was already billed', (r.data?.skipped ?? []).some((s) => s.why.includes('مفوتر')), JSON.stringify(r.data?.skipped));

const after = (await call(`/billing/invoices?period=${period}`, { token: admin })).json?.meta?.total;
check('the month still has the same number of invoices', before === after, `${before} → ${after}`);

r = await call('/billing/summary?period=' + period, { token: admin });
check('and the screen stops offering to issue it', r.data?.pending === 0, JSON.stringify(r.data));

/* ------------------------------------------------- due today is not late */

/*
 * `status` is derived and stored, and «متأخرة» is the one state that arrives
 * by the calendar. It was wrong by a day: due_on is a date cast, so an invoice
 * due today read as past-due from one minute after midnight, and every invoice
 * issued on the first of the month was born late.
 */
const today = new Date().toLocaleDateString('en-CA');

r = await call(`/billing/invoices/${mine.id}`, {
  method: 'PUT',
  token: admin,
  body: { amount: 400, due_on: today },
});
check('an invoice due today is not overdue', r.data?.status === 'unpaid', r.data?.status);

// Reading the list runs the overdue sweep on the way in — there is no cron on
// this host — and the sweep must not catch today either.
let reread = ((await call(`/billing/invoices?student_id=${priced.id}&period=${period}`, { token: admin })).json?.data ?? [])[0];
check('and a sweep on the way in leaves it alone', reread?.status === 'unpaid', reread?.status);

// Back to where it was: the first of a month eight months ago.
r = await call(`/billing/invoices/${mine.id}`, {
  method: 'PUT',
  token: admin,
  body: { amount: 400, due_on: period },
});
check('one due eight months ago is overdue', r.data?.status === 'overdue', r.data?.status);

/* ------------------------------------------------------------- paying it */

console.log('\npaying');

r = await call(`/billing/invoices/${mine.id}/pay`, {
  method: 'POST',
  token: admin,
  body: { amount: 150, paid_on: today, method: 'cash' },
});
check('a part payment', r.status === 201, r.text);
check('leaves it partial', r.json?.invoice?.status === 'partial', r.json?.invoice?.status);
check('with a receipt number', Boolean(r.data?.receipt_no), r.data?.receipt_no);

const paymentId = r.data?.id;

r = await call(`/billing/invoices/${mine.id}/pay`, {
  method: 'POST',
  token: admin,
  body: { amount: 9999, paid_on: today, method: 'cash' },
});
check('more than is owed is refused', r.status === 422, `${r.status} ${r.text}`);

r = await call(`/billing/invoices/${mine.id}/pay`, {
  method: 'POST',
  token: admin,
  body: { amount: 250, paid_on: today, method: 'transfer' },
});
check('the rest settles it', r.json?.invoice?.status === 'paid', r.json?.invoice?.status);

/* ------------------------------------------------------- the family's view */

console.log("\nthe family's account");

r = await call(`/billing/students/${priced.id}`, { token: admin });
check('readable', r.status === 200, r.text);
check(
  'one month more on the account, and nothing left owing on it',
  near(r.data?.balance?.billed, opening.billed + 400) &&
    near(r.data?.balance?.due, opening.due) &&
    r.data?.balance?.months === opening.months + 1,
  `${JSON.stringify(opening)} → ${JSON.stringify(r.data?.balance)}`,
);

const parent = await login('sanaa@haya.test');
if (parent) {
  const own = (await call('/students', { token: parent })).json?.data ?? [];
  const mineAsParent = own[0];

  r = await call(`/billing/students/${mineAsParent.id}`, { token: parent });
  check('a parent can read their own child', r.status === 200, `${r.status}`);

  const notMine = students.find((s) => !own.some((o) => o.id === s.id));
  if (notMine) {
    r = await call(`/billing/students/${notMine.id}`, { token: parent });
    check("and not another family's", r.status === 404, `${r.status}`);
  }

  r = await call('/billing/invoices', { token: parent });
  check('nor the academy-wide list', r.status === 403, `${r.status}`);
}

const specialist = await login('rana@haya.test');
if (specialist) {
  r = await call('/billing/invoices', { token: specialist });
  check('a specialist cannot see the money at all', r.status === 403, `${r.status}`);

  /*
   * The one money route that is not behind role:admin, because a parent needs
   * it. Its gate is Student::readableBy — which passes every member of staff
   * — so without an explicit check a therapist could read any family's
   * balance by opening the child she treats.
   */
  r = await call(`/billing/students/${priced.id}`, { token: specialist });
  check("nor one child's account through the parent's own route", r.status === 404, `${r.status}`);

  r = await call(`/students/${priced.id}/fee`, {
    method: 'PUT',
    token: specialist,
    body: { monthly_fee: 1 },
  });
  check('nor set what a family pays', r.status === 403, `${r.status}`);
}

if (parent) {
  r = await call(`/students/${(await call('/students', { token: parent })).json.data[0].id}/fee`, {
    method: 'PUT',
    token: parent,
    body: { monthly_fee: 1 },
  });
  check('a parent cannot price their own child', r.status === 403, `${r.status}`);
}

/* ---------------------------------------------------------- undoing it */

console.log('\nundoing');

r = await call(`/billing/payments/${paymentId}`, { method: 'DELETE', token: admin });
check('a payment can be removed', r.status === 200, r.text);
check('and the invoice reopens', r.json?.invoice?.status !== 'paid', r.json?.invoice?.status);

r = await call(`/billing/invoices/${mine.id}`, { method: 'DELETE', token: admin });
check('an invoice with payments is not deleted', r.status === 422, `${r.status} ${r.text}`);

for (const p of (await call(`/billing/invoices/${mine.id}`, { token: admin })).data?.payments ?? []) {
  await call(`/billing/payments/${p.id}`, { method: 'DELETE', token: admin });
}
r = await call(`/billing/invoices/${mine.id}`, { method: 'DELETE', token: admin });
check('once they are gone it is', r.status === 200, r.text);

/* ------------------------------------------------------------------ clean */

await setFee(priced, null);

console.log(`\n  ${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
