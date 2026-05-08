//
//  BrowserDarkModeRuntimeStateScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeRuntimeStateScript = #"""
      let forced = null;
      let scheduled = false;
      let scheduledTimer = null;
      let applying = false;
      let readyFinalized = false;
      let readyFallbackTimer = null;
      let shadowDiscoveryScheduled = false;
      const shadowDiscoveryRoots = new Set();
      let prunedDisconnectedRoots = 0;
      let prunedRootObservers = 0;
      const rootObservers = new Map();
      const dirtyRoots = new Set();
      let shadowProxyActive = false;
      let customElementRegistryProxyActive = false;
      let pageProxyBridgeInstalled = false;
      const bridgeStatus = {
        installed: false,
        configured: false,
        events: Object.create(null),
        lastEvent: "",
        lastEventAt: 0,
        config: null
      };
      const INLINE_STYLE_MUTATION_ATTRIBUTES = new Set(INLINE_STYLE_ATTRS);
      const STYLE_SHEET_MUTATION_ATTRIBUTES = new Set(["href", "media", "disabled"]);
      const SURFACE_MUTATION_ATTRIBUTES = new Set(["class", "hidden", "open", "popover", "role", "aria-hidden", "aria-expanded", "aria-modal"]);
      let queuedMutations = [];
      let mutationQueueOverflow = false;
      let mutationFlushScheduled = false;
      let mutationFlushTimer = null;
      let hiddenMutationDeferred = false;
      let hiddenMutationDeferrals = 0;
      let mutationQueueOverflows = 0;
      const MAX_QUEUED_MUTATIONS = 800;
      const installedAt = (() => {
        try { return performance.now(); } catch (_) { return Date.now(); }
      })();

      const elapsedSinceInstall = () => {
        try { return performance.now() - installedAt; } catch (_) { return Date.now() - installedAt; }
      };

      const exposeEngineStatus = () => {
        try {
          Object.defineProperty(window, "__wkdomainsDarkModeStatus", {
            configurable: true,
            enumerable: false,
            value() {
              return {
                installed: true,
                engineWorld: __wkdomainsDarkModeEngineWorldName,
                dynamicStyleStarted,
                pageProxyBridgeInstalled,
                bridgeConfigured: bridgeStatus.configured,
                bridgeLastEvent: bridgeStatus.lastEvent,
                bridgeLastEventAt: bridgeStatus.lastEventAt,
                bridgeEvents: { ...bridgeStatus.events },
                bridgeConfig: bridgeStatus.config ? { ...bridgeStatus.config } : null,
                siteFixes: siteFixDebugStatus(),
                registeredColors: registeredColorStats(),
                variables: variablesStore.status(),
                registeredCustomProperties: registeredCustomPropertyTypes.size,
                stylesheetCustomProperties: stylesheetCustomPropertyTypes.size,
                stylesheetSyncScheduled,
                stylesheetSyncNeeded,
                stylesheetSyncRootCursor,
                lastStylesheetSyncRootCount,
                lastStylesheetSyncTotalRootCount,
                finalStartupStyleSyncScheduled,
                deferredStartupStyleSyncs,
                deferredSynchronousStyleFlushes,
                pendingStyleRenderJobs: pendingStyleRenderJobs.length,
                styleRenderScheduled,
                styleRenderBatches,
                styleRenderJobsCompleted,
                styleManagerUpdateScheduled,
                pendingStyleManagerUpdates: pendingStyleManagerUpdates.size,
                styleManagerUpdateBatches,
                styleManagerUpdatesCompleted,
                styleManagerUpdatesSkipped,
                adoptedStyleUpdateScheduled,
                pendingAdoptedStyleUpdates: pendingAdoptedStyleUpdates.size,
                adoptedStyleUpdateBatches,
                adoptedStyleUpdatesCompleted,
                adoptedStyleUpdatesSkipped,
                asyncStyleConversionsStarted,
                asyncStyleConversionsCompleted,
                asyncStyleConversionsCancelled,
                asyncStyleConversionsPending: Math.max(0, asyncStyleConversionsStarted - asyncStyleConversionsCompleted - asyncStyleConversionsCancelled),
                stylesheetFetchCopyStarted,
                stylesheetFetchCopyCompleted,
                stylesheetFetchCopyFailed,
                stylesheetFetchCopyRetried,
                stylesheetFetchImportStarted,
                stylesheetFetchImportCompleted,
                stylesheetFetchImportFailed,
                stylesheetFetchImportExpanded,
                loadingStyles: loadingStyles.size,
                managedStyleElements: managedStyleElements.size,
                managedAdoptedRoots: managedAdoptedRoots.size,
                adoptedSheetCacheHits,
                adoptedSheetCacheMisses,
                discoveredShadowRoots: discoveredShadowRoots.size,
                prunedDisconnectedRoots,
                prunedRootObservers,
                pendingRootApplies: pendingRootApplyQueue.length,
                pendingRootApplyJobs: pendingRootApplyJobs.size,
                pendingElementApplies: pendingElementApplyQueue.length,
                priorityElementApplyBatches,
                priorityElementApplies,
                lightSurfaceFallbacksApplied,
                lightSurfaceFallbacksCleared,
                rootApplyScheduled,
                shadowDiscoveryScheduled,
                pendingShadowDiscoveryRoots: shadowDiscoveryRoots.size,
                rootObservers: rootObservers.size,
                hiddenMutationDeferred,
                hiddenMutationDeferrals,
                mutationQueueOverflows,
                theme: themeDebugStatus(),
                ready: document.documentElement?.getAttribute(READY_ATTRIBUTE) === "true"
              };
            }
          });
        } catch (_) {}
      };
    """#
}
