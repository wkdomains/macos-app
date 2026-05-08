//
//  BrowserDarkModeRuntimeEnvironmentScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeRuntimeEnvironmentScript = #"""
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
    """#
}
