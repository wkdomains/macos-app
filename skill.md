---
name: wkdomains-local-browser-api
description: Use wkdomains local browser-state endpoints to inspect the currently visible page, DOM, resources, XHR/fetch activity, cookies, storage, and screenshot from localhost:9001.
---

# wkdomains Local Browser API

Use this when you need live context from the page currently open in wkdomains.
The API is local-only and reflects the active browser tab/page.

Base URL:

```sh
http://localhost:9001
```

## Quick Commands

```sh
curl http://localhost:9001/api/v1/screenshot --output - > foo.png
curl http://localhost:9001/api/v1/page | jq .
curl http://localhost:9001/api/v1/dom | jq .
curl http://localhost:9001/api/v1/resources | jq .
curl http://localhost:9001/api/v1/xhr | jq .
curl http://localhost:9001/api/v1/cookies | jq .
```

## Endpoint Use

- `/api/v1/page`: Start here. Gets current URL, title, host, registrable domain, origin, viewport, loading state, and navigation state.
- `/api/v1/dom`: Use for visible page structure, text, controls, forms, tables, ARIA labels, and element rectangles. This is the main endpoint for deciding what is on screen.
- `/api/v1/resources`: Use to discover domain-level machine-readable files and common API descriptors such as `llms.txt`, OpenAPI files, sitemaps, robots, and related resources.
- `/api/v1/xhr`: Use after interacting with the page or waiting for load. Lists observed XHR/fetch requests for the current page host, including method, URL, status, size, and `jsonShape`.
- `/api/v1/cookies`: Use only when authenticated browser context is needed. Returns cookies plus localStorage and sessionStorage for the current page host. Treat as sensitive.
- `/api/v1/screenshot`: Use when visual layout, images, canvas, or rendered state matters. Writes the current visible viewport PNG.

## Workflow

1. Call `/api/v1/page` to confirm the active page and host.
2. Call `/api/v1/dom` to understand the visible UI and available actions.
3. Call `/api/v1/resources` when looking for domain documentation or API discovery files.
4. Call `/api/v1/xhr` to identify browser-observed API calls and useful JSON shapes.
5. Call `/api/v1/cookies` only if replaying authenticated requests requires browser session data.
6. Capture `/api/v1/screenshot` when the rendered view matters or DOM text is not enough.

## Notes

- `/api/v1/xhr` and `/api/v1/cookies` infer the host from the current page. Do not append a hostname path segment.
- The selected wkdomains viewport affects `/api/v1/screenshot`, `/api/v1/page`, and DOM element rectangles.
- Redact cookie values, bearer tokens, session IDs, account IDs, and user IDs before sharing output.
