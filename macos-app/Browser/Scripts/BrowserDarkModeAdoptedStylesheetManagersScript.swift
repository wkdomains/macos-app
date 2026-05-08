//
//  BrowserDarkModeAdoptedStylesheetManagersScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeAdoptedStylesheetManagersScript = #"""
      const adoptedStyleTargetForRoot = (root) => {
        if (root === document) {
          return document.head || document.documentElement;
        }
        return root;
      };

      const ensureAdoptedStyleListeners = (root) => {
        if (!root || adoptedStyleListenersByRoot.has(root)) return;
        const onChange = () => {
          try {
            for (const sheet of root.adoptedStyleSheets || []) {
              markAdoptedSheetChanged(sheet);
            }
          } catch (_) {}
          const manager = adoptedStyleManagers.get(root);
          if (manager) {
            manager.revision += 1;
          }
          queueAdoptedStyleUpdate(root);
        };
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

      const adoptedSheetSignature = (sheet, rules) => [
        variablesStore.version(),
        adoptedSheetRevisionFor(sheet),
        cssRuleListSignature(rules)
      ].join(":");

      const convertAdoptedSheetWithCache = (sheet, rules) => {
        const signature = adoptedSheetSignature(sheet, rules);
        const cached = adoptedSheetConversionCache.get(sheet);
        if (cached && cached.signature === signature) {
          adoptedSheetCacheHits += 1;
          return cached.css;
        }
        adoptedSheetCacheMisses += 1;
        const css = convertCSSRules(rules);
        adoptedSheetConversionCache.set(sheet, { signature, css });
        return css;
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
          manager = {
            style,
            signature: "",
            pendingSignature: "",
            revision: 0,
            cancelConversion: null
          };
          adoptedStyleManagers.set(root, manager);
          managedAdoptedRoots.add(root);
          ensureAdoptedStyleListeners(root);
        }

        const ruleLists = [];
        const sheetsWithRules = [];
        const signature = [];
        for (const sheet of root.adoptedStyleSheets) {
          const rules = safeGetRules(sheet);
          if (!rules) continue;
          const sheetSignature = adoptedSheetSignature(sheet, rules);
          signature.push(sheetSignature);
          sheetsWithRules.push({ sheet, rules });
          ruleLists.push(rules);
        }

        const nextSignature = [
          root.adoptedStyleSheets.length,
          variablesStore.version(),
          manager.revision,
          signature.join(",")
        ].join(":");
        const target = adoptedStyleTargetForRoot(root);
        const insertAdoptedStyle = () => {
          if (!manager.style.textContent) {
            withStylesheetProxyDisabled(() => {
              manager.style.remove();
            });
            return;
          }
          if (target && manager.style.parentNode !== target) {
            withStylesheetProxyDisabled(() => {
              try {
                target.insertBefore(manager.style, target.firstChild);
              } catch (_) {
                target.appendChild(manager.style);
              }
            });
          }
        };

        if (manager.signature === nextSignature) {
          insertAdoptedStyle();
          return;
        }

        if (shouldConvertCSSRuleListsAsync(ruleLists, CSS_ADOPTED_RULE_CONVERSION_ASYNC_THRESHOLD)) {
          if (manager.pendingSignature === nextSignature) {
            return;
          }
          cancelPendingStyleConversion(manager);
          manager.pendingSignature = nextSignature;
          asyncStyleConversionsStarted += 1;
          manager.cancelConversion = convertCSSRuleListsAsync(ruleLists, (css) => {
            manager.cancelConversion = null;
            const disconnected = root !== document && root.host && !root.host.isConnected;
            if (manager.pendingSignature !== nextSignature || disconnected) {
              if (manager.pendingSignature === nextSignature) {
                manager.pendingSignature = "";
              }
              asyncStyleConversionsCancelled += 1;
              return;
            }
            manager.pendingSignature = "";
            manager.signature = nextSignature;
            asyncStyleConversionsCompleted += 1;
            withStylesheetProxyDisabled(() => {
              manager.style.textContent = css;
            });
            insertAdoptedStyle();
          });
          return;
        }

        cancelPendingStyleConversion(manager);
        const chunks = [];
        for (const { sheet, rules } of sheetsWithRules) {
          const css = convertAdoptedSheetWithCache(sheet, rules);
          if (css) chunks.push(css);
        }
        manager.signature = nextSignature;
        withStylesheetProxyDisabled(() => {
          manager.style.textContent = chunks.join("\n");
        });
        insertAdoptedStyle();
      };

      const collectAdoptedStyleSheetRules = (root) => {
        if (!root || !root.adoptedStyleSheets || !root.adoptedStyleSheets.length) return;
        const ruleLists = [];
        let hasVariableData = false;
        for (const sheet of root.adoptedStyleSheets) {
          const rules = safeGetRules(sheet);
          if (!rules) continue;
          ruleLists.push(rules);
          hasVariableData = hasVariableData || cssRulesHaveVariableData(rules);
        }
        const signature = `${variableInputGeneration}:${ruleLists.map(cssRuleListSignature).join(",")}`;
        if (adoptedVariableInputSignaturesByRoot.get(root) === signature) {
          variableRuleInputsReused += 1;
          return;
        }
        const hadVariableData = adoptedVariableInputHasDataByRoot.get(root) === true;
        if (
          adoptedVariableInputSignaturesByRoot.has(root)
          && !variableStoreFullRebuildInProgress
          && (hadVariableData || hasVariableData)
        ) {
          markVariableStoreForFullRebuild();
        }
        adoptedVariableInputSignaturesByRoot.set(root, signature);
        adoptedVariableInputHasDataByRoot.set(root, hasVariableData);
        for (const rules of ruleLists) {
          variablesStore.addRulesForMatching(rules, { root });
          variableRuleInputsQueued += 1;
        }
      };

      const flushAdoptedStyleUpdates = () => {
        const flushStartedAt = __wkdomainsDarkModeNow();
        adoptedStyleUpdateScheduled = false;
        adoptedStyleUpdateTimer = null;
        if (pendingAdoptedStyleUpdates.size === 0) return;

        const roots = Array.from(pendingAdoptedStyleUpdates);
        pendingAdoptedStyleUpdates.clear();
        const renderRoots = [];
        let skipped = 0;

        adoptedStyleUpdateBatches += 1;
        for (const root of roots) {
          if (!root || (root !== document && root.host && !root.host.isConnected)) {
            if (root) removeAdoptedStyleManager(root);
            skipped += 1;
            continue;
          }
          collectAdoptedStyleSheetRules(root);
          renderRoots.push(root);
        }

        if (renderRoots.length === 0) {
          adoptedStyleUpdatesSkipped += skipped;
          return;
        }

        if (variableStoreNeedsFullRebuild) {
          adoptedStyleUpdatesSkipped += skipped + renderRoots.length;
          scheduleStartupAwareStyleSync(0);
          return;
        }

        variablesStore.matchVariablesAndDependents();
        updateRootVariableStyle();
        invalidateElementApplyCaches();
        for (const root of renderRoots) {
          renderAdoptedStyleSheets(root);
        }
        adoptedStyleUpdatesCompleted += renderRoots.length;
        adoptedStyleUpdatesSkipped += skipped;
        ensureSiteFixStyle();
        __wkdomainsDarkModePerf(
          "flush-adopted-style-updates",
          flushStartedAt,
          `updated=${renderRoots.length} skipped=${skipped}`,
          6
        );
      };

      const queueAdoptedStyleUpdate = (root, delay = STYLE_MANAGER_UPDATE_DELAY_MS) => {
        if (!root) return;
        pendingAdoptedStyleUpdates.add(root);
        if (adoptedStyleUpdateScheduled) return;
        adoptedStyleUpdateScheduled = true;
        adoptedStyleUpdateTimer = window.setTimeout(flushAdoptedStyleUpdates, Math.max(0, Number(delay) || 0));
      };

      const cancelAdoptedStyleUpdates = () => {
        pendingAdoptedStyleUpdates.clear();
        if (adoptedStyleUpdateTimer) {
          window.clearTimeout(adoptedStyleUpdateTimer);
          adoptedStyleUpdateTimer = null;
        }
        adoptedStyleUpdateScheduled = false;
      };
    """#
}
