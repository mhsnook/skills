---
name: audit-nextjs-rendering
description: Checks a NextJS project's reported rendering strategy against the actual build output and run-time behaviour, generates a report and recommendations.
license: MIT
---

The rendering strategy `next build` reports for each route — static, SSG, ISR, dynamic — does
not always match what the build wrote to disk or what the server does at runtime. Audit this
project's production build and report where they differ.

Before building
- Confirm the installed `next` version matches the lockfile. If they differ, work in a clean copy
  of the committed code with its own `npm ci` (or equivalent) rather than changing the user's
  install.
- Do not let the build modify tracked files. Next can rewrite `tsconfig.json`; if it does,
  restore the file and say so.
- Build against production-like data. Mock or empty datasets change what `generateStaticParams`
  returns, and so change which routes the build even attempts. State which data source you used.

1. Run the production build and save the full log. Note every warning about caching, dynamic
   usage, edge runtime, or cache size limits: these explain later findings.

2. Record what the build CLAIMS: the symbol and revalidate window the route table prints for each
   route, and the concrete paths it lists under each dynamic route.

3. Record what the build PRODUCED:
   - the entries in `.next/prerender-manifest.json` (`routes` and `dynamicRoutes`)
   - the HTML, RSC, body and meta files under `.next/server/app`
   - the entries in `.next/cache/fetch-cache`
   The route table reflects what a route asked for, not what the build wrote. A route marked
   prerendered can have no files and no manifest entry; directories with no files in them are a
   sign of this.

4. Probe the routes against `next start`. Derive the URL list from the build output and any
   sitemaps, not by guessing. For each URL:
   - Request it at least three times. Record status, `x-nextjs-cache`, `Cache-Control`, ETag, and
     time to first byte.
   - If it returns an ETag, repeat the request with `If-None-Match` and record whether it gets 304.
   - Include a route the manifest lists as a positive control, so an absent `x-nextjs-cache`
     means something.
   - For dynamic routes with `generateStaticParams`, also request a param the build did not list.
     Expect MISS, then HIT, then new files on disk. Say which you saw.
   - If middleware rewrites some URLs and not others (a locale prefix, for example), test the
     unlisted-param case through both kinds of URL.
   Judge by `x-nextjs-cache` first. `Cache-Control` and ETag are supporting evidence: under
   `next start` a dynamic HTML route gets `private, no-cache, no-store` and no ETag, and a cached
   one gets `s-maxage` and an ETag. Do not rely on `age`; `next start` may not send it.

5. Check the Data Cache separately from the Full Route Cache.
   - Look in the build and server logs for fetches that failed to cache, such as the 2 MB item
     limit. Count them per request, per route.
   - Compare first-request and repeat-request timings on dynamic routes: a drop means the Data
     Cache is warm even though the page itself is not cached.
   - Watch whether the fetch cache directory grows while you probe.

Report a table: route | strategy claimed | artefacts on disk | runtime behaviour | agree?

Where they disagree, find what pushes the route off the prerender path: a dynamic API
(`headers()`, `cookies()`, `searchParams`, `connection()`) in a layout or a page,
`export const dynamic` or `revalidate`, an uncached or oversized fetch, the edge runtime, a
dynamic segment with no `generateStaticParams`, or middleware. Where you can, confirm a cause
directly: remove it in a scratch copy, rebuild, and see which routes enter the manifest. Label
each cause as confirmed by experiment or inferred from reading the code.

Keep the Full Route Cache and the Data Cache separate in your conclusions. A route can lose one
and keep the other.

Report what you measured, including anything that contradicts this prompt. Stop any servers you
started, and leave the working tree as you found it.
