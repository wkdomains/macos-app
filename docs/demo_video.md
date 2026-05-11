# wkdomains Browser Demo Notes

Goal: repeat the same flow from the original Cloudflare starter page, but move with enough preparation that the screen recording feels fast and intentional. The audience should see a coding agent and a human-visible browser working side by side, not a hidden headless test run.

## Starting Setup

- Repo: `/Users/aa/dialtoneapp/cloudflare-starter`
- Dev server: user runs `npm run dev`
- Browser: wkdomains open on `http://localhost:5173/`
- Recording layout: wkdomains browser on left half, terminal on right half
- Viewport target: desktop mode at about half-screen width, roughly `735-750px` wide

## Demo Story

1. The user asks for a design fix and a product rewrite.
2. Inspect the live page through wkdomains, not Playwright.
3. Notice the real layout problem: the theme icon wraps onto a second header row in desktop mode at the narrow viewport.
4. Patch the React/CSS while the Vite page hot reloads in the visible browser.
5. Turn the generic Cloudflare starter into a wkdomains homepage.
6. Use wkdomains layout, console, snapshot, and human scroll APIs to verify the result.

## Use These Skills

- `inspect-website`: use the live wkdomains browser API at `http://localhost:9001`.
- `frontend-skill`: keep the page visually strong, product-specific, and recording-friendly.

## Fast Inspection Commands

Run these early. They establish that the browser is live, visible, and useful.

```sh
curl -sS http://localhost:9001/api/v1/page | jq .
curl -sS http://localhost:9001/api/v1/observe | jq .
curl -sS http://localhost:9001/api/v1/layout | jq .
curl -sS http://localhost:9001/api/v1/snapshot | jq '{title,url,viewport,elements:[.elements[] | {role,text,label,rect}]}'
```

What to call out:

- Page is `localhost:5173`.
- Viewport is desktop mode but narrow.
- Original theme button appears at about `top: 67`, meaning it wrapped below the brand row.
- Layout has no horizontal overflow, but the header composition is wrong and small tap targets are flagged.

## Files To Change

- `src/components/Layout/Layout.jsx`
- `src/pages/Home/index.jsx`
- `src/styles.css`
- `src/shared/documentMetadata.js`
- `src/index.html`
- `src/public/favicon.svg`

Avoid editing more files unless the reset content changes.

## Prepared Content Direction

Visual thesis: crisp operator-grade browser homepage with a live-console feel, precise type, and proof-oriented motion.

Content plan:

- Hero: `wkdomains` as the loudest text, with a visible browser/inspection preview.
- Proof strip: live Worker API status plus viewport/demo posture.
- Tools section: explain Playwright-style control, Pencil.dev-style inspection, browser-native context, and agent handoff.
- Workflow section: Observe, Act, Replay.
- Demo section: the recording flow itself.

Interaction thesis:

- Hero entrance animation.
- Command rail animation.
- Human-style scroll through section stops.

## Header Fix

The key responsive fix:

- Keep `.site-header` as one row at this viewport.
- Hide secondary nav and the header CTA below about `860px`.
- Keep `.theme-toggle` fixed at `44px x 44px`.
- Give `.brand` `min-height: 44px`.
- Ensure `.app-shell` has enough horizontal breathing room but no overflow.

Verification target after fix:

- Theme toggle should be in the first header row, around `top: 12`, `height: 44`.
- `layout.document.hasHorizontalOverflow` should be `false`.
- `layout.counts.smallTapTargets` should be `0`.

## Good Live Verification Commands

Use these after hot reload:

```sh
curl -sS http://localhost:9001/api/v1/page | jq .
curl -sS http://localhost:9001/api/v1/layout | jq '{document:.document, counts:.counts, smallTapTargets:.smallTapTargets, clipped:.clipped}'
curl -sS http://localhost:9001/api/v1/console | jq .
curl -sS http://localhost:9001/api/v1/snapshot | jq '{title,viewport,elements:[.elements[] | {role,text,label,rect}]}'
```

Expected:

- Title is `wkdomains browser`.
- No console messages.
- No horizontal overflow.
- No clipped elements.
- No small tap targets.
- Header has brand and theme toggle on the same row.

## Human Scroll Moment

This is the strongest “new era” part. Make sure the audience sees the browser move.

```sh
curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"scroll","direction":"top","durationMs":800}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"scroll","direction":"bottom","style":"human","durationMs":18000}' | jq .
```

Then inspect:

```sh
curl -sS http://localhost:9001/api/v1/scroll | jq .
```

What good looks like:

- Scroll trace has section stops.
- Stops land on hero, tools, workflow, and demo.
- Final dominant section is the demo CTA area.
- The terminal shows structured evidence while the browser visibly moves.

## Do Not Over-Cheat

Prepared:

- Know the file names.
- Know the rough content architecture.
- Know the verification commands.
- Know the responsive breakpoint strategy.

Keep live:

- Actually inspect the page first.
- Actually observe the wrapping bug from snapshot/layout.
- Actually patch the files in response to what the browser reports.
- Actually run the human scroll and layout checks.
- Let the hot reload be visible.

The point is not to pretend the agent invented everything from scratch. The point is to show that with a visible browser, structured page state, and local code access, the agent can move from observation to implementation to verification in one tight loop.

## If Time Is Tight

Minimum viable recording sequence:

1. `page`, `observe`, `layout`, `snapshot`
2. Explain the nav icon wrapping from the snapshot rects.
3. Patch `Layout.jsx`, `Home/index.jsx`, `styles.css`, metadata, favicon.
4. Run `layout` and `console`.
5. Run the human-style scroll.
6. Final `layout` check showing no overflow, no clipping, no small tap targets.

## Useful Lines To Say

- “The browser is not just a screenshot. It is giving the agent DOM, XHR, cookies, console, layout, and scroll state.”
- “The user can watch every interaction while the agent still gets machine-readable state.”
- “This is the difference between headless automation and collaborative browsing.”
- “The terminal is not guessing. It is reading the same page the human can see.”
