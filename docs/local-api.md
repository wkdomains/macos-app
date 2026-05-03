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

## XHR and fetch calls

```sh
curl http://localhost:9001/api/v1/xhr | jq .
```

Returns browser-observed XHR/fetch calls for the current page host. The key
field is `jsonShape`, a compact map of the response body that helps identify
useful API endpoints without dumping full JSON.

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
