//
//  BrowserDarkModeStylesheetManagerCoreScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetManagerCoreScript = #"""
      const cancelPendingStyleConversion = (manager) => {
        if (!manager || !manager.cancelConversion) return;
        manager.cancelConversion();
        manager.cancelConversion = null;
        manager.pendingSignature = "";
        asyncStyleConversionsCancelled += 1;
      };

      const isSVGStyleElementNode = (element) => (
        typeof window.SVGStyleElement === "function" && element instanceof window.SVGStyleElement
      );

      const startupStyleSyncDelay = (delay = 30) => {
        const requestedDelay = Math.max(0, Number(delay) || 0);
        if (stylesheetSyncElapsedSinceInstall() >= STARTUP_STYLE_SYNC_WINDOW_MS) {
          return requestedDelay;
        }
        deferredStartupStyleSyncs += 1;
        return Math.max(requestedDelay, STARTUP_STYLE_SYNC_MIN_DELAY_MS);
      };

      const scheduleStartupAwareStyleSync = (delay = 30) => {
        scheduleStyleSync(startupStyleSyncDelay(delay));
      };

      const flushStyleSyncNowOrSchedule = () => {
        if (
          stylesheetSyncElapsedSinceInstall() < STARTUP_STYLE_SYNC_WINDOW_MS
          && (stylesheetSyncNeeded || stylesheetSyncScheduled)
        ) {
          deferredSynchronousStyleFlushes += 1;
          scheduleStartupAwareStyleSync(STARTUP_STYLE_SYNC_MIN_DELAY_MS);
          return false;
        }

        flushStyleSyncNow();
        return true;
      };

      const ensureStyleManager = (element) => {
        let manager = styleManagers.get(element);
        if (!manager) {
          const syncStyle = isSVGStyleElementNode(element)
            ? document.createElementNS("http://www.w3.org/2000/svg", "style")
            : document.createElement("style");
          syncStyle.classList.add(INLINE_CLASS, "darkreader", STYLE_SYNC_CLASS);
          syncStyle.media = "screen";
          manager = {
            syncStyle,
            signature: "",
            pendingSignature: "",
            revision: 0,
            observer: null,
            onSheetChange: null,
            cancelConversion: null
          };
          const onSheetChange = () => {
            queueStyleManagerUpdate(element);
          };
          manager.onSheetChange = onSheetChange;
          styleManagers.set(element, manager);
          managedStyleElements.add(element);
          element.addEventListener(STYLE_UPDATE_EVENT, onSheetChange);

          if (window.MutationObserver) {
            manager.observer = new MutationObserver(() => queueStyleManagerUpdate(element));
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

      const flushStyleManagerUpdates = () => {
        const flushStartedAt = __wkdomainsDarkModeNow();
        styleManagerUpdateScheduled = false;
        styleManagerUpdateTimer = null;
        if (pendingStyleManagerUpdates.size === 0) return;

        const styles = Array.from(pendingStyleManagerUpdates);
        pendingStyleManagerUpdates.clear();
        const detailsByStyle = [];
        let missingManagers = 0;
        let skipped = 0;

        styleManagerUpdateBatches += 1;
        for (const element of styles) {
          if (!element || !element.isConnected || !shouldManageStyle(element)) {
            if (element) removeStyleManager(element);
            skipped += 1;
            continue;
          }

          const manager = styleManagers.get(element);
          if (!manager) {
            missingManagers += 1;
            continue;
          }

          const details = getStyleManagerDetails(element, { secondRound: true });
          if (!details) {
            skipped += 1;
            continue;
          }
          queueRulesForVariableMatching(element, manager, details.rules);
          detailsByStyle.push(element);
        }

        if (missingManagers > 0) {
          scheduleStartupAwareStyleSync(120);
        }

        if (detailsByStyle.length === 0) {
          styleManagerUpdatesSkipped += skipped + missingManagers;
          return;
        }

        if (variableStoreNeedsFullRebuild) {
          styleManagerUpdatesSkipped += skipped + missingManagers + detailsByStyle.length;
          scheduleStartupAwareStyleSync(0);
          return;
        }

        variablesStore.matchVariablesAndDependents();
        updateRootVariableStyle();
        invalidateElementApplyCaches();
        for (const element of detailsByStyle) {
          renderStyleManager(element);
        }
        styleManagerUpdatesCompleted += detailsByStyle.length;
        styleManagerUpdatesSkipped += skipped + missingManagers;
        ensureSiteFixStyle();
        __wkdomainsDarkModePerf(
          "flush-style-manager-updates",
          flushStartedAt,
          `updated=${detailsByStyle.length} skipped=${skipped} missing=${missingManagers}`,
          6
        );
      };

      const queueStyleManagerUpdate = (element, delay = STYLE_MANAGER_UPDATE_DELAY_MS) => {
        if (!element) return;
        const manager = styleManagers.get(element);
        if (!manager) {
          if (shouldManageStyle(element)) scheduleStartupAwareStyleSync(120);
          return;
        }
        manager.revision += 1;
        pendingStyleManagerUpdates.add(element);
        if (styleManagerUpdateScheduled) return;
        styleManagerUpdateScheduled = true;
        styleManagerUpdateTimer = window.setTimeout(flushStyleManagerUpdates, Math.max(0, Number(delay) || 0));
      };

      const cancelStyleManagerUpdates = () => {
        pendingStyleManagerUpdates.clear();
        if (styleManagerUpdateTimer) {
          window.clearTimeout(styleManagerUpdateTimer);
          styleManagerUpdateTimer = null;
        }
        styleManagerUpdateScheduled = false;
      };

      const signatureForStyleManager = (element, manager, rules) => [
        rules ? rules.length : 0,
        cssRuleListSignature(rules),
        variablesStore.version(),
        manager.revision,
        element.href || "",
        element.media || "",
        element.disabled ? "disabled" : "",
        element instanceof HTMLStyleElement || isSVGStyleElementNode(element)
          ? hashString(element.textContent || "")
          : ""
      ].join(":");

      const variableInputSignatureForStyleManager = (element, manager, rules) => [
        rules ? rules.length : 0,
        cssRuleListSignature(rules),
        manager ? manager.revision : 0,
        element.href || "",
        element.media || "",
        element.disabled ? "disabled" : "",
        element instanceof HTMLStyleElement || isSVGStyleElementNode(element)
          ? hashString(element.textContent || "")
          : ""
      ].join(":");

      const markVariableStoreForFullRebuild = () => {
        variableStoreNeedsFullRebuild = true;
      };

      const queueRulesForVariableMatching = (element, manager, rules) => {
        if (!rules) return false;
        const signature = `${variableInputGeneration}:${variableInputSignatureForStyleManager(element, manager, rules)}`;
        if (variableInputSignaturesByElement.get(element) === signature) {
          variableRuleInputsReused += 1;
          return false;
        }
        const hadVariableData = variableInputHasDataByElement.get(element) === true;
        const hasVariableData = cssRulesHaveVariableData(rules);
        if (
          variableInputSignaturesByElement.has(element)
          && !variableStoreFullRebuildInProgress
          && (hadVariableData || hasVariableData)
        ) {
          markVariableStoreForFullRebuild();
        }
        variableInputHasDataByElement.set(element, hasVariableData);
        variableInputSignaturesByElement.set(element, signature);
        variableRuleInputsQueued += 1;
        const root = element && element.getRootNode ? element.getRootNode() : document;
        variablesStore.addRulesForMatching(rules, { root });
        return true;
      };

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

        if (element instanceof HTMLLinkElement && startStyleSheetFetchCopy(element)) {
          markStyleLoading(element);
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
        const renderStartedAt = __wkdomainsDarkModeNow();
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

        if (shouldConvertCSSRulesAsync(rules)) {
          if (manager.pendingSignature === signature) {
            __wkdomainsDarkModeDebug("render-style-pending");
            return;
          }
          cancelPendingStyleConversion(manager);
          manager.pendingSignature = signature;
          asyncStyleConversionsStarted += 1;
          __wkdomainsDarkModeDebug(`render-style-async:${rules.length}`);
          manager.cancelConversion = convertCSSRulesAsync(rules, (css) => {
            manager.cancelConversion = null;
            if (manager.pendingSignature !== signature || !element.isConnected) {
              if (manager.pendingSignature === signature) {
                manager.pendingSignature = "";
              }
              asyncStyleConversionsCancelled += 1;
              return;
            }
            manager.pendingSignature = "";
            manager.signature = signature;
            asyncStyleConversionsCompleted += 1;
            withStylesheetProxyDisabled(() => {
              manager.syncStyle.textContent = css;
            });

            if (!css) {
              withStylesheetProxyDisabled(() => {
                manager.syncStyle.remove();
              });
              __wkdomainsDarkModeDebug("render-style-async-empty");
              return;
            }

            withStylesheetProxyDisabled(() => {
              if (element.parentNode && manager.syncStyle.parentNode !== element.parentNode) {
                element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
              } else if (element.parentNode && manager.syncStyle.previousSibling !== element) {
                element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
              }
            });
            __wkdomainsDarkModeDebug("render-style-async-end");
          });
          return;
        }

        cancelPendingStyleConversion(manager);

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
        __wkdomainsDarkModePerf("render-style-manager", renderStartedAt, `rules=${rules.length} css=${css.length}`, 10);
        __wkdomainsDarkModeDebug("render-style-end");
      };
    """#
}
