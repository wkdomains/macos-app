//
//  BrowserDarkModeScripts.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let renderInvalidationScript = #"""
    (() => {
      if (window.__wkdomainsRenderInstalled) return;
      window.__wkdomainsRenderInstalled = true;

      let timer;

      const post = (reason) => {
        try {
          window.webkit.messageHandlers.wkdomainsRender.postMessage({
            reason,
            pageURL: location.href
          });
        } catch (_) {}
      };

      const schedule = (reason) => {
        window.clearTimeout(timer);
        timer = window.setTimeout(() => post(reason), 180);
      };

      window.addEventListener("load", () => schedule("load"), { passive: true });
      window.addEventListener("pageshow", () => schedule("pageshow"), { passive: true });
      window.addEventListener("resize", () => schedule("resize"), { passive: true });
      window.addEventListener("scroll", () => schedule("scroll"), { passive: true, capture: true });
      document.addEventListener("readystatechange", () => schedule("readystatechange"));

      if (window.visualViewport) {
        window.visualViewport.addEventListener("resize", () => schedule("visualViewportResize"), { passive: true });
        window.visualViewport.addEventListener("scroll", () => schedule("visualViewportScroll"), { passive: true });
      }

      const observeDocument = () => {
        if (!document.documentElement || !window.MutationObserver) return;

        const observer = new MutationObserver(() => schedule("mutation"));
        observer.observe(document.documentElement, {
          attributes: true,
          attributeFilter: [
            "class",
            "hidden",
            "aria-hidden",
            "aria-expanded",
            "open",
            "src",
            "href"
          ],
          childList: true,
          characterData: true,
          subtree: true
        });
      };

      if (document.documentElement) {
        observeDocument();
      } else {
        document.addEventListener("DOMContentLoaded", observeDocument, { once: true });
      }

      schedule("install");
    })();
    """#

    nonisolated private static func javaScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    static func forcedDarkModeScript(disabledSites: [String]) -> String {
        let disabledSiteList = disabledSites.map(javaScriptStringLiteral).joined(separator: ", ")

        return #"""
    (() => {
      if (window.__wkdomainsDarkModeInstalled) return;
      window.__wkdomainsDarkModeInstalled = true;

      const DISABLED_SITES = new Set([\#(disabledSiteList)]);
      const currentHost = String(location.hostname || "").toLowerCase().replace(/^\.+|\.+$/g, "");
      if (DISABLED_SITES.has(currentHost)) {
        return;
      }

    \#(Self.browserDarkModeConstantsScript)

    \#(Self.browserDarkModeColorScript)

    \#(Self.browserDarkModeStaticStyleScript)

    \#(Self.browserDarkModeStylesheetScript)

    \#(Self.browserDarkModeInlineDOMScript)

    \#(Self.browserDarkModeRuntimeScript)
    })();
    """#
    }
}
