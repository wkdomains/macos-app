//
//  BrowserDarkModeRuntimeLifecycleScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeRuntimeLifecycleScript = #"""
      const createThemeAndWatchForUpdates = () => {
        ensureBaseStyle();
        changeMetaThemeColorWhenAvailable();
        if (!documentIsVisible()) {
          runWhenDocumentVisible(runDynamicStyle);
        } else {
          runDynamicStyle();
        }
      };

      const cleanDynamicThemeCache = () => {
        if (readyFallbackTimer) {
          window.clearTimeout(readyFallbackTimer);
          readyFallbackTimer = null;
        }
        if (scheduledTimer) {
          window.clearTimeout(scheduledTimer);
          scheduledTimer = null;
        }
        forced = null;
        scheduled = false;
        applying = false;
        readyFinalized = false;
        dynamicStyleStarted = false;
        bridgeStatus.configured = false;
        bridgeStatus.config = null;
        shadowDiscoveryScheduled = false;
        shadowDiscoveryRoots.clear();
        pendingRootApplySet.clear();
        pendingRootApplyQueue.splice(0);
        pendingRootApplyJobs.clear();
        pendingElementApplySet.clear();
        pendingElementApplyQueue.splice(0);
        fallbackWasCleared = false;
        elementApplyScheduled = false;
        lightSurfaceFallbacksApplied = 0;
        lightSurfaceFallbacksCleared = 0;
        priorityElementApplyBatches = 0;
        priorityElementApplies = 0;
        deferredStartupStyleSyncs = 0;
        deferredSynchronousStyleFlushes = 0;
        pendingStyleRenderJobs.splice(0);
        styleRenderScheduled = false;
        styleRenderBatches = 0;
        styleRenderJobsCompleted = 0;
        cancelStyleManagerUpdates();
        styleManagerUpdateBatches = 0;
        styleManagerUpdatesCompleted = 0;
        styleManagerUpdatesSkipped = 0;
        cancelAdoptedStyleUpdates();
        adoptedStyleUpdateBatches = 0;
        adoptedStyleUpdatesCompleted = 0;
        adoptedStyleUpdatesSkipped = 0;
        shadowProxyActive = false;
        customElementRegistryProxyActive = false;
        cancelStyleSync();
        stopStylesheetProxy();
        restorePrototypePatches();
        stopStylePositionWatchers();
        for (const observer of rootObservers.values()) {
          observer.disconnect();
        }
        rootObservers.clear();
        dirtyRoots.clear();
        queuedMutations = [];
        mutationQueueOverflow = false;
        hiddenMutationDeferred = false;
        if (mutationFlushTimer) {
          window.clearTimeout(mutationFlushTimer);
          mutationFlushTimer = null;
        }
        mutationFlushScheduled = false;
      };

      const removeDynamicTheme = () => {
        cleanDynamicThemeCache();
        try {
          document.dispatchEvent(new CustomEvent(PAGE_PROXY_CLEANUP_EVENT));
        } catch (_) {}
        destroyInlineDOMState();
        destroyStyleManagers();
        removeBaseStyle();
        restoreMetaThemeColor();
        removeNode(document.querySelector(`meta[name="${DARKREADER_META_NAME}"][content="${INSTANCE_ID}"]`));
        if (metaObserver) {
          metaObserver.disconnect();
          metaObserver = null;
        }
        if (headObserver) {
          headObserver.disconnect();
          headObserver = null;
        }
        const tasks = cleanupTasks.splice(0);
        for (const clean of tasks) {
          try { clean(); } catch (_) {}
        }
      };

      window.__wkdomainsRemoveDynamicTheme = removeDynamicTheme;
      exposeEngineStatus();

      const startDynamicTheme = () => {
        __wkdomainsDarkModeDebug("start-theme");
        setupDocumentPiPFontFix();

        const ready = () => {
          const success = () => {
            disableConflictingPlugins();
            createDarkReaderInstanceMarker();
            addMetaListener();
            createThemeAndWatchForUpdates();
          };

          const failure = () => {
            removeDynamicTheme();
          };

          if (isDRLocked()) {
            removeNode(document.querySelector(".wkdomains-darkreader--fallback"));
          } else if (isAnotherDarkReaderInstanceActive()) {
            interceptOldScript({ success, failure });
          } else {
            success();
          }
        };

        if (document.head) {
          ready();
          return;
        }

        if (document.documentElement) {
          const fallbackStyle = createOrUpdateStyle("wkdomains-darkreader--fallback", document);
          fallbackStyle.id = STYLE_ID;
          fallbackStyle.textContent = getFallbackStyle();
          try {
            document.documentElement.appendChild(fallbackStyle);
          } catch (_) {}
        }

        if (!window.MutationObserver) return;
        if (headObserver) headObserver.disconnect();
        headObserver = new MutationObserver(() => {
          if (!document.head) return;
          headObserver?.disconnect();
          headObserver = null;
          ready();
        });
        headObserver.observe(document, { childList: true, subtree: true });
        cleanupTasks.push(() => {
          headObserver?.disconnect();
          headObserver = null;
        });
      };

      document.addEventListener("__darkreader__cleanUp", removeDynamicTheme);
      cleanupTasks.push(() => document.removeEventListener("__darkreader__cleanUp", removeDynamicTheme));
      startDynamicTheme();
    
    """#
}
