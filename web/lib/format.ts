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

const MONTHS = [
  "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
  "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
];

const DAYS = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];

function parse(value: string | null | undefined): Date | null {
  if (!value) return null;
  const d = new Date(value.replace(" ", "T"));
  return Number.isNaN(d.getTime()) ? null : d;
}

/** 23 أغسطس 2026 */
export function date(value: string | null | undefined): string {
  const d = parse(value);
  if (!d) return "—";
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/** الأحد 23 أغسطس — for a diary, where the weekday is what is scanned for. */
export function dayDate(value: string | null | undefined): string {
  const d = parse(value);
  if (!d) return "—";
  return `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

/** 23 أغسطس، 10:30 */
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

  const phrase = (n: number, one: string, two: string, few: string, many: string) => {
    if (n === 1) return one;
    if (n === 2) return two;
    if (n <= 10) return `${n} ${few}`;
    return `${n} ${many}`;
  };

  let unit: string;

  if (minutes < 1) return "الآن";
  else if (minutes < 60) unit = phrase(minutes, "دقيقة", "دقيقتين", "دقائق", "دقيقة");
  else if (minutes < 1440) {
    const hours = Math.round(minutes / 60);
    unit = phrase(hours, "ساعة", "ساعتين", "ساعات", "ساعة");
  } else if (minutes < 43200) {
    const days = Math.round(minutes / 1440);
    unit = phrase(days, "يوم", "يومين", "أيام", "يوماً");
  } else {
    const months = Math.round(minutes / 43200);
    unit = phrase(months, "شهر", "شهرين", "شهور", "شهراً");
  }

  return past ? `قبل ${unit}` : `بعد ${unit}`;
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
