# wkdomains

wkdomains is a macOS browser for developers working with coding agents like
Codex, Claude Code, and similar tools.

It gives the agent a clean view into the browser state the human is already
using: screenshots, observed XHR/fetch calls, compact JSON response shapes, and
the auth context needed to replay those same requests.

The goal is to make the browser a shared workbench. The human stays in control
of navigation, login, permissions, and intent. The coding agent gets structured
local APIs for the exact page the human is looking at.

## Why not just use Playwright?

Playwright is excellent when the agent needs to own the browser and automate a
repeatable workflow from scratch. That is not always what you want while
debugging or building against a real logged-in product.

A coding agent usually does not need the full browser automation stack. It does
not need to recreate your login flow, maintain fragile selectors, wait on UI
states, scrape the page to guess which data matters, or fight an app that
behaves differently under automation.

wkdomains takes a narrower approach:

- The human uses the browser normally.
- The app records the useful browser facts.
- The coding agent asks local endpoints for exactly what it needs.

That means the agent can see the current page, inspect the real network traffic,
understand response shapes, and replay authenticated API calls without turning
the whole task into a browser automation project.

## Local API

The local API currently runs on:

```sh
http://localhost:9001
```

You can change the API port in:

```sh
~/.config/wkdomains/settings.json
```

## Screenshot the current page

Use `/api/v1/screenshot` to get a PNG of the currently rendered visible page:

```sh
curl http://localhost:9001/api/v1/screenshot --output - > foo.png
```

The screenshot comes from the active browser viewport. wkdomains keeps a fresh
screenshot in memory after pages load and after visible state changes. If a
fresh render is still in progress when the endpoint is called, the request waits
briefly so the PNG is usually ready by the time curl returns.

The toolbar supports multiple viewport modes:

- Desktop: the normal app viewport
- Mobile Large: 700px wide
- Mobile Small: 390px wide

Select a mobile viewport in the app, then run the same screenshot curl command.
The returned PNG will use the selected viewport width.

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

The important field is `jsonShape`. It gives the agent a compact map of the
response body without dumping the full response. That is enough to identify
which API calls exist, what they return, and which endpoint is likely to contain
the data needed for the task.

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

## Inspect the agent view of the page

Screenshots and XHR are only part of what an agent needs. wkdomains also exposes
structured page context so a coding tool can understand the current URL,
visible UI, console output, links, forms, scripts, and machine-readable domain
resources.

### Current page

Use `/api/v1/page` for the browser's current page metadata:

```sh
curl http://localhost:9001/api/v1/page | jq .
```

Example shape:

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

This is the quick orientation endpoint: where the human is, which registrable
domain should be inspected, and what viewport the agent is seeing.

### Visible DOM

Use `/api/v1/dom` for a sanitized visible DOM summary:

```sh
curl http://localhost:9001/api/v1/dom | jq .
```

This is intentionally not raw HTML. It focuses on what an agent can act on:

- visible text
- headings
- buttons, links, inputs, selects, and textareas
- forms and fields
- tables and sample rows
- ARIA labels and roles
- important attributes like `id`, `data-testid`, `aria-expanded`, `disabled`,
  and `required`
- active element context
- element rectangles in the visible viewport

Example shape:

```json
{
  "url": "https://wkdomains.com/",
  "title": "wkdomains.com | Official bots for domains",
  "visibleText": "WK wkdomains Sign in OFFICIAL DOMAIN BOTS ...",
  "headings": [
    {
      "tag": "h1",
      "text": "Give your domain a bot that keeps watch.",
      "rect": { "x": 39, "y": 166, "width": 760, "height": 96 }
    }
  ],
  "controls": [
    {
      "tag": "button",
      "text": "Open navigation",
      "ariaLabel": "Open navigation",
      "importantAttributes": {
        "aria-expanded": "false"
      }
    }
  ],
  "links": [
    {
      "tag": "a",
      "text": "Claim your domain bot",
      "href": "https://wkdomains.com/login"
    }
  ],
  "forms": [],
  "tables": []
}
```

### Console messages

Use `/api/v1/console` for page-level console output captured inside WKWebView:

```sh
curl http://localhost:9001/api/v1/console | jq .
```

Example shape:

```json
{
  "activePageHost": "www.cnn.com",
  "activePageURL": "https://www.cnn.com/",
  "captureScope": "page JavaScript console calls, window errors, unhandled promise rejections, and CSP violations captured inside WKWebView; browser-engine DevTools diagnostics are not exposed by WKWebView",
  "capturedLevels": ["debug", "error", "info", "log", "warn"],
  "messages": [
    {
      "level": "warn",
      "message": "[GPT] Slot.setTargeting is deprecated...",
      "pageHost": "www.cnn.com",
      "pageURL": "https://www.cnn.com/",
      "createdAt": "2026-05-02T23:56:41Z"
    }
  ]
}
```

Quiet pages may legitimately return an empty `messages` array. Browser-engine
diagnostics from another browser, such as Firefox layout warnings, are not page
JavaScript console calls and are not exposed by WKWebView.

### Links, forms, and scripts

Use `/api/v1/links` to inspect important anchors, forms, scripts, and link tags:

```sh
curl http://localhost:9001/api/v1/links | jq .
```

Example shape:

```json
{
  "url": "https://dialtoneapp.com/",
  "anchors": [
    {
      "text": "Products",
      "href": "https://dialtoneapp.com/products"
    },
    {
      "text": "Run Free Scan",
      "href": "https://dialtoneapp.com/#free-scan"
    }
  ],
  "forms": [
    {
      "action": "https://dialtoneapp.com/",
      "method": "GET",
      "fields": [
        {
          "tag": "input",
          "type": "url",
          "placeholder": "example.com"
        }
      ]
    }
  ],
  "linkTags": [
    {
      "rel": "alternate",
      "type": "text/markdown",
      "href": "https://dialtoneapp.com/llms-full.txt"
    },
    {
      "rel": "agent",
      "href": "https://dialtoneapp.com/.well-known/agent.json"
    }
  ],
  "scripts": [
    {
      "src": "https://dialtoneapp.com/assets/index-CHgbgE8Y.js",
      "type": "module"
    }
  ]
}
```

This endpoint is useful when an agent needs to find navigation paths, discover
machine-readable alternates, understand form shape, or identify the JavaScript
bundle driving the current page.

### Domain resources

Use `/api/v1/resources` to discover common machine-readable files for the
current domain:

```sh
curl http://localhost:9001/api/v1/resources | jq .
```

wkdomains currently probes:

- `/llms.txt`
- `/llms-full.txt`
- `/openapi.json`
- `/swagger.json`
- `/sitemap.xml`
- `/robots.txt`
- `/.well-known/openapi.json`
- `/.well-known/agent-card.json`
- `/.well-known/ai-plugin.json`

Example shape:

```json
{
  "domain": "wkdomains.com",
  "pageHost": "wkdomains.com",
  "resources": [
    {
      "path": "/llms.txt",
      "status": 200,
      "found": true,
      "contentType": "text/plain",
      "sampledBytes": 8273
    },
    {
      "path": "/openapi.json",
      "status": 200,
      "found": true,
      "contentType": "application/json",
      "sampledBytes": 27591
    },
    {
      "path": "/.well-known/agent-card.json",
      "status": 200,
      "found": true,
      "contentType": "application/json",
      "sampledBytes": 2573
    }
  ]
}
```

Responses include a short `bodyPreview` for text, JSON, and XML resources so an
agent can quickly decide which discovered files matter without fetching every
full document immediately.

## Browser left, agent view right

The larger vision is that wkdomains becomes "what an agent sees" beside what
the human sees. The left side stays a normal browser. The right side is an
agent-native interpretation of the current page, domain, APIs, auth state,
network behavior, and integration affordances.

The memory-chip icon in the upper-right toolbar is the agent-view toggle. When
opened, the browser moves to 75% width and the right 25% becomes a black
terminal panel with green text. Today it starts the current `llms.txt` request.
The intended direction is for that terminal to become a live notebook of
wkdomains discovery events and MCP-agent insight. Tapping the memory-chip icon
again closes the terminal.

### Domain discovery

Whenever the human lands on a domain, wkdomains should automatically check the
likely agent and developer entry points:

- `/llms.txt`
- `/llms-full.txt`
- `/openapi.json`
- `/swagger.json`
- `/.well-known/openapi.json`
- `/.well-known/ai-plugin.json`
- `/.well-known/agent-card.json`
- `/sitemap.xml`
- `/robots.txt`

The terminal can then show a compact domain map:

```text
Domain: withone.ai
Found: llms.txt, sitemap.xml, markdown docs routes
API: api.withone.ai
Agent affordance: universal MCP, knowledge search API
```

### Agent insight loop

When the page or domain changes, the attached MCP agent should be asked to
synthesize a rolling agent view from the normalized data wkdomains already has:

- current URL, title, host, and viewport
- screenshot
- visible DOM summary
- recent XHR and response shapes
- cookies and auth shape
- discovered `llms.txt`, OpenAPI, sitemap, robots, and agent-card files
- console messages and browser-observed errors

The prompt is effectively:

```text
Here is the current URL, screenshot, DOM summary, recent XHR,
cookies/auth shape, discovered llms.txt, OpenAPI, and sitemap.
Explain what this domain offers to an agent and what actions are possible.
```

The terminal becomes a live notebook:

```text
Fetching llms.txt...
Found OpenAPI candidate...
Recent XHR suggests authenticated dashboard API...
This page appears to be a projects list.
Useful API endpoint: GET /teams/{slug}/sites
Agent-facing summary:
...
```

### MCP owns reasoning, wkdomains owns data

wkdomains should gather, sanitize, and normalize the browser data. The MCP
client should reason over it. That keeps the app valuable across different
agents and editors:

- Codex
- Claude Code
- Cursor
- other MCP clients later

Direct LLM API streaming can come later, but it should not be the first step.
It adds API keys, billing, model settings, and privacy questions. MCP keeps the
human's chosen coding agent as the brain while wkdomains stays the local
browser data source.

### Terminal event UX

The terminal should append structured events immediately, then add agent
summaries when they are ready:

```text
[page] https://www.withone.ai/
[discover] found /llms.txt
[discover] found /sitemap.xml
[xhr] 12 requests observed
[agent] This domain exposes an agent integration platform...
```

Even if MCP returns a final answer instead of token streaming, the terminal
still feels alive because wkdomains streams its own page, discovery, network,
and resource events as they happen.

## A better agent workflow

Typical flow:

1. Open wkdomains.
2. Navigate to the app or website you want to inspect.
3. Log in normally.
4. Use the local API from a coding tool or terminal:

```sh
curl http://localhost:9001/api/v1/screenshot --output - > foo.png
curl http://localhost:9001/api/v1/page | jq .
curl http://localhost:9001/api/v1/dom | jq .
curl http://localhost:9001/api/v1/links | jq .
curl http://localhost:9001/api/v1/console | jq .
curl http://localhost:9001/api/v1/resources | jq .
curl http://localhost:9001/api/v1/xhr/app.netlify.com | jq .
curl http://localhost:9001/api/v1/cookies/app.netlify.com | jq .
```

From there, the coding tool can compare the screenshot with the API state,
identify the relevant XHR calls, and replay authenticated requests using the
same browser session.

Instead of saying "look at this page" and hoping the agent can infer everything,
wkdomains gives the agent the same practical signals a developer would use:

- What is visible?
- What page, domain, and viewport is active?
- What links, controls, forms, tables, and ARIA labels are visible?
- Which API calls produced it?
- What shape is the JSON?
- Which console errors or warnings happened?
- Which `llms.txt`, OpenAPI, sitemap, robots, or agent-card resources exist?
- Which authenticated request should be replayed?
- Does the issue happen in mobile viewports too?

## Future MCP ideas

wkdomains already exposes a small MCP bridge for the current human request
flow. Future versions should expand it so coding agents can use wkdomains as a
live browser context without asking the human to paste screenshots, cookies,
network logs, or copied JSON.

The most interesting direction is a real human-agent loop.

Imagine right-clicking a button, table row, chart, error message, or confusing
piece of UI and choosing "Ask coding agent". wkdomains could package the current
URL, viewport, screenshot, screenshot crop, element text, accessibility info,
nearby DOM, recent XHR calls, console errors, and auth shape into one pending
MCP request. The agent could notice it, investigate, and reply back into the
browser.

That makes the browser interactive for both sides:

- Human: "Why is this button disabled?"
- Agent: checks the element state, failed API calls, permissions response, and
  answers in the browser.
- Human: "Where does this number come from?"
- Agent: maps the visible text to the XHR response that produced it.
- Human: "Make this section work on mobile."
- Agent: captures desktop, mobile-large, and mobile-small screenshots, then
  edits the app and verifies the layout.
- Agent: "Please log in and navigate to billing."
- Human: does it and clicks "Done".
- Agent: continues using the live authenticated browser state.

Possible MCP tools:

- `get_current_screenshot`: inspect the exact rendered page the human sees.
- `list_xhr`: list important browser-observed API calls with `jsonShape`
  summaries.
- `replay_xhr`: rerun a selected authenticated request and inspect the full JSON
  response.
- `find_api_for_visible_text`: connect a visible label, table value, or error
  message to the API response that produced it.
- `compare_viewports`: capture desktop, mobile-large, and mobile-small
  screenshots to find responsive layout bugs.
- `watch_page_changes`: notify the agent when navigation, new XHR calls, or
  visible renders happen.
- `extract_auth_context`: provide the minimum cookies, headers, and storage
  values needed to reproduce a request, with sensitive values clearly marked.
- `debug_failed_state`: package screenshot, recent XHR failures, console errors,
  URL, viewport, and auth shape into one debugging bundle.
- `generate_curl_for_request`: turn a browser-observed XHR into a sanitized curl
  command the developer can run and edit.
- `verify_fix`: reload the page after a code change, inspect screenshots and
  XHR, and confirm the UI state changed as expected.
- `get_human_requests`: let the agent poll for right-click questions or toolbar
  requests created by the human.
- `reply_to_human_request`: let the agent answer inside wkdomains instead of
  forcing the conversation back into a terminal.
- `highlight_page_region`: let the agent point to the exact part of the page it
  is talking about.
- `request_human_action`: let the agent ask the human to log in, navigate,
  approve replaying a sensitive request, or perform a step that should remain
  human-controlled.

The long-term goal is for a coding agent to work with web apps the way a human
developer does: see the screen, understand the network traffic behind it, ask
for help when it needs human action, and use the browser's real authenticated
state when deeper data is needed.
