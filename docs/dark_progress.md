# Dark Mode Progress

Last updated: 2026-05-07

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
- Expanded modern color-space handling:
  - direct `lab()` and `lch()` parsing with D50-to-sRGB conversion
  - direct `oklab()` and `oklch()` parsing with OKLab-to-sRGB conversion
  - unsupported `color-*()` functions no longer fall through the generic `color()` parser and turn into bogus black values
- Improved shorthand color coverage:
  - named-color detection now uses browser-backed parsing instead of a short hardcoded keyword subset
  - literal replacement skips tokens inside `url(...)` so filenames like `red-icon.svg` are not rewritten
  - `color(srgb ...)`, `color(srgb-linear ...)`, and `color(display-p3 ...)` are parsed directly
  - `color-mix()` now accepts interpolation methods with multiple tokens before the first comma
- Added the first Dark Reader-style site-fix config parser:
  - URL blocks with `INVERT`, `CSS`, `IGNORE INLINE STYLE`, `IGNORE IMAGE ANALYSIS`, `IGNORE CSS`, and CSS URL ignore sections can now be parsed into fix objects
  - stylesheet conversion can skip selectors listed under `IGNORE CSS`
- Improved parsed/configured site-fix selection:
  - all generic fixes are combined
  - equally specific matching fixes are combined instead of dropping all but one
  - config parsing now supports `DISABLE SHADOW ROOT PROXY` and opt-in `ENABLE CUSTOM ELEMENT REGISTRY PROXY`
- Reduced page-world residue from prototype hooks:
  - patched prototype/object descriptors are remembered before wrapping
  - cleanup restores stylesheet, adopted stylesheet, custom element, and shadow-root hooks instead of only disabling callbacks
  - descriptor restore tasks are queued on every install cycle so cleanup stays reversible after remove/reinstall
  - `customElements.define` is no longer patched by default; it is site-fix opt-in only
- Added HN regression diagnostics and replaced the temporary bypass with a general stylesheet-manager fix:
  - native `[wkdomains-debug]` logs now trace navigation, script installation, console warnings/errors, XHR, and local API evaluation timing
  - dark-mode injection emits `[wkdomains-dark]` phase pings around startup, proxy install, stylesheet sync, and root application
  - startup diagnostics now cover listener setup, root observer setup, initial style-sync scheduling, and stylesheet-sync phases
  - stylesheet rule access now follows Dark Reader's `details()`/render split: first pass creates managers and starts guarded loading, second pass renders only readable rules
  - stylesheet render signatures are now manager-revision based instead of serializing every `CSSRule.cssText` during startup render
  - generated sync/adopted stylesheet writes now temporarily suppress stylesheet-proxy callbacks to avoid page-world reentry during our own rendering
  - stylesheet conversion now uses Dark Reader-style duck-typed CSS rule handling, media filtering, and recursion guards instead of relying on `rule.type` and grouping `rule.cssText`
  - declaration iteration now matches Dark Reader's narrower empty-background-shorthand fallback instead of probing every `background` shorthand
  - fixed an infinite loop in URL detection when a CSS value has `url(...)` before a later color token, e.g. image backgrounds with transparent gradients
  - the HN-specific stylesheet-processing disable was removed so simple legacy stylesheets are handled by the shared pipeline
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
- Per-stylesheet managers with loading lifecycle, fallback clearing, and two-pass updates: 88%
- Mature optimized DOM/style watchers: 74%
- Robust adopted stylesheet management: 77%
- Full stylesheet proxy behavior and cross-context coordination: 78%
- Dark Reader's color pipeline and extensive config corpus: 63%
- Mature fix selection/config parser behavior across many sites: 62%
- Extension-world isolation: 22%

## Remaining Gaps

- Variables graph is still not a full Dark Reader port. Current estimate: 76%.
  - no full variable sheet registration/release lifecycle
  - limited CSS parser behavior for unusual declarations
  - limited scoped variable handling
- Per-stylesheet managers still need more mature behavior. Current estimate: 88%.
  - inaccessible/CORS sheets
  - imported stylesheet retries
  - incremental large-sheet rendering
- Watchers are improved but still less mature than Dark Reader's separated watch modules and throttling strategy. Current estimate: 74%.
- Adopted stylesheet handling is better, but not equivalent to Dark Reader's CSSStyleSheet override/fallback model. Current estimate: 77%.
- Stylesheet proxy is closer, but cross-context coordination is still partial. Current estimate: 78%.
- Color pipeline is still a major gap. Current estimate: 63%.
  - no full Dark Reader palette/cache system
  - limited image analysis
  - limited relative-color handling
  - no theme knob parity
- Config/fix support is still hardcoded. Current estimate: 62%.
  - parser exists, but no bundled Dark Reader config corpus yet
  - no broad site corpus
  - only a small set of targeted fixes
- Extension-world isolation is not solved. Current estimate: 22%.
  - current logic still runs as WKUserScript-injected page JavaScript
  - complex SPAs can still be perturbed more than they would be by Dark Reader's extension-world architecture
  - prototype hooks now restore on cleanup, but stylesheet and shadow-root hooks still execute in the page world while active

## Latest Validation

- Combined dark-mode JavaScript passed `node --check`.
- Swift sources passed `xcrun swiftc -parse`.
