//
//  BrowserPageScripts.swift
//  macos-app
//
//  Page script constants are split by responsibility into nearby files.
//

import Foundation

extension BrowserModel {
    static let renderInvalidationScript = """
    (() => {
      if (window.__wkdomainsRenderInvalidationInstalled) return;
      window.__wkdomainsRenderInvalidationInstalled = true;

      let pending = false;
      const post = (reason) => {
        if (pending) return;
        pending = true;
        setTimeout(() => {
          pending = false;
          try {
            window.webkit.messageHandlers.wkdomainsRender.postMessage({
              type: "render-invalidated",
              reason,
              href: location.href,
              timestamp: Date.now()
            });
          } catch (_) {}
        }, 120);
      };

      window.addEventListener("load", () => post("load"), { passive: true });
      window.addEventListener("resize", () => post("resize"), { passive: true });
      window.addEventListener("scroll", () => post("scroll"), { passive: true });

      const observe = () => {
        if (!document.documentElement) return;
        const observer = new MutationObserver(() => post("mutation"));
        observer.observe(document.documentElement, {
          subtree: true,
          childList: true,
          attributes: true,
          characterData: true
        });
      };

      if (document.documentElement) {
        observe();
      } else {
        document.addEventListener("DOMContentLoaded", observe, { once: true });
      }
    })();
    """
}
