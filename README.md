# wkdomains

wkdomains is a small macOS browser built for developers working with coding
tools like Codex, Claude Code, and similar agents.

The idea is simple: the human uses the browser normally, logs in normally, and
navigates to the page they care about. A coding tool can then inspect the same
page state over a local HTTP API. That lets the tool see what the human sees,
capture the current viewport, inspect browser-observed XHR/fetch traffic, and
use the same auth context to reproduce API calls.

This is intentionally much narrower than driving a site with Playwright. A
coding tool usually does not need to own the whole browser automation stack,
recreate a login flow, maintain selectors, wait on fragile UI states, or scrape
around the page to guess what matters. wkdomains exposes the specific developer
primitives the tool needs: the visible screenshot, the XHR/fetch calls, compact
JSON shapes, and the browser auth context needed to replay those calls. The
human stays in control of the browser, and the tool gets a clean API for the
useful state.

The local API currently runs on:

```sh
http://localhost:9001
```

## Screenshot the current page

Use `/api/v1/screenshot` to get a PNG of the currently rendered visible page:

```sh
curl http://localhost:9001/api/v1/screenshot --output - > foo.png
```

The screenshot is rendered from the active browser viewport. wkdomains keeps a
fresh screenshot in memory after pages load and after visible state changes. If
a fresh render is still in progress when the endpoint is called, the request
waits briefly so the PNG is usually ready by the time curl returns.

The toolbar has viewport buttons for:

- Desktop: the normal app viewport
- Mobile Large: 700px wide
- Mobile Small: 390px wide

Select a mobile viewport in the app, then run the same screenshot curl command.
The returned PNG will use that selected viewport width.

## Inspect XHR and fetch calls

Use `/api/v1/xhr/{hostname}` to see requests the browser observed for a host:

```sh
curl http://localhost:9001/api/v1/xhr/app.netlify.com | jq .
```

Example shape:

```json
{
  "activePageHost": "app.netlify.com",
  "activePageURL": "https://app.netlify.com/teams/example-team/projects",
  "hostname": "app.netlify.com",
  "requests": [
    {
      "kind": "fetch",
      "method": "GET",
      "url": "https://app.netlify.com/access-control/bb-api/api/v1/accounts/example-team",
      "status": 200,
      "responseBytes": 7331,
      "jsonType": "object",
      "jsonShape": "object{name:\"Example Team\",slug:\"example-team\",role:\"Owner\",capabilities:object<capabilities>[dev_servers,identity,analytics,+51 more],user_capabilities:object<crud permissions>[accounts,billing,builds,deploys,domains,+4 more],...}",
      "startedAt": "2026-05-02T22:56:25Z",
      "completedAt": "2026-05-02T22:56:26Z"
    },
    {
      "kind": "fetch",
      "method": "GET",
      "url": "https://app.netlify.com/access-control/bb-api/api/v1/example-team/sites?filter=all&sort_by=published_at&order_by=asc&page=1&per_page=25&include_favorites=true",
      "status": 200,
      "responseBytes": 4970,
      "jsonType": "array",
      "jsonItems": 1,
      "jsonShape": "array[1]<object{id,site_id,plan,ssl_plan,premium,claimed,name,custom_domain,+77 more}>",
      "startedAt": "2026-05-02T22:56:26Z",
      "completedAt": "2026-05-02T22:56:27Z"
    }
  ]
}
```

The useful part is `jsonShape`. It gives a compact description of the response
body without dumping the full response. That is enough for a coding agent to
understand which API calls exist, what they return, and which endpoint is likely
to contain the data it needs.

## Inspect cookies and browser storage

Use `/api/v1/cookies/{hostname}` to inspect cookies, localStorage, and
sessionStorage related to a host:

```sh
curl http://localhost:9001/api/v1/cookies/app.netlify.com | jq .
```

Example shape with sensitive values redacted:

```json
{
  "domain": "app.netlify.com",
  "cookies": [
    {
      "domain": ".netlify.com",
      "name": "_nf-auth",
      "value": "<redacted>",
      "isHTTPOnly": true,
      "isSecure": true,
      "sameSitePolicy": "strict",
      "expiresAt": "2026-05-23T21:33:20Z"
    },
    {
      "domain": "app.netlify.com",
      "name": "connect.sid",
      "value": "<redacted>",
      "isHTTPOnly": true,
      "isSecure": true
    }
  ],
  "localStorage": [
    {
      "origin": "https://app.netlify.com",
      "items": [
        {
          "key": "nf-session",
          "value": "{\"access_token\":\"<redacted>\"}"
        },
        {
          "key": "nf-team",
          "value": "example-team"
        }
      ]
    }
  ],
  "sessionStorage": [
    {
      "origin": "https://app.netlify.com",
      "items": [
        {
          "key": "routePath",
          "value": "/teams/:account_slug/projects"
        }
      ]
    }
  ]
}
```

This endpoint gives a coding tool the auth and session context needed to hit
the same XHR endpoints and retrieve full JSON directly. Treat the output as
sensitive. Cookie values, bearer tokens, session IDs, account IDs, and user IDs
should be redacted before sharing logs or examples.

## Workflow

1. Open wkdomains.
2. Navigate to the app or website you want to inspect.
3. Log in normally.
4. Use the local API from a coding tool or terminal:

```sh
curl http://localhost:9001/api/v1/screenshot --output - > foo.png
curl http://localhost:9001/api/v1/xhr/app.netlify.com | jq .
curl http://localhost:9001/api/v1/cookies/app.netlify.com | jq .
```

From there, the coding tool can compare the screenshot with the DOM/API state,
identify the relevant XHR calls, and replay authenticated API requests using
the same browser session.

## Roadmap

Future versions will add an MCP server and many more developer-agent features.
