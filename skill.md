---
name: wkdomains-local-browser-api
description: Use the wkdomains WebKit browser and local API to inspect, drive, QA, rebuild, and relaunch local web apps without Playwright. Covers localhost:9001 browser endpoints, ../web Vite/Wrangler dev workflow, local auth OTP testing, source x-ray markers, visual diffing, and Xcode launch/build loops.
---

# wkdomains Local Browser Skill

Use this when working on the wkdomains macOS browser or a local web app opened inside it. The goal is to replace Playwright with the real WebKit browser plus `http://localhost:9001/api/v1/*` inspection/action endpoints.

Do not reach for Playwright for this project. If an endpoint is missing, add it to the browser API, rebuild, relaunch, and keep going.

## Repos And Processes

- macOS browser repo: `/Users/aa/wkdomains/macos-app`
- web app repo: `/Users/aa/wkdomains/web`
- browser local API: `http://localhost:9001`
- local web app URL: `http://localhost:5173/`
- local worker URL: `http://localhost:8787`
- web dev log: `/tmp/wkdomains-web-dev.log`

## Start Or Check The Web App

Run from `../web`:

```sh
npm run dev
```

This runs migrations, Vite on `localhost:5173`, and Wrangler/workerd on `localhost:8787`.

For a detached dev server that a fresh Codex turn can leave running:

```sh
screen -dmS wkdomains-web-dev zsh -lc 'cd /Users/aa/wkdomains/web && npm run dev > /tmp/wkdomains-web-dev.log 2>&1'
```

Check it:

```sh
curl -sS --max-time 3 http://localhost:5173/ >/dev/null && echo vite-up
curl -sS --max-time 3 http://localhost:8787/ >/dev/null && echo worker-up
tail -n 80 /tmp/wkdomains-web-dev.log
```

Restart it:

```sh
pids=$(pgrep -f "vite|wrangler|workerd|npm run dev|scripts/dev" || true)
if [ -n "$pids" ]; then kill $pids 2>/dev/null || true; fi
screen -S wkdomains-web-dev -X quit 2>/dev/null || true
screen -dmS wkdomains-web-dev zsh -lc 'cd /Users/aa/wkdomains/web && npm run dev > /tmp/wkdomains-web-dev.log 2>&1'
```

Build check:

```sh
cd /Users/aa/wkdomains/web && npm run build
```

## Xcode / App Loop

From `docs/xcode.md`: yes, the app can be launched, killed, rebuilt, and relaunched from the CLI.

Build only when the macOS change is complex or affects compiled Swift:

```sh
cd /Users/aa/wkdomains/macos-app
xcodebuild -project macos-app.xcodeproj -scheme macos-app -configuration Debug -destination 'platform=macOS' build
```

Launch latest debug app:

```sh
app=$(ls -td ~/Library/Developer/Xcode/DerivedData/macos-app-*/Build/Products/Debug/wkdomains.app 2>/dev/null | head -n 1)
open "$app"
```

Find and kill the browser app:

```sh
pgrep -fl wkdomains
pid=$(pgrep -x wkdomains | head -n 1)
if [ -n "$pid" ]; then kill "$pid"; fi
```

Verify local API after launch:

```sh
for i in {1..30}; do
  if curl -sS --max-time 1 http://localhost:9001/api/v1/page >/tmp/wk-page.json 2>/dev/null; then
    cat /tmp/wk-page.json | jq '{url,title,viewportMode,isLoading}'
    break
  fi
  sleep 0.5
done
```

Typical loop:

1. Kill running `wkdomains`.
2. Edit Swift/browser code.
3. Run `xcodebuild`.
4. Launch rebuilt app.
5. Hit `localhost:9001` endpoints to verify.

Fast demo loop after a local `-derivedDataPath build/DerivedData` build:

```sh
cd /Users/aa/wkdomains/macos-app
xcodebuild -scheme macos-app -configuration Debug -derivedDataPath build/DerivedData build

app=/Users/aa/wkdomains/macos-app/build/DerivedData/Build/Products/Debug/wkdomains.app
pids=$(pgrep -f '/wkdomains\.app/Contents/MacOS/wkdomains' || true)
if [ -n "$pids" ]; then kill -9 $pids 2>/dev/null || true; fi

for i in {1..20}; do
  pgrep -f '/wkdomains\.app/Contents/MacOS/wkdomains' >/dev/null || break
  sleep 0.1
done

open -n "$app" || (sleep 1 && open -n "$app")

for i in {1..40}; do
  if curl -sS --max-time 1 http://localhost:9001/api/v1/page >/tmp/wk-page.json 2>/dev/null; then
    cat /tmp/wk-page.json | jq '{url,title,viewportMode,isLoading}'
    break
  fi
  sleep 0.5
done
```

Notes:

- Prefer `open -n "$app"` over launching `Contents/MacOS/wkdomains` directly for recordings; Launch Services gives the app a normal foreground window.
- If `open` returns `-600`, it usually means the previous app instance was killed too recently. Wait one second and retry `open -n "$app"`.
- Do not keep retrying a dead direct executable launch. Verify with `/api/v1/page`; if the local API does not come back, launch through Finder/Launch Services or ask the human to reopen the built app.
- For route changes in `LocalAPIServer.swift`, verify POST routes are above the general `guard request.method == "GET"` fallback.

## Core Browser API

Base URL:

```sh
http://localhost:9001
```

Quick probes:

```sh
curl -sS http://localhost:9001/api/v1/page | jq .
curl -sS http://localhost:9001/api/v1/observe | jq .
curl -sS http://localhost:9001/api/v1/snapshot | jq .
curl -sS http://localhost:9001/api/v1/dom | jq .
curl -sS http://localhost:9001/api/v1/layout | jq .
curl -sS http://localhost:9001/api/v1/links | jq .
curl -sS http://localhost:9001/api/v1/console | jq .
curl -sS http://localhost:9001/api/v1/timing | jq .
curl -sS http://localhost:9001/api/v1/resources | jq .
curl -sS http://localhost:9001/api/v1/xhr | jq .
curl -sS http://localhost:9001/api/v1/cookies | jq .
curl -sS http://localhost:9001/api/v1/dark-reader | jq .
curl -sS http://localhost:9001/api/v1/screenshot --output current.png
```

Endpoints:

- `GET /api/v1/page`: current URL, title, host/domain/origin, viewport, load state, back/forward state.
- `POST /api/v1/navigate`: navigate the visible browser. Body: `{"url":"http://localhost:5173/","mode":"hard|soft|auto"}`.
- `GET /api/v1/observe`: agent bundle with page, screenshot pointer, snapshot, console, XHR, resources, and auth shape.
- `GET /api/v1/snapshot`: stable visible interactive element refs like `@e8`.
- `GET /api/v1/dom`: visible text, headings, forms, fields, tables, ARIA, rectangles.
- `GET /api/v1/layout`: overflow, clipped elements, small tap targets, outside-viewport elements, fixed/sticky overlaps.
- `GET /api/v1/scroll`: latest human-style or manually recorded scroll trace with planned stops, visible content samples, and dwell timing.
- `POST /api/v1/scroll/record`: start/stop/reset manual scroll recording with `{"action":"start|stop|reset"}`.
- `GET /api/v1/element/@eN`: element x-ray: computed styles, box model, accessibility state, selector/source hints, ancestors, siblings, contrast.
- `GET /api/v1/links`: anchors, forms, scripts, link tags.
- `GET /api/v1/console`: page console calls, window errors, unhandled promises, CSP violations.
- `GET /api/v1/console-panel`: current in-app JavaScript console drawer state.
- `POST /api/v1/console-panel`: show or hide the in-app JavaScript console drawer. Body: `{"visible":true}` or `{"visible":false}`.
- `GET /api/v1/timing`: browser/API timing rollup.
- `GET /api/v1/timing/reset`: reset timing session.
- `GET /api/v1/resources`: common machine files: `llms.txt`, OpenAPI, agent cards, sitemap, robots, etc.
- `GET /api/v1/xhr`: observed XHR/fetch for current page host, including redacted `jsonShape` and redacted `responseBodyPreview`.
- `GET /api/v1/xhr/{index}/replay`: replay an observed request when available.
- `GET /api/v1/cookies`: cookies plus local/session storage. Sensitive.
- `GET /api/v1/dark-reader`: Dark Reader extension/page diagnostics.
- `GET /api/v1/screenshot`: current visible viewport PNG.
- `GET /api/v1/viewport`: current visible browser viewport.
- `POST /api/v1/viewport`: switch visible browser viewport. Body: `{"mode":"mobileSmall"}`, `{"mode":"mobileLarge"}`, or `{"width":390}`.
- `POST /api/v1/capture`: offscreen exact WebKit capture for one viewport.
- `POST /api/v1/qa/viewports`: batch offscreen WebKit capture for responsive QA.
- `GET /api/v1/captures/{id}/screenshot`: PNG from capture, QA, or visual diff.
- `POST /api/v1/visual/compare`: compare current/local page to reference/baseline URL and return pixel metrics plus current/reference/diff PNG endpoints.
- `POST /api/v1/visual-diff`: alias for visual compare.
- `POST /api/v1/action`: click/fill/select/submit/press/focus/clear/scroll visible elements or the page.
- `POST /api/v1/actions`: alias for action.
- `POST /api/v1/scenario`: run a short ordered browser flow and return a step trace.
- `POST /api/v1/flow`: alias for scenario.
- `POST /mcp`: JSON-RPC MCP shim for human request tools.

## Action Endpoint

Use `POST /api/v1/action` instead of Playwright.

Targets can be a current `ref`, a CSS `selector`, accessible `name`, visible `text`, `role`, or active element for `press`. `name` checks the accessibility label first and falls back to visible text/title/placeholder so it stays useful on local apps with imperfect ARIA labels.

Prefer user-facing targets over selectors when possible:

- `{"role":"button","name":"Email me a 6-digit code"}`
- `{"role":"link","name":"Sign in"}`
- `{"text":"Sign out","exact":true}`

`exact` defaults to `true`; set `exact:false` for case-insensitive contains matching. Action responses include `targetStrategy`, `role`, `name`, `text`, and nearby `candidates` when useful. Failed query actions include ranked `nearMatches` with role/name/text match flags; use those labels for the next action instead of guessing selectors. Sensitive input values such as passwords, OTPs, tokens, and auth codes are redacted in action summaries.

Supported actions:

- `click`
- `fill` / `setvalue`
- `clear`
- `select`
- `submit`
- `press`
- `focus`
- `scroll`

Examples:

```sh
curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"click","role":"link","name":"Sign in","waitFor":{"selector":"#login-email","timeoutMs":5000}}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"fill","selector":"#login-email","value":"test@example.com"}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"press","active":true,"key":"Enter","waitFor":{"urlContains":"/dashboard","timeoutMs":10000}}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"scroll","direction":"down"}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"scroll","direction":"bottom","durationMs":9000}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"scroll","direction":"bottom","style":"human","durationMs":45000}' | jq .

curl -sS http://localhost:9001/api/v1/scroll | jq .

curl -sS -X POST http://localhost:9001/api/v1/scroll/record \
  -H 'Content-Type: application/json' \
  -d '{"action":"start"}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/scroll/record \
  -H 'Content-Type: application/json' \
  -d '{"action":"stop"}' | jq .
```

Wait conditions supported in `waitFor` or `wait`:

- `url`
- `urlContains`
- `titleContains`
- `readyState`
- `text` / `textIncludes`
- `selector`
- `selectorGone`
- `visible`
- `xhr`
- `xhrURLContains` / `xhrUrlContains`
- `xhrMethod`
- `xhrStatus`
- `xhrCompleted`
- `xhrResponseBodyContains`
- `xhrJsonShapeContains`
- `timeoutMs` or `timeoutSeconds` (capped at 20s)

XHR waits start counting after the action begins, so stale earlier requests do not satisfy the wait.

```sh
curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"click","role":"button","name":"Email me a 6-digit code","waitFor":{"selector":"#login-code","xhr":{"urlContains":"/api/auth/email/request-code","method":"POST","status":200},"timeoutMs":10000}}' | jq .
```

## Viewport QA And Visual Diff

## Scenario Endpoint

Use `POST /api/v1/scenario` when a task would otherwise need many back-and-forth calls. It runs steps in order and returns a trace with `ok`, `op`, elapsed time, and each step result.

Supported `kind` / `op` values:

- `navigate`
- `action`
- `page`
- `snapshot`
- `observe`
- `dom`
- `layout`
- `console`
- `xhr`
- `sleep`

For action steps, use either `{"kind":"action","action":"click",...}` or a direct action-shaped step such as `{"type":"click","role":"button","name":"Sign out"}`.

```sh
curl -sS -X POST http://localhost:9001/api/v1/scenario \
  -H 'Content-Type: application/json' \
  -d '{"name":"open-login","steps":[{"kind":"navigate","url":"http://localhost:5173/","mode":"hard"},{"type":"click","role":"link","name":"Sign in","waitFor":{"selector":"#login-email","timeoutMs":5000}},{"kind":"page"}]}' | jq .
```

Batch QA default sizes are:

- `390x844`
- `768x1024`
- `1280x800`
- `1440x900`

Example:

```sh
curl -sS -X POST http://localhost:9001/api/v1/qa/viewports \
  -H 'Content-Type: application/json' \
  -d '{"url":"http://localhost:5173/dashboard","includeScreenshot":false}' | jq .
```

Visual compare example:

```sh
curl -sS -X POST http://localhost:9001/api/v1/visual/compare \
  -H 'Content-Type: application/json' \
  -d '{"referenceUrl":"http://localhost:5173/","currentUrl":"http://localhost:5173/dashboard","width":390,"height":844,"threshold":8,"name":"homepage-vs-dashboard-mobile"}' \
  | jq '{name,changedPercent:.metrics.changedPercent,diff:.diff.endpoint,current:.current.screenshot.endpoint,reference:.reference.screenshot.endpoint}'
```

The response includes:

- `metrics.changedPixels`
- `metrics.changedPercent`
- `metrics.boundingBox`
- `metrics.regions`
- current screenshot endpoint
- reference screenshot endpoint
- diff screenshot endpoint

## Source X-Ray

`GET /api/v1/element/@eN` returns `sourceHint`.

The browser first reads explicit DOM metadata:

- `data-wk-source="src/pages/Dashboard/index.jsx:500:15"`
- `data-wk-component="DashboardPage"`

Then it falls back to React fiber debug metadata. For the Vite app in `../web`, `vite.config.js` adds dev-only source markers by post-processing generated `jsxDEV` calls. This gives x-ray enough information to map a rendered element back to a file and line.

Verify:

```sh
curl -sS http://localhost:9001/api/v1/snapshot | jq -r '.elements[] | select((.text // "") == "add domain") | [.ref,.tag,.role,.text] | @tsv'
curl -sS http://localhost:9001/api/v1/element/@e8 | jq '{element:.element, sourceHint:.sourceHint}'
```

Expected for the dashboard add-domain button:

```json
{
  "fileName": "src/pages/Dashboard/index.jsx",
  "lineNumber": 500,
  "columnNumber": 15,
  "note": "Explicit DOM source metadata."
}
```

## Local Login / OTP Test

The local `../web` app is configured to avoid real email:

- `.dev.vars` contains `WKDOMAINS_DEV_AUTH=1`.
- `scripts/dev.mjs` defaults `WKDOMAINS_DEV_AUTH` to `1`.
- `scripts/dev.mjs` starts a 127.0.0.1-only OTP sink with a random token and writes JSONL to `/tmp/wkdomains-dev-otp.jsonl`.
- `worker/routes/auth.js` posts plaintext OTPs to that local sink instead of calling Resend when in local dev.
- `/api/auth/email/request-code` does not return `dev_code`; the browser-visible response only reports `delivery: "local-dev"`.

Sample browser-API login flow:

```sh
curl -sS -X POST http://localhost:9001/api/v1/navigate \
  -H 'Content-Type: application/json' \
  -d '{"url":"http://localhost:5173/","mode":"hard"}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"click","role":"link","name":"Sign in","waitFor":{"selector":"#login-email","timeoutMs":5000}}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"fill","selector":"#login-email","value":"test@example.com"}' | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"click","role":"button","name":"Email me a 6-digit code","waitFor":{"selector":"#login-code","xhr":{"urlContains":"/api/auth/email/request-code","method":"POST","status":200},"timeoutMs":10000}}' | jq .
```

Get OTP from the local JSONL file, not email and not XHR:

```sh
otp=$(jq -r 'select(.email=="test@example.com") | .code' /tmp/wkdomains-dev-otp.jsonl | tail -n 1)
echo "$otp"
```

Submit OTP:

```sh
curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d "{\"type\":\"fill\",\"selector\":\"#login-code\",\"value\":\"$otp\"}" | jq .

curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"click","role":"button","name":"Sign in","waitFor":{"urlContains":"/dashboard","xhr":{"urlContains":"/api/auth/email/verify-code","method":"POST","status":200},"timeoutMs":10000}}' | jq .

curl -sS http://localhost:9001/api/v1/page | jq '{url,title,isLoading}'
```

Confirm verification:

```sh
curl -sS http://localhost:9001/api/v1/xhr \
  | jq '{requests:[.requests[] | select(.url|contains("/api/auth/email/verify-code")) | {method,url,status,jsonShape,responseBodyPreview,error}]}'
```

## Typical Fresh-Context Workflow

1. Read this file.
2. Check `../web` is up with `curl localhost:5173` and `curl localhost:8787`; start via `screen` if needed.
3. Check browser API with `curl localhost:9001/api/v1/page`.
4. If browser is not running, launch the latest debug app.
5. Use `/api/v1/navigate` to open `http://localhost:5173/`.
6. Use `/api/v1/snapshot`, `/api/v1/action`, `/api/v1/xhr`, and `/api/v1/element/@eN` for interaction and x-ray.
7. Use `/api/v1/qa/viewports` for responsive diagnostics.
8. Use `/api/v1/visual/compare` for screenshot reference checks.
9. If browser API blocks the task, implement the missing endpoint or reader, rebuild with Xcode, kill/relaunch app, and retry.
10. If the web app changes, Vite reloads automatically. Use `/tmp/wkdomains-web-dev.log` for worker/Vite logs.

## Safety And Notes

- Treat cookies, storage, OTPs, session tokens, and XHR body previews as sensitive.
- XHR `jsonShape` and `responseBodyPreview` redact common token/session keys but still review before sharing.
- `/api/v1/xhr` and `/api/v1/cookies` infer the current page host.
- The visible browser viewport affects `/api/v1/page`, `/api/v1/screenshot`, DOM rectangles, and action targeting.
- Offscreen captures use real WebKit and the same website data store.
- Navigation has a hard-load fallback for WebKit policy-handler hangs.
- Prefer source markers and x-ray over guessing file paths from UI text.
