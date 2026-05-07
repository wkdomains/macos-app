//
//  BrowserDarkModeRuntimeScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeRuntimeScript = #"""
      let forced = null;
      let scheduled = false;
      let scheduledTimer = null;
      let applying = false;
      let readyFinalized = false;
      let readyFallbackTimer = null;
      const rootObservers = new Map();
      const dirtyRoots = new Set();
      let shadowProxyActive = false;
      let customElementRegistryProxyActive = false;
      const INLINE_STYLE_MUTATION_ATTRIBUTES = new Set(INLINE_STYLE_ATTRS);
      const STYLE_SHEET_MUTATION_ATTRIBUTES = new Set(["href", "media", "disabled"]);
      let queuedMutations = [];
      let mutationQueueOverflow = false;
      let mutationFlushScheduled = false;
      let mutationFlushTimer = null;
      const MAX_QUEUED_MUTATIONS = 800;
      const installedAt = (() => {
        try { return performance.now(); } catch (_) { return Date.now(); }
      })();

      const elapsedSinceInstall = () => {
        try { return performance.now() - installedAt; } catch (_) { return Date.now() - installedAt; }
      };

      const removeNode = (node) => {
        try { node?.parentNode?.removeChild(node); } catch (_) {}
      };

      const documentIsVisible = () => document.visibilityState !== "hidden";

      const runWhenDocumentVisible = (callback) => {
        if (documentIsVisible()) {
          callback();
          return;
        }

        const onVisible = () => {
          if (!documentIsVisible()) return;
          document.removeEventListener("visibilitychange", onVisible);
          callback();
        };
        document.addEventListener("visibilitychange", onVisible);
        cleanupTasks.push(() => document.removeEventListener("visibilitychange", onVisible));
      };

      const createDarkReaderInstanceMarker = () => {
        if (!document.head) return;
        let meta = document.head.querySelector(`meta[name="${DARKREADER_META_NAME}"]`);
        if (!meta) {
          meta = document.createElement("meta");
          meta.name = DARKREADER_META_NAME;
          document.head.appendChild(meta);
        }
        meta.content = INSTANCE_ID;
      };

      const isDRLocked = () => !!document.querySelector(`meta[name="${DARKREADER_LOCK_META_NAME}"]`);

      const addMetaListener = () => {
        if (!window.MutationObserver || metaObserver || !document.head) return;
        metaObserver = new MutationObserver(() => {
          if (isDRLocked()) {
            metaObserver?.disconnect();
            metaObserver = null;
            removeDynamicTheme();
          }
        });
        metaObserver.observe(document.head, { childList: true, subtree: true });
      };

      const isAnotherDarkReaderInstanceActive = () => {
        const meta = document.querySelector(`meta[name="${DARKREADER_META_NAME}"]`);
        if (meta) {
          return meta.content !== INSTANCE_ID;
        }
        createDarkReaderInstanceMarker();
        addMetaListener();
        return false;
      };

      const interceptOldScript = ({ success, failure }) => {
        if (--interceptorAttempts <= 0) {
          failure();
          return;
        }

        const oldMeta = document.head?.querySelector(`meta[name="${DARKREADER_META_NAME}"]`);
        if (!oldMeta || oldMeta.content === INSTANCE_ID) {
          success();
          return;
        }

        const lock = document.createElement("meta");
        lock.name = DARKREADER_LOCK_META_NAME;
        document.head.append(lock);
        queueMicrotask(() => {
          lock.remove();
          createDarkReaderInstanceMarker();
          addMetaListener();
          success();
        });
      };

      const disableConflictingPlugins = () => {
        if (!document.documentElement || !document.documentElement.hasAttribute("data-wp-dark-mode-preset")) return;

        const disableWPDarkMode = () => {
          document.dispatchEvent(new CustomEvent("__darkreader__disableConflictingPlugins"));
          document.documentElement.classList.remove("wp-dark-mode-active");
          document.documentElement.removeAttribute("data-wp-dark-mode-active");
        };

        disableWPDarkMode();
        if (!window.MutationObserver) return;
        const observer = new MutationObserver(() => {
          if (
            document.documentElement.classList.contains("wp-dark-mode-active")
            || document.documentElement.hasAttribute("data-wp-dark-mode-active")
          ) {
            disableWPDarkMode();
          }
        });
        observer.observe(document.documentElement, {
          attributes: true,
          attributeFilter: ["class", "data-wp-dark-mode-active"]
        });
        cleanupTasks.push(() => observer.disconnect());
      };

      const setupDocumentPiPFontFix = () => {
        if (pipListenerRegistered) return;
        const docPiP = window.documentPictureInPicture;
        if (!docPiP) return;
        pipListenerRegistered = true;

        const collectFontSheetCSS = () => {
          const fontSheetRules = [];
          for (const sheet of document.styleSheets) {
            try {
              const rules = Array.from(sheet.cssRules);
              if (rules.some((rule) => window.CSSFontFaceRule && rule instanceof CSSFontFaceRule)) {
                for (const rule of rules) {
                  fontSheetRules.push(rule.cssText);
                }
              }
            } catch (_) {}
          }
          return fontSheetRules.join("\n");
        };

        const injectFontCSS = (pipDoc, fontCSS) => {
          if (!pipDoc || pipDoc.querySelector(".wkdomains-darkreader--font-fix")) return;
          const style = pipDoc.createElement("style");
          style.classList.add(INLINE_CLASS, "darkreader", "wkdomains-darkreader--font-fix");
          style.textContent = fontCSS;
          (pipDoc.head || pipDoc.documentElement).appendChild(style);
        };

        const onPiPEnter = () => {
          const pipWindow = docPiP.window;
          if (!pipWindow) return;
          const fontCSS = collectFontSheetCSS();
          if (!fontCSS) return;
          const pipDoc = pipWindow.document;
          injectFontCSS(pipDoc, fontCSS);
          if (!window.MutationObserver) return;
          const observer = new MutationObserver(() => injectFontCSS(pipDoc, fontCSS));
          observer.observe(pipDoc, { childList: true, subtree: true });
          pipWindow.addEventListener("unload", () => observer.disconnect(), { once: true });
        };

        docPiP.addEventListener("enter", onPiPEnter);
        cleanupTasks.push(() => {
          docPiP.removeEventListener("enter", onPiPEnter);
          pipListenerRegistered = false;
        });
      };

      const documentGeometryFor = (element) => {
        try {
          const scrollingElement = document.scrollingElement || document.documentElement || document.body;
          const pageWidth = Math.max(
            scrollingElement ? scrollingElement.scrollWidth || 0 : 0,
            document.documentElement ? document.documentElement.scrollWidth || 0 : 0,
            document.body ? document.body.scrollWidth || 0 : 0,
            innerWidth
          );
          const pageHeight = Math.max(
            scrollingElement ? scrollingElement.scrollHeight || 0 : 0,
            document.documentElement ? document.documentElement.scrollHeight || 0 : 0,
            document.body ? document.body.scrollHeight || 0 : 0,
            innerHeight
          );
          const rect = element.getBoundingClientRect();
          const left = clamp(rect.left + scrollX, 0, pageWidth);
          const right = clamp(rect.right + scrollX, 0, pageWidth);
          const top = clamp(rect.top + scrollY, 0, pageHeight);
          const bottom = clamp(rect.bottom + scrollY, 0, pageHeight);
          const width = Math.max(0, right - left);
          const height = Math.max(0, bottom - top);
          const area = width * height;
          const viewportArea = Math.max(1, innerWidth * innerHeight);
          const documentArea = Math.max(1, pageWidth * pageHeight);

          return {
            area,
            height,
            viewportAreaShare: area / viewportArea,
            documentAreaShare: area / documentArea,
            widthShare: width / Math.max(1, pageWidth)
          };
        } catch (_) {
          return null;
        }
      };

      const hasLargeLightDocumentSurface = () => {
        if (!document.documentElement || !document.body || innerWidth <= 0 || innerHeight <= 0) {
          return false;
        }

        const candidates = new Set([
          document.documentElement,
          document.body,
          ...document.querySelectorAll([
            "main",
            "section",
            "article",
            "aside",
            "header",
            "footer",
            "[class*='bg']",
            "[class*='surface']",
            "[class*='section']",
            "[class*='component']",
            "[class*='container']",
            "[class*='wrapper']"
          ].join(","))
        ]);

        for (const element of candidates) {
          if (!element || SKIP_TAGS.has(element.tagName.toUpperCase())) continue;

          const style = getComputedStyle(element);
          if (style.display === "none" || style.visibility === "hidden" || Number.parseFloat(style.opacity || "1") <= 0.02) {
            continue;
          }

          const geometry = documentGeometryFor(element);
          if (!geometry || geometry.area <= 0) continue;

          const largeSurface = geometry.viewportAreaShare > 0.26
            || geometry.documentAreaShare > 0.045
            || (geometry.widthShare > 0.72 && geometry.height > 180);
          if (!largeSurface) continue;

          if (relativeLuminance(surfaceColorFor(element)) > 0.68) {
            return true;
          }
        }

        return false;
      };

      const isPageAlreadyDark = () => {
        if (!document.documentElement || !document.body || innerWidth <= 0 || innerHeight <= 0) {
          return false;
        }

        const rootStyle = getComputedStyle(document.documentElement);
        if (rootStyle.filter.includes("invert(1)")) return true;

        const columns = Math.min(4, Math.max(1, Math.ceil(innerWidth / 256)));
        const rows = Math.min(4, Math.max(1, Math.ceil(innerHeight / 256)));
        let darkCount = 0;
        let total = 0;
        let luminanceSum = 0;

        for (let row = 0; row < rows; row += 1) {
          for (let column = 0; column < columns; column += 1) {
            const x = Math.floor((column + 0.5) * innerWidth / columns);
            const y = Math.floor((row + 0.5) * innerHeight / rows);
            const element = document.elementFromPoint(x, y);
            if (!element) continue;

            const luminance = relativeLuminance(surfaceColorFor(element));
            luminanceSum += luminance;
            total += 1;
            if (luminance < 0.34) darkCount += 1;
          }
        }

        if (total === 0) return false;
        const average = luminanceSum / total;
        const darkShare = darkCount / total;
        return darkShare >= 0.65 && average < 0.42 && !hasLargeLightDocumentSurface();
      };

      const hasUsefulRenderedContent = () => {
        if (!document.body) return false;

        const text = (document.body.innerText || document.body.textContent || "").trim();
        if (text.length > 550) return true;

        const usefulElementCount = document.body.querySelectorAll("article, main, h1, h2, h3, p, li, td, a").length;
        if (usefulElementCount > 22) return true;

        const bodyHeight = Math.max(
          document.body.scrollHeight || 0,
          document.documentElement ? document.documentElement.scrollHeight || 0 : 0
        );

        return usefulElementCount > 6 && bodyHeight > Math.max(900, innerHeight * 1.25);
      };

      const finalizeReadyWhenUseful = () => {
        const root = document.documentElement;
        if (!root || readyFinalized) return;

        if (hasUsefulRenderedContent() || document.readyState !== "loading" || elapsedSinceInstall() > 650) {
          root.setAttribute(READY_ATTRIBUTE, "true");
          readyFinalized = true;
          if (readyFallbackTimer) {
            window.clearTimeout(readyFallbackTimer);
            readyFallbackTimer = null;
          }
          return;
        }

        if (!readyFallbackTimer) {
          readyFallbackTimer = window.setTimeout(() => {
            readyFallbackTimer = null;
            finalizeReadyWhenUseful();
          }, 45);
        }
      };

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

      const normalizeDirtyRoots = () => {
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

      const discoverShadowRootsForAddedNode = (node) => {
        if (!node) return;
        if (node.nodeType === Node.ELEMENT_NODE && node.shadowRoot) {
          discoverShadowRoot(node.shadowRoot);
        }
        const deferred = discoverExistingShadowRoots(node, 512);
        if (deferred) {
          window.setTimeout(() => discoverExistingShadowRoots(node), 0);
        }
      };

      const handleMutations = (mutations) => {
        if (applying) return;
        let stylesChanged = false;
        let inlineChanged = false;

        for (const mutation of mutations) {
          if (mutation.type === "attributes") {
            if (ATTRIBUTES_OWNED_BY_DARK_MODE.includes(mutation.attributeName)) {
              continue;
            }
            if (INLINE_STYLE_MUTATION_ATTRIBUTES.has(mutation.attributeName)) {
              clearCachedSourceFor(mutation.target);
              markDirty(mutation.target);
              inlineChanged = true;
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
            if (shouldManageStyle(node)) stylesChanged = true;
            if (node.querySelector && node.querySelector(STYLE_SELECTOR)) stylesChanged = true;
            if (
              node.nodeType === Node.DOCUMENT_FRAGMENT_NODE
              || (node.matches && node.matches(STYLE_OVERRIDE_SELECTOR))
              || (node.querySelector && node.querySelector(STYLE_OVERRIDE_SELECTOR))
            ) {
              markDirty(node);
              inlineChanged = true;
            }
            discoverShadowRootsForAddedNode(node);
          }

          for (const node of mutation.removedNodes) {
            if (node.nodeType === Node.ELEMENT_NODE && shouldManageStyle(node)) stylesChanged = true;
          }
        }

        if (stylesChanged) scheduleStyleSync(0);
        if (inlineChanged) schedule(0);
      };

      const queueMutations = (mutations) => {
        if (applying || !mutations || mutations.length === 0) return;
        if (mutationQueueOverflow || queuedMutations.length + mutations.length > MAX_QUEUED_MUTATIONS) {
          queuedMutations = [];
          mutationQueueOverflow = true;
        } else {
          queuedMutations.push(...mutations);
        }
        if (mutationFlushScheduled) return;
        mutationFlushScheduled = true;
        mutationFlushTimer = window.setTimeout(() => {
          mutationFlushScheduled = false;
          mutationFlushTimer = null;
          if (mutationQueueOverflow) {
            mutationQueueOverflow = false;
            queuedMutations = [];
            dirtyRoots.add(document);
            scheduleStyleSync(0);
            schedule(0);
            return;
          }
          const mutationsToHandle = queuedMutations;
          queuedMutations = [];
          handleMutations(mutationsToHandle);
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
            "disabled",
            "href",
            "media"
          ],
          childList: true,
          subtree: true
        });
        rootObservers.set(root, observer);
      };

      const installShadowRootProxy = () => {
        if (siteFixFlag("disableShadowRootProxy")) return;
        shadowProxyActive = true;
        if (!Element.prototype.attachShadow || Element.prototype.__wkdomainsDarkModeShadowProxy) return;
        const nativeAttachShadow = Element.prototype.attachShadow;
        defineHiddenProperty(Element.prototype, "__wkdomainsDarkModeShadowProxy", true);
        rememberPropertyDescriptor(Element.prototype, "attachShadow");
        Element.prototype.attachShadow = function(init) {
          const root = nativeAttachShadow.call(this, init);
          if (shadowProxyActive) {
            window.setTimeout(() => discoverShadowRoot(root), 0);
          }
          return root;
        };
      };

      const installCustomElementRegistryProxy = () => {
        if (siteFixFlag("disableCustomElementRegistryProxy") || !siteFixFlag("enableCustomElementRegistryProxy")) return;
        if (!window.customElements || customElements.__wkdomainsDarkModeRegistryProxy) {
          customElementRegistryProxyActive = true;
          return;
        }
        const nativeDefine = customElements.define;
        try {
          defineHiddenProperty(customElements, "__wkdomainsDarkModeRegistryProxy", true);
          rememberPropertyDescriptor(customElements, "define");
          customElements.define = function(name, constructor, options) {
            const result = nativeDefine.call(this, name, constructor, options);
            if (customElementRegistryProxyActive) {
              window.setTimeout(() => discoverExistingShadowRoots(document), 0);
            }
            return result;
          };
          customElementRegistryProxyActive = true;
        } catch (_) {}
      };

      const run = () => {
        __wkdomainsDarkModeDebug("run-start");
        scheduled = false;
        if (!document.documentElement || !document.body) return;

        forced = true;

        applying = true;
        __wkdomainsDarkModeDebug("run-base-style");
        ensureBaseStyle();
        discoverExistingShadowRoots(document);
        __wkdomainsDarkModeDebug("run-sync-styles");
        flushStyleSyncNow();
        ensureSiteFixStyle();
        tryInvertPDF();

        const roots = normalizeDirtyRoots();
        dirtyRoots.clear();
        __wkdomainsDarkModeDebug(`run-apply-roots:${roots.length}`);
        withFallbackDisabled(() => {
          for (const root of roots) {
            applyRoot(root);
          }
        });
        ensureSiteFixStyle();
        tryInvertPDF();

        finalizeReadyWhenUseful();
        __wkdomainsDarkModeDebug("run-end");
        window.setTimeout(() => {
          applying = false;
        }, 0);
      };

      const schedule = (delay = 80) => {
        if (forced === false) return;
        if (scheduled) return;
        scheduled = true;
        scheduledTimer = window.setTimeout(() => {
          scheduledTimer = null;
          run();
        }, delay);
      };

      const handleDOMReady = () => {
        __wkdomainsDarkModeDebug("dom-ready");
        watchRoot(document);
        dirtyRoots.add(document);
        scheduleStyleSync(0);
        schedule(0);
      };

      const handleWindowLoad = () => {
        __wkdomainsDarkModeDebug("window-load");
        dirtyRoots.add(document);
        scheduleStyleSync(0);
        schedule(40);
      };

      const handlePageShow = () => {
        __wkdomainsDarkModeDebug("page-show");
        dirtyRoots.add(document);
        scheduleStyleSync(0);
        schedule(40);
      };

      const runDynamicStyle = () => {
        if (dynamicStyleStarted) return;
        dynamicStyleStarted = true;
        __wkdomainsDarkModeDebug("dynamic-start");
        installStylesheetProxy();
        __wkdomainsDarkModeDebug("dynamic-after-stylesheet-proxy");
        installShadowRootProxy();
        __wkdomainsDarkModeDebug("dynamic-after-shadow-proxy");
        installCustomElementRegistryProxy();
        __wkdomainsDarkModeDebug("dynamic-after-custom-elements");

        document.addEventListener("DOMContentLoaded", handleDOMReady, { once: true });
        window.addEventListener("load", handleWindowLoad, { passive: true });
        window.addEventListener("pageshow", handlePageShow, { passive: true });
        __wkdomainsDarkModeDebug("dynamic-after-listeners");
        cleanupTasks.push(() => {
          document.removeEventListener("DOMContentLoaded", handleDOMReady);
          window.removeEventListener("load", handleWindowLoad);
          window.removeEventListener("pageshow", handlePageShow);
        });

        __wkdomainsDarkModeDebug("dynamic-before-watch-root");
        watchRoot(document);
        __wkdomainsDarkModeDebug("dynamic-after-watch-root");
        dirtyRoots.add(document);
        __wkdomainsDarkModeDebug("dynamic-before-schedule-style-sync");
        scheduleStyleSync(0);
        __wkdomainsDarkModeDebug("dynamic-before-schedule-run");
        schedule(0);
        __wkdomainsDarkModeDebug("dynamic-end");
      };

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
        fallbackWasCleared = false;
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
        if (mutationFlushTimer) {
          window.clearTimeout(mutationFlushTimer);
          mutationFlushTimer = null;
        }
        mutationFlushScheduled = false;
      };

      const removeDynamicTheme = () => {
        cleanDynamicThemeCache();
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
