//
//  BrowserDarkModeStylesheetVariableUpdatesScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetVariableUpdatesScript = #"""
      const styleHasVariableData = (style) => {
        if (!style) return false;
        for (let index = 0; index < style.length; index += 1) {
          const property = style.item(index);
          const value = style.getPropertyValue(property);
          if (isGeneratedDarkModeProperty(property)) continue;
          if (property.startsWith("--") || (String(value || "").includes("var(") && !String(value || "").includes(DARK_VAR_PREFIX))) {
            return true;
          }
        }
        return false;
      };

      const collectInlineVariableStyles = (root) => {
        const collectStartedAt = __wkdomainsDarkModeNow();
        if (!root || !root.querySelectorAll) return;
        let collected = 0;
        let visited = 0;
        const startupCollection = stylesheetSyncElapsedSinceInstall() < STARTUP_STYLE_SYNC_WINDOW_MS;
        const collectLimit = startupCollection ? 360 : 2000;
        const collect = (element) => {
          if (!element || !element.style || !styleHasVariableData(element.style)) return;
          variablesStore.addInlineStyleForMatching(element.style);
          collected += 1;
        };

        if (root.nodeType === Node.DOCUMENT_NODE) {
          collect(document.documentElement);
          if (document.body) collect(document.body);
        } else if (root.nodeType === Node.ELEMENT_NODE) {
          collect(root);
        }

        let elements = [];
        try {
          elements = root.querySelectorAll("[style*='--'], [style*='var(']");
        } catch (_) {
          elements = [];
        }
        for (const element of elements) {
          visited += 1;
          collect(element);
          if (collected >= collectLimit) break;
        }
        __wkdomainsDarkModePerf("collect-inline-vars", collectStartedAt, `startup=${startupCollection} collected=${collected} queried=${elements.length} visited=${visited}`, 8);
      };

      const updateRootVariableStyle = () => {
        if (!document.documentElement) return;
        const rootVarsStyle = createOrUpdateStyle("wkdomains-darkreader--root-vars", document);
        const declarations = variablesStore.rootDeclarations();
        rootVarsStyle.textContent = declarations.length > 0
          ? `:root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) {\n${declarations.map(([property, value]) => `  ${property}: ${value};`).join("\n")}\n}`
          : "";
      };

      const flushInlineVariableUpdate = () => {
        const flushStartedAt = __wkdomainsDarkModeNow();
        inlineVariableUpdateScheduled = false;
        inlineVariableUpdateTimer = null;
        inlineVariableUpdateBatches += 1;
        variablesStore.matchVariablesAndDependents();
        updateRootVariableStyle();
        inlineVariableUpdatesCompleted += 1;
        __wkdomainsDarkModePerf(
          "flush-inline-variable-update",
          flushStartedAt,
          `version=${variablesStore.version()}`,
          6
        );
      };

      const queueInlineVariableUpdate = (style, delay = 80) => {
        if (style) {
          variablesStore.addInlineStyleForMatching(style);
        }
        if (inlineVariableUpdateScheduled) return;
        inlineVariableUpdateScheduled = true;
        inlineVariableUpdateTimer = window.setTimeout(flushInlineVariableUpdate, Math.max(0, Number(delay) || 0));
      };

      const cancelInlineVariableUpdate = () => {
        if (inlineVariableUpdateTimer) {
          window.clearTimeout(inlineVariableUpdateTimer);
          inlineVariableUpdateTimer = null;
        }
        inlineVariableUpdateScheduled = false;
      };

      const removeStyleManager = (element) => {
        const manager = styleManagers.get(element);
        pendingStyleManagerUpdates.delete(element);
        clearStyleSheetFetchRetry(element);
        const listener = loadingStyleListenersByElement.get(element);
        if (listener && element instanceof HTMLLinkElement) {
          element.removeEventListener("load", listener);
          element.removeEventListener("error", listener);
          loadingStyleListenersByElement.delete(element);
        }
        markStyleLoaded(element);
        if (manager) {
          markVariableStoreForFullRebuild();
          cancelPendingStyleConversion(manager);
          element.removeEventListener(STYLE_UPDATE_EVENT, manager.onSheetChange);
          if (manager.observer) manager.observer.disconnect();
          withStylesheetProxyDisabled(() => {
            manager.syncStyle.remove();
          });
          styleManagers.delete(element);
        }
        variableInputSignaturesByElement.delete(element);
        variableInputHasDataByElement.delete(element);
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
        pendingAdoptedStyleUpdates.delete(root);
        if (manager) {
          markVariableStoreForFullRebuild();
          cancelPendingStyleConversion(manager);
          withStylesheetProxyDisabled(() => {
            manager.style.remove();
          });
          adoptedStyleManagers.delete(root);
        }
        adoptedVariableInputSignaturesByRoot.delete(root);
        adoptedVariableInputHasDataByRoot.delete(root);
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
        cancelStyleManagerUpdates();
        cancelAdoptedStyleUpdates();
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
    """#
}
