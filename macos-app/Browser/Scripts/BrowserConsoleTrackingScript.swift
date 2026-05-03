//
//  BrowserConsoleTrackingScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let consoleTrackingScript = """
    (() => {
      if (window.__wkdomainsConsoleInstalled) return;
      window.__wkdomainsConsoleInstalled = true;

      const stringify = (value) => {
        try {
          if (typeof value === "string") return value;
          if (value instanceof Error) return value.stack || value.message || String(value);
          if (value === undefined) return "undefined";
          return JSON.stringify(value);
        } catch (_) {
          try { return String(value); } catch (_) { return "[unprintable]"; }
        }
      };

      const post = (level, values, stack) => {
        const args = Array.from(values || []).map(stringify).map((text) => {
          if (text.length > 1200) return `${text.slice(0, 1200)}...`;
          return text;
        });

        try {
          window.webkit.messageHandlers.wkdomainsConsole.postMessage({
            level,
            arguments: args,
            message: args.join(" "),
            stack: stack || undefined,
            pageURL: location.href,
            pageHost: location.hostname
          });
        } catch (_) {}
      };

      ["debug", "error", "info", "log", "warn"].forEach((level) => {
        const original = console[level];
        if (typeof original !== "function") return;

        try {
          Object.defineProperty(console, level, {
            configurable: true,
            writable: true,
            value: function() {
              post(level, arguments);
              return original.apply(this, arguments);
            }
          });
        } catch (_) {
          console[level] = function() {
            post(level, arguments);
            return original.apply(this, arguments);
          };
        }
      });

      const originalAssert = console.assert;
      if (typeof originalAssert === "function") {
        try {
          Object.defineProperty(console, "assert", {
            configurable: true,
            writable: true,
            value: function(condition) {
              if (!condition) {
                post("error", Array.prototype.slice.call(arguments, 1));
              }

              return originalAssert.apply(this, arguments);
            }
          });
        } catch (_) {}
      }

      window.addEventListener("error", (event) => {
        post("error", [event.message || "Window error"], event.error && event.error.stack);
      });

      window.addEventListener("unhandledrejection", (event) => {
        post("error", ["Unhandled promise rejection", event.reason], event.reason && event.reason.stack);
      });

      document.addEventListener("securitypolicyviolation", (event) => {
        post("warn", [
          "Content Security Policy violation",
          event.violatedDirective,
          event.blockedURI
        ]);
      });
    })();
    """

}
