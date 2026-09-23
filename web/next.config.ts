import type { NextConfig } from "next";

/**
 * Built as a static site.
 *
 * The whole dashboard is a client-side SPA: the session is a bearer token in
 * localStorage and every byte of data comes from the Laravel API, so there is
 * nothing for a Node server to do at request time. It exports to plain HTML
 * and JS that any web server hands out — including the shared cPanel hosting
 * this deploys to, which has no Node at all.
 *
 * The cost is one constraint the code honours throughout: no path parameters.
 * Record screens read `?id=` instead, because a path parameter would force
 * Next.js to know every child's id at build time — and a build that enumerates
 * the children would be a build that leaks them.
 */
const nextConfig: NextConfig = {
  output: "export",

  /*
   * Emits `students/view/index.html` rather than `students/view.html`, so a
   * plain Apache docroot resolves /students/view without rewrite rules.
   */
  trailingSlash: true,

  /*
   * Next's image optimiser is a server feature. Session photos are streamed
   * from the API behind an auth check and never go through <Image>, but
   * leaving this unset makes the export fail the moment someone uses it.
   */
  images: { unoptimized: true },

  /*
   * Several systems share one server, so this one is mounted at /haya. It has
   * to be baked in at build time: a static export writes absolute URLs for
   * every chunk into the HTML, and without this they point at /_next/… and 404
   * anywhere but the domain root. Unset locally, where `next dev` serves from
   * the root.
   */
  basePath: process.env.NEXT_PUBLIC_BASE_PATH || undefined,
};

export default nextConfig;
