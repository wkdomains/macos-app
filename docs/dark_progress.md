# Dark Mode Progress

Last updated: 2026-05-06

## Current Focus

Bring the WKWebView forced dark-mode injector closer to Dark Reader's dynamic-theme architecture, with Reddit as the main stress case.

## Progress

- Expanded color handling:
  - direct `hsl()`, `hsla()`, and `hwb()` parsing
  - simple `color-mix()` parsing
  - balanced CSS color-function scanning so nested functions are not truncated by the old regex path
  - color replacement now covers literals and supported functions without double-transforming generated `rgb(...)`
- Added custom property registration awareness:
  - `@property --token { syntax: "<color>"; ... }` rules are included in variable matching
  - `CSS.registerProperty({ name, syntax: "<color>" })` is proxied and schedules a stylesheet sync
- Improved watcher efficiency with dirty-root compression:
  - descendant dirty roots are skipped when an ancestor is already queued
  - very noisy mutation batches fall back to a single document pass
- Improved adopted stylesheet/proxy bookkeeping:
  - adopted stylesheet ownership is refreshed per root instead of accumulating stale owners
  - adopted rule declaration tracking now recurses through nested rule lists
  - empty adopted override styles are removed
- Improved stylesheet loading cleanup:
  - stale link `load`/`error` listeners are removed when a sheet loads, errors, times out, or is removed
- Site-fix matching now supports wildcard hosts and path patterns instead of treating every fix as host-only.
- Replaced regex-only `var()` handling with balanced variable-reference scanning:
  - nested fallbacks are now discovered for dependency matching
  - fallback values are recursively rewritten when generating wrapped dark variables
  - color/raw-color fallbacks are transformed after nested variables are preserved
- Reduced expensive SPA work:
  - inline DOM passes no longer force a full stylesheet conversion every run
  - stylesheet sync now has an explicit dirty flag and immediate flush path
  - very noisy mutation batches collapse into one document pass instead of retaining hundreds of mutation records
- Improved custom property registration behavior:
  - color `@property` rules now emit wrapped dark-property registrations with transformed `initial-value`
  - proxied `CSS.registerProperty()` now mirrors color properties into bg/text/border wrapped registrations when possible
- Stylesheet proxy now catches nested `CSSGroupingRule.insertRule()` and `deleteRule()` changes inside media/supports/container-style rule groups.
- Color parsing now understands `light-dark()` by selecting the dark branch before applying the relevant transformer.
- Added unavailable stylesheet lifecycle handling:
  - stylesheets that never expose readable `cssRules` no longer hold the fallback style open forever
  - loading stylesheets now time out after 3.5s and are marked unavailable until they become readable
  - rejected `CSSStyleSheet.replace()` promises no longer create unhandled observer noise from our proxy
- Fixed a regression where the `adoptedStyleSheets` proxy recursively called its own getter from `rememberAdoptedSheetOwners`, causing `Maximum call stack size exceeded` and aborting dark-mode rendering on simple pages like Hacker News.
- Stylesheet code was split into focused files:
  - `BrowserDarkModeStylesheetStateScript.swift`
  - `BrowserDarkModeStylesheetVariablesScript.swift`
  - `BrowserDarkModeStylesheetTransformScript.swift`
  - `BrowserDarkModeStylesheetManagersScript.swift`
  - `BrowserDarkModeStylesheetProxyScript.swift`
  - `BrowserDarkModeStylesheetScript.swift` now only preserves the injection order.
- Variables graph is now bidirectional enough to propagate usage types from color-like aliases back to their owners and forward to referenced variables.
- Stylesheet sync is two-pass:
  - collect document and shadow stylesheet inputs
  - match variable dependencies once
  - render document and shadow managers from the shared graph
- Per-stylesheet managers handle loading fallback, load/error listeners, stale manager cleanup, and Dark Reader-style `__darkreader__updateSheet` events.
- Adopted stylesheet management handles document and shadow-root insertion targets separately.
- Adopted stylesheet managers now listen for Dark Reader-style adopted sheet/declaration events.
- Stylesheet proxy now covers:
  - `insertRule`
  - `deleteRule`
  - `addRule`
  - `removeRule`
  - `replace`
  - `replaceSync`
  - declaration `setProperty`
  - declaration `removeProperty`
  - `adoptedStyleSheets` getter/setter
  - in-place adopted stylesheet array changes such as `push`, `splice`, and `length` updates
- DOM/style mutation watchers are batched and narrowed to style-relevant attributes and added/removed stylesheet nodes.
- Color handling supports named colors, hex colors, rgb-like functions, and raw RGB variable values.
- Site fix selection combines generic fixes with the most-specific matching fix.

## Completion Estimates

- Full `variablesStore` dependency graph for matching variables and dependents: 76%
- Per-stylesheet managers with loading lifecycle, fallback clearing, and two-pass updates: 83%
- Mature optimized DOM/style watchers: 74%
- Robust adopted stylesheet management: 77%
- Full stylesheet proxy behavior and cross-context coordination: 74%
- Dark Reader's color pipeline and extensive config corpus: 48%
- Mature fix selection/config parser behavior across many sites: 48%
- Extension-world isolation: 10%

## Remaining Gaps

- Variables graph is still not a full Dark Reader port. Current estimate: 76%.
  - no full variable sheet registration/release lifecycle
  - limited CSS parser behavior for unusual declarations
  - limited scoped variable handling
- Per-stylesheet managers still need more mature behavior. Current estimate: 83%.
  - inaccessible/CORS sheets
  - imported stylesheet retries
  - incremental large-sheet rendering
- Watchers are improved but still less mature than Dark Reader's separated watch modules and throttling strategy. Current estimate: 74%.
- Adopted stylesheet handling is better, but not equivalent to Dark Reader's CSSStyleSheet override/fallback model. Current estimate: 77%.
- Stylesheet proxy is closer, but cross-context coordination is still partial. Current estimate: 74%.
- Color pipeline is still a major gap. Current estimate: 48%.
  - no full Dark Reader palette/cache system
  - limited image analysis
  - limited advanced gradient and relative-color handling
  - no theme knob parity
- Config/fix support is still hardcoded. Current estimate: 48%.
  - no parser for Dark Reader's config corpus
  - no broad site corpus
  - only a small set of targeted fixes
- Extension-world isolation is not solved. Current estimate: 10%.
  - current logic still runs as WKUserScript-injected page JavaScript
  - complex SPAs can still be perturbed more than they would be by Dark Reader's extension-world architecture

## Latest Validation

- Combined dark-mode JavaScript passed `node --check`.
- Swift sources passed `xcrun swiftc -parse`.
