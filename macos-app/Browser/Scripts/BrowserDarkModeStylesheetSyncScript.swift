//
//  BrowserDarkModeStylesheetSyncScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetSyncScript = #"""
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
            queueRulesForVariableMatching(style, details.manager, details.rules);
          }
        }
        collectAdoptedStyleSheetRules(root);
        collectInlineVariableStyles(root);
        return styles;
      };

      const cancelPendingStyleRenderJobs = () => {
        pendingStyleRenderJobs.splice(0);
        styleRenderScheduled = false;
      };

      const schedulePendingStyleRenderJobs = (delay = 0) => {
        if (styleRenderScheduled) return;
        styleRenderScheduled = true;
        window.setTimeout(flushPendingStyleRenderJobs, delay);
      };

      const shouldSliceStyleRendering = (styles) => {
        return stylesheetSyncElapsedSinceInstall() < STARTUP_STYLE_SYNC_WINDOW_MS
          && ((styles && styles.length > 1) || pendingStyleRenderJobs.length > 0);
      };

      const queueStyleRenderJob = (root, styles) => {
        pendingStyleRenderJobs.push({
          root,
          styles: Array.from(styles || []),
          index: 0
        });
        schedulePendingStyleRenderJobs(0);
      };

      const flushPendingStyleRenderJobs = () => {
        const flushStartedAt = __wkdomainsDarkModeNow();
        styleRenderScheduled = false;
        if (pendingStyleRenderJobs.length === 0) return;

        const started = performance.now();
        let rendered = 0;
        styleRenderBatches += 1;

        while (pendingStyleRenderJobs.length > 0) {
          const job = pendingStyleRenderJobs[0];
          if (!job.root || (job.root !== document && job.root.host && !job.root.host.isConnected)) {
            pendingStyleRenderJobs.shift();
            continue;
          }

          while (job.index < job.styles.length) {
            renderStyleManager(job.styles[job.index]);
            job.index += 1;
            rendered += 1;
            if (
              rendered >= STARTUP_STYLE_RENDER_MAX_PER_SLICE
              || performance.now() - started >= STARTUP_STYLE_RENDER_BUDGET_MS
            ) {
              schedulePendingStyleRenderJobs(16);
              return;
            }
          }

          renderAdoptedStyleSheets(job.root);
          pendingStyleRenderJobs.shift();
          styleRenderJobsCompleted += 1;
        }

        if (loadingStyles.size === 0 && document.readyState !== "loading") {
          cleanFallbackStyle();
        }
        ensureSiteFixStyle();
        __wkdomainsDarkModePerf("flush-style-render-jobs", flushStartedAt, `rendered=${rendered} remaining=${pendingStyleRenderJobs.length}`, 8);
      };

      const renderManageableStyles = (root, styles) => {
        if (shouldSliceStyleRendering(styles)) {
          queueStyleRenderJob(root, styles);
          return;
        }

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
        const syncStartedAt = __wkdomainsDarkModeNow();
        __wkdomainsDarkModeDebug("sync-styles-start");
        stylesheetSyncNeeded = false;
        cancelPendingStyleRenderJobs();
        pruneStyleManagers();
        pruneAdoptedStyleManagers();
        invalidateElementApplyCaches();
        variableRuleInputsQueued = 0;
        variableRuleInputsReused = 0;
        const rebuildingVariableStore = variableStoreNeedsFullRebuild;
        if (variableStoreNeedsFullRebuild) {
          variablesStore.clear();
          variableInputGeneration += 1;
          variableStoreNeedsFullRebuild = false;
        }

        const allRoots = getStylesheetSyncRoots();
        const work = getStylesheetSyncWorkRoots(allRoots);
        const roots = work.roots;
        __wkdomainsDarkModeDebug(`sync-styles-roots:${roots.length}/${allRoots.length}`);
        const stylesByRoot = new Map();
        const collectStartedAt = __wkdomainsDarkModeNow();
        variableStoreFullRebuildInProgress = rebuildingVariableStore;
        try {
          for (const root of roots) {
            stylesByRoot.set(root, collectVariableInputs(root));
          }
        } finally {
          variableStoreFullRebuildInProgress = false;
        }
        if (variableStoreNeedsFullRebuild) {
          scheduleStyleSync(0);
          return;
        }
        __wkdomainsDarkModePerf("sync-all-styles-collect", collectStartedAt, `roots=${roots.length}/${allRoots.length}`, 12);

        __wkdomainsDarkModeDebug("sync-styles-match-vars");
        const matchStartedAt = __wkdomainsDarkModeNow();
        variablesStore.matchVariablesAndDependents();
        __wkdomainsDarkModePerf("sync-all-styles-match-vars", matchStartedAt, variablesStore.status ? JSON.stringify(variablesStore.status()) : "", 12);
        __wkdomainsDarkModeDebug("sync-styles-root-vars");
        const rootVarsStartedAt = __wkdomainsDarkModeNow();
        updateRootVariableStyle();
        __wkdomainsDarkModePerf("sync-all-styles-root-vars", rootVarsStartedAt, "", 12);

        __wkdomainsDarkModeDebug("sync-styles-render");
        const renderStartedAt = __wkdomainsDarkModeNow();
        for (const root of roots) {
          renderManageableStyles(root, stylesByRoot.get(root) || []);
        }
        __wkdomainsDarkModePerf("sync-all-styles-render", renderStartedAt, `pendingRender=${pendingStyleRenderJobs.length}`, 12);

        if (pendingStyleRenderJobs.length > 0) {
          schedulePendingStyleRenderJobs(0);
        }
        if (pendingStyleRenderJobs.length === 0 && loadingStyles.size === 0 && document.readyState !== "loading") {
          cleanFallbackStyle();
        }
        if (work.hasMore) {
          scheduleStyleSync(120);
        }
        __wkdomainsDarkModePerf(
          "sync-all-styles",
          syncStartedAt,
          `roots=${roots.length}/${allRoots.length} styleManagers=${managedStyleElements.size} adopted=${managedAdoptedRoots.size} pendingRender=${pendingStyleRenderJobs.length} loading=${loadingStyles.size} varsQueued=${variableRuleInputsQueued} varsReused=${variableRuleInputsReused} varGeneration=${variableInputGeneration}`,
          8
        );
        __wkdomainsDarkModeDebug("sync-styles-end");
      };

      const updateManageableStyles = () => {
        stylesheetSyncNeeded = true;
        scheduleStartupAwareStyleSync(0);
      };

      const scheduleStyleSync = (delay = 30) => {
        stylesheetSyncNeeded = true;
        if (stylesheetSyncScheduled) return;
        __wkdomainsDarkModeDebug(`schedule-style-sync:${delay}`);
        stylesheetSyncScheduled = true;
        const runSync = () => {
          stylesheetSyncScheduled = false;
          stylesheetSyncTimer = null;
          stylesheetSyncTimerKind = "";
          if (!stylesheetSyncNeeded) return;
          syncAllStyles();
          ensureSiteFixStyle();
        };
        const scheduleRun = () => {
          if (window.requestIdleCallback) {
            stylesheetSyncTimerKind = "idle";
            stylesheetSyncTimer = window.requestIdleCallback(runSync, { timeout: 600 });
          } else {
            stylesheetSyncTimerKind = "timeout";
            stylesheetSyncTimer = window.setTimeout(runSync, 0);
          }
        };
        if (delay > 0) {
          stylesheetSyncTimerKind = "timeout";
          stylesheetSyncTimer = window.setTimeout(scheduleRun, delay);
        } else {
          scheduleRun();
        }
      };

      const flushStyleSyncNow = () => {
        __wkdomainsDarkModeDebug("flush-style-sync");
        if (!stylesheetSyncNeeded && !stylesheetSyncScheduled) return;
        if (stylesheetSyncTimer) {
          if (stylesheetSyncTimerKind === "idle" && window.cancelIdleCallback) {
            window.cancelIdleCallback(stylesheetSyncTimer);
          } else {
            window.clearTimeout(stylesheetSyncTimer);
          }
          stylesheetSyncTimer = null;
          stylesheetSyncTimerKind = "";
        }
        stylesheetSyncScheduled = false;
        syncAllStyles();
        ensureSiteFixStyle();
      };

      const cancelStyleSync = () => {
        cancelStyleManagerUpdates();
        cancelAdoptedStyleUpdates();
        cancelInlineVariableUpdate();
        if (stylesheetSyncTimer) {
          if (stylesheetSyncTimerKind === "idle" && window.cancelIdleCallback) {
            window.cancelIdleCallback(stylesheetSyncTimer);
          } else {
            window.clearTimeout(stylesheetSyncTimer);
          }
          stylesheetSyncTimer = null;
          stylesheetSyncTimerKind = "";
        }
        stylesheetSyncScheduled = false;
        stylesheetSyncNeeded = false;
        finalStartupStyleSyncScheduled = false;
      };
    """#
}
