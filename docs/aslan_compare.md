High-Level Split

  aslan-browser is better as an agent-controlled automation browser.
  wkdomains/macos-app is better as a human-controlled inspection browser.

  Both use native macOS WebKit, but they optimize for different workflows.

  | Area | aslan-browser | wkdomains/macos-app |
  |---|---|---|
  | App stack | Swift/AppKit + WKWebView | SwiftUI/AppKit + WKWebView + Combine |
  | Local API | SwiftNIO Unix socket + NDJSON JSON-RPC | Network.framework TCP HTTP API on localhost |
  | Control model | Agent can navigate, click, fill, eval JS, manage tabs | Agent mostly reads current human page state
  |
  | Page model | Accessibility-tree-first with @eN refs | Visible DOM summary, links/forms/tables/resources |
  | SDK | Python sync + async SDK, CLI | curl/local HTTP + MCP terminal workflow |
  | Multi-agent | Sessions, owned tabs, batch/parallel calls | Human request queue via MCP |
  | Strongest use case | Autonomous browser tasks | Debugging/understanding a page the human is viewing |

  What Aslan Does Better

  1. Actual automation, not just observation.
     Aslan exposes first-class actions: navigate, evaluate, click, fill, select, keypress, scroll, cookies, tabs,
     sessions, batch, and learn mode in aslan-browser/MethodRouter.swift:18. wkdomains’ local API is GET-oriented for
     page state like /dom, /xhr, /cookies, /screenshot, /resources in /Users/aa/wkdomains/macos-app/macos-app/LocalAPI/
     LocalAPIServer.swift:94; it does not expose comparable click/fill/navigation endpoints.
  2. Better agent action loop.
     Aslan’s core loop is “read tree -> choose @eN -> act.” The README shows get_accessibility_tree(), then fill("@e0"),
     click("@e2") in README.md:55. wkdomains gives richer page context, but Aslan gives the agent stable handles for
     doing work.
  3. Leaner IPC for automation.
     Aslan uses SwiftNIO over a Unix-domain socket in aslan-browser/SocketServer.swift:90. wkdomains uses a localhost
     TCP HTTP server via NWListener in /Users/aa/wkdomains/macos-app/macos-app/LocalAPI/LocalAPIServer.swift:28. For
     tight command loops, Aslan’s JSON-RPC socket is the cleaner design.
  4. Purpose-built Python SDK.
     Aslan has sync/async Python clients with automatic sessions and tab cleanup in sdk/python/aslan_browser/
     client.py:26. wkdomains is intentionally curl/MCP/local-HTTP oriented. That makes Aslan easier to embed directly in
     agent code.
  5. Multi-tab and multi-agent isolation.
     Aslan has explicit sessions and batch operations: session cleanup, owned tabs, parallel navigation/tree/screenshot
     APIs in README.md:360. wkdomains has a richer human browser tab model, but not an equivalent agent-owned tab/
     session API.
  6. Deterministic wait primitives for automation.
     Aslan tracks DOM stability, network idle, navigation completion, and ready state in aslan-browser/
     BrowserTab.swift:51, plus page-side waitForSelector in aslan-browser/ScriptBridge.swift:398. wkdomains is more
     about current-state inspection than command sequencing.
  7. Learn mode/playbooks.
     Aslan records user clicks, inputs, navigation, scroll, screenshots, and annotations so agents can turn
     demonstrations into reusable playbooks. That is a stronger automation-training primitive than wkdomains’ human
     terminal request loop.
