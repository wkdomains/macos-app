//
//  BrowserDarkModeInlineQueueScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeInlineQueueScript = #"""
      const elementApplyIsConnected = (element) => {
        if (!element || element.nodeType !== Node.ELEMENT_NODE) return false;
        if (element === document.documentElement || element === document.body) return true;
        return element.isConnected !== false;
      };

      const priorityElementApplySelector = () => (
        pageLoadFired || document.readyState === "complete"
          ? POST_LOAD_PRIORITY_STYLE_OVERRIDE_SELECTOR
          : PRIORITY_STYLE_OVERRIDE_SELECTOR
      );

      const queuePostLoadSurfaceApplies = (root = document, limit = 64) => {
        if (!root || !root.querySelectorAll || !(pageLoadFired || document.readyState === "complete")) return 0;
        let queued = 0;
        try {
          for (const element of root.querySelectorAll(LIGHT_SURFACE_SELECTOR)) {
            if (queued >= limit) break;
            if (!element || element.nodeType !== Node.ELEMENT_NODE) continue;
            if (queueElementApply(element, 24)) queued += 1;
          }
        } catch (_) {}
        return queued;
      };

      const scheduleQueuedElementApplies = (delay = 0) => {
        if (elementApplyScheduled) return;
        elementApplyScheduled = true;
        scheduleIdleTask(flushQueuedElementApplies, delay, 220);
      };

      const queueElementApply = (element, delay = 0) => {
        if (!element || element.nodeType !== Node.ELEMENT_NODE || pendingElementApplySet.has(element)) return false;
        pendingElementApplySet.add(element);
        pendingElementApplyQueue.push(element);
        scheduleQueuedElementApplies(delay);
        scheduleApplyQueueWatchdog(800);
        return true;
      };

      const queueElementSubtreeApply = (node, limit = ELEMENT_SUBTREE_QUEUE_LIMIT) => {
        if (!node) return 0;
        let queued = 0;
        const selector = priorityElementApplySelector();
        const queueCandidate = (element) => {
          if (!element || queued >= limit || element.nodeType !== Node.ELEMENT_NODE) return;
          if (!element.matches || !element.matches(selector)) return;
          if (queueElementApply(element, 0)) queued += 1;
        };

        if (node.nodeType === Node.ELEMENT_NODE) {
          queueCandidate(node);
        }

        if (!node.querySelectorAll) return queued;
        try {
          for (const element of node.querySelectorAll(selector)) {
            queueCandidate(element);
            if (queued >= limit) break;
          }
        } catch (_) {}
        return queued;
      };

      const flushQueuedElementApplies = () => {
        const flushStartedAt = __wkdomainsDarkModeNow();
        elementApplyScheduled = false;
        if (pendingElementApplyQueue.length === 0) return;

        const started = performance.now();
        const wasApplying = applying;
        let applied = 0;
        applying = true;
        priorityElementApplyBatches += 1;

        try {
          while (pendingElementApplyQueue.length > 0) {
            const element = pendingElementApplyQueue.shift();
            pendingElementApplySet.delete(element);
            if (!elementApplyIsConnected(element)) continue;
            safeApplyElement(element);
            applied += 1;
            priorityElementApplies += 1;
            if (
              applied >= ELEMENT_APPLY_MAX_PER_SLICE
              || performance.now() - started > ELEMENT_APPLY_BUDGET_MS
            ) {
              break;
            }
          }
        } catch (error) {
          elementApplyErrors += 1;
          lastElementApplyError = `flush-element ${error && error.message ? error.message : String(error)}`;
          __wkdomainsDarkModePerf("apply-element-error", flushStartedAt, lastElementApplyError, 0);
        } finally {
          applying = wasApplying;
        }

        if (pendingElementApplyQueue.length > 0) {
          scheduleQueuedElementApplies(24);
          scheduleApplyQueueWatchdog(400);
        }
        __wkdomainsDarkModePerf(
          "flush-element-applies",
          flushStartedAt,
          `applied=${applied} remaining=${pendingElementApplyQueue.length} batches=${priorityElementApplyBatches}`,
          6
        );
      };

      const applyRoot = (root) => {
        if (!root || !root.querySelectorAll) return;

        if (root.nodeType === Node.DOCUMENT_NODE) {
          safeApplyElement(document.documentElement);
          if (document.body) safeApplyElement(document.body);
        } else if (root.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
          createShadowStaticStyleOverrides(root);
          renderAdoptedStyleSheets(root);
        } else if (root.nodeType === Node.ELEMENT_NODE) {
          if (root.matches && root.matches(ROOT_STYLE_OVERRIDE_SELECTOR)) {
            safeApplyElement(root);
          }
        }

        for (const element of root.querySelectorAll(ROOT_STYLE_OVERRIDE_SELECTOR)) {
          safeApplyElement(element);
        }
      };

      const rootApplyWalkerRoot = (root) => {
        if (!root) return null;
        if (root.nodeType === Node.DOCUMENT_NODE) return root.documentElement;
        return root;
      };

      const createRootApplyJob = (root) => ({
        root,
        initialized: false,
        waitingForPageLoad: false,
        walker: null,
        fallbackElements: null,
        index: 0,
        matched: 0,
        scanned: 0,
        done: false
      });

      const initializeRootApplyWalker = (job, root) => {
        const walkerRoot = rootApplyWalkerRoot(root);
        if (!walkerRoot) return;
        if (walkerRoot.querySelectorAll) {
          try {
            job.fallbackElements = Array.from(walkerRoot.querySelectorAll(ROOT_STYLE_OVERRIDE_SELECTOR));
            return;
          } catch (_) {
            job.fallbackElements = [];
          }
        }
        if (document.createTreeWalker) {
          try {
            const showElement = window.NodeFilter ? NodeFilter.SHOW_ELEMENT : 1;
            job.walker = document.createTreeWalker(walkerRoot, showElement);
            return;
          } catch (_) {
            job.walker = null;
          }
        }
      };

      const nextRootApplyElement = (job, started) => {
        if (job.walker) {
          let node = job.walker.nextNode();
          let scannedThisSlice = 0;
          while (node) {
            job.scanned += 1;
            scannedThisSlice += 1;
            if (
              node.nodeType === Node.ELEMENT_NODE
              && node.matches
              && node.matches(ROOT_STYLE_OVERRIDE_SELECTOR)
            ) {
              job.matched += 1;
              return node;
            }
            if (
              scannedThisSlice >= rootApplyScanLimit()
              || performance.now() - started > rootApplyBudgetMS()
            ) {
              return undefined;
            }
            node = job.walker.nextNode();
          }
          return null;
        }

        if (job.fallbackElements) {
          while (job.index < job.fallbackElements.length) {
            const node = job.fallbackElements[job.index];
            job.index += 1;
            job.scanned += 1;
            job.matched += 1;
            return node;
          }
        }

        return null;
      };

      const processRootApplyJob = (job, started) => {
        if (!job || job.done) return true;
        const root = job.root;
        if (!root || (root.host && !root.host.isConnected)) {
          job.done = true;
          return true;
        }
        job.waitingForPageLoad = false;

        const shouldWaitForPageLoadBeforeRootScan = () => {
          if (pageLoadFired || elapsedSinceInstall() >= 7000) return false;
          if (root === document) return true;
          if (root.nodeType === Node.ELEMENT_NODE && root.matches && root.matches(ROOT_STYLE_OVERRIDE_SELECTOR)) {
            return false;
          }
          if (root.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
            return false;
          }
          return !!(root && root.querySelectorAll);
        };

        if (!job.initialized) {
          job.initialized = true;
          if (root.nodeType === Node.DOCUMENT_NODE) {
            safeApplyElement(document.documentElement);
            if (document.body) safeApplyElement(document.body);
          } else if (root.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
            createShadowStaticStyleOverrides(root);
            renderAdoptedStyleSheets(root);
          } else if (root.nodeType === Node.ELEMENT_NODE) {
            if (root.matches && root.matches(ROOT_STYLE_OVERRIDE_SELECTOR)) {
              safeApplyElement(root);
            }
          }

          if (shouldWaitForPageLoadBeforeRootScan()) {
            job.waitingForPageLoad = true;
            return false;
          }

          initializeRootApplyWalker(job, root);
        }

        if (shouldWaitForPageLoadBeforeRootScan() && !job.walker && !job.fallbackElements) {
          job.waitingForPageLoad = true;
          return false;
        }

        if (!job.walker && !job.fallbackElements) {
          initializeRootApplyWalker(job, root);
        }

        let count = 0;
        while (true) {
          const node = nextRootApplyElement(job, started);
          if (node === undefined) return false;
          if (!node) break;
          if (elementApplyIsConnected(node)) {
            safeApplyElement(node);
          }
          count += 1;
          if (
            count >= rootApplyElementLimit()
            || performance.now() - started > rootApplyBudgetMS()
          ) {
            return false;
          }
        }

        job.done = true;
        return true;
      };

      const flushQueuedRootApplies = () => {
        const flushStartedAt = __wkdomainsDarkModeNow();
        rootApplyScheduled = false;
        if (pendingRootApplyQueue.length === 0) return;

        const started = performance.now();
        let count = 0;
        const wasApplying = applying;
        applying = true;

        try {
          while (pendingRootApplyQueue.length > 0) {
            const root = pendingRootApplyQueue.shift();
            if (!root || (root.host && !root.host.isConnected)) continue;
            let job = pendingRootApplyJobs.get(root);
            if (!job) {
              job = createRootApplyJob(root);
              pendingRootApplyJobs.set(root, job);
            }
            let done = false;
            try {
              done = processRootApplyJob(job, started);
            } catch (error) {
              elementApplyErrors += 1;
              lastElementApplyError = `root-job ${error && error.message ? error.message : String(error)}`;
              __wkdomainsDarkModePerf("apply-element-error", flushStartedAt, lastElementApplyError, 0);
            }
            if (done) {
              pendingRootApplyJobs.delete(root);
              pendingRootApplySet.delete(root);
              count += 1;
            } else {
              pendingRootApplyQueue.unshift(root);
              break;
            }
            if (count >= ROOT_APPLY_MAX_PER_SLICE || performance.now() - started > rootApplyBudgetMS()) {
              break;
            }
          }
        } catch (error) {
          elementApplyErrors += 1;
          lastElementApplyError = `flush-root ${error && error.message ? error.message : String(error)}`;
          __wkdomainsDarkModePerf("apply-element-error", flushStartedAt, lastElementApplyError, 0);
        } finally {
          applying = wasApplying;
        }

        if (pendingRootApplyQueue.length > 0) {
          const activeRootJob = pendingRootApplyJobs.size > 0 ? pendingRootApplyJobs.values().next().value : null;
          scheduleQueuedRootApplies(activeRootJob && activeRootJob.waitingForPageLoad ? 240 : rootApplyRescheduleDelay());
          scheduleApplyQueueWatchdog(400);
        }
        const activeRootJob = pendingRootApplyJobs.size > 0 ? pendingRootApplyJobs.values().next().value : null;
        __wkdomainsDarkModePerf(
          "flush-root-applies",
          flushStartedAt,
          `rootsDone=${count} remaining=${pendingRootApplyQueue.length} jobs=${pendingRootApplyJobs.size} active=${activeRootJob ? `matched=${activeRootJob.matched} scanned=${activeRootJob.scanned}` : "none"} startup=${rootApplyInStartupWindow()}`,
          6
        );
      };

      const scheduleQueuedRootApplies = (delay = 0) => {
        if (rootApplyScheduled) return;
        rootApplyScheduled = true;
        scheduleIdleTask(flushQueuedRootApplies, delay, 260);
      };

      const scheduleApplyQueueWatchdog = (delay = 500) => {
        if (applyQueueWatchdogTimer) return;
        applyQueueWatchdogTimer = window.setTimeout(() => {
          applyQueueWatchdogTimer = null;
          const needsElementFlush = pendingElementApplyQueue.length > 0 && !elementApplyScheduled;
          const needsRootFlush = pendingRootApplyQueue.length > 0 && !rootApplyScheduled;
          if (needsElementFlush) scheduleQueuedElementApplies(0);
          if (needsRootFlush) scheduleQueuedRootApplies(rootApplyRescheduleDelay());
          if (needsElementFlush || needsRootFlush) {
            applyQueueWatchdogTicks += 1;
            scheduleApplyQueueWatchdog(700);
          }
        }, Math.max(0, Number(delay) || 0));
      };

      const queueRootApply = (root, delay = 16) => {
        if (!root || pendingRootApplySet.has(root)) return;
        pendingRootApplySet.add(root);
        pendingRootApplyQueue.push(root);
        scheduleQueuedRootApplies(delay);
        scheduleApplyQueueWatchdog(800);
      };

      const clearCachedSourceFor = (node) => {
        if (node && node.nodeType === Node.ELEMENT_NODE) {
          sourceStyleCache.delete(node);
          inlineStyleCache.delete(node);
          elementApplyCache.delete(node);
        }
      };

      const discoverShadowRoot = (root) => {
        if (!root || discoveredShadowRoots.has(root)) return;
        discoveredShadowRoots.add(root);
        createShadowStaticStyleOverrides(root);
        watchRoot(root);
        queueRootApply(root);
        scheduleStyleSync(60);
      };

      const destroyInlineDOMState = () => {
        clearAllInlineOverrides(document);
        for (const root of Array.from(discoveredShadowRoots)) {
          clearAllInlineOverrides(root);
        }
        discoveredShadowRoots.clear();
        pendingRootApplySet.clear();
        pendingRootApplyQueue.splice(0);
        pendingRootApplyJobs.clear();
        pendingElementApplySet.clear();
        pendingElementApplyQueue.splice(0);
        legacyBackgroundDescendantQueue.splice(0);
        legacyBackgroundDescendantQueued = new WeakSet();
        legacyBackgroundDescendantRetries = new WeakMap();
        rootApplyScheduled = false;
        elementApplyScheduled = false;
        legacyBackgroundDescendantScheduled = false;
        imageAnalysisCanvas = null;
        imageAnalysisContext = null;
      };
    """#
}
