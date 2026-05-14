Your three-part split is good. I’d sharpen the third category:

**Together is not “the human drives and the LLM watches.”
Together is “the browser becomes a shared workspace where the human supplies judgment, taste, intent, and permission, while the LLM supplies memory, comparison, vigilance, and tactical execution.”**

Current AI browsers and agents are mostly converging on automation: OpenAI’s Operator used its own browser to look at pages and interact by typing, clicking, and scrolling; Google describes Gemini in Chrome as using page and open-tab context; Perplexity’s Comet pitches delegated browsing tasks like email, shopping, studying, and planning; and Chrome’s developer docs are moving toward browser-managed AI models and structured agent tools like WebMCP. ([OpenAI][1])

But the more interesting frontier is **co-browsing**, not delegation. Here are the creative ways I think an LLM helps when it can see the DOM and every user action in real time.

## 1. The intent mirror

The LLM watches your clicks, tabs, searches, scroll pauses, backtracks, and form edits, then reflects the likely goal:

> “It looks like you’re comparing whether this hotel is actually cheaper after fees. I’m tracking nightly rate, taxes, resort fee, cancellation policy, and walk time.”

This is powerful because you often do not explicitly declare your task. Your behavior declares it.

The assistant can maintain a live “working theory”:

> “Current goal: decide between these three insurance plans.”
> “Unresolved: deductible, out-of-network coverage, prescription costs.”
> “You keep returning to plan B; probably because monthly price is lower, but total risk is higher.”

That turns browsing from a stream of pages into a stateful decision process.

## 2. A semantic map of the session

Instead of “23 tabs,” the assistant sees:

**Trip planning**

* Flights
* Hotels
* Weather
* Visa rules
* Reddit advice
* Restaurant list

**Purchase decision**

* Product pages
* Reviews
* Return policies
* Price history
* Alternatives

**Work research**

* Primary sources
* Secondary summaries
* Contradictory claims
* Things to cite

It can say:

> “You have four tabs that answer the same question, two that are probably irrelevant, and one primary source you haven’t read yet.”

This is a big deal. The browser’s old unit was the **page**. The AI browser’s unit becomes the **task**.

## 3. Live comparison across pages

Humans are terrible at comparing information scattered across pages. The LLM can turn normal browsing into an automatically maintained comparison table.

For shopping:

> “I’m tracking price, shipping, warranty, return window, hidden fees, seller reputation, and whether the photos match the model number.”

For jobs:

> “I’m comparing compensation, commute, remote policy, hiring manager, tech stack, and likely interview difficulty.”

For research:

> “Claim A appears in three sources. Claim B appears only in the vendor’s blog. Claim C contradicts the government report.”

The key is that the human keeps browsing naturally. The model silently builds the table.

## 4. “Why did I open this?” memory

Browsers remember URLs. They do not remember **why the URL mattered**.

An LLM can create semantic bookmarks like:

> “This was the page with the cancellation-policy loophole.”
> “This is where the author defined the term differently.”
> “This Reddit comment had the practical workaround, but it was anecdotal.”
> “This PDF had the chart you wanted on page 17.”

That is much closer to how human memory works.

## 5. The friction debugger

Because the LLM can see the DOM, it can explain broken or confusing pages:

> “The submit button is disabled because the phone field is failing validation, even though the page is not showing the error.”
> “This dropdown has 147 options, but typing filters it.”
> “You are on the mobile version of the page; the desktop page has the export button.”
> “The coupon failed because it excludes sale items; that text is hidden in the terms panel.”

This is one of the most underrated use cases. A lot of browsing pain is not information retrieval. It is UI combat.

## 6. A dark-pattern and scam sentinel

The assistant can watch for:

* Prechecked boxes
* Subscription traps
* Fake countdown timers
* Hidden fees
* “Free trial” language with auto-renewal
* Confusing opt-outs
* Misleading button hierarchy
* Phishing domain tricks
* Inconsistent seller identities
* Risky downloads

It can intervene only when needed:

> “Pause. This checkout page added a recurring protection plan.”
> “The visible price is $49, but the DOM shows a $19.95 monthly renewal below the fold.”
> “This login page is visually similar to Microsoft, but the domain is not Microsoft.”

That is where “always watching” becomes valuable rather than annoying.

## 7. Source quality radar

While you read, the LLM can classify what kind of source you are on:

> “Primary source.”
> “Affiliate review.”
> “Forum anecdote.”
> “SEO content farm.”
> “Vendor documentation.”
> “Regulatory filing.”
> “Possibly outdated.”

It can also notice when your evidence diet is skewed:

> “So far, every source you opened supports buying this product, but three are monetized by affiliate links. Want a negative-review pass?”

This could make people better thinkers, not just faster browsers.

## 8. Just-in-time explanation

The LLM can explain exactly what is confusing **on the current page**:

> “This mortgage disclosure is saying your payment can rise after year five.”
> “This API error means the token is valid, but the account lacks permission.”
> “This medical paper’s main result is weaker than the headline suggests.”
> “This legal clause is about arbitration, not cancellation.”

The DOM matters because the model knows where you are looking, what you highlighted, what you paused on, and what surrounding context exists.

## 9. Micro-delegation without surrendering the browser

The best “together” pattern may be:

> “You stay here. I’ll check the side quest.”

Examples:

> “While you read this review, I’ll check whether the same model is cheaper elsewhere.”
> “While you fill this form, I’ll find the required ID number from the other tab.”
> “While you inspect this candidate’s resume, I’ll compare it to the job description.”
> “While you read this article, I’ll pull the original study.”

This is different from a solo agent. The human remains in the flow. The LLM runs small parallel errands.

## 10. A real-time “attention bouncer”

The assistant can notice when browsing drifts away from the stated goal:

> “You started looking for a dishwasher repair manual. You are now 18 minutes into appliance reviews. Is this still useful?”

Or:

> “You’ve opened six articles about the same political outrage. None adds new information.”

Or:

> “You are rereading the same paragraph. Want me to summarize the blocker?”

This has to be optional and tactful. But for knowledge workers, students, shoppers, and doomscrollers, it could be huge.

## 11. Turning repeated browsing into automations

If the LLM sees your actions over time, it can say:

> “You do this every Friday: open dashboard, filter by region, export CSV, paste into Sheets, email summary. Want me to turn this into a reviewed workflow?”

The browser becomes a training environment. You demonstrate once or twice; the agent learns the recipe.

The important part is that the human does not have to write automation logic. The browser history becomes the programming language.

## 12. A form-filling conscience

Not just autofill. Judgment-aware form help.

> “This field asks for your Social Security number, but the site does not appear to require it for the quote.”
> “You are about to give marketing consent.”
> “This insurance form changed your answer from ‘no’ to blank after the page refreshed.”
> “This job application asks for salary history; you may want to answer carefully.”

The LLM can also protect against accidental self-sabotage:

> “Your resume says 2021–2024, but this form says 2020–2024. Which is correct?”

## 13. DOM-aware accessibility superpowers

For people with vision, attention, motor, reading, or cognitive challenges, this is enormous.

The assistant can say:

> “There are three main actions on this page: download bill, change payment method, cancel plan.”
> “The page has a modal blocking the form.”
> “The next required field is date of birth.”
> “This table is visually messy; I’ll read it as rows.”
> “The checkout button is after the ad block.”

Screen readers already use structure. An LLM with DOM access can turn structure into intent-level navigation.

## 14. A “decision journal” created automatically

At the end of a browsing session, the assistant can produce:

> “You considered A, B, and C.”
> “You rejected A because of return policy.”
> “You preferred B because of total cost.”
> “Unresolved risk: warranty terms.”
> “Best next action: call support or search one more source.”

This is useful for purchases, medical research, legal forms, hiring, investing, travel, and any decision where people later ask, “How did I get here?”

## 15. Real-time contradiction detection

The assistant can catch inconsistencies across tabs:

> “This product page says 16GB RAM, but the manufacturer spec says 8GB.”
> “The article says the law changed in 2025, but the government page still shows the older rule.”
> “This hotel says free cancellation, but checkout says nonrefundable.”
> “The job post says remote, but the application form says hybrid in Austin.”

Humans miss these because the contradictions live in different tabs.

## 16. A browser-native tutor

When learning something, the LLM can watch your path and adapt:

> “You skipped the prerequisite section. That is why the next paragraph feels opaque.”
> “You keep searching definitions. Want a glossary for this topic?”
> “This documentation page assumes you already understand OAuth scopes. Here’s the missing bridge.”

Instead of a generic tutor, it becomes a tutor grounded in your actual reading path.

## 17. Negotiation and message drafting in context

When you are on a support page, refund form, landlord portal, insurance appeal, or vendor email, the assistant can draft with full context:

> “You are asking for a refund. The strongest argument is that their own policy says cancellation is allowed within 14 days, and you are on day 11.”

Or:

> “Do not send that yet. The tone is angrier than useful. Here’s a firmer version.”

This is especially good when the browser contains the relevant receipts, policies, dates, and prior messages.

## 18. Personal “web memory” with boundaries

The assistant can remember useful facts from prior browsing:

> “Last time you bought this, you preferred the medium size.”
> “You usually reject hotels with resort fees.”
> “You already compared these two laptops in March.”
> “You tend to choose flights with fewer connections even when they cost more.”

That becomes powerful only if the user controls it. Some memory should be durable; some should be session-only; some should never be stored.

## 19. A second cursor

One creative UI pattern: the LLM gets a visible “ghost cursor” or highlight layer, but not full control unless permitted.

It can point:

> “This is the relevant clause.”
> “Click here for the non-ad result.”
> “These two fields conflict.”
> “This button is the destructive one.”

That is better than chat because it lives directly on the page.

## 20. The browser as a shared whiteboard

Imagine the LLM can annotate pages:

* Highlight claims
* Tag evidence
* Mark “read later”
* Attach questions
* Collapse irrelevant sections
* Overlay simpler explanations
* Pin unresolved items
* Create a “task rail” beside the page

The browser stops being just a window into websites. It becomes a thinking environment.

---

## The big design rule

The assistant should not constantly talk. The best version is mostly quiet.

It should interrupt for only five reasons:

1. **You are stuck.**
2. **You are about to make a costly mistake.**
3. **There is a contradiction.**
4. **There is a faster path.**
5. **There is a useful synthesis across pages.**

Otherwise it should quietly maintain state.

## The danger

The same capabilities that make this magical also make it risky. Security researchers are already showing that browser agents can be vulnerable to indirect prompt injection, where malicious instructions hidden in web content are consumed by the AI; Palo Alto’s Unit 42 describes this as a growing attack surface as LLMs and agents become integrated into browsers and web workflows. ([Unit 42][2]) Trail of Bits reported prompt-injection techniques against Comet that could extract private information when external content was not treated as untrusted input. ([The Trail of Bits Blog][3]) Microsoft’s security team has also warned that when AI models are wired to tools, prompt injection can become an execution risk rather than merely a content problem. ([Microsoft][4])

So the winning design needs hard boundaries:

* Watch-only by default.
* Explicit permission before acting.
* No silent cross-site data movement.
* Strong separation between webpage text and user instructions.
* No access to passwords, tokens, or payment credentials.
* Human confirmation for purchases, account changes, messages, and destructive actions.
* A visible action log.
* Per-site and per-session memory controls.

## My strongest take

The killer feature is not “an AI that browses for you.”

The killer feature is **an AI that makes your own browsing cumulative**.

Today, most browsing evaporates. You search, click, skim, compare, forget, repeat. A co-browsing LLM can turn that into memory, structure, judgment, and action.

The browser becomes less like a windshield and more like a cockpit.

[1]: https://openai.com/index/introducing-operator/ "Introducing Operator | OpenAI"
[2]: https://unit42.paloaltonetworks.com/ai-agent-prompt-injection/ "Fooling AI Agents: Web-Based Indirect Prompt Injection Observed in the Wild"
[3]: https://blog.trailofbits.com/2026/02/20/using-threat-modeling-and-prompt-injection-to-audit-comet/ "Using threat modeling and prompt injection to audit Comet - The Trail of Bits Blog"
[4]: https://www.microsoft.com/en-us/security/blog/2026/05/07/prompts-become-shells-rce-vulnerabilities-ai-agent-frameworks/ "When prompts become shells: RCE vulnerabilities in AI agent frameworks | Microsoft Security Blog"


I haven’t used `wkdomains` as a local daily-driver browser, so I won’t pretend I have. I have used agent-visible browsing workflows in this environment, and I’ve looked closely at your repo/docs. My take: the interesting part is **not** “LLM controls a browser.” That is already getting crowded. The interesting part is **human-owned browser state made legible to an agent**.

Your repo already says the right thing: wkdomains lets the human browse normally while the agent gets structured access to the same page: screenshot, URL, viewport, visible DOM, links, forms, console, XHR/fetch shapes, cookies/storage, and domain discovery files like `llms.txt`, OpenAPI, sitemap, robots, and agent cards. The README’s “browser left, machine-readable context right” framing is exactly the category. ([GitHub][1])

## My favorite feature

The killer feature is **XHR/fetch `jsonShape` plus authenticated browser context**.

Screenshots are useful. DOM summaries are useful. But the moment an agent can say, “this visible table is probably powered by `GET /api/...`, and the response shape is `array<object{id,name,status,...}>`,” the browser stops being just a viewport and becomes a live reverse-engineering console. Your docs describe `/api/v1/xhr` as returning observed XHR/fetch calls with compact redacted `jsonShape` summaries, and `/api/v1/cookies` as giving the coding tool the auth/session context needed to replay those same endpoints. That is powerful, and it is also sensitive, so it should become a first-class permission boundary. ([GitHub][2])

My second favorite feature is the **browser terminal backed by MCP human requests**. The “watcher agent” loop is the right human-agent interaction pattern: the user asks from inside the browser, the agent inspects current browser state, replies in place, and the main coding session remains separate. ([GitHub][3])

## What I’d put on the wish list

The feature I want most is **evidence-backed answers**. Every browser-agent reply should be able to say: “I know this because of DOM ref `@e23`, XHR request `r17`, console message `c4`, and screenshot crop `s2`.” Not just “the agent says so.” A Together browser should make the agent show its work at the page-state level.

The next feature is **visible-text-to-API provenance**: select a number, label, table cell, error message, or disabled button, then ask, “Where did this come from?” The browser should correlate visible DOM text, recent XHR JSON, console events, and source hints. Your own vision doc already lists future tools like `find_api_for_visible_text`, `replay_xhr`, `list_xhr`, and `compare_viewports`; I would promote those from “future tools” to the core identity of the project. ([GitHub][4])

The third is a hard **permission and redaction model**. Localhost-only is not enough when the API can expose cookies, storage, screenshots, and authenticated replay. A local process can still call localhost. Add explicit scopes like `read.page`, `read.dom`, `read.screenshot`, `read.network.shape`, `read.network.body`, `read.storage`, `act.click`, `act.fill`, `act.submit`, `replay.xhr`. MCP’s own spec emphasizes explicit user consent, user control over data sharing/actions, and clear UIs for authorization; your project should embody that better than the generic agent browsers. ([Model Context Protocol][5])

## The Netscape analogy

The Marc Andreessen/Netscape lesson is not “build a browser.” It is: **find the new interface layer, make it radically easier, then let developers build against it before the incumbents know what standard they are supposed to defend**.

Mosaic’s breakthrough was making the web visible and usable: inline images with text, simple clicking, and an installable graphical experience that made people want to create web pages. ([WIRED][6]) Netscape then moved fast commercially: Andreessen and Jim Clark formed the company in 1994, released early browser versions over the internet, made it available free to individuals/nonprofits, and pushed a cross-platform browser that integrated web, email, and newsgroups. ([LivingInternet][7])

Your equivalent is not HTML rendering. WebKit already does that. Your equivalent is:

> Make the live browser state readable, controllable, attributable, permissioned, and portable for a human+agent pair.

That is the standard.

## What I would do today with `wkdomains`

Create a `standards/` directory and publish a v0.1 spec. Do not wait for polish. Netscape did not wait for permission from a standards body. But avoid the browser-war mistake: make the interface open, testable, and easy for other browsers to copy.

Call it something like:

```text
standards/
  together-browser-context-v0.md
  schemas/
    context.schema.json
    snapshot.schema.json
    dom-node.schema.json
    network-event.schema.json
    action.schema.json
    evidence.schema.json
    permission.schema.json
  examples/
    basic-page.context.json
    xhtml-table-with-xhr.bundle.json
    disabled-button-diagnosis.answer.json
```

Define five primitive objects:

```text
Context
  What page/tab/identity/viewport/domain am I looking at?

Snapshot
  What is visible now? Screenshot, DOM summary, accessibility tree, layout rects.

Network
  What did the page request? Method, URL, status, timing, initiator, jsonShape, redaction state.

Action
  What can the agent do? click/fill/press/scroll/submit/replay, with wait conditions and permission requirements.

Evidence
  Why does the agent believe its answer? DOM refs, XHR refs, console refs, screenshot refs, source hints.
```

Then add one endpoint that returns the whole agent-readable bundle:

```http
GET /api/v1/context-bundle
```

Return a normalized object like:

```json
{
  "version": "together-browser-context/v0.1",
  "page": {
    "url": "https://example.com/dashboard",
    "title": "Dashboard",
    "host": "example.com",
    "viewport": { "mode": "mobile-small", "width": 390, "height": 844 }
  },
  "permissions": {
    "granted": ["read.page", "read.dom", "read.network.shape"],
    "withheld": ["read.storage", "read.network.body", "act.submit"]
  },
  "snapshot": {
    "screenshotRef": "s1",
    "domRefs": ["@e1", "@e2", "@e3"]
  },
  "network": {
    "requests": [
      {
        "ref": "xhr17",
        "method": "GET",
        "urlPattern": "/api/sites",
        "status": 200,
        "jsonShape": "array<object{id,name,status,+8 more}>",
        "bodyRedacted": true
      }
    ]
  },
  "console": {
    "messages": []
  }
}
```

That one endpoint becomes your “view source” moment for the AI browser era.

## The standards that matter

**1. The permission standard.**
Every endpoint gets a scope. Every agent session gets a visible badge. Every sensitive read has an audit trail. Every write action is either human-approved or explicitly pre-authorized. MCP elicitation already has a useful model for user interaction, including form mode and URL mode, and it explicitly forbids using form-mode elicitation for secrets like passwords, API keys, access tokens, and payment credentials. That maps directly onto browser-agent safety. ([Model Context Protocol][8])

**2. The evidence standard.**
Agent answers should cite browser evidence the way serious research cites sources. Example:

```json
{
  "answer": "The Pricing button is disabled because the account lacks billing_admin.",
  "evidence": [
    { "type": "dom", "ref": "@e44", "field": "disabled", "value": true },
    { "type": "xhr", "ref": "xhr12", "jsonPath": "$.user.roles", "valueShape": "array<string>" },
    { "type": "console", "ref": "c3", "message": "billing_admin required" }
  ],
  "confidence": "high"
}
```

This is where wkdomains can beat generic agent browsers. The answer is not just natural language. It is grounded in page state.

**3. The `jsonShape` standard.**
Make your `jsonShape` grammar public. Define how arrays, objects, nullable fields, redacted values, nested objects, samples, and diffs are represented. This could become the agent-readable equivalent of HAR for modern app APIs.

**4. The action target standard.**
Do not rely on CSS selectors alone. Define an action target envelope:

```json
{
  "target": {
    "ref": "@e12",
    "role": "button",
    "name": "Save changes",
    "text": "Save",
    "selectorHints": ["button[data-testid='save']"],
    "rect": { "x": 312, "y": 640, "width": 128, "height": 44 }
  }
}
```

This gives agents a stable ref, semantic fallback, visual fallback, and selector fallback.

**5. The session bundle standard.**
Make “write current page files to `/tmp`” into a formal export format. Your article already describes saving `console.json`, `dom.json`, and `screenshot.png`; turn that into `together-session-bundle.json` plus artifacts. ([wkdomains.com][9]) This becomes the thing people attach to GitHub issues: “Here is the exact browser state my agent saw.”

## How to position against Chrome DevTools MCP, Stagehand, and Browser Use

Chrome DevTools MCP is already a serious incumbent for agent-visible Chrome: Google describes it as giving coding agents DevTools access, and its tool reference includes input automation, navigation, emulation, performance, network, debugging, memory, extensions, and WebMCP tools. ([Chrome for Developers][10]) Stagehand is pushing the “act/extract/observe/agent” automation layer, explicitly trying to sit between brittle selectors and unpredictable agents. ([docs.stagehand.dev][11]) Browser Use is a large open-source automation project that can run locally or self-hosted. ([docs.browser-use.com][12])

So do **not** compete on “agent can click a button.” That will commoditize.

Compete on:

> The human is already there. The agent sees exactly what the human sees, with permissions, provenance, auth context, network shape, and a browser-native conversation loop.

That is the gap.

## The concrete move

Open a GitHub issue or doc titled:

```text
Together Browser Context v0.1: a shared human-agent browser state format
```

Then define the first compliance checklist:

```text
A Together Browser v0.1 implementation MUST expose:
- current page metadata
- viewport-aware screenshot
- sanitized visible DOM with stable refs
- accessibility role/name for interactive elements
- recent XHR/fetch summaries with jsonShape
- console/error summaries
- scoped permission manifest
- action endpoint with wait conditions
- evidence refs for DOM/network/console/screenshot
- exportable session bundle
```

That is how you define the category. Not by saying “AI browser,” but by making the first crisp contract other people can implement.

Your best feature today is `jsonShape`. Your best strategic move is turning it, plus DOM refs, permissions, and evidence bundles, into the **HAR file of the human+agent browser era**.

[1]: https://github.com/wkdomains/macos-app "GitHub - wkdomains/macos-app: A macOS browser for developers and coding agents. wkdomains lets tools like Codex and Claude Code see the page you are viewing, capture screenshots, inspect XHR/fetch calls, understand JSON response shapes, and reuse your authenticated browser context through a local API. · GitHub"
[2]: https://github.com/wkdomains/macos-app/blob/main/docs/local-api.md "macos-app/docs/local-api.md at main · wkdomains/macos-app · GitHub"
[3]: https://github.com/wkdomains/macos-app/blob/main/docs/mcp-terminal.md "macos-app/docs/mcp-terminal.md at main · wkdomains/macos-app · GitHub"
[4]: https://github.com/wkdomains/macos-app/blob/main/docs/vision.md "macos-app/docs/vision.md at main · wkdomains/macos-app · GitHub"
[5]: https://modelcontextprotocol.io/specification/2025-11-25 "Specification - Model Context Protocol"
[6]: https://www.wired.com/2010/04/0422mosaic-web-browser "April 22, 1993: Mosaic Browser Lights Up Web With Color, Creativity | WIRED"
[7]: https://www.livinginternet.com/w/wi_netscape.htm "Netscape History - Web Browser, Marc Andreessen, Jim Clark, Mosaic | LivingInternet"
[8]: https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation "Elicitation - Model Context Protocol"
[9]: https://wkdomains.com/2026/may/on-the-dark-side/ "On the Dark Side | wkdomains.com"
[10]: https://developer.chrome.com/docs/devtools/agents "Chrome DevTools for agents  |  Chrome for Developers"
[11]: https://docs.stagehand.dev/v3/first-steps/introduction "Introducing Stagehand - Stagehand"
[12]: https://docs.browser-use.com/open-source/introduction "Browser Use Open Source - Browser Use"

