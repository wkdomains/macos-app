# Local API

wkdomains exposes a local HTTP API for the currently visible browser state.

Default base URL:

```sh
http://localhost:9001
```

The port can be changed in:

```sh
~/.config/wkdomains/settings.json
```

## Screenshot

Get a PNG of the currently rendered visible page:

```sh
curl http://localhost:9001/api/v1/screenshot --output - > foo.png
```

The screenshot uses the selected viewport mode:

- Desktop: normal app viewport
- Mobile Large: 700px wide
- Mobile Small: 390px wide

wkdomains keeps a fresh screenshot in memory after pages load and after visible
state changes. If a fresh render is still in progress, the request waits briefly.

## Page

```sh
curl http://localhost:9001/api/v1/page | jq .
```

Returns the current URL, title, host, registrable domain, origin, viewport mode,
viewport size, loading state, and back/forward state.

Example:

```json
{
  "url": "https://wkdomains.com/",
  "title": "wkdomains.com | Official bots for domains",
  "host": "wkdomains.com",
  "domain": "wkdomains.com",
  "origin": "https://wkdomains.com",
  "viewportMode": "desktop",
  "viewportWidth": 964,
  "viewportHeight": 671,
  "isLoading": false
}
```

## Visible DOM

```sh
curl http://localhost:9001/api/v1/dom | jq .
```

This is not raw HTML. It is a sanitized agent-facing summary focused on:

- visible text
- headings
- buttons, links, inputs, selects, and textareas
- forms and fields
- tables and sample rows
- ARIA labels and roles
- important attributes such as `id`, `data-testid`, `aria-expanded`,
  `disabled`, and `required`
- active element context
- element rectangles in the visible viewport

## Links, forms, and scripts

```sh
curl http://localhost:9001/api/v1/links | jq .
```

Returns important anchors, forms, scripts, and link tags. This helps an agent
find navigation paths, machine-readable alternates, form shape, and the
JavaScript bundle driving the page.

## Console

```sh
curl http://localhost:9001/api/v1/console | jq .
```

Captures page JavaScript console calls, window errors, unhandled promise
rejections, and CSP violations inside WKWebView.

Quiet pages may return an empty `messages` array. Browser-engine diagnostics
from other browsers, such as Firefox layout warnings, are not page JavaScript
console calls and are not exposed by WKWebView.

## Domain resources

```sh
curl http://localhost:9001/api/v1/resources | jq .
```

Probes common machine-readable files for the current domain:

- `/llms.txt`
- `/llms-full.txt`
- `/openapi.json`
- `/swagger.json`
- `/.well-known/openapi.json`
- `/.well-known/ai-plugin.json`
- `/.well-known/agent-card.json`
- `/sitemap.xml`
- `/robots.txt`

Responses include status, content type, sampled byte count, and a short
`bodyPreview` for text, JSON, and XML resources.

## Dark Reader status

```sh
curl http://localhost:9001/api/v1/dark-reader | jq .
```

Returns Dark Reader WebExtension diagnostics for the current page:

- `extension.enabled`: whether wkdomains tried to enable Dark Reader
- `extension.loaded`: whether the WebExtension context loaded successfully
- `extension.globalDarkSetting`: the `dark` setting from `settings.json`
- `extension.disabledSites`: hosts excluded with the context menu
- `darkReader.styleCount`: Dark Reader styles currently present in the page
- `darkReader.documentClasses`: Dark Reader classes on the document element

## XHR and fetch calls

```sh
curl http://localhost:9001/api/v1/xhr | jq .
```

Returns browser-observed XHR/fetch calls for the current page host. The key
field is `jsonShape`, a compact, redacted map of the response body that helps
identify useful API endpoints without dumping full JSON.

Example shape:

```json
{
  "activePageHost": "app.netlify.com",
  "hostname": "app.netlify.com",
  "requests": [
    {
      "kind": "fetch",
      "method": "GET",
      "url": "https://app.netlify.com/api/example",
      "status": 200,
      "responseBytes": 4970,
      "jsonType": "array",
      "jsonItems": 1,
      "jsonShape": "array[1]<object{id,name,created_at,updated_at,+12 more}>"
    }
  ]
}
```

Action waits can also watch for fresh XHR/fetch activity triggered by the
action. A matching request must start after the action begins, which prevents an
old request from satisfying the wait.

```sh
curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"click","role":"button","name":"Email me a 6-digit code","waitFor":{"selector":"#login-code","xhr":{"urlContains":"/api/auth/email/request-code","method":"POST","status":200},"timeoutMs":10000}}' | jq .
```

Supported XHR wait fields:

- `urlContains`
- `method`
- `status`
- `completed`
- `responseBodyContains`
- `jsonShapeContains`

The same fields can be supplied as shorthands on `waitFor`:
`xhrURLContains`, `xhrUrlContains`, `xhrMethod`, `xhrStatus`,
`xhrCompleted`, `xhrResponseBodyContains`, and `xhrJsonShapeContains`.

## Cookies and browser storage

```sh
curl http://localhost:9001/api/v1/cookies | jq .
```

Returns matching cookies, localStorage, and sessionStorage for the current page
host.

This endpoint gives a coding tool the auth/session context needed to replay the
same XHR endpoints and retrieve full JSON directly. Treat this output as
sensitive. Redact cookie values, bearer tokens, session IDs, account IDs, and
user IDs before sharing logs or examples.

## Action

```sh
curl -sS -X POST http://localhost:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"click","role":"link","name":"Sign in","waitFor":{"selector":"#login-email","timeoutMs":5000}}' | jq .
```

Actions drive the visible WebKit browser. Supported action types are `click`,
`fill`, `clear`, `select`, `submit`, `press`, and `focus`.

Targets can be a current `ref`, CSS `selector`, accessible `name`, visible
`text`, `role`, or active element for key presses. `name` checks the
accessibility label first and falls back to visible text/title/placeholder.
Prefer `role` plus `name` for controls when possible because it matches how a
user and assistive technology find the element. Set `exact:false` to use
contains matching instead of exact matching.

Useful wait fields are `url`, `urlContains`, `titleContains`, `readyState`,
`text`, `textIncludes`, `selector`, `selectorGone`, `visible`, `xhr`, and
`timeoutMs`.

## Viewport QA

```sh
curl -sS -X POST http://localhost:9001/api/v1/qa/viewports \
  -H 'Content-Type: application/json' \
  -d '{"url":"http://localhost:5173/","includeScreenshot":false}' | jq .
```

The default viewport set is `390x844`, `768x1024`, `1280x800`, and
`1440x900`. Each result includes page, DOM, layout, console, and optional
screenshot diagnostics.

## Element x-ray and source hints

```sh
curl -sS http://localhost:9001/api/v1/snapshot | jq .
curl -sS http://localhost:9001/api/v1/element/@e8 | jq .
```

Element x-ray returns computed style, box model, accessibility state, selector
hints, parent context, contrast diagnostics, and `sourceHint` when dev source
metadata is available.

## Visual compare

```sh
curl -sS -X POST http://localhost:9001/api/v1/visual/compare \
  -H 'Content-Type: application/json' \
  -d '{"referenceUrl":"http://localhost:5173/","currentUrl":"http://localhost:5173/dashboard","width":390,"height":844,"threshold":8}' | jq .
```

The response includes changed-pixel metrics and screenshot endpoints for the
current, reference, and diff images.
