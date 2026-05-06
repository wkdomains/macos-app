//
//  BrowserDarkModeStylesheetManagersScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetManagersScript = #"""
      const renderStyleManager = (element) => {
        const rules = safeGetRules(element.sheet);
        if (!rules) {
          markStyleLoading(element);
          return;
        }
        markStyleLoaded(element);

        let manager = styleManagers.get(element);
        if (!manager) {
          const syncStyle = element instanceof SVGStyleElement
            ? document.createElementNS("http://www.w3.org/2000/svg", "style")
            : document.createElement("style");
          syncStyle.classList.add(INLINE_CLASS, "darkreader", STYLE_SYNC_CLASS);
          syncStyle.media = "screen";
          const onSheetChange = () => scheduleStyleSync(0);
          manager = { syncStyle, signature: "", observer: null, onSheetChange };
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

        const signature = `${signatureForRules(rules)}:${hashString(element.textContent || "")}:${element.href || ""}`;
        if (manager.signature === signature && manager.syncStyle.textContent) {
          if (manager.syncStyle.parentNode !== element.parentNode && element.parentNode) {
            element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
          }
          return;
        }

        const css = convertCSSRules(rules);
        manager.signature = signature;
        manager.syncStyle.textContent = css;

        if (!css) {
          manager.syncStyle.remove();
          return;
        }

        if (element.parentNode && manager.syncStyle.parentNode !== element.parentNode) {
          element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
        } else if (element.parentNode && manager.syncStyle.previousSibling !== element) {
          element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
        }
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
          const existing = adoptedStyleManagers.get(root);
          if (existing) {
            existing.style.remove();
            adoptedStyleManagers.delete(root);
            managedAdoptedRoots.delete(root);
          }
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
          manager.style.textContent = chunks.join("\n");
        }

        const target = adoptedStyleTargetForRoot(root);
        if (manager.style.textContent && target && manager.style.parentNode !== target) {
          try {
            target.insertBefore(manager.style, target.firstChild);
          } catch (_) {
            target.appendChild(manager.style);
          }
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
          manager.syncStyle.remove();
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
          manager.style.remove();
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
        for (const style of document.querySelectorAll(`style.${STYLE_SYNC_CLASS}, style.${ADOPTED_STYLE_CLASS}`)) {
          style.remove();
        }
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
          variablesStore.addRulesForMatching(safeGetRules(style.sheet));
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

      const syncAllStyles = () => {
        pruneStyleManagers();
        pruneAdoptedStyleManagers();
        variablesStore.clear();

        const roots = getStylesheetSyncRoots();
        const stylesByRoot = new Map();
        for (const root of roots) {
          stylesByRoot.set(root, collectVariableInputs(root));
        }

        variablesStore.matchVariablesAndDependents();
        updateRootVariableStyle();

        for (const root of roots) {
          renderManageableStyles(root, stylesByRoot.get(root) || []);
        }

        if (loadingStyles.size === 0 && document.readyState !== "loading") {
          cleanFallbackStyle();
        }
      };

      const updateManageableStyles = () => {
        syncAllStyles();
      };

      const scheduleStyleSync = (delay = 30) => {
        if (stylesheetSyncScheduled) return;
        stylesheetSyncScheduled = true;
        stylesheetSyncTimer = window.setTimeout(() => {
          stylesheetSyncScheduled = false;
          stylesheetSyncTimer = null;
          syncAllStyles();
          ensureSiteFixStyle();
        }, delay);
      };

      const cancelStyleSync = () => {
        if (stylesheetSyncTimer) {
          window.clearTimeout(stylesheetSyncTimer);
          stylesheetSyncTimer = null;
        }
        stylesheetSyncScheduled = false;
      };
    """#
}
