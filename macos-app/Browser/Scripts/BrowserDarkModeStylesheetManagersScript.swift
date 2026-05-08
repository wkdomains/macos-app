//
//  BrowserDarkModeStylesheetManagersScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetManagersScript = #"""
      const ensureStyleManager = (element) => {
        let manager = styleManagers.get(element);
        if (!manager) {
          const syncStyle = element instanceof SVGStyleElement
            ? document.createElementNS("http://www.w3.org/2000/svg", "style")
            : document.createElement("style");
          syncStyle.classList.add(INLINE_CLASS, "darkreader", STYLE_SYNC_CLASS);
          syncStyle.media = "screen";
          manager = { syncStyle, signature: "", revision: 0, observer: null, onSheetChange: null };
          const onSheetChange = () => {
            manager.revision += 1;
            scheduleStyleSync(0);
          };
          manager.onSheetChange = onSheetChange;
          styleManagers.set(element, manager);
          managedStyleElements.add(element);
          element.addEventListener(STYLE_UPDATE_EVENT, onSheetChange);

          if (window.MutationObserver) {
            manager.observer = new MutationObserver(() => scheduleStyleSync(0));
            const isLink = element instanceof HTMLLinkElement;
            manager.observer.observe(element, {
              attributes: true,
              attributeFilter: isLink ? ["href", "media", "disabled"] : ["media", "disabled"],
              childList: !isLink,
              subtree: !isLink,
              characterData: !isLink
            });
          }
        }

        return manager;
      };

      const signatureForStyleManager = (element, manager, rules) => [
        rules ? rules.length : 0,
        variablesStore.version(),
        manager.revision,
        element.href || "",
        element.media || "",
        element.disabled ? "disabled" : "",
        element instanceof HTMLStyleElement || element instanceof SVGStyleElement
          ? hashString(element.textContent || "")
          : ""
      ].join(":");

      const getStyleManagerDetails = (element, options = { secondRound: false }) => {
        if (!shouldManageStyle(element)) return null;
        const manager = ensureStyleManager(element);
        const access = getStyleElementRulesOrError(element);

        if (access.rules) {
          markStyleAccessible(element);
          return { manager, rules: access.rules };
        }

        if (options.secondRound) {
          return null;
        }

        if (styleRulesAreStillLoading(element, access)) {
          if (!isStyleLoading(element)) {
            markStyleLoading(element);
          }
          return null;
        }

        if (access.hasSheet || access.error || document.readyState !== "loading") {
          markStyleUnavailable(element);
          return null;
        }

        markStyleLoading(element);
        return null;
      };

      const renderStyleManager = (element) => {
        const details = getStyleManagerDetails(element, { secondRound: true });
        if (!details) return;

        const { manager, rules } = details;
        __wkdomainsDarkModeDebug(`render-style-start:${rules.length}`);
        const signature = signatureForStyleManager(element, manager, rules);
        if (manager.signature === signature && manager.syncStyle.textContent) {
          if (manager.syncStyle.parentNode !== element.parentNode && element.parentNode) {
            element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
          }
          __wkdomainsDarkModeDebug("render-style-cached");
          return;
        }

        __wkdomainsDarkModeDebug(`render-style-convert:${rules.length}`);
        const css = convertCSSRules(rules);
        manager.signature = signature;
        __wkdomainsDarkModeDebug(`render-style-write:${css.length}`);
        withStylesheetProxyDisabled(() => {
          manager.syncStyle.textContent = css;
        });

        if (!css) {
          withStylesheetProxyDisabled(() => {
            manager.syncStyle.remove();
          });
          __wkdomainsDarkModeDebug("render-style-empty");
          return;
        }

        withStylesheetProxyDisabled(() => {
          if (element.parentNode && manager.syncStyle.parentNode !== element.parentNode) {
            element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
          } else if (element.parentNode && manager.syncStyle.previousSibling !== element) {
            element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
          }
        });
        __wkdomainsDarkModeDebug("render-style-end");
      };

      const adoptedStyleTargetForRoot = (root) => {
        if (root === document) {
          return document.head || document.documentElement;
        }
        return root;
      };

      const ensureAdoptedStyleListeners = (root) => {
        if (!root || adoptedStyleListenersByRoot.has(root)) return;
        const onChange = () => scheduleStyleSync(0);
        root.addEventListener(ADOPTED_STYLE_CHANGE_EVENT, onChange);
        root.addEventListener(ADOPTED_STYLES_CHANGE_EVENT, onChange);
        root.addEventListener(ADOPTED_DECLARATION_CHANGE_EVENT, onChange);
        adoptedStyleListenersByRoot.set(root, onChange);
      };

      const removeAdoptedStyleListeners = (root) => {
        const listener = adoptedStyleListenersByRoot.get(root);
        if (!listener) return;
        root.removeEventListener(ADOPTED_STYLE_CHANGE_EVENT, listener);
        root.removeEventListener(ADOPTED_STYLES_CHANGE_EVENT, listener);
        root.removeEventListener(ADOPTED_DECLARATION_CHANGE_EVENT, listener);
        adoptedStyleListenersByRoot.delete(root);
      };

      const renderAdoptedStyleSheets = (root) => {
        if (!root || !root.adoptedStyleSheets) return;
        if (!root.adoptedStyleSheets.length) {
          removeAdoptedStyleManager(root);
          return;
        }
        let manager = adoptedStyleManagers.get(root);
        if (!manager) {
          const style = document.createElement("style");
          style.classList.add(INLINE_CLASS, "darkreader", ADOPTED_STYLE_CLASS);
          style.media = "screen";
          manager = { style, signature: "" };
          adoptedStyleManagers.set(root, manager);
          managedAdoptedRoots.add(root);
          ensureAdoptedStyleListeners(root);
        }

        const chunks = [];
        const signature = [];
        for (const sheet of root.adoptedStyleSheets) {
          const rules = safeGetRules(sheet);
          if (!rules) continue;
          signature.push(signatureForRules(rules));
          const css = convertCSSRules(rules);
          if (css) chunks.push(css);
        }

        const nextSignature = signature.join(",");
        if (manager.signature !== nextSignature) {
          manager.signature = nextSignature;
          withStylesheetProxyDisabled(() => {
            manager.style.textContent = chunks.join("\n");
          });
        }

        const target = adoptedStyleTargetForRoot(root);
        if (!manager.style.textContent) {
          withStylesheetProxyDisabled(() => {
            manager.style.remove();
          });
          return;
        }
        if (manager.style.textContent && target && manager.style.parentNode !== target) {
          withStylesheetProxyDisabled(() => {
            try {
              target.insertBefore(manager.style, target.firstChild);
            } catch (_) {
              target.appendChild(manager.style);
            }
          });
        }
      };

      const collectAdoptedStyleSheetRules = (root) => {
        if (!root || !root.adoptedStyleSheets || !root.adoptedStyleSheets.length) return;
        for (const sheet of root.adoptedStyleSheets) {
          variablesStore.addRulesForMatching(safeGetRules(sheet));
        }
      };

      const updateRootVariableStyle = () => {
        if (!document.documentElement) return;
        const rootVarsStyle = createOrUpdateStyle("wkdomains-darkreader--root-vars", document);
        const declarations = variablesStore.rootDeclarations();
        rootVarsStyle.textContent = declarations.length > 0
          ? `:root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) {\n${declarations.map(([property, value]) => `  ${property}: ${value};`).join("\n")}\n}`
          : "";
      };

      const removeStyleManager = (element) => {
        const manager = styleManagers.get(element);
        const listener = loadingStyleListenersByElement.get(element);
        if (listener && element instanceof HTMLLinkElement) {
          element.removeEventListener("load", listener);
          element.removeEventListener("error", listener);
          loadingStyleListenersByElement.delete(element);
        }
        markStyleLoaded(element);
        if (manager) {
          element.removeEventListener(STYLE_UPDATE_EVENT, manager.onSheetChange);
          if (manager.observer) manager.observer.disconnect();
          withStylesheetProxyDisabled(() => {
            manager.syncStyle.remove();
          });
          styleManagers.delete(element);
        }
        managedStyleElements.delete(element);
      };

      const pruneStyleManagers = () => {
        for (const element of Array.from(managedStyleElements)) {
          if (!element.isConnected) {
            removeStyleManager(element);
          }
        }
      };

      const removeAdoptedStyleManager = (root) => {
        const manager = adoptedStyleManagers.get(root);
        if (manager) {
          withStylesheetProxyDisabled(() => {
            manager.style.remove();
          });
          adoptedStyleManagers.delete(root);
        }
        removeAdoptedStyleListeners(root);
        managedAdoptedRoots.delete(root);
      };

      const pruneAdoptedStyleManagers = () => {
        for (const root of Array.from(managedAdoptedRoots)) {
          if (root !== document && root.host && !root.host.isConnected) {
            removeAdoptedStyleManager(root);
          }
        }
      };

      const destroyStyleManagers = () => {
        for (const element of Array.from(managedStyleElements)) {
          removeStyleManager(element);
        }
        loadingStyles.clear();
        for (const root of Array.from(managedAdoptedRoots)) {
          removeAdoptedStyleManager(root);
        }
        withStylesheetProxyDisabled(() => {
          for (const style of document.querySelectorAll(`style.${STYLE_SYNC_CLASS}, style.${ADOPTED_STYLE_CLASS}`)) {
            style.remove();
          }
        });
      };

      const getStylesheetSyncRoots = () => {
        const roots = [document];
        for (const root of Array.from(discoveredShadowRoots)) {
          if (!root) continue;
          if (root.host && !root.host.isConnected) {
            discoveredShadowRoots.delete(root);
            removeAdoptedStyleManager(root);
            continue;
          }
          roots.push(root);
        }
        return roots;
      };

      const collectVariableInputs = (root) => {
        const styles = getManageableStyles(root);
        for (const style of styles) {
          const details = getStyleManagerDetails(style, { secondRound: false });
          if (details) {
            variablesStore.addRulesForMatching(details.rules);
          }
        }
        collectAdoptedStyleSheetRules(root);
        if (root === document && document.documentElement) {
          variablesStore.addInlineStyleForMatching(document.documentElement.style);
        }
        return styles;
      };

      const renderManageableStyles = (root, styles) => {
        for (const style of styles) {
          renderStyleManager(style);
        }
        renderAdoptedStyleSheets(root);
      };

      const scheduleFinalStartupStyleSync = () => {
        if (finalStartupStyleSyncScheduled) return;
        finalStartupStyleSyncScheduled = true;
        const delay = Math.max(0, 4300 - elapsedSinceInstall());
        window.setTimeout(() => {
          finalStartupStyleSyncScheduled = false;
          scheduleStyleSync(0);
        }, delay);
      };

      const getStylesheetSyncWorkRoots = (roots) => {
        if (!roots || roots.length <= 1) {
          lastStylesheetSyncRootCount = roots ? roots.length : 0;
          lastStylesheetSyncTotalRootCount = roots ? roots.length : 0;
          return { roots, hasMore: false };
        }

        lastStylesheetSyncTotalRootCount = roots.length;
        const startupWindow = elapsedSinceInstall() < 4200;
        const startupRootLimit = 28;
        if (!startupWindow || roots.length <= startupRootLimit + 1) {
          stylesheetSyncRootCursor = 0;
          lastStylesheetSyncRootCount = roots.length;
          return { roots, hasMore: false };
        }

        const shadowRoots = roots.slice(1);
        const start = stylesheetSyncRootCursor % shadowRoots.length;
        const selected = [];
        for (let offset = 0; offset < Math.min(startupRootLimit, shadowRoots.length); offset += 1) {
          selected.push(shadowRoots[(start + offset) % shadowRoots.length]);
        }
        const nextCursor = (start + selected.length) % shadowRoots.length;
        const hasMore = start + selected.length < shadowRoots.length;
        stylesheetSyncRootCursor = nextCursor;
        scheduleFinalStartupStyleSync();

        const workRoots = [roots[0], ...selected];
        lastStylesheetSyncRootCount = workRoots.length;
        return {
          roots: workRoots,
          hasMore
        };
      };

      const syncAllStyles = () => {
        __wkdomainsDarkModeDebug("sync-styles-start");
        stylesheetSyncNeeded = false;
        pruneStyleManagers();
        pruneAdoptedStyleManagers();
        variablesStore.clear();

        const allRoots = getStylesheetSyncRoots();
        const work = getStylesheetSyncWorkRoots(allRoots);
        const roots = work.roots;
        __wkdomainsDarkModeDebug(`sync-styles-roots:${roots.length}/${allRoots.length}`);
        const stylesByRoot = new Map();
        for (const root of roots) {
          stylesByRoot.set(root, collectVariableInputs(root));
        }

        __wkdomainsDarkModeDebug("sync-styles-match-vars");
        variablesStore.matchVariablesAndDependents();
        __wkdomainsDarkModeDebug("sync-styles-root-vars");
        updateRootVariableStyle();

        __wkdomainsDarkModeDebug("sync-styles-render");
        for (const root of roots) {
          renderManageableStyles(root, stylesByRoot.get(root) || []);
        }

        if (loadingStyles.size === 0 && document.readyState !== "loading") {
          cleanFallbackStyle();
        }
        if (work.hasMore) {
          scheduleStyleSync(120);
        }
        __wkdomainsDarkModeDebug("sync-styles-end");
      };

      const updateManageableStyles = () => {
        stylesheetSyncNeeded = true;
        flushStyleSyncNow();
      };

      const scheduleStyleSync = (delay = 30) => {
        stylesheetSyncNeeded = true;
        if (stylesheetSyncScheduled) return;
        __wkdomainsDarkModeDebug(`schedule-style-sync:${delay}`);
        stylesheetSyncScheduled = true;
        stylesheetSyncTimer = window.setTimeout(() => {
          stylesheetSyncScheduled = false;
          stylesheetSyncTimer = null;
          if (!stylesheetSyncNeeded) return;
          syncAllStyles();
          ensureSiteFixStyle();
        }, delay);
      };

      const flushStyleSyncNow = () => {
        __wkdomainsDarkModeDebug("flush-style-sync");
        if (!stylesheetSyncNeeded && !stylesheetSyncScheduled) return;
        if (stylesheetSyncTimer) {
          window.clearTimeout(stylesheetSyncTimer);
          stylesheetSyncTimer = null;
        }
        stylesheetSyncScheduled = false;
        syncAllStyles();
        ensureSiteFixStyle();
      };

      const cancelStyleSync = () => {
        if (stylesheetSyncTimer) {
          window.clearTimeout(stylesheetSyncTimer);
          stylesheetSyncTimer = null;
        }
        stylesheetSyncScheduled = false;
        stylesheetSyncNeeded = false;
        finalStartupStyleSyncScheduled = false;
      };
    """#
}
