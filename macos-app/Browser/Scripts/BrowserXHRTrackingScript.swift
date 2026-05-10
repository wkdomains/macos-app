//
//  BrowserXHRTrackingScript.swift
//  macos-app
//

import Foundation

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

      const normalizedHeaders = (headers) => {
        const result = {};

        try {
          if (!headers) return result;

          new Headers(headers).forEach((value, name) => {
            result[String(name).toLowerCase()] = String(value);
          });
        } catch (_) {}

        return result;
      };

      const fetchHeaders = (input, init) => {
        return {
          ...normalizedHeaders(input instanceof Request ? input.headers : undefined),
          ...normalizedHeaders(init && init.headers)
        };
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

      const truncateText = (value, limit = 2200) => {
        const text = String(value || "");
        return text.length > limit ? `${text.slice(0, limit)}...` : text;
      };

      const shouldRedactKey = (key) => {
        return /(authorization|cookie|password|secret|session_token|access_token|refresh_token|id_token|bearer|stripe|api[_-]?key)/i.test(String(key || ""));
      };

      const redactedJSON = (value, depth = 0) => {
        if (depth > 6) return "[truncated]";
        if (Array.isArray(value)) return value.slice(0, 20).map((item) => redactedJSON(item, depth + 1));
        if (!value || typeof value !== "object") return value;

        const output = {};
        Object.keys(value).slice(0, 60).forEach((key) => {
          output[key] = shouldRedactKey(key) ? "[redacted]" : redactedJSON(value[key], depth + 1);
        });

        return output;
      };

      const bodyPreviewFor = (text) => {
        if (typeof text !== "string" || text.length === 0) return undefined;

        try {
          const jsonText = text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text;
          return truncateText(JSON.stringify(redactedJSON(JSON.parse(jsonText))));
        } catch (_) {
          return truncateText(text.replace(/\\s+/g, " ").trim());
        }
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
          if (shouldRedactKey(key)) return `${key}:"[redacted]"`;
          return `${key}:${shapeForValue(value[key], depth + 1)}`;
        });

        return `object{${fields.join(",")}}`;
      };

      const summarizeJSON = (text) => {
        const summary = {
          responseBytes: typeof text === "string" ? byteSize(text) : undefined
        };

        if (typeof text !== "string" || text.length === 0) return summary;
        summary.responseBodyPreview = bodyPreviewFor(text);

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

      const headerValue = (headers, name) => {
        try {
          return headers.get(name) || "";
        } catch (_) {
          return "";
        }
      };

      const responseContentLength = (response) => {
        const rawLength = headerValue(response.headers, "content-length");
        if (!rawLength) return undefined;

        const length = Number(rawLength);
        return Number.isFinite(length) && length >= 0 ? length : undefined;
      };

      const responseHeaderSummary = (response) => {
        const length = responseContentLength(response);
        return length === undefined ? {} : { responseBytes: length };
      };

      const finishFetch = (id, response, url) => {
        const finishPayload = {
          event: "finish",
          id,
          status: response.status,
          responseURL: response.url || url
        };
        const headerSummary = responseHeaderSummary(response);

        try {
          response.clone().text().then((text) => {
            post({ ...finishPayload, ...summarizeJSON(text) });
          }).catch(() => {
            post({ ...finishPayload, ...headerSummary });
          });
        } catch (_) {
          post({ ...finishPayload, ...headerSummary });
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
          const requestHeaders = fetchHeaders(input, init);

          post({
            event: "start",
            id,
            kind: "fetch",
            method,
            url,
            requestHeaders,
            userAgent: navigator.userAgent
          });

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
        const originalSetRequestHeader = OriginalXHR.prototype.setRequestHeader;
        const originalSend = OriginalXHR.prototype.send;

        OriginalXHR.prototype.open = function(method, url) {
          this.__wkdomainsXHR = {
            method: method || "GET",
            url: normalizeURL(url),
            headers: {}
          };

          return originalOpen.apply(this, arguments);
        };

        OriginalXHR.prototype.setRequestHeader = function(name, value) {
          if (!this.__wkdomainsXHR) this.__wkdomainsXHR = { headers: {} };
          if (!this.__wkdomainsXHR.headers) this.__wkdomainsXHR.headers = {};

          this.__wkdomainsXHR.headers[String(name).toLowerCase()] = String(value);

          return originalSetRequestHeader.apply(this, arguments);
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
            url: info.url || "",
            requestHeaders: info.headers || {},
            userAgent: navigator.userAgent
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

}
