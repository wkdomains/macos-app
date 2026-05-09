# wkdomains

wkdomains is a macOS browser for developers working with coding agents like
Codex, Claude Code, Cursor, and similar tools.

It lets the human browse normally while an agent gets structured local access to
the same page: screenshot, URL, viewport, visible DOM, links, forms, console
messages, XHR/fetch shapes, cookies/storage, and discovered domain files such as
`llms.txt`, OpenAPI, sitemap, robots, and agent cards.

The core idea: the human sees the website on the left; the agent sees the
machine-readable browser and domain context on the right.

## Why not just use Playwright?

Playwright is excellent when the agent owns the browser and automates a repeatable
flow from scratch. wkdomains is for the other case: the human is already logged
in, already looking at the real page, and wants the coding agent to understand
that exact state without rebuilding the login flow or guessing from screenshots.

wkdomains keeps the browser human-controlled and exposes focused local endpoints
for the agent:

- current page and viewport
- visible UI and accessibility context
- screenshots
- XHR/fetch requests and compact `jsonShape` summaries
- cookies, localStorage, and sessionStorage for replaying authenticated requests
- domain discovery files for agent/developer entry points
- a browser terminal backed by MCP human requests

## Quick start

The local API runs on:

```sh
http://localhost:9001
```

Change the port in:

```sh
~/.config/wkdomains/settings.json
```

Examples:

```sh
curl http://localhost:9001/api/v1/screenshot --output - > foo.png
curl http://localhost:9001/api/v1/page | jq .
curl http://localhost:9001/api/v1/dom | jq .
curl http://localhost:9001/api/v1/links | jq .
curl http://localhost:9001/api/v1/console | jq .
curl http://localhost:9001/api/v1/resources | jq .
curl http://localhost:9001/api/v1/xhr | jq .
curl http://localhost:9001/api/v1/cookies | jq .
```

The toolbar supports three viewport modes:

- Desktop: the normal app viewport
- Mobile Large: 700px wide
- Mobile Small: 390px wide

Selecting a mobile viewport changes what `/api/v1/screenshot`, `/api/v1/page`,
and the visible DOM describe.

## Optional Dark Reader support

wkdomains can use Dark Reader as a bundled WebExtension for dark mode. This is
optional: the app still builds and runs without it, but Dark Reader support is
only available when the generated extension folder is present.

Set it up next to this repo:

```sh
cd ..
git clone https://github.com/darkreader/darkreader.git
cd darkreader
npm install
npm run build -- --chrome-mv3
cd ../macos-app
rm -rf DarkReaderWebExtension
ditto ../darkreader/build/release/chrome-mv3 DarkReaderWebExtension
```

`DarkReaderWebExtension/` is gitignored and copied into the app bundle by
Xcode. Re-run the final `ditto` command whenever you rebuild or update Dark
Reader.

Dark mode is controlled by the `dark` setting:

```json
{
  "dark": true
}
```

That setting lives in:

```sh
~/.config/wkdomains/settings.json
```

When `dark` is `true` and `DarkReaderWebExtension/` exists, wkdomains loads the
Dark Reader WebExtension. When `dark` is `false`, no dark-mode extension is
loaded. The right-click "Exclude from Dark" item stores the current host in
`darkDisabledSites` and reloads the page with Dark Reader access denied for that
site.

You can verify what is active on the current page with:

```sh
curl http://localhost:9001/api/v1/dark-reader | jq .
```

## Agent terminal

The memory-chip icon in the upper-right toolbar opens the agent terminal. The
browser moves to 75% width and the right 25% becomes a black terminal panel.

When opened, wkdomains automatically checks likely agent/developer entry points:

- `/llms.txt`
- `/llms-full.txt`
- `/openapi.json`
- `/swagger.json`
- `/.well-known/openapi.json`
- `/.well-known/ai-plugin.json`
- `/.well-known/agent-card.json`
- `/sitemap.xml`
- `/robots.txt`

After discovery, the terminal input focuses automatically so the human can ask
page-aware questions such as:

```text
What API powers this table?
Is there pricing info?
Why is this button disabled?
What actions could an agent take on this domain?
```

Those questions become MCP human requests. A connected agent can answer them
inside wkdomains instead of forcing the human back to a separate terminal.

## Recommended MCP workflow

Use two agent sessions:

1. Normal coding chat: keep using Codex or Claude Code for implementation,
   architecture, and repo work.
2. wkdomains watcher: run a second agent session dedicated to the browser
   terminal.

In the watcher session, say:

```text
Watch wkdomains terminal. Use the wkdomains MCP server. Call
wait_for_human_request, answer the request, send the reply with
reply_to_human_request, then immediately wait again. Keep doing this until I
tell you to stop.
```

Then the browser terminal can drive the loop:

```text
human types in wkdomains
watcher agent wakes up
watcher inspects page/dom/xhr/resources as needed
watcher replies into wkdomains
```

This keeps wkdomains MCP-first. The app gathers and normalizes browser data; the
human's chosen coding agent remains the brain. No OpenAI or Anthropic API key is
needed inside wkdomains.

## Docs

- [Local API](docs/local-api.md)
- [MCP and browser terminal](docs/mcp-terminal.md)
- [Product vision](docs/vision.md)

## Repository status

wkdomains is early and experimental. The current focus is making the human's
live browser state usable by coding agents, then turning the right-side terminal
into an agent-native view of each domain.
