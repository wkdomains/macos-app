# wkdomains Fast Mode Skill

Use this with `skills/skill_recording.md` when the goal is a fast, watchable AI-speed website digest.

Do not use this as a replacement for the recording skill. This file only describes the fast-mode flow: rapid site reconnaissance, route mapping, audio-first timing, and a recorded sweep that looks fast but remains understandable to a human viewer.

## Goal

Create a 1 to 3 minute video where the agent appears to digest an entire site quickly:

- Start at a late/high-information section, often FAQ.
- Say that it is time to read fast.
- Visit many same-site pages.
- Scroll each page quickly but not as a blur.
- Do not leave the site.
- End back at the FAQ or original high-information page.
- Close with one useful unanswered question.

For `https://www.withone.ai/`, the opening idea:

```text
Maybe it is time I just actually read the FAQ. Buckle up humans. I am going to read these at my speed.
```

## Relationship To Recording Skill

Use the recording skill for:

- Recording API controls.
- WAV generation.
- Exact WAV duration measurement.
- One-WAV-per-clip muxing.
- Concatenating clips without overlapping audio.
- Verifying final video output.

Use this skill for:

- Fast route discovery.
- Same-site-only browsing rules.
- AI-speed scroll pacing.
- Choosing narration content for rapid site digestion.
- Ending with a synthesized unanswered question.

## Rules

- Stay on the same site unless the user explicitly allows external links.
- Same-site HTML, markdown, text, and JSON routes are allowed.
- `.txt` files are allowed, especially `llms.txt`.
- `.json` files are allowed.
- Do not open `.xml` files.
- Do not open external domains such as GitHub, status pages, social links, app dashboards, or third-party docs unless explicitly allowed.
- Do not log in, submit forms, create accounts, send messages, or purchase anything.
- Click and navigate quickly, but leave enough dwell time for a viewer to register the page.
- Use fast scrolls, not instant jumps, during the recorded pass.
- Avoid scroll motion that turns into unreadable blur.

## Two-Pass Flow

### Pass 1: Reconnaissance Without Recording

Map the site before recording.

1. Navigate to the target page.
2. Read:

```sh
curl -sS http://127.0.0.1:9001/api/v1/page | jq .
curl -sS http://127.0.0.1:9001/api/v1/dom | jq .
curl -sS http://127.0.0.1:9001/api/v1/links | jq .
curl -sS http://127.0.0.1:9001/api/v1/layout | jq .
```

3. Fetch machine-readable same-site routes when available:

```sh
curl -sSL https://www.withone.ai/llms.txt
curl -sSL https://www.withone.ai/md
```

4. Build a route list from nav, footer, markdown, and discovered links.
5. Filter the list:

```text
keep: same host, same registrable domain, /docs, /products, /pricing, /knowledge, /changelog, /blog, /md, .txt, .json
drop: external domains, app login/dashboard, GitHub, status pages, social links, mailto, tel, .xml
```

6. Visit candidate pages without recording to learn what matters.
7. Decide the final recorded route order.

For `withone.ai`, useful likely routes:

```text
/
/md
/llms.txt
/pricing
/docs/welcome
/docs/cli
/docs/mcp
/products/cli
/products/auth
/products/agents
/products/flows
/products/bridge
/knowledge
/changelog
```

Keep the final recorded route list shorter if the video would become too long.

### Pass 2: Script And Audio

Write narration after reconnaissance and before recording.

The narration should sound like fast analysis, not generic commentary. It should include:

- What the company appears to do.
- What new information each page adds.
- How the pieces connect.
- One or two skeptical observations.
- One unanswered question at the end.

Avoid narration about:

- The fact that the agent is recording.
- The mechanics of clicking and scrolling.
- Tool calls.
- Browser APIs.

Generate all WAVs before recording and measure durations. Prefer one voice for the whole video unless the user asks otherwise.

Example fast-mode structure:

```text
01_faq_start        FAQ: what One actually does and who it is for.
02_home             Hero and metrics: command center, tools, developers, uptime.
03_llms             llms.txt: the machine-readable product story is much clearer.
04_docs             Docs: setup path and developer surface area.
05_products         Product pages: CLI, Auth, Agents, Flows, Bridge.
06_knowledge        Knowledge directory: breadth of apps/actions.
07_pricing          Pricing: what adoption costs or does not explain.
08_changelog        Changelog: velocity and product evolution.
09_back_to_faq      Return to FAQ and state unanswered question.
```

## Recorded Fast Sweep

Start the visible recorded pass at FAQ, not the hero, when the user asks for the “actually read the FAQ” framing.

Before recording:

1. Navigate to the homepage.
2. Scroll to FAQ.
3. Make sure FAQ is visible and stable.

Recorded pattern per clip:

1. Start recording.
2. Dwell on the page/section for 1 to 3 seconds.
3. Navigate or scroll quickly.
4. Scroll toward the bottom with fast but readable motion.
5. Stop recording.
6. Later trim clip to the WAV duration and mux with its matching WAV.

Fast scroll guidance:

```sh
curl -sS -X POST http://127.0.0.1:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"scroll","direction":"bottom","style":"human","durationMs":7000}'
```

For short pages use 2500 to 5000 ms.

For long pages use 7000 to 12000 ms.

Avoid `durationMs` below about 1500 ms unless it is just a small transition. Too fast becomes blur and is hard to follow in a screen recording.

## Route Pacing

For a 1 to 3 minute video:

- Use 6 to 10 clips.
- Keep most WAVs 7 to 14 seconds.
- Keep total narration around 70 to 150 seconds.
- Record each raw clip 0.5 to 1.5 seconds longer than its WAV.
- Trim to the WAV duration during assembly.

Do not attempt to literally visit every discovered route if it makes the video boring. “Every page” in demo mode should mean every meaningful top-level or content-bearing route found during reconnaissance, not every individual blog post and API reference leaf.

## Ending

Return to the FAQ or another high-information section and close with one unanswered question.

Good unanswered-question examples:

```text
My remaining question is not whether One can reach the apps. It is how a team reviews, approves, and simulates agent actions before those actions hit production data.
```

```text
The site tells me the agent can do a lot. The question I still want answered is: where is the permission preview that shows exactly what this agent is allowed to do tomorrow morning?
```

## WithOne-Specific Notes

From reconnaissance, `withone.ai` presents One as:

- Agent infrastructure.
- A command center for AI workforces.
- One CLI for apps/actions.
- Managed auth and token lifecycle.
- 50,000+ or 62,000+ tools/actions depending on page context.
- 250+ platforms.
- Universal MCP and API integration surface.
- Flows, Agents, Bridge, Relay, Knowledge, and Auth products.

The homepage is marketing-heavy, but `/llms.txt` and `/md` explain the product more directly. Mention that if useful:

```text
The public page gives me the trailer. The markdown and llms file give me the blueprint: CLI, auth, memory, webhooks, channels, and a universal MCP server.
```

Potential unanswered questions:

- How are permissions reviewed before an agent acts?
- Can teams simulate or dry-run actions?
- What does audit logging look like across apps?
- How do usage limits and pricing behave for a busy agent fleet?
- How does a company restrict an agent to only specific actions inside broad apps like Gmail, Slack, HubSpot, or Shopify?

## Final Verification

After assembling the final video:

```sh
ffprobe -v error -show_entries format=duration,size -show_streams -of json final.mov | jq .
```

Watch for:

- No overlapping audio.
- Each clip has one matching audio line.
- Pages are visible long enough to understand.
- Fast scrolls are readable.
- External sites were not visited.
- Final unanswered question is about the site/product, not the recording process.
