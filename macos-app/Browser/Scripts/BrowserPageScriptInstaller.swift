//
//  BrowserPageScriptInstaller.swift
//  macos-app
//

import Foundation
import WebKit

extension BrowserModel {
    func installPageTrackingScripts(on userContentController: WKUserContentController) {
        BrowserDebugLogging.log("[wkdomains-debug] scripts install handlers")
        userContentController.add(self, name: "wkdomainsXHR")
        userContentController.add(self, name: "wkdomainsRender")
        userContentController.add(self, name: "wkdomainsConsole")
        userContentController.add(self, name: "wkdomainsLogin")
        installPageTrackingUserScripts(on: userContentController)
    }

    private func installPageTrackingUserScripts(on userContentController: WKUserContentController) {
        BrowserDebugLogging.log("[wkdomains-debug] scripts install userScripts")
        userContentController.addUserScript(
            WKUserScript(
                source: Self.darkReaderExclusionScript(disabledSites: settingsStore.darkDisabledSites),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.xhrTrackingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.renderInvalidationScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.consoleTrackingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.jsonViewerScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: .defaultClient
            )
        )
    }

    func refreshPageTrackingUserScripts() {
        for tab in tabStates {
            let userContentController = tab.webView.configuration.userContentController
            userContentController.removeAllUserScripts()
            installPageTrackingUserScripts(on: userContentController)
        }
    }

    static func darkReaderToggleCleanupScript(isDisabled: Bool) -> String {
        """
        (() => {
          const storageKey = "__darkreader__wasEnabledForHost";
          try {
            if (\(isDisabled ? "true" : "false")) {
              sessionStorage.setItem(storageKey, "false");
            } else {
              sessionStorage.removeItem(storageKey);
            }
          } catch (_) {}

          const removeDarkReaderArtifacts = () => {
            document.documentElement.removeAttribute("data-darkreader-mode");
            document.documentElement.removeAttribute("data-darkreader-scheme");
            document.querySelectorAll(".darkreader, meta[name='darkreader']").forEach((node) => node.remove());
          };

          if (\(isDisabled ? "true" : "false")) {
            let lock = document.querySelector("meta[name='darkreader-lock']");
            if (!lock) {
              lock = document.createElement("meta");
              lock.name = "darkreader-lock";
              (document.head || document.documentElement).append(lock);
            }
            removeDarkReaderArtifacts();
          } else {
            document.querySelectorAll("meta[name='darkreader-lock']").forEach((node) => node.remove());
          }
        })();
        """
    }

    private static func darkReaderExclusionScript(disabledSites: [String]) -> String {
        let sites = disabledSites
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let sitesJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: sites),
           let json = String(data: data, encoding: .utf8) {
            sitesJSON = json
        } else {
            sitesJSON = "[]"
        }

        return """
        (() => {
          const disabledSites = \(sitesJSON);
          if (!disabledSites.length) {
            return;
          }

          const normalizeHost = (host) => String(host || "").toLowerCase().replace(/\\.+$/, "");
          const host = normalizeHost(location.hostname);
          const isDisabled = disabledSites.some((site) => {
            const normalized = normalizeHost(site);
            return host === normalized || host.endsWith(`.${normalized}`);
          });
          if (!isDisabled) {
            return;
          }

          const storageKey = "__darkreader__wasEnabledForHost";
          try {
            sessionStorage.setItem(storageKey, "false");
          } catch (_) {}

          let isCleaning = false;
          const ensureLock = () => {
            if (document.querySelector("meta[name='darkreader-lock']")) {
              return;
            }
            const lock = document.createElement("meta");
            lock.name = "darkreader-lock";
            (document.head || document.documentElement).append(lock);
          };
          const clean = () => {
            if (isCleaning) {
              return;
            }
            isCleaning = true;
            try {
              ensureLock();
              document.documentElement.removeAttribute("data-darkreader-mode");
              document.documentElement.removeAttribute("data-darkreader-scheme");
              document.querySelectorAll(".darkreader, meta[name='darkreader']").forEach((node) => node.remove());
            } finally {
              isCleaning = false;
            }
          };

          clean();
          new MutationObserver(clean).observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ["data-darkreader-mode", "data-darkreader-scheme", "class"]
          });
        })();
        """
    }
}
