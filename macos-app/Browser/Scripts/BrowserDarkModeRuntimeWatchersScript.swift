//
//  BrowserDarkModeRuntimeWatchersScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeRuntimeWatchersScript = #"""
      const markDirty = (node) => {
        if (!node) {
          dirtyRoots.add(document);
          return;
        }

        if (node.nodeType === Node.DOCUMENT_NODE || node.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
          dirtyRoots.add(node);
          return;
        }

        if (node.nodeType === Node.ELEMENT_NODE) {
          dirtyRoots.add(node);
          return;
        }

        if (node.parentElement) {
          dirtyRoots.add(node.parentElement);
        }
      };

      const rootIsConnected = (root) => {
        if (!root) return false;
        if (root === document) return true;
        if (root.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
          return root.host.isConnected;
        }
        return root.isConnected !== false;
      };

      const forgetQueuedRootApply = (root) => {
        if (!root || !pendingRootApplySet.has(root)) return;
        pendingRootApplySet.delete(root);
        pendingRootApplyJobs.delete(root);
        for (let index = pendingRootApplyQueue.length - 1; index >= 0; index -= 1) {
          if (pendingRootApplyQueue[index] === root) {
            pendingRootApplyQueue.splice(index, 1);
          }
        }
      };

      const forgetDisconnectedRoot = (root) => {
        if (!root || root === document) return false;
        let changed = false;
        const observer = rootObservers.get(root);
        if (observer) {
          observer.disconnect();
          rootObservers.delete(root);
          prunedRootObservers += 1;
          changed = true;
        }
        if (discoveredShadowRoots.delete(root)) changed = true;
        if (shadowRootsWithOverrides.delete(root)) changed = true;
        if (dirtyRoots.delete(root)) changed = true;
        if (shadowDiscoveryRoots.delete(root)) changed = true;
        forgetQueuedRootApply(root);
        removeAdoptedStyleManager(root);
        if (changed) prunedDisconnectedRoots += 1;
        return changed;
      };

      const pruneDisconnectedRoots = () => {
        let pruned = false;
        for (const root of Array.from(discoveredShadowRoots)) {
          if (!rootIsConnected(root)) {
            pruned = forgetDisconnectedRoot(root) || pruned;
          }
        }
        for (const root of Array.from(rootObservers.keys())) {
          if (!rootIsConnected(root)) {
            pruned = forgetDisconnectedRoot(root) || pruned;
          }
        }
        return pruned;
      };

      const normalizeDirtyRoots = () => {
        pruneDisconnectedRoots();
        if (dirtyRoots.size === 0) return [document];
        if (dirtyRoots.has(document) || dirtyRoots.size > 80) return [document];

        const roots = Array.from(dirtyRoots).filter((root) => {
          if (!root) return false;
          if (root === document) return true;
          if (root.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
            return root.host.isConnected;
          }
          return root.isConnected !== false;
        });

        const normalized = [];
        outer:
        for (const root of roots) {
          for (const existing of normalized) {
            if (existing === document) continue outer;
            try {
              if (existing !== root && existing.contains && root.nodeType === Node.ELEMENT_NODE && existing.contains(root)) {
                continue outer;
              }
            } catch (_) {}
          }
          for (let index = normalized.length - 1; index >= 0; index -= 1) {
            const existing = normalized[index];
            try {
              if (root !== existing && root.contains && existing.nodeType === Node.ELEMENT_NODE && root.contains(existing)) {
                normalized.splice(index, 1);
              }
            } catch (_) {}
          }
          normalized.push(root);
        }

        return normalized.length > 0 ? normalized : [document];
      };

      const walkElementSubtree = (root, iterate, limit = Number.POSITIVE_INFINITY) => {
        if (!root) return false;
        let count = 0;
        const visit = (element) => {
          count += 1;
          iterate(element);
          return count >= limit;
        };

        if (root.nodeType === Node.ELEMENT_NODE && visit(root)) {
          return true;
        }

        const walkerRoot = root.nodeType === Node.DOCUMENT_NODE ? root.documentElement : root;
        if (!walkerRoot || !document.createTreeWalker) return false;

        const showElement = window.NodeFilter ? NodeFilter.SHOW_ELEMENT : 1;
        const walker = document.createTreeWalker(walkerRoot, showElement);
        let node = walker.nextNode();
        while (node) {
          if (visit(node)) return true;
          node = walker.nextNode();
        }
        return false;
      };

      const discoverExistingShadowRoots = (root = document, limit = Number.POSITIVE_INFINITY) => {
        return walkElementSubtree(root, (element) => {
          if (element.shadowRoot) discoverShadowRoot(element.shadowRoot);
        }, limit);
      };

      const scheduleShadowRootDiscovery = (root = document, delay = 40) => {
        if (root) shadowDiscoveryRoots.add(root);
        if (shadowDiscoveryScheduled) return;
        shadowDiscoveryScheduled = true;
        scheduleIdleTask(() => {
          shadowDiscoveryScheduled = false;
          const roots = Array.from(shadowDiscoveryRoots);
          shadowDiscoveryRoots.clear();
          for (const discoveryRoot of roots) {
            discoverExistingShadowRoots(discoveryRoot);
          }
        }, delay, 500);
      };

      const discoverShadowRootsForAddedNode = (node) => {
        if (!node) return;
        if (node.nodeType === Node.ELEMENT_NODE && node.shadowRoot) {
          discoverShadowRoot(node.shadowRoot);
        }
        if (
          node.nodeType === Node.DOCUMENT_FRAGMENT_NODE
          || (node.querySelector && node.querySelector("*"))
        ) {
          scheduleShadowRootDiscovery(node, 40);
        }
      };

      const handleMutations = (mutations) => {
        const handleStartedAt = __wkdomainsDarkModeNow();
        if (applying) return;
        let stylesChanged = false;
        let inlineChanged = false;
        let addedElementCount = 0;
        let priorityQueuedCount = 0;

        for (const mutation of mutations) {
          if (mutation.type === "attributes") {
            if (ATTRIBUTES_OWNED_BY_DARK_MODE.includes(mutation.attributeName)) {
              continue;
            }
            if (
              mutation.attributeName === "style"
              && !inlineStyleMutationChangedSource(mutation.target, mutation.oldValue)
            ) {
              continue;
            }
            if (INLINE_STYLE_MUTATION_ATTRIBUTES.has(mutation.attributeName)) {
              clearCachedSourceFor(mutation.target);
              queueElementApply(mutation.target, 0);
              markDirty(mutation.target);
              inlineChanged = true;
            }
            if (SURFACE_MUTATION_ATTRIBUTES.has(mutation.attributeName)) {
              clearCachedSourceFor(mutation.target);
              if (
                mutation.target.nodeType === Node.ELEMENT_NODE
                && (
                  mutation.target.matches(STYLE_OVERRIDE_SELECTOR)
                  || mutation.target.querySelector?.(EDITABLE_CONTROL_SELECTOR)
                )
              ) {
                queueElementApply(mutation.target, 0);
                queueElementSubtreeApply(mutation.target, 12);
                markDirty(mutation.target);
                inlineChanged = true;
              }
            }
            if (
              STYLE_SHEET_MUTATION_ATTRIBUTES.has(mutation.attributeName)
              && shouldManageStyle(mutation.target)
            ) {
              stylesChanged = true;
            }
            continue;
          }

          for (const node of mutation.addedNodes) {
            if (node.nodeType !== Node.ELEMENT_NODE && node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) continue;
            addedElementCount += 1;
            if (shouldManageStyle(node)) stylesChanged = true;
            if (node.querySelector && node.querySelector(STYLE_SELECTOR)) stylesChanged = true;
            const queuedPriorityElements = queueElementSubtreeApply(node, 32);
            priorityQueuedCount += queuedPriorityElements;
            if (queuedPriorityElements > 0) {
              markDirty(node);
              inlineChanged = true;
            }
            discoverShadowRootsForAddedNode(node);
          }

          for (const node of mutation.removedNodes) {
            if (node.nodeType === Node.ELEMENT_NODE && shouldManageStyle(node)) stylesChanged = true;
          }
        }

        if (stylesChanged) scheduleStartupAwareStyleSync(0);
        if (inlineChanged) schedule(0);
        __wkdomainsDarkModePerf(
          "handle-mutations",
          handleStartedAt,
          `mutations=${mutations.length} added=${addedElementCount} priorityQueued=${priorityQueuedCount} styles=${stylesChanged} inline=${inlineChanged}`,
          8
        );
      };

      const queueMutations = (mutations) => {
        if (applying || !mutations || mutations.length === 0) return;
        if (!documentIsVisible()) {
          hiddenMutationDeferred = true;
          hiddenMutationDeferrals += 1;
          queuedMutations = [];
          mutationQueueOverflow = false;
          dirtyRoots.add(document);
          return;
        }
        if (mutationQueueOverflow || queuedMutations.length + mutations.length > MAX_QUEUED_MUTATIONS) {
          queuedMutations = [];
          mutationQueueOverflow = true;
          mutationQueueOverflows += 1;
        } else {
          queuedMutations.push(...mutations);
        }
        if (mutationFlushScheduled) return;
        mutationFlushScheduled = true;
        mutationFlushTimer = window.setTimeout(() => {
          const flushStartedAt = __wkdomainsDarkModeNow();
          mutationFlushScheduled = false;
          mutationFlushTimer = null;
          if (mutationQueueOverflow) {
            mutationQueueOverflow = false;
            queuedMutations = [];
            dirtyRoots.add(document);
            scheduleStartupAwareStyleSync(0);
            schedule(0);
            return;
          }
          const mutationsToHandle = queuedMutations;
          queuedMutations = [];
          handleMutations(mutationsToHandle);
          __wkdomainsDarkModePerf("flush-mutation-queue", flushStartedAt, `mutations=${mutationsToHandle.length}`, 8);
        }, 16);
      };

      const watchRoot = (root) => {
        if (!root || rootObservers.has(root) || !window.MutationObserver) return;
        const target = root.nodeType === Node.DOCUMENT_NODE ? document.documentElement : root;
        if (!target) return;

        const observer = new MutationObserver(queueMutations);
        observer.observe(target, {
          attributes: true,
          attributeFilter: [
            "style",
            "fill",
            "stroke",
            "stop-color",
            "bgcolor",
            "color",
            "background",
            "class",
            "disabled",
            "href",
            "media",
            "hidden",
            "open",
            "popover",
            "role",
            "aria-hidden",
            "aria-expanded",
            "aria-modal"
          ],
          childList: true,
          attributeOldValue: true,
          subtree: true
        });
        rootObservers.set(root, observer);
      };
    """#
}
