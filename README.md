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

## A better agent workflow

Typical flow:

1. Open wkdomains.
2. Navigate to the app or website you want to inspect.
3. Log in normally.
4. Use the local API from a coding tool or terminal:

```sh
curl http://localhost:9001/api/v1/screenshot --output - > foo.png
curl http://localhost:9001/api/v1/xhr/app.netlify.com | jq .
curl http://localhost:9001/api/v1/cookies/app.netlify.com | jq .
```

From there, the coding tool can compare the screenshot with the API state,
identify the relevant XHR calls, and replay authenticated requests using the
same browser session.

Instead of saying "look at this page" and hoping the agent can infer everything,
wkdomains gives the agent the same practical signals a developer would use:

- What is visible?
- Which API calls produced it?
- What shape is the JSON?
- Which authenticated request should be replayed?
- Does the issue happen in mobile viewports too?

## Future MCP ideas

Future versions will add an MCP server so coding agents can use wkdomains as a
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
