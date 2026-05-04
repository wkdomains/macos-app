//
//  BrowserDarkModeRuntimeScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeRuntimeScript = #"""
      let forced = null;
      let scheduled = false;
      let applying = false;
      let readyFinalized = false;
      let readyFallbackTimer = null;
      const rootObservers = new WeakMap();
      const dirtyRoots = new Set();
      const installedAt = (() => {
        try { return performance.now(); } catch (_) { return Date.now(); }
      })();

      const elapsedSinceInstall = () => {
        try { return performance.now() - installedAt; } catch (_) { return Date.now() - installedAt; }
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

      const handleMutations = (mutations) => {
        if (applying) return;
        let stylesChanged = false;

        for (const mutation of mutations) {
          if (mutation.type === "attributes") {
            if (ATTRIBUTES_OWNED_BY_DARK_MODE.includes(mutation.attributeName)) {
              continue;
            }
            clearCachedSourceFor(mutation.target);
            markDirty(mutation.target);
            if (shouldManageStyle(mutation.target)) stylesChanged = true;
            continue;
          }

          if (mutation.type === "characterData") {
            if (mutation.target.parentElement && shouldManageStyle(mutation.target.parentElement)) {
              stylesChanged = true;
            }
            markDirty(mutation.target);
            continue;
          }

          for (const node of mutation.addedNodes) {
            if (node.nodeType !== Node.ELEMENT_NODE && node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) continue;
            markDirty(node);
            if (shouldManageStyle(node)) stylesChanged = true;
            if (node.querySelector && node.querySelector(STYLE_SELECTOR)) stylesChanged = true;
            if (node.shadowRoot) discoverShadowRoot(node.shadowRoot);
            if (node.querySelectorAll) {
              for (const host of node.querySelectorAll("*")) {
                if (host.shadowRoot) discoverShadowRoot(host.shadowRoot);
              }
            }
          }

          for (const node of mutation.removedNodes) {
            if (node.nodeType === Node.ELEMENT_NODE && shouldManageStyle(node)) stylesChanged = true;
          }
        }

        if (stylesChanged) scheduleStyleSync(0);
        schedule(0);
      };

      const watchRoot = (root) => {
        if (!root || rootObservers.has(root) || !window.MutationObserver) return;
        const target = root.nodeType === Node.DOCUMENT_NODE ? document.documentElement : root;
        if (!target) return;

        const observer = new MutationObserver(handleMutations);
        observer.observe(target, {
          attributes: true,
          attributeFilter: [
            "class",
            "style",
            "fill",
            "stroke",
            "stop-color",
            "bgcolor",
            "color",
            "background",
            "hidden",
            "aria-hidden",
            "aria-expanded",
            "open",
            "disabled",
            "href",
            "media"
          ],
          childList: true,
          characterData: true,
          subtree: true
        });
        rootObservers.set(root, observer);
      };

      const installShadowRootProxy = () => {
        if (!Element.prototype.attachShadow || Element.prototype.__wkdomainsDarkModeShadowProxy) return;
        const nativeAttachShadow = Element.prototype.attachShadow;
        Object.defineProperty(Element.prototype, "__wkdomainsDarkModeShadowProxy", { value: true });
        Element.prototype.attachShadow = function(init) {
          const root = nativeAttachShadow.call(this, init);
          window.setTimeout(() => discoverShadowRoot(root), 0);
          return root;
        };
      };

      const discoverExistingShadowRoots = (root = document) => {
        if (!root || !root.querySelectorAll) return;
        for (const element of root.querySelectorAll("*")) {
          if (element.shadowRoot) discoverShadowRoot(element.shadowRoot);
        }
      };

      const run = () => {
        scheduled = false;
        if (!document.documentElement || !document.body) return;

        if (forced !== true) {
          forced = !withFallbackDisabled(isPageAlreadyDark);
          if (!forced) {
            removeBaseStyle();
            return;
          }
        }

        applying = true;
        ensureBaseStyle();
        updateManageableStyles(document);
        discoverExistingShadowRoots(document);

        const roots = dirtyRoots.size > 0 ? Array.from(dirtyRoots) : [document];
        dirtyRoots.clear();
        withFallbackDisabled(() => {
          for (const root of roots) {
            applyRoot(root);
          }
        });

        finalizeReadyWhenUseful();
        window.setTimeout(() => {
          applying = false;
        }, 0);
      };

      const schedule = (delay = 80) => {
        if (forced === false) return;
        if (scheduled) return;
        scheduled = true;
        window.setTimeout(run, delay);
      };

      installStylesheetProxy();
      installShadowRootProxy();

      document.addEventListener("DOMContentLoaded", () => {
        watchRoot(document);
        dirtyRoots.add(document);
        scheduleStyleSync(0);
        schedule(0);
      }, { once: true });
      window.addEventListener("load", () => {
        dirtyRoots.add(document);
        scheduleStyleSync(0);
        schedule(40);
      }, { passive: true });
      window.addEventListener("pageshow", () => {
        dirtyRoots.add(document);
        scheduleStyleSync(0);
        schedule(40);
      }, { passive: true });

      watchRoot(document);
      dirtyRoots.add(document);
      scheduleStyleSync(0);
      schedule(0);
    """#
}
