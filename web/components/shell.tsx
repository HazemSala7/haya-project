"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import type { NavCounts, Role } from "@/lib/types";

/* -------------------------------------------------------------------------
 * Icons
 *
 * Drawn inline rather than pulled from a library. There are seven of them and
 * the app already hand-draws its charts — a 300KB icon package to put seven
 * glyphs in a sidebar is a bad trade for a page a mother opens on a phone.
 *
 * They also carry real weight here: collapsed, the icon is the only thing
 * left of a menu item, so each one has to be recognisable on its own.
 * ---------------------------------------------------------------------- */

type IconProps = { className?: string };

const stroke = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.7,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

function Icon({ children, className = "size-5" }: IconProps & { children: React.ReactNode }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden {...stroke}>
      {children}
    </svg>
  );
}

const ICONS: Record<string, (p: IconProps) => React.ReactElement> = {
  home: (p) => (
    <Icon {...p}>
      <path d="M3 10.5 12 3l9 7.5" />
      <path d="M5.5 9.5V20h13V9.5" />
      <path d="M9.5 20v-5.5h5V20" />
    </Icon>
  ),
  sessions: (p) => (
    <Icon {...p}>
      <rect x="3.5" y="4.5" width="17" height="16" rx="2.5" />
      <path d="M3.5 9.5h17M8 3v3M16 3v3" />
      <path d="m8.5 14 2.2 2.2 4.3-4.3" />
    </Icon>
  ),
  children: (p) => (
    <Icon {...p}>
      <circle cx="9" cy="8" r="3.2" />
      <path d="M3.5 20c0-3.3 2.5-5.5 5.5-5.5s5.5 2.2 5.5 5.5" />
      <path d="M16.5 5.6a3.2 3.2 0 0 1 0 5.6M17.5 14.9c1.9.6 3.2 2.5 3.2 5.1" />
    </Icon>
  ),
  analytics: (p) => (
    <Icon {...p}>
      <path d="M4 20V4M4 20h16" />
      <path d="M8 20v-6M12 20v-10M16 20v-4M20 20v-8" />
    </Icon>
  ),
  reports: (p) => (
    <Icon {...p}>
      <path d="M6 3.5h8L18.5 8v12.5h-12.5z" />
      <path d="M13.5 3.5V8h5" />
      <path d="M9 13h6M9 16.5h4" />
    </Icon>
  ),
  messages: (p) => (
    <Icon {...p}>
      <path d="M20.5 12c0 4-3.8 7-8.5 7a10 10 0 0 1-2.6-.34L4.5 20.5l1.2-3.5A6.7 6.7 0 0 1 3.5 12c0-4 3.8-7 8.5-7s8.5 3 8.5 7Z" />
      <path d="M8.8 11.5h.01M12 11.5h.01M15.2 11.5h.01" strokeWidth={2.2} />
    </Icon>
  ),
  accounts: (p) => (
    <Icon {...p}>
      <circle cx="12" cy="8" r="3.4" />
      <path d="M5 20c0-3.6 3.1-6 7-6s7 2.4 7 6" />
    </Icon>
  ),
  settings: (p) => (
    <Icon {...p}>
      <circle cx="12" cy="12" r="3" />
      <path d="M12 3.5v2M12 18.5v2M20.5 12h-2M5.5 12h-2M18 6l-1.4 1.4M7.4 16.6 6 18M18 18l-1.4-1.4M7.4 7.4 6 6" />
    </Icon>
  ),
};

/* -------------------------------------------------------------------------
 * Navigation
 * ---------------------------------------------------------------------- */

type Item = {
  href: string;
  label: string;
  icon: keyof typeof ICONS;
  roles: Role[];
  /** Which key in /nav-counts feeds this item's badge, if any. */
  count?: keyof NavCounts;
};
type Group = { label: string | null; items: Item[] };

/*
 * Three menus out of one list.
 *
 * A parent's app is four words long, because she came to read about her child
 * and everything else is in her way. The specialist's leads with today's
 * diary; the office's leads with the children.
 *
 * The grouping is what stops eight items reading as one undifferentiated
 * column. A group whose whole contents are hidden for this role disappears
 * with them — a heading over nothing is worse than no heading.
 */
const GROUPS: Group[] = [
  {
    label: null,
    items: [
      { count: "home", href: "/", label: "الرئيسية", icon: "home", roles: ["admin", "specialist", "guardian"] },
    ],
  },
  {
    label: "المتابعة",
    items: [
      { count: "sessions", href: "/sessions", label: "الجلسات", icon: "sessions", roles: ["admin", "specialist"] },
      { count: "students", href: "/students", label: "الأطفال", icon: "children", roles: ["admin", "specialist"] },
      { href: "/analytics", label: "التحليلات", icon: "analytics", roles: ["admin", "specialist"] },
      {
        count: "reports",
        href: "/reports",
        label: "التقارير الدورية",
        icon: "reports",
        roles: ["admin", "specialist", "guardian"],
      },
    ],
  },
  {
    label: "التواصل",
    items: [
      {
        count: "messages",
        href: "/messages",
        label: "الرسائل",
        icon: "messages",
        roles: ["admin", "specialist", "guardian"],
      },
    ],
  },
  {
    label: "الإدارة",
    items: [
      { count: "staff", href: "/staff", label: "الحسابات", icon: "accounts", roles: ["admin"] },
      {
        href: "/settings",
        label: "الإعدادات",
        icon: "settings",
        roles: ["admin", "specialist", "guardian"],
      },
    ],
  },
];

const COLLAPSED_KEY = "haya.sidebar.collapsed";

/*
 * The export is mounted at /haya on the server and at the root locally, so a
 * bare "/mark.png" 404s in one of the two. Next rewrites `basePath` into its
 * own links but not into a plain <img src>.
 */
const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export function Shell({ children }: { children: React.ReactNode }) {
  const { user, loading, signOut } = useAuth();
  const pathname = usePathname();
  const router = useRouter();

  /** Mobile: the drawer slides in over the page. */
  const [drawer, setDrawer] = useState(false);
  const [counts, setCounts] = useState<NavCounts>({});
  /** Desktop: the full sidebar shrinks to an icon rail. */
  const [collapsed, setCollapsed] = useState(false);

  /*
   * Read after mount, never during render: the server has no localStorage, so
   * seeding state from it directly makes the first client paint disagree with
   * the prerendered HTML and React throws away the tree.
   */
  useEffect(() => {
    try {
      setCollapsed(window.localStorage.getItem(COLLAPSED_KEY) === "1");
    } catch {
      /* private windows and blocked storage — the default is fine */
    }
  }, []);

  const toggleCollapsed = useCallback(() => {
    setCollapsed((value) => {
      const next = !value;
      try {
        window.localStorage.setItem(COLLAPSED_KEY, next ? "1" : "0");
      } catch {
        /* nothing to do; it just will not be remembered */
      }
      return next;
    });
  }, []);

  const onLogin = pathname?.startsWith("/login") ?? false;

  /*
   * The guard lives here rather than in each page: one place that can be
   * wrong, and every screen inherits it. It waits for `loading` so a refresh
   * does not bounce a signed-in user to the login screen before the profile
   * has come back.
   */
  useEffect(() => {
    if (loading) return;
    if (!user && !onLogin) router.replace("/login");
    if (user && onLogin) router.replace("/");
  }, [loading, user, onLogin, router]);

  // Tapping a link on a phone should not leave the drawer sitting open over
  // the page it just navigated to.
  useEffect(() => {
    setDrawer(false);
  }, [pathname]);

  /*
   * Re-read the badges on every navigation.
   *
   * A specialist who has just published the last report she owed must not walk
   * away from that screen still looking at a menu that says she owes one. The
   * endpoint is eight counts against indexed columns, so paying for it per
   * navigation is cheaper than the alternative of being wrong.
   */
  useEffect(() => {
    if (!user) return;

    let cancelled = false;

    api<{ data: NavCounts }>("/nav-counts")
      .then((res) => !cancelled && setCounts(res.data))
      .catch(() => {
        /* the menu still works without its numbers */
      });

    return () => {
      cancelled = true;
    };
  }, [user, pathname]);

  // Escape closes the drawer, like every other overlay in the app.
  useEffect(() => {
    if (!drawer) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setDrawer(false);
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [drawer]);

  if (onLogin) return <>{children}</>;

  /*
   * The gap before the profile comes back.
   *
   * The academy's own mark, breathing — rather than a bare line of grey text.
   * It is the first thing anyone sees after signing in, and on a slow phone
   * connection it can be on screen for a second or two.
   */
  if (loading || !user) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={`${BASE_PATH}/mark.png`}
          alt=""
          className="size-16 animate-pulse object-contain opacity-80"
        />
        <p className="text-sm font-semibold text-muted">عم نحمّل…</p>
      </div>
    );
  }

  const groups = GROUPS.map((group) => ({
    ...group,
    items: group.items.filter((item) => item.roles.includes(user.role)),
  })).filter((group) => group.items.length > 0);

  /*
   * Headings only when the list is long enough to need them.
   *
   * A guardian sees four items, and grouping them puts three headings over
   * three single links — which reads as more structure than there is, and
   * calls the settings page "الإدارة" to a parent. Six is where an
   * undifferentiated column starts being hard to scan.
   */
  const showGroupLabels =
    groups.reduce((total, group) => total + group.items.length, 0) >= 6;

  const isActive = (href: string) =>
    href === "/" ? pathname === "/" : (pathname?.startsWith(href) ?? false);

  return (
    <div className="min-h-screen">
      {/* Mobile scrim. Clicking anywhere off the drawer closes it. */}
      {drawer && (
        <div
          className="fixed inset-0 z-40 bg-ink/40 backdrop-blur-[2px] lg:hidden"
          onClick={() => setDrawer(false)}
          aria-hidden
        />
      )}

      {/*
        The sidebar sits at the inline start — which in RTL is the right edge,
        where this reader's eye already begins.

        `fixed` with its own `overflow-y-auto`, so the menu scrolls on its own
        and the page behind it scrolls normally underneath. A sidebar that
        moves with the page is the thing that makes a long table unreadable on
        a laptop.

        The wash runs the logo's two halves top to bottom — the brain's blue
        down into the tree's sage — at about a tenth of their strength. Any
        more and a menu starts competing with the numbers it is next to.
      */}
      <aside
        className={`no-print fixed inset-y-0 start-0 z-50 flex flex-col border-line bg-gradient-to-b from-sky-soft via-panel to-sage-soft shadow-[1px_0_20px_-8px_rgb(27_106_102_/_0.18)] transition-[width,transform] duration-200 ltr:border-r rtl:border-l
          ${collapsed ? "lg:w-[4.75rem]" : "lg:w-64"}
          w-64
          ${drawer ? "translate-x-0" : "translate-x-full lg:translate-x-0"}`}
      >
        {/* Brand — the academy's own mark, not a letter in a box. */}
        <div className="flex h-16 shrink-0 items-center gap-2.5 border-b border-line/70 px-4">
          <Link href="/" className="group flex min-w-0 items-center gap-2.5">
            <span className="grid size-10 shrink-0 place-items-center overflow-hidden rounded-xl bg-panel shadow-card ring-1 ring-sky/60 transition group-hover:ring-brand/45">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`${BASE_PATH}/mark.png`} alt="" className="size-8 object-contain" />
            </span>
            {/*
              `lg:hidden` rather than not rendering it at all: `collapsed` is a
              desktop-only idea, and the drawer on a phone is always the full
              width. Dropping the element outright left the phone menu with a
              bare logo and no name on it.
            */}
            <span className={`min-w-0 leading-tight ${collapsed ? "lg:hidden" : ""}`}>
              <span className="block truncate text-sm font-extrabold text-ink">
                أكاديمية الحياة
              </span>
              <span className="block text-[11px] text-muted">للتأهيل</span>
            </span>
          </Link>
        </div>

        {/* Menu — the part that scrolls if it ever outgrows the screen. */}
        <nav className="relative flex-1 overflow-y-auto px-4 py-4">
          {/*
            The tree again, very faint, anchored to the bottom of the menu.
            It fills the gap a short menu leaves without putting anything in it
            that has to be read — and it is the academy's own mark, so the
            empty space still says whose software this is.
          */}
          {!collapsed && (
            <img
              src={`${BASE_PATH}/mark.png`}
              alt=""
              aria-hidden
              className="pointer-events-none absolute inset-x-0 bottom-2 mx-auto w-40 opacity-[0.055] select-none"
            />
          )}

          <div className={`relative ${showGroupLabels ? "space-y-5" : "space-y-1"}`}>
            {groups.map((group, index) => (
              <div key={group.label ?? index}>
                {group.label && showGroupLabels && (
                  <p
                    className={`mb-2 flex items-center gap-2 px-3 text-[10px] font-bold tracking-widest text-muted/80 ${
                      collapsed ? "lg:hidden" : ""
                    }`}
                  >
                    {group.label}
                    {/* A rule that runs out to the edge, so the heading reads
                        as a divider rather than as another menu item. */}
                    <span aria-hidden className="h-px flex-1 bg-gradient-to-l from-line to-transparent" />
                  </p>
                )}

                <ul className="space-y-1">
                  {group.items.map((item) => {
                    const Glyph = ICONS[item.icon];
                    const active = isActive(item.href);

                    return (
                      <li key={item.href}>
                        <Link
                          href={item.href}
                          title={collapsed ? item.label : undefined}
                          aria-current={active ? "page" : undefined}
                          className={`group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition-all duration-200 ${
                            collapsed ? "lg:justify-center lg:px-0" : ""
                          } ${
                            active
                              ? "bg-gradient-to-l from-brand to-brand-deep text-white shadow-glow"
                              : "text-muted hover:bg-panel hover:text-brand hover:shadow-soft"
                          }`}
                        >
                          {/*
                            A short bar on the reading edge of the live item.
                            The filled pill already says which page this is; the
                            bar is what makes it findable in the corner of the
                            eye on the way back from the content.
                          */}
                          {active && !collapsed && (
                            <span
                              aria-hidden
                              className="absolute inset-y-2 start-0 w-1 rounded-full bg-white/70 lg:block"
                            />
                          )}
                          <Glyph
                            className={`size-5 shrink-0 transition-transform duration-200 ${
                              active ? "" : "group-hover:scale-110"
                            }`}
                          />
                          <span className={collapsed ? "lg:hidden" : ""}>{item.label}</span>
                          <NavBadge
                            count={item.count ? counts[item.count] : undefined}
                            active={active}
                            collapsed={collapsed}
                          />
                        </Link>
                      </li>
                    );
                  })}
                </ul>
              </div>
            ))}
          </div>
        </nav>

        {/* Who is signed in, and the way out. */}
        <div className="shrink-0 border-t border-line/70 p-3">
          <div
            className={`flex items-center gap-2.5 rounded-xl bg-panel px-2.5 py-2 shadow-soft ring-1 ring-line/70 ${
              collapsed ? "lg:justify-center lg:bg-transparent lg:px-0 lg:shadow-none lg:ring-0" : ""
            }`}
          >
            <span className="grid size-9 shrink-0 place-items-center rounded-full bg-gradient-to-br from-sky to-sage text-sm font-bold text-ink/75 shadow-soft ring-2 ring-panel">
              {user.name.trim().replace(/^(أم|أبو)\s+/, "").charAt(0)}
            </span>
            <span className={`min-w-0 leading-tight ${collapsed ? "lg:hidden" : ""}`}>
              <span className="block truncate text-xs font-bold text-ink">{user.name}</span>
              <span className="block truncate text-[11px] text-muted">
                {user.title || user.role_label}
              </span>
            </span>
          </div>

          <button
            onClick={() => signOut().then(() => router.replace("/login"))}
            title={collapsed ? "خروج" : undefined}
            className={`mt-1.5 flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold text-muted transition hover:bg-bad-soft hover:text-bad ${
              collapsed ? "lg:justify-center lg:px-0" : ""
            }`}
          >
            <svg viewBox="0 0 24 24" className="size-5 shrink-0" aria-hidden {...stroke}>
              <path d="M14.5 8.5V6a2 2 0 0 0-2-2h-6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2v-2.5" />
              <path d="M10 12h10.5M18 9l3 3-3 3" />
            </svg>
            <span className={collapsed ? "lg:hidden" : ""}>خروج</span>
          </button>
        </div>
      </aside>

      {/*
        The page. Its inline-start margin matches the sidebar so the two never
        overlap on a desktop; on a phone the sidebar is an overlay and the page
        keeps the full width.
      */}
      <div
        className={`transition-[margin] duration-200 ${
          collapsed ? "lg:ms-[4.75rem]" : "lg:ms-64"
        }`}
      >
        {/* Slim bar: the drawer button on a phone, the collapse toggle on a desktop. */}
        <header className="no-print sticky top-0 z-30 flex h-16 items-center gap-3 border-b border-line bg-panel/80 px-4 shadow-[0_1px_12px_-6px_rgb(27_106_102_/_0.25)] backdrop-blur-xl">
          <button
            onClick={() => setDrawer(true)}
            className="rounded-lg border border-line bg-panel p-2 text-muted shadow-soft transition hover:border-brand/40 hover:bg-brand-soft hover:text-brand lg:hidden"
            aria-label="افتح القائمة"
            aria-expanded={drawer}
          >
            <svg viewBox="0 0 24 24" className="size-5" aria-hidden {...stroke}>
              <path d="M4 7h16M4 12h16M4 17h16" />
            </svg>
          </button>

          <button
            onClick={toggleCollapsed}
            className="hidden rounded-lg border border-line bg-panel p-2 text-muted shadow-soft transition hover:border-brand/40 hover:bg-brand-soft hover:text-brand lg:block"
            aria-label={collapsed ? "وسّع القائمة" : "اطوِ القائمة"}
          >
            <svg viewBox="0 0 24 24" className="size-5" aria-hidden {...stroke}>
              <path d="M4 7h16M4 12h16M4 17h16" />
            </svg>
          </button>

          {/* On a phone the sidebar is hidden, so the name goes here. */}
          <span className="flex items-center gap-2 lg:hidden">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${BASE_PATH}/mark.png`} alt="" className="size-7 object-contain" />
            <span className="text-sm font-extrabold text-ink">أكاديمية الحياة</span>
          </span>
        </header>

        {/*
          Keyed on the path so each screen fades up as it arrives. It is 0.5s
          of movement on a navigation the user asked for, and it covers the gap
          between the route changing and the first request coming back — which
          is otherwise a blank rectangle.
        */}
        <main key={pathname} className="rise mx-auto max-w-7xl px-4 py-6">
          {children}
        </main>
      </div>
    </div>
  );
}

/** Page heading with an optional action on the far side. */
export function PageHead({
  title,
  subtitle,
  action,
  back,
}: {
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
  back?: { href: string; label: string };
}) {
  return (
    <div className="no-print mb-6">
      {back && (
        <Link
          href={back.href}
          className="group mb-3 inline-flex items-center gap-1.5 rounded-lg text-xs font-semibold text-muted transition hover:text-brand"
        >
          <span aria-hidden className="transition-transform group-hover:translate-x-0.5">
            →
          </span>
          {back.label}
        </Link>
      )}
      <div className="flex flex-wrap items-end justify-between gap-3 border-b border-line pb-4">
        <div className="flex items-center gap-3">
          {/*
            The logo's two colours as a bar down the reading edge of the title.
            Twelve screens share this component, so it is the one mark that
            makes every page in the app look like it came from the same place.
          */}
          <span
            aria-hidden
            className="h-11 w-1.5 shrink-0 rounded-full bg-gradient-to-b from-brand via-sky to-sage"
          />
          <div className="min-w-0">
            <h1 className="text-2xl font-extrabold tracking-tight text-ink">{title}</h1>
            {subtitle && <p className="mt-1 text-sm text-muted">{subtitle}</p>}
          </div>
        </div>
        {action}
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------
 * The number beside a menu item
 * ---------------------------------------------------------------------- */

/**
 * Two badges in one, because the two numbers are read differently.
 *
 *   `attention` — something is waiting for a person: reports nobody has
 *                 written, a parent's question nobody has answered. Filled,
 *                 coloured, and it wins whenever it is non-zero.
 *   `total`     — simply how many exist: children on the roll, sessions today.
 *                 Quiet, and only ever shown when there is nothing waiting.
 *
 * Nothing is drawn for a zero. A menu wearing eight badges teaches people to
 * stop seeing badges, and then the one that mattered goes unread too.
 *
 * Collapsed, the number will not fit beside a centred icon, so it becomes a
 * dot on the corner — present enough to make someone open the rail, which is
 * all a collapsed menu can honestly promise.
 */
function NavBadge({
  count,
  active,
  collapsed,
}: {
  count?: { total: number; attention: number };
  active: boolean;
  collapsed: boolean;
}) {
  if (!count) return null;

  const attention = count.attention > 0;
  const value = attention ? count.attention : count.total;

  if (value <= 0) return null;

  const label = attention ? `${value} بحاجة لمتابعة` : `${value}`;

  return (
    <>
      {/* Expanded: a pill at the far end of the row. */}
      <span
        aria-label={label}
        className={`tabular ms-auto hidden min-w-6 rounded-full px-1.5 py-0.5 text-center text-[11px] font-bold leading-tight lg:inline-block ${
          collapsed ? "lg:hidden" : ""
        } ${
          active
            ? "bg-white/25 text-white"
            : attention
              ? "bg-bad text-white"
              : "bg-line/80 text-muted"
        }`}
      >
        {value > 99 ? "٩٩+" : value}
      </span>

      {/* The same pill on a phone, where the rail is never collapsed. */}
      <span
        aria-hidden
        className={`tabular ms-auto min-w-6 rounded-full px-1.5 py-0.5 text-center text-[11px] font-bold leading-tight lg:hidden ${
          active
            ? "bg-white/25 text-white"
            : attention
              ? "bg-bad text-white"
              : "bg-line/80 text-muted"
        }`}
      >
        {value > 99 ? "٩٩+" : value}
      </span>

      {/* Collapsed: a dot on the icon's corner. Only for things that wait. */}
      {collapsed && attention && (
        <span
          aria-label={label}
          className="absolute end-2.5 top-1.5 hidden size-2 rounded-full bg-bad ring-2 ring-panel lg:block"
        />
      )}
    </>
  );
}
