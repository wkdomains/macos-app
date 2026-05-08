//
//  BrowserDarkModeScripts.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static var darkModeUsesIsolatedContentWorld: Bool {
        (UserDefaults.standard.object(forKey: "wkdomains.darkModeUseIsolatedWorld") as? Bool) ?? true
    }

    private static let bundledDarkModeSiteFixConfig: String = {
        if
            let url = Bundle.main.url(forResource: "dynamic-theme-fixes", withExtension: "config"),
            let config = try? String(contentsOf: url, encoding: .utf8)
        {
            return config
        }
        return ""
    }()

    static var darkModeSiteFixConfig: String {
        if let config = UserDefaults.standard.string(forKey: "wkdomains.darkModeDynamicThemeFixesConfig"), !config.isEmpty {
            return config
        }
        if
            let path = UserDefaults.standard.string(forKey: "wkdomains.darkModeDynamicThemeFixesConfigPath"),
            !path.isEmpty,
            let config = try? String(contentsOfFile: path, encoding: .utf8)
        {
            return config
        }
        return bundledDarkModeSiteFixConfig
    }

    static var darkModeThemeConfig: [String: Any] {
        let defaults = UserDefaults.standard
        func number(_ keys: [String], _ fallback: Int, minimum: Int, maximum: Int) -> Int {
            for key in keys {
                guard let value = defaults.object(forKey: key) else { continue }
                let parsed: Int?
                if let number = value as? NSNumber {
                    parsed = number.intValue
                } else if let string = value as? String {
                    parsed = Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    parsed = nil
                }
                if let parsed {
                    return min(max(parsed, minimum), maximum)
                }
            }
            return fallback
        }

        func string(_ keys: [String], fallback: String) -> String {
            for key in keys {
                if let value = defaults.string(forKey: key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
            return fallback
        }

        return [
            "mode": number(["wkdomains.darkModeThemeMode", "wkdomains.darkModeMode"], 1, minimum: 0, maximum: 1),
            "brightness": number(["wkdomains.darkModeThemeBrightness", "wkdomains.darkModeBrightness"], 100, minimum: 50, maximum: 150),
            "contrast": number(["wkdomains.darkModeThemeContrast", "wkdomains.darkModeContrast"], 100, minimum: 50, maximum: 150),
            "sepia": number(["wkdomains.darkModeThemeSepia", "wkdomains.darkModeSepia"], 0, minimum: 0, maximum: 100),
            "grayscale": number(["wkdomains.darkModeThemeGrayscale", "wkdomains.darkModeGrayscale"], 0, minimum: 0, maximum: 100),
            "darkSchemeBackgroundColor": string(["wkdomains.darkModeThemeBackgroundColor", "wkdomains.darkModeBackgroundColor"], fallback: "#181a1b"),
            "darkSchemeTextColor": string(["wkdomains.darkModeThemeTextColor", "wkdomains.darkModeTextColor"], fallback: "#e8e6e3"),
            "lightSchemeBackgroundColor": string(["wkdomains.lightModeThemeBackgroundColor", "wkdomains.lightModeBackgroundColor"], fallback: "#ffffff"),
            "lightSchemeTextColor": string(["wkdomains.lightModeThemeTextColor", "wkdomains.lightModeTextColor"], fallback: "#000000")
        ]
    }

    static var darkModeThemeConfigScript: String {
        let data = (try? JSONSerialization.data(withJSONObject: darkModeThemeConfig, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "      Object.assign(THEME, \(json));\n"
    }

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

    nonisolated static func javaScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    static func forcedDarkModeScript(disabledSites: [String]) -> String {
        let disabledSiteList = disabledSites.map(javaScriptStringLiteral).joined(separator: ", ")
        let debugLoggingEnabled = BrowserDebugLogging.darkModeScriptEnabled ? "true" : "false"
        let engineWorldName = Self.darkModeUsesIsolatedContentWorld ? Self.darkModeContentWorldName : "page"
        let engineWorldNameLiteral = javaScriptStringLiteral(engineWorldName)

        return #"""
    (() => {
      if (window.__wkdomainsDarkModeInstalled) return;
      window.__wkdomainsDarkModeInstalled = true;
      const __wkdomainsDarkModeDebugEnabled = \#(debugLoggingEnabled);
      const __wkdomainsDarkModeEngineWorldName = \#(engineWorldNameLiteral);
      const __wkdomainsDarkModeDebug = (phase) => {
        if (!__wkdomainsDarkModeDebugEnabled) return;
        try {
          console.debug("[wkdomains-dark]", phase, location.href, Math.round(performance.now()));
        } catch (_) {}
      };
      __wkdomainsDarkModeDebug("install-start");

      const DISABLED_SITES = new Set([\#(disabledSiteList)]);
      const currentHost = String(location.hostname || "").toLowerCase().replace(/^\.+|\.+$/g, "");
      const disabledSiteMatches = (site) => {
        const normalizedSite = String(site || "").toLowerCase().replace(/^\.+|\.+$/g, "");
        return currentHost === normalizedSite || currentHost.endsWith(`.${normalizedSite}`);
      };
      if (Array.from(DISABLED_SITES).some(disabledSiteMatches)) {
        __wkdomainsDarkModeDebug("disabled-site");
        return;
      }

    \#(Self.browserDarkModeConstantsScript)

    \#(Self.darkModeThemeConfigScript)

    \#(Self.browserDarkModeColorScript)

    \#(Self.browserDarkModeSiteFixesScript(siteFixConfig: Self.darkModeSiteFixConfig))

    \#(Self.browserDarkModeStaticStyleScript)

    \#(Self.browserDarkModeStylesheetScript)

    \#(Self.browserDarkModeInlineDOMScript)

    \#(Self.browserDarkModeRuntimeScript)
      __wkdomainsDarkModeDebug("install-end");
    })();
    """#
    }
}
