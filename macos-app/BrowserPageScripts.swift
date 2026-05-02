//
//  BrowserPageScripts.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

extension BrowserModel {
    static let xhrTrackingScript = """
    (() => {
      if (window.__wkdomainsXHRInstalled) return;
      window.__wkdomainsXHRInstalled = true;

      let nextID = 1;

      const post = (payload) => {
        try {
          window.webkit.messageHandlers.wkdomainsXHR.postMessage({
            pageURL: location.href,
            pageHost: location.hostname,
            ...payload
          });
        } catch (_) {}
      };

      const requestID = () => `${Date.now()}-${nextID++}`;

      const normalizeURL = (input) => {
        try {
          if (input instanceof Request) return input.url;
          if (input && typeof input === "object" && "href" in input) return input.href;
          return new URL(String(input), location.href).href;
        } catch (_) {
          return String(input);
        }
      };

      const byteSize = (text) => {
        try {
          if (window.TextEncoder) return new TextEncoder().encode(text).length;
        } catch (_) {}

        return String(text || "").length;
      };

      const valueType = (value) => {
        if (value === null) return "null";
        if (Array.isArray(value)) return "array";
        return typeof value;
      };

      const truncatedKeys = (object, limit = 20) => {
        if (!object || typeof object !== "object" || Array.isArray(object)) return [];

        const keys = Object.keys(object);
        if (keys.length <= limit) return keys;

        return keys.slice(0, limit).concat(`+${keys.length - limit} more`);
      };

      const isPlainObject = (value) => {
        return !!value && typeof value === "object" && !Array.isArray(value);
      };

      const hasOnlyKeys = (value, expectedKeys) => {
        if (!isPlainObject(value)) return false;

        const keys = Object.keys(value);
        if (keys.length !== expectedKeys.length) return false;

        return expectedKeys.every((key) => keys.includes(key));
      };

      const isCRUDObject = (value) => {
        return hasOnlyKeys(value, ["c", "r", "u", "d"])
          && ["c", "r", "u", "d"].every((key) => typeof value[key] === "boolean");
      };

      const isCapabilityObject = (value) => {
        return isPlainObject(value) && Object.prototype.hasOwnProperty.call(value, "included");
      };

      const collapsedObjectMap = (object) => {
        const keys = Object.keys(object);
        if (keys.length < 4) return undefined;

        const values = keys.map((key) => object[key]);

        if (values.every(isCRUDObject)) {
          return `object<crud permissions>[${truncatedKeys(object).join(",")}]`;
        }

        if (values.every(isCapabilityObject)) {
          return `object<capabilities>[${truncatedKeys(object).join(",")}]`;
        }

        return undefined;
      };

      const sampleScalar = (value) => {
        const type = valueType(value);

        if (type === "string") {
          const text = value.length > 80 ? `${value.slice(0, 80)}...` : value;
          return JSON.stringify(text);
        }

        if (type === "number" || type === "boolean" || type === "null") {
          return String(value);
        }

        return type;
      };

      const shapeForValue = (value, depth = 0) => {
        const type = valueType(value);

        if (type === "array") {
          const count = value.length;
          if (count === 0) return "array[0]";

          return `array[${count}]<${shapeForValue(value[0], depth + 1)}>`;
        }

        if (type !== "object") return sampleScalar(value);

        const collapsed = collapsedObjectMap(value);
        if (collapsed) return collapsed;

        const keys = truncatedKeys(value, depth === 0 ? 45 : 14);
        if (keys.length === 0) return "object{}";

        if (depth >= 3 || (depth > 0 && Object.keys(value).length > 14)) {
          return `object{${keys.join(",")}}`;
        }

        const fields = keys.map((key) => {
          if (key.startsWith("+") && key.endsWith(" more")) return key;
          return `${key}:${shapeForValue(value[key], depth + 1)}`;
        });

        return `object{${fields.join(",")}}`;
      };

      const summarizeJSON = (text) => {
        const summary = {
          responseBytes: typeof text === "string" ? byteSize(text) : undefined
        };

        if (typeof text !== "string" || text.length === 0) return summary;

        try {
          const jsonText = text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text;
          const value = JSON.parse(jsonText);
          const type = valueType(value);

          summary.jsonType = type;
          summary.jsonShape = shapeForValue(value);

          if (type === "array") {
            summary.jsonItems = value.length;
            return summary;
          }
        } catch (_) {}

        return summary;
      };

      const finishFetch = (id, response, url) => {
        const finishPayload = {
          event: "finish",
          id,
          status: response.status,
          responseURL: response.url || url
        };

        try {
          response.clone().text().then((text) => {
            post({ ...finishPayload, ...summarizeJSON(text) });
          }).catch(() => {
            post(finishPayload);
          });
        } catch (_) {
          post(finishPayload);
        }
      };

      const xhrResponseText = (xhr) => {
        try {
          if (!xhr.responseType || xhr.responseType === "text") return xhr.responseText;
          if (xhr.responseType === "json") return JSON.stringify(xhr.response);
        } catch (_) {}

        try {
          if (xhr.response instanceof ArrayBuffer) return { responseBytes: xhr.response.byteLength };
          if (xhr.response instanceof Blob) return { responseBytes: xhr.response.size };
        } catch (_) {}

        return undefined;
      };

      const originalFetch = window.fetch;
      if (typeof originalFetch === "function") {
        window.fetch = function(input, init) {
          const id = requestID();
          const method = (init && init.method) || (input && input.method) || "GET";
          const url = normalizeURL(input);

          post({ event: "start", id, kind: "fetch", method, url });

          return originalFetch.apply(this, arguments).then((response) => {
            finishFetch(id, response, url);
            return response;
          }).catch((error) => {
            post({
              event: "error",
              id,
              error: error && error.message ? error.message : String(error)
            });
            throw error;
          });
        };
      }

      const OriginalXHR = window.XMLHttpRequest;
      if (typeof OriginalXHR === "function") {
        const originalOpen = OriginalXHR.prototype.open;
        const originalSend = OriginalXHR.prototype.send;

        OriginalXHR.prototype.open = function(method, url) {
          this.__wkdomainsXHR = {
            method: method || "GET",
            url: normalizeURL(url)
          };

          return originalOpen.apply(this, arguments);
        };

        OriginalXHR.prototype.send = function() {
          const info = this.__wkdomainsXHR || {};
          const id = requestID();
          info.id = id;

          post({
            event: "start",
            id,
            kind: "xmlhttprequest",
            method: info.method || "GET",
            url: info.url || ""
          });

          this.addEventListener("loadend", () => {
            const body = xhrResponseText(this);
            const bodySummary = typeof body === "string"
              ? summarizeJSON(body)
              : (body || {});

            post({
              event: "finish",
              id,
              status: this.status,
              responseURL: this.responseURL || info.url || "",
              ...bodySummary
            });
          }, { once: true });

          this.addEventListener("error", () => {
            post({ event: "error", id, error: "XMLHttpRequest error" });
          }, { once: true });

          this.addEventListener("abort", () => {
            post({ event: "error", id, error: "XMLHttpRequest aborted" });
          }, { once: true });

          return originalSend.apply(this, arguments);
        };
      }
    })();
    """

    static let renderInvalidationScript = """
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
    """

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
