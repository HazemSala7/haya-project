/**
 * The one place a list screen gets its rows.
 *
 * Every list in the system is the same problem — a filter, a page number, and
 * a request that must not be allowed to answer out of order — so it is solved
 * once here rather than ten times across the screens. What each screen keeps
 * is the part that is actually its own: which columns, which filters.
 */

"use client";

import { useCallback, useEffect, useState } from "react";
import { api, type Page, type PageMeta } from "@/lib/api";

type Query = Record<string, string | number | boolean | undefined | null>;

/**
 * `Extra` is whatever the endpoint puts in `meta` beyond the page counts —
 * the summary figures a screen shows above its table. They belong in the
 * response rather than being added up from `rows`, because a total computed
 * from one page describes that page and quietly claims to describe the filter.
 */
export type PagedList<T, Extra> = {
  rows: T[];
  /** Null until the first response lands — a pager has nothing to draw yet. */
  meta: (PageMeta & Extra) | null;
  loading: boolean;
  page: number;
  setPage: (page: number) => void;
  /** Re-fetch the current page — after a save, a delete, a cheque cleared. */
  reload: () => void;
};

export function usePagedList<T, Extra = Record<string, never>>(
  path: string,
  query: Query,
  { perPage = 25, enabled = true }: { perPage?: number; enabled?: boolean } = {},
): PagedList<T, Extra> {
  /*
   * The filters, flattened to a string. Callers build the query object inline,
   * so a fresh object arrives on every render and its identity says nothing
   * about whether anything changed; its contents do.
   */
  const key = JSON.stringify(query);

  const [page, setPage] = useState(1);
  const [seenKey, setSeenKey] = useState(key);
  const [rows, setRows] = useState<T[]>([]);
  const [meta, setMeta] = useState<(PageMeta & Extra) | null>(null);
  const [loading, setLoading] = useState(true);
  const [nonce, setNonce] = useState(0);

  /*
   * A filter changed, so page 5 of the old result set is meaningless — asking
   * for it lands the user on an empty screen when there are plenty of matches.
   *
   * Reset during render, not in an effect: an effect runs *after* this render
   * has already fired the fetch, so the stale page goes out first and two
   * responses race to be the one that sticks.
   */
  if (key !== seenKey) {
    setSeenKey(key);
    setPage(1);
  }

  useEffect(() => {
    // A screen whose role cannot see this list at all — the accounts list
    // opened by a specialist. Not asking is the point: a request that is
    // certain to come back 403 is noise in the log and a flash of "لا توجد
    // نتائج" on the way there.
    if (!enabled) {
      setLoading(false);
      return;
    }

    let cancelled = false;

    setLoading(true);

    api<Page<T> & { meta: PageMeta & Extra }>(path, {
      query: { ...(JSON.parse(key) as Query), page, per_page: perPage },
    })
      .then((res) => {
        // Typing in a search box fires a request per debounce tick, and they do
        // not come back in the order they were sent. Without this, a slow early
        // reply can overwrite the rows the user is actually looking at.
        if (cancelled) return;

        setRows(res.data);
        setMeta(res.meta);

        /*
         * The last row on the last page was just deleted: that page is gone and
         * the server answers with nothing at all. Step back to the new last page
         * rather than show "no results" for a list that still has plenty.
         */
        if (res.meta.current_page > res.meta.last_page && res.meta.last_page >= 1) {
          setPage(res.meta.last_page);
        }
      })
      .catch(() => {
        // `api()` has already turned this into a message the user can act on —
        // a dead connection, an expired session. What is left to do here is not
        // leave the previous page's rows on screen pretending to be this one's.
        if (!cancelled) {
          setRows([]);
          setMeta(null);
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [path, key, page, perPage, enabled, nonce]);

  const reload = useCallback(() => setNonce((n) => n + 1), []);

  return { rows, meta, loading, page, setPage, reload };
}
