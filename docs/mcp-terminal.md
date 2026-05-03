# MCP And Browser Terminal

wkdomains includes an MCP bridge so an attached coding agent can answer
questions from the browser terminal.

## Current MCP tools

- `get_current_page`: return the current browser URL and host.
- `get_human_requests`: return pending browser-terminal requests.
- `wait_for_human_request`: long-poll until a browser-terminal request appears
  or the timeout expires.
- `reply_to_human_request`: send a reply back into the wkdomains terminal.

## Why long-poll?

`get_human_requests` is normal polling:

```text
agent asks: any requests?
wkdomains answers: yes/no
agent has to ask again later
```

`wait_for_human_request` is long-polling:

```text
agent asks: wait until the human asks something
wkdomains holds the MCP tool call open
human types in the terminal
wkdomains returns immediately
agent replies
agent calls wait_for_human_request again
```

This is still request/response MCP, but it feels like a stream because the agent
is parked on the tool call. There is no tight polling loop.

## Recommended setup: two agent sessions

Run two agent sessions:

1. Main coding session: normal repo work, planning, implementation, review.
2. Browser watcher session: dedicated to the wkdomains terminal.

In the watcher session, use a prompt like:

```text
Watch wkdomains terminal. Use the wkdomains MCP server. Call
wait_for_human_request, answer the request, send the reply with
reply_to_human_request, then immediately wait again. Keep doing this until I
tell you to stop.
```

Then the human can type into wkdomains instead of returning to the main terminal:

```text
Human: What API powers this table?
Agent: This table appears to come from GET /teams/{slug}/sites...
```

The main coding session stays free for normal work while the watcher session
acts like the agent attached to the browser.

## What the terminal sends

When the human types in the terminal, wkdomains creates a pending MCP request
with:

- the human's message
- current URL
- title
- page host
- registrable domain
- viewport mode
- observed XHR count
- suggested local endpoints to inspect:
  - `/api/v1/page`
  - `/api/v1/dom`
  - `/api/v1/links`
  - `/api/v1/console`
  - `/api/v1/resources`
  - `/api/v1/screenshot`
  - `/api/v1/xhr/{host}`
  - `/api/v1/cookies/{host}`

The watcher agent can use those endpoints, reason over the context, and reply
with `reply_to_human_request`.

## Why not direct LLM API streaming?

Direct LLM API streaming would make wkdomains itself call OpenAI, Anthropic, or
another model provider. That would require:

- API keys
- billing/account ownership
- model selection
- prompt and context budgeting
- rate limits and error handling
- privacy decisions around browser data

The MCP-first approach keeps wkdomains as the local browser/context provider.
The human's chosen coding agent remains the brain.

Direct API streaming can still become an optional built-in brain later, but it
should not be required for the main workflow.

## Future watcher daemon

The productized version of the watcher session is a small local helper or daemon
that keeps the MCP wait loop alive:

```text
connect to wkdomains MCP
wait_for_human_request
forward request to an agent
reply_to_human_request
repeat
```

That could make wkdomains feel always-on without tying the behavior to a chat
turn. The helper still needs a brain: either a running agent CLI or a direct LLM
API integration.
