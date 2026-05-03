# Product Vision

wkdomains is a normal browser for the human and an agent-native browser context
for coding tools.

The human sees the website. The agent sees the current page, domain discovery
files, visible UI, network behavior, auth shape, console messages, and API
affordances.

## Browser left, agent view right

The memory-chip icon in the upper-right toolbar opens the agent terminal. The
browser moves to 75% width and the right 25% becomes a black terminal panel.

The terminal should feel alive even before an LLM responds. wkdomains can stream
its own events immediately:

```text
Loading llms.txt...
Loading openapi.json...
Loading sitemap.xml...
Discovery complete.
```

Then it can show a compact summary:

```text
Domain: withone.ai
Found: llms.txt, sitemap.xml, markdown docs routes
API: api.withone.ai
Agent affordance: universal MCP, knowledge search API
```

## Domain discovery

Whenever the human lands on a domain, wkdomains should automatically inspect
likely agent/developer entry points:

- `/llms.txt`
- `/llms-full.txt`
- `/openapi.json`
- `/swagger.json`
- `/.well-known/openapi.json`
- `/.well-known/ai-plugin.json`
- `/.well-known/agent-card.json`
- `/sitemap.xml`
- `/robots.txt`

This gives the agent a domain map before it starts guessing from the visual UI.

## Agent insight loop

When the page or domain changes, the attached MCP agent should be able to
synthesize a rolling agent view from:

- current URL, title, host, and viewport
- screenshot
- visible DOM summary
- links, forms, scripts, and link tags
- recent XHR and response shapes
- cookies and auth shape
- discovered `llms.txt`, OpenAPI, sitemap, robots, and agent-card files
- console messages and page errors

The working prompt is:

```text
Here is the current URL, screenshot, DOM summary, recent XHR,
cookies/auth shape, discovered llms.txt, OpenAPI, and sitemap.
Explain what this domain offers to an agent and what actions are possible.
```

## Data ownership

wkdomains should gather, sanitize, and normalize browser data. The MCP client
should reason over it.

That keeps the app useful with different agents:

- Codex
- Claude Code
- Cursor
- other MCP clients later

It also avoids forcing wkdomains to own LLM keys, billing, model routing, and
browser-data privacy policy from day one.

## Human-agent loop ideas

The important product loop is not just "agent inspects page." It is "human and
agent share the same browser state."

Examples:

- Human: "Why is this button disabled?"
- Agent: checks visible DOM, permissions XHR, console errors, and replies in the
  browser.
- Human: "Where does this number come from?"
- Agent: maps visible text to the XHR response that produced it.
- Human: "Make this section work on mobile."
- Agent: captures desktop, mobile-large, and mobile-small screenshots, edits the
  app, then verifies layout.
- Agent: "Please log in and navigate to billing."
- Human: does it in the browser and types "done."
- Agent: continues using the live authenticated browser state.

## Future MCP tools

Possible future tools:

- `get_current_screenshot`: inspect the exact rendered page.
- `list_xhr`: list browser-observed API calls with `jsonShape` summaries.
- `replay_xhr`: rerun a selected authenticated request and inspect full JSON.
- `find_api_for_visible_text`: connect a visible label, table value, or error to
  the API response that produced it.
- `compare_viewports`: capture desktop, mobile-large, and mobile-small
  screenshots.
- `watch_page_changes`: notify the agent when navigation, XHR, or visible render
  state changes.
- `extract_auth_context`: provide minimum cookies, headers, and storage values
  needed to reproduce a request, with sensitive values marked.
- `debug_failed_state`: package screenshot, recent XHR failures, console errors,
  URL, viewport, and auth shape into one bundle.
- `highlight_page_region`: let the agent point to the exact page region it is
  talking about.
- `request_human_action`: let the agent ask the human to log in, navigate, or
  approve replaying a sensitive request.

The long-term goal is for coding agents to work with web apps the way human
developers do: see the screen, understand the network traffic behind it, ask for
human help when needed, and use the browser's real authenticated state when
deeper data is required.
