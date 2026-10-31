/**
 * Formatting and wording, in one place.
 *
 * The labels matter more here than in most systems. Everything below is read
 * by a worried parent on a phone, and the difference between "الحالة: غياب"
 * and "ما إجا ع الجلسة" is the difference between a case file and a letter.
 * The keys stay in English and stay stable — they are what the API and the
 * filters match on — so the wording can be argued about without touching any
 * logic.
 */

export function number(value: string | number | null | undefined): string {
  return Number(value ?? 0).toLocaleString("en-US");
}

export function percent(value: number | null | undefined): string {
  if (value === null || value === undefined) return "—";
  return `${Math.round(value)}%`;
}

/**
 * «١,٢٠٠ ₪».
 *
 * Laravel sends a decimal column as a string ("400.00") on purpose — a float
 * is the wrong type for money — so this takes either and never does
 * arithmetic on what it is given.
 *
 * An unset figure is "—", never "0 ₪". A child whose fee has not been agreed
 * and a child who owes nothing are different facts, and printing a zero for
 * the first is how the second gets assumed.
 *
 * The academy charges in shekels and only in shekels; there is no currency
 * column, and inventing one for a single-currency academy would be a column
 * that is wrong the first time anybody fills it in.
 */
export function money(
  value: string | number | null | undefined,
  { zero = "—" }: { zero?: string } = {},
): string {
  if (value === null || value === undefined || value === "") return zero;

  const figure = Number(value);
  if (!Number.isFinite(figure)) return zero;

  // Halves show when there are halves — 400 rather than 400.00, and 12.50
  // rather than 13.
  const fractions = Number.isInteger(figure) ? 0 : 2;

  return `${figure.toLocaleString("en-US", {
    minimumFractionDigits: fractions,
    maximumFractionDigits: 2,
  })} ₪`;
}

/* -------------------------------------------------------------------------
 * The money
 * ---------------------------------------------------------------------- */

export const INVOICE_LABELS: Record<string, string> = {
  unpaid: "ما تسدّدت",
  partial: "مسدّدة جزئياً",
  paid: "مسدّدة",
  overdue: "متأخرة",
};

/**
 * «متأخرة» is the only one that wears red.
 *
 * An unpaid invoice for the current month is not a problem — it is the normal
 * state of a bill issued three days ago. Colouring it the same as a family
 * three months behind is how a screen stops being read.
 */
export const INVOICE_TONES: Record<string, string> = {
  unpaid: "bg-line/60 text-ink",
  partial: "bg-warn-soft text-warn",
  paid: "bg-good-soft text-good",
  overdue: "bg-bad-soft text-bad",
};

export const METHOD_LABELS: Record<string, string> = {
  cash: "نقداً",
  transfer: "حوالة بنكية",
  cheque: "شيك",
};

/**
 * The months as the Levant writes them — «تشرين الأول», not «أكتوبر».
 *
 * Both sets are understood in Palestine, but only one can be on a screen at a
 * time: an invoice row that reads «تشرين الأول 2026 · استحقاق 1 أكتوبر 2026»
 * looks like two different dates, and a parent counting her months has to stop
 * and translate. The API names the billed month in Levantine (see
 * Invoice::monthName) because that is what the academy writes on paper, so the
 * dashboard follows it rather than the other way round.
 */
const MONTHS = [
  "كانون الثاني", "شباط", "آذار", "نيسان", "أيار", "حزيران",
  "تموز", "آب", "أيلول", "تشرين الأول", "تشرين الثاني", "كانون الأول",
];

const DAYS = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];

function parse(value: string | null | undefined): Date | null {
  if (!value) return null;
  const d = new Date(value.replace(" ", "T"));
  return Number.isNaN(d.getTime()) ? null : d;
}

/** 23 آب 2026 */
export function date(value: string | null | undefined): string {
  const d = parse(value);
  if (!d) return "—";
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/** الأحد 23 آب — for a diary, where the weekday is what is scanned for. */
export function dayDate(value: string | null | undefined): string {
  const d = parse(value);
  if (!d) return "—";
  return `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

/**
 * «تشرين الأول 2026» from "2026-10" — the month a bill is for.
 *
 * The API labels an invoice's own period the same way (Invoice::monthName),
 * so a row and the picker above it name the month with the same words. This
 * exists because a native `<input type="month">` labels itself in the
 * browser's locale, not the page's: on an office machine set to English it
 * reads "October 2026" beside «فواتير تشرين الأول 2026», which is two names
 * for one month on one screen.
 */
export function monthLabel(ym: string): string {
  const [year, month] = ym.split("-").map(Number);
  const name = MONTHS[(month ?? 0) - 1];
  return name ? `${name} ${year}` : ym;
}

/** 23 آب — a point on an axis, where the year is the chart's and not the tick's. */
export function monthDay(value: string | null | undefined): string {
  const d = parse(value);
  if (!d) return "—";
  return `${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

/** الأحد 23 آب 2026 — the whole thing, for the one line that says what today is. */
export function fullDate(value: string | null | undefined): string {
  const d = parse(value);
  if (!d) return "—";
  return `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/** 23 آب، 10:30 */
export function dateTime(value: string | null | undefined): string {
  const d = parse(value);
  if (!d) return "—";
  return `${d.getDate()} ${MONTHS[d.getMonth()]}، ${time(value)}`;
}

/** 10:30 */
export function time(value: string | null | undefined): string {
  const d = parse(value);
  if (!d) return "—";
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/**
 * "قبل ٣ أيام" / "بعد ساعتين".
 *
 * Arabic counts in three forms — one, two, and many — and getting it wrong
 * ("قبل 2 يوم") is the kind of thing that makes software read as foreign.
 */
export function relative(value: string | null | undefined): string {
  const d = parse(value);
  if (!d) return "—";

  const diff = d.getTime() - Date.now();
  const past = diff < 0;
  const minutes = Math.round(Math.abs(diff) / 60000);

  let unit: string;

  if (minutes < 1) return "الآن";
  else if (minutes < 60) unit = plural(minutes, "دقيقة", "دقيقتين", "دقائق", "دقيقة");
  else if (minutes < 1440) {
    const hours = Math.round(minutes / 60);
    unit = plural(hours, "ساعة", "ساعتين", "ساعات", "ساعة");
  } else if (minutes < 43200) {
    const days = Math.round(minutes / 1440);
    unit = plural(days, "يوم", "يومين", "أيام", "يوماً");
  } else {
    const months = Math.round(minutes / 43200);
    unit = plural(months, "شهر", "شهرين", "شهور", "شهراً");
  }

  return past ? `قبل ${unit}` : `بعد ${unit}`;
}

/**
 * Arabic counts in four shapes, not two.
 *
 * One, two, a few (3–10, which takes the plural), and many (11 and up, which
 * goes back to the singular). "٦ طفل" and "٢ أطفال" are both wrong, and both
 * are what a template literal produces — which is why this is a function and
 * not a suffix somebody remembers to add.
 *
 * `one` and `two` carry no numeral, because Arabic does not put one there.
 */
export function plural(n: number, one: string, two: string, few: string, many: string): string {
  if (n === 1) return one;
  if (n === 2) return two;
  if (n <= 10) return `${n} ${few}`;
  return `${n} ${many}`;
}

/** «طفل واحد» · «طفلين» · «٦ أطفال» · «١٥ طفل» */
export function childCount(n: number): string {
  return plural(n, "طفل واحد", "طفلين", "أطفال", "طفل");
}

/** «فاتورة واحدة» · «فاتورتين» · «٤ فواتير» · «١٢ فاتورة» */
export function invoiceCount(n: number): string {
  return plural(n, "فاتورة واحدة", "فاتورتين", "فواتير", "فاتورة");
}


/* -------------------------------------------------------------------------
 * The prompt scale
 * ---------------------------------------------------------------------- */

/**
 * The five steps, worded for whoever is reading them.
 *
 * A specialist scoring a goal and a mother reading the score need the same
 * five buckets to mean the same five things — so there is one set of words,
 * not a clinical set and a friendly set that drift apart.
 */
export const LEVEL_LABELS: Record<number, string> = {
  4: "مستقل",
  3: "تلميح لفظي",
  2: "مساعدة جزئية",
  1: "مساعدة كاملة",
  0: "رفض / ما استجاب",
};

/** What each step means, so two specialists score the same child the same. */
export const LEVEL_HINTS: Record<number, string> = {
  4: "عملها لحاله بدون أي تذكير.",
  3: "عملها لحاله بعد ما ذكّرناه بالكلام أو بالإشارة.",
  2: "بدأ لحاله واحتاج مساعدة بالنص، أو لمسة توجيه.",
  1: "عملناها معه يداً بيد من أولها لآخرها.",
  0: "ما قبل يجرّب، أو ما استجاب إطلاقاً.",
};

/** The validated ordinal ramp — see globals.css for what was measured. */
export function levelColor(level: number): string {
  return `var(--viz-level-${Math.max(0, Math.min(4, level))})`;
}

/**
 * The text colour to put ON a level swatch.
 *
 * The ramp's two lightest steps take dark ink; the rest take white. Computed
 * from the step index rather than eyeballed per component, so a swatch is
 * never white-on-pale anywhere in the app.
 */
export function levelInk(level: number): string {
  return level <= 1 ? "#04302b" : "#ffffff";
}

/* -------------------------------------------------------------------------
 * Session state
 * ---------------------------------------------------------------------- */

export const SESSION_LABELS: Record<string, string> = {
  scheduled: "مجدولة",
  held: "تمّت",
  absent: "ما إجا",
  excused: "غياب بعذر",
  cancelled: "ملغية",
};

export const SESSION_TONES: Record<string, string> = {
  scheduled: "bg-line/60 text-ink",
  held: "bg-good-soft text-good",
  absent: "bg-bad-soft text-bad",
  excused: "bg-warn-soft text-warn",
  cancelled: "bg-line/50 text-muted",
};

export const REPORT_LABELS: Record<string, string> = {
  draft: "مسوّدة",
  published: "وصل الأهل",
};

export const REPORT_TONES: Record<string, string> = {
  draft: "bg-warn-soft text-warn",
  published: "bg-good-soft text-good",
};

export const MOOD_LABELS: Record<string, string> = {
  calm: "هادئ",
  happy: "مبسوط",
  tired: "تعبان",
  agitated: "متوتّر",
  crying: "بيبكي",
  resistant: "رافض",
};

export const MOOD_FACES: Record<string, string> = {
  calm: "😌",
  happy: "😄",
  tired: "😪",
  agitated: "😣",
  crying: "😢",
  resistant: "😤",
};

export const SPECIALTY_LABELS: Record<string, string> = {
  speech: "النطق واللغة",
  occupational: "العلاج الوظيفي",
  behavioral: "تعديل السلوك",
  special_ed: "التربية الخاصة",
};

export const SPECIALTY_FULL: Record<string, string> = {
  speech: "النطق واللغة والتخاطب",
  occupational: "العلاج الوظيفي والتكامل الحسي",
  behavioral: "تعديل السلوك والتوحد",
  special_ed: "التربية الخاصة وصعوبات التعلّم",
};

export const GOAL_LABELS: Record<string, string> = {
  active: "شغّال",
  achieved: "تحقّق",
  paused: "موقوف",
  dropped: "أُلغي",
};

export const GOAL_TONES: Record<string, string> = {
  active: "bg-brand-soft text-brand",
  achieved: "bg-good-soft text-good",
  paused: "bg-warn-soft text-warn",
  dropped: "bg-line/50 text-muted",
};

export const STUDENT_LABELS: Record<string, string> = {
  active: "مستمرّ",
  paused: "متوقّف مؤقتاً",
  graduated: "تخرّج",
  withdrawn: "انسحب",
};

export const RELATION_LABELS: Record<string, string> = {
  father: "الأب",
  mother: "الأم",
  grandparent: "جد/جدة",
  sibling: "أخ/أخت",
  guardian: "وصي",
};

export const TREND_LABELS: Record<string, string> = {
  improving: "متحسّن",
  steady: "ثابت",
  declining: "متراجع",
};

export const TREND_TONES: Record<string, string> = {
  improving: "bg-good-soft text-good",
  steady: "bg-line/60 text-muted",
  declining: "bg-bad-soft text-bad",
};

export const ROLE_LABELS: Record<string, string> = {
  admin: "الإدارة",
  specialist: "أخصائية",
  guardian: "ولي أمر",
};
