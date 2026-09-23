/**
 * The one place that talks to the Laravel API.
 *
 * Every call goes through `api()`: it attaches the bearer token, turns a 401
 * into a clean sign-out rather than a screen full of empty state, and throws
 * an `ApiError` carrying the server's Arabic message — so a form can show the
 * real reason a save was refused ("اكتب شو بدكم من الأهل بالبيت") instead of
 * "something went wrong".
 */

export const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ?? "http://127.0.0.1:8020/api";

const TOKEN_KEY = "haya.token";

export class ApiError extends Error {
  status: number;
  /** Laravel's field-level validation errors, when there are any. */
  errors: Record<string, string[]>;

  constructor(status: number, message: string, errors: Record<string, string[]> = {}) {
    super(message);
    this.status = status;
    this.errors = errors;
  }

  /** The first message for a field — what goes under the input. */
  for(field: string): string | undefined {
    return this.errors[field]?.[0];
  }
}

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string | null): void {
  if (typeof window === "undefined") return;
  if (token) window.localStorage.setItem(TOKEN_KEY, token);
  else window.localStorage.removeItem(TOKEN_KEY);
}

type Options = {
  method?: string;
  body?: unknown;
  /** Query parameters; undefined and empty values are dropped. */
  query?: Record<string, string | number | boolean | undefined | null>;
};

function url(path: string): URL {
  return new URL(path.startsWith("/") ? `${API_BASE}${path}` : `${API_BASE}/${path}`);
}

export async function api<T = unknown>(path: string, options: Options = {}): Promise<T> {
  const { method = "GET", body, query } = options;

  const target = url(path);

  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined && value !== null && value !== "") {
      target.searchParams.set(key, String(value));
    }
  }

  const token = getToken();

  let response: Response;

  try {
    response = await fetch(target, {
      method,
      headers: {
        Accept: "application/json",
        ...(body ? { "Content-Type": "application/json" } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    // A dead network and a dead server look the same from here, and the
    // distinction does not change what the user should do about it.
    throw new ApiError(0, "تعذّر الوصول إلى الخادم. تحقّق من الاتصال.");
  }

  return unwrap<T>(response);
}

/**
 * File upload — a session photo or clip.
 *
 * Separate from `api()` because the body is FormData: setting Content-Type by
 * hand on a multipart request omits the boundary and the server sees an empty
 * body, so the header is deliberately left for the browser to write.
 */
export async function upload<T = unknown>(path: string, form: FormData): Promise<T> {
  const token = getToken();

  let response: Response;

  try {
    response = await fetch(url(path), {
      method: "POST",
      headers: {
        Accept: "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: form,
    });
  } catch {
    throw new ApiError(0, "تعذّر رفع الملف. تحقّق من الاتصال.");
  }

  return unwrap<T>(response);
}

/**
 * Fetch a session attachment and hand back a blob URL for `<img>`/`<video>`.
 *
 * A browser sets no headers on an `<img src>`, so the obvious shortcut is to
 * put the token in the query string — and that is exactly what must not
 * happen: query strings land in access logs, in `Referer`, and in browser
 * history, and this one would be a bearer token that opens every child's file
 * in the building. So the bytes are fetched with a proper Authorization header
 * and wrapped in an object URL instead.
 *
 * The caller owns the URL and must `URL.revokeObjectURL` it on unmount —
 * `useAttachment` in components/ui.tsx does.
 */
export async function fetchAttachment(id: number): Promise<string> {
  const token = getToken();

  const response = await fetch(url(`/attachments/${id}`), {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });

  if (!response.ok) {
    throw new ApiError(response.status, "تعذّر تحميل المرفق.");
  }

  return URL.createObjectURL(await response.blob());
}

async function unwrap<T>(response: Response): Promise<T> {
  if (response.status === 401) {
    setToken(null);
    if (typeof window !== "undefined" && !window.location.pathname.endsWith("/login/")) {
      window.location.href = `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/login/`;
    }
    throw new ApiError(401, "انتهت الجلسة.");
  }

  const text = await response.text();
  let payload: unknown = null;

  try {
    payload = text ? JSON.parse(text) : null;
  } catch {
    /* a non-JSON body from a proxy or PHP fatal — handled below */
  }

  if (!response.ok) {
    const data = (payload ?? {}) as { message?: string; errors?: Record<string, string[]> };

    throw new ApiError(
      response.status,
      data.message ?? "تعذّر إتمام العملية.",
      data.errors ?? {},
    );
  }

  return payload as T;
}

/**
 * The counts every list endpoint reports alongside its rows.
 *
 * `from`/`to` are the 1-based positions of the first and last row *on this
 * page* — the numbers a pager shows — and are null when the page is empty.
 */
export type PageMeta = {
  total: number;
  per_page: number;
  current_page: number;
  last_page: number;
  from: number | null;
  to: number | null;
};

/** The shape every list endpoint answers with. */
export type Page<T> = {
  data: T[];
  meta: PageMeta;
};
