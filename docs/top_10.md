# Top 10 Ideas To Borrow From Agent Browsers

wkdomains should stay a human-controlled inspection browser. The best ideas from
Aslan, Lightpanda, Nook, BrowserOS, PinchTab, Playwriter, dev-browser, and the
larger agent frameworks are the ones that make the human's current page more
legible, controllable, and safe for an attached coding agent.

## 1. Ref-based interactive snapshots

Borrow from Aslan, agent-browser, PinchTab, Lightpanda, and Playwriter.

Add an agent-facing snapshot endpoint that gives stable refs for the visible
interactive page surface:

```text
@e12 button "Save"
@e13 textbox "Email" value="a***@example.com"
@e14 link "Billing" href="/settings/billing"
```

This should not replace `/dom`; it should be a smaller "what can the agent act
or reason about?" view. The current visible DOM summary is useful for debugging,
but refs let the agent and human talk about exact UI elements.

## 2. Snapshot diffs after page changes

Borrow from PinchTab and agent-browser.

Add a change-aware endpoint that returns only what changed since the last
snapshot:

```text
GET /api/v1/snapshot?filter=interactive
GET /api/v1/snapshot?diff=true
```

This is a major token saver for the watcher loop. When the human clicks a tab,
opens a menu, logs in, or triggers an XHR, the agent should not reread the whole
page if only five elements changed.

## 3. Browser-side "observe" bundles

Borrow from Stagehand, Browser Use, Skyvern, and Nook.

Expose one high-level context bundle that packages the current page into the
shape an agent actually needs:

- URL, title, host, viewport
- screenshot metadata
- interactive snapshot
- recent console errors
- recent XHR/fetch summaries
- discovered domain files
- auth/cookie shape without secret values

This can become:

```text
GET /api/v1/observe
```

The watcher agent should be able to call one endpoint before answering the human.

## 4. Human-approved action tools

Borrow from Aslan, BrowserOS, Nook, and Playwriter, but keep wkdomains safer.

wkdomains does not need full autonomous browsing first. It should add a small
set of optional action requests that require human approval in the browser UI:

- highlight `@eN`
- click `@eN`
- fill `@eN` with a proposed value
- scroll to `@eN`
- replay XHR `n`

The agent proposes an action, wkdomains shows it in the right-side terminal, and
the human approves or rejects. This preserves the product's human-in-loop model
while still letting the agent help with repetitive page operations.

## 5. Learn-from-human recording

Borrow from Aslan learn mode, BrowserOS workflows, Stagehand caching, and
Skyvern workflows.

Add a recording mode where wkdomains observes the human's sequence:

- navigations
- clicks
- form edits
- XHRs triggered by each action
- screenshots after each step
- optional human notes

The output should be a playbook draft, not an auto-run bot:

```json
{
  "name": "create-staging-user",
  "steps": [
    {"humanAction": "click", "target": "@e5", "label": "Users"},
    {"humanAction": "fill", "target": "@e9", "label": "Email"}
  ]
}
```

This helps an agent understand app-specific workflows without guessing.

## 6. MCP server as a first-class control surface

Borrow from BrowserOS, Lightpanda, PinchTab, Playwriter, and Nook.

wkdomains already has MCP human-request tools. Add page-inspection tools directly
to MCP so the watcher agent does not need to mix MCP with curl:

- `get_current_snapshot`
- `get_current_screenshot`
- `list_xhr`
- `get_xhr`
- `get_console`
- `get_domain_discovery`
- `highlight_element`
- `request_human_action`

Keep the existing local HTTP API. MCP should be the ergonomic agent interface;
HTTP should remain the simple debugging and scripting interface.

## 7. Safe local security posture

Borrow from PinchTab.

Make the local security model explicit and visible:

- bind to `127.0.0.1` by default
- show API/MCP status in the UI
- warn if any privileged endpoint is enabled
- separate read-only endpoints from action endpoints
- gate cookies, storage export, XHR replay, and JS eval behind explicit toggles
- never expose the service to the public internet by accident

PinchTab's clearest lesson is not a feature; it is the discipline of treating
browser control as a privileged local operator surface.

## 8. Real-browser session reuse without automation smell

Borrow from Playwriter, Camoufox, Browser Use, and agent-browser.

wkdomains' advantage is the real human session: logged in, normal extensions,
normal cookies, normal browsing. Lean into that:

- make it obvious when the agent is only observing
- keep action proposals separate from direct automation
- never force private/incognito state for agent access
- expose profile/session metadata without secret values
- let the human disconnect the agent immediately

Do not chase anti-detect like Camoufox unless there is a specific legitimate
testing need. The useful idea is that the agent should work with a normal browser
state instead of a sterile automation profile.

## 9. Agent-facing browser terminal upgrades

Borrow from BrowserOS, Nook, agent-browser, and dev-browser.

The right-side terminal should become an agent cockpit for the current domain:

- live request status from the watcher
- clickable refs from the latest snapshot
- "ask about this element" from page selection
- "send current context to agent"
- "copy observe bundle"
- "open relevant domain files"
- progress messages for long investigations

This keeps wkdomains differentiated: the agent conversation is attached to the
page the human is actually viewing.

## 10. Optional engine adapters, not engine replacement

Borrow from agent-browser and Lightpanda.

Do not replace WKWebView. Add optional bridge points for other engines when they
are better suited:

- Lightpanda for cheap markdown/link extraction on unauthenticated public pages
- Playwright/Chrome for cross-browser verification
- Camoufox only for controlled anti-bot testing where policy allows it
- Browser Use or Stagehand for high-level autonomous workflows outside wkdomains

wkdomains should remain the canonical human-visible WebKit state. Other engines
can be sidecars that compare, crawl, or verify.

## Priority Order

1. Interactive snapshot with refs
2. MCP page-inspection tools
3. Observe bundle
4. Snapshot diffs
5. Security posture UI and endpoint gates
6. Agent terminal upgrades
7. Human-approved action proposals
8. Learn-from-human recording
9. Session/profile visibility
10. Optional external engine adapters

The main product rule: borrow the agent-native interfaces, not the full platform
complexity. wkdomains should make the human's live browser state radically easier
for agents to understand and discuss.

## Repos Reviewed

Native macOS/WebKit browser projects:

- [aslan-browser](https://github.com/aaos/aslan-browser) — local WKWebView browser
  control over Unix socket JSON-RPC with Python SDK.
- [nook-browser/nook](https://github.com/nook-browser/nook) — native macOS
  browser with built-in AI tools and MCP client support.
- [the-ora/browser](https://github.com/the-ora/browser) — native macOS WebKit
  browser foundation with privacy/content-blocking work.
- [PetarRan/bowl](https://github.com/PetarRan/bowl) — minimal hackable
  developer browser with overlay and plugin API.
- [MrBlankCoding/Illuminate](https://github.com/MrBlankCoding/Illuminate) —
  early Arc/Zen-style macOS WebKit browser.
- [revblaze/WiBlaze](https://github.com/revblaze/WiBlaze) — older iOS
  WKWebView browser.
- [nuance-dev/Web](https://github.com/nuance-dev/Web) — experimental macOS
  WebKit AI browser with local MLX model support.

Headless engines, browser control planes, and browser APIs:

- [lightpanda-io/browser](https://github.com/lightpanda-io/browser) — Zig
  headless browser engine with CDP and native MCP.
- [daijro/camoufox](https://github.com/daijro/camoufox) — anti-detect Firefox
  fork with Playwright compatibility.
- [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser) —
  Rust browser automation CLI for AI agents.
- [steel-dev/steel-browser](https://github.com/steel-dev/steel-browser) —
  open-source browser API and Chrome session infrastructure.
- [pinchtab/pinchtab](https://github.com/pinchtab/pinchtab) — local-first Go
  HTTP control plane for Chrome.
- [remorses/playwriter](https://github.com/remorses/playwriter) — Chrome
  extension plus CLI/MCP bridge exposing Playwright/CDP against the user's
  existing browser.
- [SawyerHood/dev-browser](https://github.com/SawyerHood/dev-browser) —
  sandboxed Playwright scripting CLI for agents.

Agent frameworks and full agentic browsers:

- [browserbase/stagehand](https://github.com/browserbase/stagehand) — AI
  browser automation framework combining Playwright code and natural language.
- [browser-use/browser-use](https://github.com/browser-use/browser-use) —
  Python browser-agent framework and cloud offering.
- [skyvern-ai/skyvern](https://github.com/skyvern-ai/skyvern) — LLM and
  computer-vision workflow automation platform.
- [browseros-ai/BrowserOS](https://github.com/browseros-ai/BrowserOS) —
  agentic Chromium fork with MCP, workflows, local model options, and browser UI.
