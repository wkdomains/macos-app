# Dark Mode Baseline

Last updated: 2026-05-08

## Reference Point

Upstream reference: [Dark Reader `src/inject/dynamic-theme/index.ts`](https://github.com/darkreader/darkreader/blob/main/src/inject/dynamic-theme/index.ts).

That file is the dynamic-theme coordinator. It owns:

- instance locking, startup, deferred visibility handling, and cleanup
- static style injection order: fallback, user-agent, text, invert, inline, variables, root-vars, proxy, site overrides
- stylesheet manager creation, loading fallback, `details()` collection, render, targeted updates, and fallback clearing
- variables-store matching for stylesheet rules, inline styles, and root variable output
- inline style override watching across the document and shadow roots
- adopted stylesheet override/fallback handling
- stylesheet proxy installation for page-owned CSSOM mutation APIs
- style and inline mutation watchers
- meta theme-color changes, Chrome PDF inversion, and Document Picture-in-Picture font handling

Our implementation is not a literal TypeScript port. It is a WKWebView-specific dynamic-theme engine that preserves the same architecture while splitting the code into Swift-hosted JavaScript fragments and using an isolated content world plus a small page-world bridge.

## Local Architecture

- The engine is assembled in `BrowserDarkModeScripts.swift` from focused script fragments.
- The main engine runs in the named `wkdomainsDarkMode` `WKContentWorld` by default.
- `BrowserDarkModePageProxyScript.swift` runs in the page world only to observe APIs that isolated scripts cannot reliably see.
- `BrowserDarkModeRuntimeLifecycleScript.swift` handles Dark Reader-style startup, instance markers, visibility deferral, cleanup, and reentry.
- `BrowserDarkModeStaticStyleScript.swift` owns static style creation, ordering, fallback/user-agent/inline/variables/site-fix styles, meta theme-color, and persistent fallback behavior.
- `BrowserDarkModeStylesheetScript.swift` preserves stylesheet-layer order:
  - state
  - variables
  - transform
  - managers
  - proxy
- `BrowserDarkModeInlineDOMScript.swift` owns inline attributes, root/shadow application queues, computed fallback surfaces, and bounded post-load recovery.
- `/api/v1/dark-mode` exposes runtime status for the engine, page proxy, variables, managers, queues, theme values, and site-fix matching.

## Current Baseline

Startup and lifecycle are close to the upstream shape:

- Starts at document start, installs fallback early, waits for `document.head` when needed, and respects visibility before the first dynamic run.
- Uses Dark Reader-style instance marker and lock handling.
- Cleans static styles, managers, observers, proxy hooks, meta theme-color changes, queues, and runtime counters on removal.
- Keeps a small persistent fallback after stylesheet loading to cover late SPA surfaces without app-specific selectors.

Static styles are in good shape:

- Fallback, user-agent, inline override, variable, root-variable, site-fix, and invert styles are generated separately.
- Style order is watched and restored.
- Theme knobs are configurable through UserDefaults: mode, brightness, contrast, sepia, grayscale, dark scheme colors, and light scheme colors.
- `color-scheme`, selection colors, form controls, semantic surfaces, dialogs, popovers, structural read surfaces, and site-fix inversion filters have generic dark treatment.

Stylesheet managers are mature:

- Manage document and shadow-root `<style>` / stylesheet `<link>` nodes.
- Use a Dark Reader-style first-pass details collection and second-pass render flow.
- Track loading stylesheets, load/error listeners, timeouts, unavailable sheets, stale manager cleanup, and fallback clearing.
- Use targeted `__darkreader__updateSheet` updates instead of rebuilding everything for common CSSOM mutations.
- Slice startup rendering and large CSS rule conversion to reduce Gmail/Reddit-style main-thread stalls.
- Fetch-copy inaccessible stylesheet links when page-world fetch and CORS allow it, including bounded same-CORS `@import` expansion.

Variables support is strong but not complete:

- Collects custom properties from stylesheet rules, inline styles, root-scoped selectors, adopted sheets, and `@property` rules.
- Tracks variable references and reverse references, then propagates color usage types through alias chains.
- Emits both wkdomains-prefixed variables and Dark Reader-compatible aliases such as `--darkreader-bg--token`.
- Handles registered color custom properties from stylesheet `@property`, including wildcard syntax for color-like tokens, and runtime `CSS.registerProperty()`.
- Carries stylesheet root context into variable matching so document-root variables are separated from shadow/adopted rule inputs.
- Uses cached per-stylesheet variable inputs to avoid repeated full graph rebuilds.
- Falls back to a full variable graph rebuild when a changed stylesheet or adopted-sheet root previously contributed variable data, avoiding stale custom-property types after removals.

Color conversion has broad modern coverage:

- Supports named colors, hex, RGB/HSL/HWB, Lab/LCH, OKLab/OKLCH, `color()`, `light-dark()`, `color-mix()`, relative color forms, gradients, shadows, and raw RGB variables.
- Avoids rewriting color-looking tokens inside `url(...)`.
- Handles `scrollbar-color`, masked background-color icons, gradient `list-style-image`, and theme-aware `color-scheme`.
- Uses a Dark Reader-style palette/cache shape, but the color math is still our approximation rather than an exact upstream port.
- Image analysis is limited compared with upstream, but generic media/backdrop avoidance now catches URL-backed, `image-set()`, and `cross-fade()` backgrounds instead of treating mixed gradient/image stacks as plain surfaces. Inline SVG logos now get a bounded Dark Reader-style image analysis path before applying invert filters.

Inline DOM handling is intentionally narrower than the earlier broad fallback path:

- Root and priority queues now focus on Dark Reader-like inline style candidates.
- Computed-style fallback is reserved for real controls, editable fields, dialogs, popovers, form-like surfaces, and structural read surfaces.
- Root and element application are time-budgeted, watchdog-protected, and visibility-aware.
- Generated inline properties are ignored in cache keys so our own writes do not repeatedly retrigger conversion.
- Inline style handling includes Dark Reader-style loop protection, the ProseMirror node-view-content guard, four-digit legacy `color` normalization, and small-SVG fill classification.
- Legacy HTML background and body text/link attributes now get generic transformed fallbacks when old document markup would otherwise strand dark inherited/link text.
- Post-load computed fallback covers broader light header, titlebar, toolbar, and labeled region surfaces without adding app-specific selectors.

Adopted stylesheet handling is solid for WebKit:

- Document and shadow-root adopted stylesheets are managed independently.
- Page-world and isolated-world proxies observe adopted stylesheet assignment, in-place array changes, declaration changes, and sheet mutations.
- Adopted conversion is sliced for large roots and cached per sheet revision across roots.
- Lightweight rule-list signatures catch same-count stylesheet/adopted-sheet changes that miss a revision bump.
- Disconnected shadow roots prune their observers, managers, dirty-root state, and pending work.

Proxy and bridge coverage is broad:

- Page-world bridge batches global CSSOM/shadow/custom-element events before notifying the isolated engine.
- Proxy coverage includes `insertRule`, `deleteRule`, `addRule`, `removeRule`, `replace`, `replaceSync`, declaration `setProperty`, declaration `removeProperty`, declaration `cssText`, rule `selectorText`, keyframes append/delete, keyframes/keyframe name changes, media-list changes, grouping rule insert/delete across `CSSGroupingRule` and WebKit's concrete grouping-rule constructors, `CSS.registerProperty`, `adoptedStyleSheets`, `attachShadow`, and opt-in custom element registry observation. Stylesheet media matching now keeps mixed screen/print sheets in scope instead of treating any print token as an exclusion.
- Hooks are reversible through saved descriptors and cleanup tasks.
- Site-fix flags can disable stylesheet or shadow-root proxying and can opt into custom element registry proxying.
- SVG stylesheet handling carries Dark Reader's small host denylist for pages known to break on SVG style overrides.

Config/fix support is much closer to upstream:

- The upstream `dynamic-theme-fixes.config` corpus is bundled as an app resource.
- Runtime config can be supplied through `wkdomains.darkModeDynamicThemeFixesConfig` or `wkdomains.darkModeDynamicThemeFixesConfigPath`.
- Parser supports global blocks, multiple URL lines, separators, wildcard hosts, schemes, ports, paths, localhost, CSS templates, invert selectors, ignored inline styles, ignored image analysis, ignored CSS selectors, ignored CSS URLs, and proxy flags.
- Unknown future section headers are skipped and reported instead of being leaked into the previous `CSS` section.
- Selection combines generic fixes with the most-specific matching block or blocks.

## Parity Estimate

Overall dynamic-theme parity against Dark Reader's current `index.ts` orchestration is about 97%.

- Startup, static styles, lifecycle, cleanup: 97%
- Per-stylesheet managers and loading lifecycle: 99%
- DOM/style watchers and scheduling: 99%
- Variables/dependency handling: 96%
- Adopted stylesheet handling: 95%
- Stylesheet proxy and page/isolated-world bridge: 98%
- Dynamic-theme fix config parsing and selection: 96%
- Color parsing/conversion coverage: 95%
- Image/background analysis: 85%
- Extension-world isolation for this WKWebView architecture: 92%

The remaining delta is not one big missing subsystem. It is mostly exact upstream color math, broader bitmap/background image analysis, Dark Reader's fuller variables sheet lifecycle, and adopted stylesheet fallback behavior for browser paths that do not map perfectly to WKWebView.

## Remaining Work

Highest-value gaps:

- Variables-store parity: scoped matching and stale-input cleanup are better, but this is still not a full upstream variables sheet registration/release lifecycle.
- Color parity: decide whether to port Dark Reader color math more directly or keep our compatible approximation and test against real sites.
- Image handling: upstream image/background analysis is still deeper than our generic media/backdrop avoidance and SVG-logo analysis.
- Adopted stylesheet parity: current WebKit path works, but it is still not equivalent to Dark Reader's full override/fallback model for every browser path.
- CSSOM edge APIs: proxy coverage is broader now, but obscure mutation APIs still need long-run testing against framework-heavy pages.
- Config parser resilience: unknown sections are guarded, but future upstream data shapes may still need parser updates.
- Isolation boundary: the named content world is the right default, but page-world hooks are still required for page-owned CSSOM and shadow APIs.
- Runtime validation: keep checking Gmail, Reddit, Hacker News, GitHub, docs sites, and at least one Web Component-heavy app after stylesheet or watcher changes.

Watch items:

- Startup budget on large SPAs, especially repeated variable matching and first root/adopted render.
- Late inserted read panes and form/dialog surfaces that are not styled by converted CSS.
- Pages with aggressive custom element or adopted stylesheet churn.
- Cross-origin stylesheet fetch-copy failure and retry behavior.
- Dark Reader corpus updates that add new sections or unexpected URL block shapes.

## Validation Baseline

This document should track useful runtime evidence, not command history.

Keep future entries focused on:

- page or site tested
- symptoms before the change
- runtime counters from `/api/v1/dark-mode` or `/api/v1/timing`
- visual result after the change
- any remaining follow-up

Current useful validation state:

- Hacker News no longer needs a site-specific stylesheet bypass.
- Gmail startup work has been narrowed to Dark Reader-like inline candidates plus sliced stylesheet rendering, and late light title/header surfaces are handled by the generic surface path.
- Reddit remains the primary stress case for shadow roots, adopted stylesheets, and bursty CSSOM updates.
- The bundled upstream config corpus is the active source of site-specific behavior when present.
