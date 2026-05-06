# Dark Mode Progress

Last updated: 2026-05-06

## Current Focus

Bring the WKWebView forced dark-mode injector closer to Dark Reader's dynamic-theme architecture, with Reddit as the main stress case.

## Progress

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

- Full `variablesStore` dependency graph for matching variables and dependents: 65%
- Per-stylesheet managers with loading lifecycle, fallback clearing, and two-pass updates: 75%
- Mature optimized DOM/style watchers: 60%
- Robust adopted stylesheet management: 65%
- Full stylesheet proxy behavior and cross-context coordination: 58%
- Dark Reader's color pipeline and extensive config corpus: 25%
- Mature fix selection/config parser behavior across many sites: 35%
- Extension-world isolation: 10%

## Remaining Gaps

- Variables graph is still not a full Dark Reader port. Current estimate: 65%.
  - no full variable sheet registration/release lifecycle
  - limited CSS parser behavior for unusual declarations
  - limited scoped variable handling
- Per-stylesheet managers still need more mature behavior. Current estimate: 75%.
  - inaccessible/CORS sheets
  - imported stylesheet retries
  - incremental large-sheet rendering
- Watchers are improved but still less mature than Dark Reader's separated watch modules and throttling strategy. Current estimate: 60%.
- Adopted stylesheet handling is better, but not equivalent to Dark Reader's CSSStyleSheet override/fallback model. Current estimate: 65%.
- Stylesheet proxy is closer, but cross-context coordination is still partial. Current estimate: 58%.
- Color pipeline is still a major gap. Current estimate: 25%.
  - no full Dark Reader palette/cache system
  - limited image analysis
  - limited gradient and complex color-function handling
  - no theme knob parity
- Config/fix support is still hardcoded. Current estimate: 35%.
  - no parser for Dark Reader's config corpus
  - no broad site corpus
  - only a small set of targeted fixes
- Extension-world isolation is not solved. Current estimate: 10%.
  - current logic still runs as WKUserScript-injected page JavaScript
  - complex SPAs can still be perturbed more than they would be by Dark Reader's extension-world architecture

## Latest Validation

- Combined dark-mode JavaScript passed `node --check`.
- Swift sources passed `xcrun swiftc -parse`.
