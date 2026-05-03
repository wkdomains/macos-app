//
//  BrowserPageScripts.swift
//  macos-app
//
//  Created by aa on 5/2/26.
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

    static let jsonViewerScript = """
    (() => {
      if (window.__wkdomainsJSONViewerInstalled) return;
      window.__wkdomainsJSONViewerInstalled = true;

      const mimeType = String(document.contentType || "").toLowerCase().split(";")[0].trim();
      const isJSONDocument = mimeType === "application/json"
        || mimeType === "text/json"
        || mimeType.endsWith("+json");

      if (!isJSONDocument || !document.body) return;

      const originalText = document.body.innerText || document.body.textContent || "";
      const jsonText = originalText.charCodeAt(0) === 0xFEFF ? originalText.slice(1) : originalText;

      let rootValue;
      try {
        rootValue = JSON.parse(jsonText);
      } catch (_) {
        return;
      }

      const typeOf = (value) => {
        if (value === null) return "null";
        if (Array.isArray(value)) return "array";
        return typeof value;
      };

      const byteSize = (text) => {
        try {
          return new TextEncoder().encode(text).length;
        } catch (_) {
          return text.length;
        }
      };

      const formatBytes = (bytes) => {
        if (bytes < 1024) return `${bytes} B`;
        if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
      };

      const scalarText = (value) => {
        if (typeof value === "string") return JSON.stringify(value);
        if (value === null) return "null";
        return String(value);
      };

      const collectionSize = (value) => {
        if (Array.isArray(value)) return value.length;
        if (value && typeof value === "object") return Object.keys(value).length;
        return 0;
      };

      const addText = (parent, className, text) => {
        const span = document.createElement("span");
        span.className = className;
        span.textContent = text;
        parent.appendChild(span);
        return span;
      };

      const keyLabel = (key) => {
        if (key === null || key === undefined) return "";
        if (typeof key === "number") return String(key);
        return JSON.stringify(String(key));
      };

      const compactPreview = (value) => {
        const type = typeOf(value);
        if (type === "array") return `Array(${value.length})`;
        if (type === "object") return `Object(${Object.keys(value).length})`;
        if (type === "string" && value.length > 64) return `${JSON.stringify(value.slice(0, 64))}...`;
        return scalarText(value);
      };

      const makeScalarRow = (key, value, depth) => {
        const row = document.createElement("div");
        const type = typeOf(value);
        row.className = `json-line depth-${Math.min(depth, 8)}`;
        row.dataset.searchText = `${keyLabel(key)} ${scalarText(value)}`.toLowerCase();

        if (key !== null && key !== undefined) {
          addText(row, "json-key", keyLabel(key));
          addText(row, "json-punctuation", ": ");
        }

        addText(row, `json-value is-${type}`, scalarText(value));
        return row;
      };

      const makeNode = (key, value, depth) => {
        const type = typeOf(value);
        if (type !== "array" && type !== "object") {
          return makeScalarRow(key, value, depth);
        }

        const details = document.createElement("details");
        const count = collectionSize(value);
        const isRoot = key === null || key === undefined;
        details.className = `json-node is-${type} depth-${Math.min(depth, 8)}`;
        details.open = depth < 2 || count <= 3;
        details.dataset.searchText = `${keyLabel(key)} ${type} ${count}`.toLowerCase();

        const summary = document.createElement("summary");
        summary.className = "json-summary";

        addText(summary, "json-fold", "");
        if (!isRoot) {
          addText(summary, "json-key", keyLabel(key));
          addText(summary, "json-punctuation", ": ");
        }

        addText(summary, "json-punctuation", type === "array" ? "[" : "{");
        addText(summary, "json-muted", type === "array" ? `${count} items` : `${count} keys`);
        addText(summary, "json-punctuation", type === "array" ? "]" : "}");
        details.appendChild(summary);

        const children = document.createElement("div");
        children.className = "json-children";

        if (type === "array") {
          value.forEach((item, index) => {
            children.appendChild(makeNode(index, item, depth + 1));
          });
        } else {
          Object.keys(value).forEach((childKey) => {
            children.appendChild(makeNode(childKey, value[childKey], depth + 1));
          });
        }

        if (count === 0) {
          const empty = document.createElement("div");
          empty.className = "json-empty";
          empty.textContent = type === "array" ? "Empty array" : "Empty object";
          children.appendChild(empty);
        }

        details.appendChild(children);
        return details;
      };

      const prettyText = (() => {
        try {
          return JSON.stringify(rootValue, null, 2);
        } catch (_) {
          return jsonText;
        }
      })();

      const style = document.createElement("style");
      style.textContent = `
        :root {
          color-scheme: light dark;
          --json-bg: #fbfbfa;
          --json-surface: #ffffff;
          --json-border: rgba(18, 22, 28, 0.12);
          --json-text: #1c2028;
          --json-muted: #69707d;
          --json-key: #7b341e;
          --json-string: #106b38;
          --json-number: #1459c8;
          --json-boolean: #7b3fb2;
          --json-null: #6d7480;
          --json-accent: #0969da;
          --json-match: #fff2a8;
        }

        @media (prefers-color-scheme: dark) {
          :root {
            --json-bg: #15171a;
            --json-surface: #1c1f23;
            --json-border: rgba(235, 238, 242, 0.14);
            --json-text: #e7e9ee;
            --json-muted: #a3a9b4;
            --json-key: #ffb86b;
            --json-string: #77d889;
            --json-number: #8ab4ff;
            --json-boolean: #d2a8ff;
            --json-null: #aeb5c0;
            --json-accent: #73a7ff;
            --json-match: rgba(255, 212, 79, 0.28);
          }
        }

        html, body {
          min-height: 100%;
          margin: 0;
          background: var(--json-bg);
          color: var(--json-text);
          font: 13px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
        }

        body {
          box-sizing: border-box;
          padding: 24px;
        }

        .json-shell {
          max-width: 1200px;
          margin: 0 auto;
          border: 1px solid var(--json-border);
          border-radius: 8px;
          background: var(--json-surface);
          box-shadow: 0 18px 45px rgba(0, 0, 0, 0.08);
          overflow: hidden;
        }

        .json-toolbar {
          position: sticky;
          top: 0;
          z-index: 2;
          display: flex;
          align-items: center;
          gap: 8px;
          min-height: 52px;
          padding: 8px 12px;
          border-bottom: 1px solid var(--json-border);
          background: color-mix(in srgb, var(--json-surface) 92%, transparent);
          backdrop-filter: blur(14px);
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }

        .json-title {
          display: flex;
          align-items: baseline;
          gap: 8px;
          min-width: 150px;
          margin-right: auto;
          white-space: nowrap;
        }

        .json-title strong {
          font-size: 14px;
          font-weight: 650;
        }

        .json-title span {
          color: var(--json-muted);
          font-size: 12px;
        }

        .json-search {
          width: min(280px, 26vw);
          min-width: 160px;
          height: 32px;
          box-sizing: border-box;
          border: 1px solid var(--json-border);
          border-radius: 6px;
          padding: 0 10px;
          background: var(--json-bg);
          color: var(--json-text);
          font: inherit;
          outline: none;
        }

        .json-search:focus {
          border-color: var(--json-accent);
          box-shadow: 0 0 0 3px color-mix(in srgb, var(--json-accent) 22%, transparent);
        }

        .json-button {
          min-height: 32px;
          border: 1px solid var(--json-border);
          border-radius: 6px;
          padding: 0 10px;
          background: var(--json-surface);
          color: var(--json-text);
          font: inherit;
          cursor: pointer;
        }

        .json-button:hover {
          background: color-mix(in srgb, var(--json-accent) 8%, var(--json-surface));
        }

        .json-button:focus-visible {
          outline: 3px solid color-mix(in srgb, var(--json-accent) 28%, transparent);
          outline-offset: 1px;
        }

        .json-tree,
        .json-raw {
          padding: 18px 22px 24px;
          overflow-x: auto;
        }

        .json-raw {
          display: none;
          margin: 0;
          white-space: pre;
          line-height: 1.55;
        }

        .json-shell[data-view="raw"] .json-tree {
          display: none;
        }

        .json-shell[data-view="raw"] .json-raw {
          display: block;
        }

        .json-line,
        .json-summary {
          min-height: 24px;
          display: flex;
          align-items: center;
          gap: 0;
          border-radius: 5px;
          line-height: 1.6;
          white-space: nowrap;
        }

        .json-line {
          padding-left: calc(var(--depth, 0) * 18px + 20px);
        }

        .json-node {
          --depth: 0;
        }

        .json-node > .json-summary {
          padding-left: calc(var(--depth, 0) * 18px);
          cursor: default;
          list-style: none;
        }

        .json-summary::-webkit-details-marker {
          display: none;
        }

        .depth-1 { --depth: 1; }
        .depth-2 { --depth: 2; }
        .depth-3 { --depth: 3; }
        .depth-4 { --depth: 4; }
        .depth-5 { --depth: 5; }
        .depth-6 { --depth: 6; }
        .depth-7 { --depth: 7; }
        .depth-8 { --depth: 8; }

        .json-line:hover,
        .json-summary:hover {
          background: color-mix(in srgb, var(--json-accent) 7%, transparent);
        }

        .json-fold {
          width: 20px;
          flex: 0 0 20px;
          color: var(--json-muted);
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          text-align: center;
        }

        .json-fold::before {
          content: ">";
          display: inline-block;
          transform: translateY(-1px);
          transition: transform 0.16s ease;
        }

        details[open] > .json-summary .json-fold::before {
          transform: rotate(90deg) translateX(1px);
        }

        @media (prefers-reduced-motion: reduce) {
          .json-fold::before {
            transition: none;
          }
        }

        .json-key {
          color: var(--json-key);
          font-weight: 600;
        }

        .json-punctuation,
        .json-muted {
          color: var(--json-muted);
        }

        .json-muted {
          margin: 0 6px;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          font-size: 12px;
        }

        .json-value.is-string { color: var(--json-string); }
        .json-value.is-number { color: var(--json-number); }
        .json-value.is-boolean { color: var(--json-boolean); font-weight: 650; }
        .json-value.is-null { color: var(--json-null); font-weight: 650; }

        .json-empty {
          margin-left: 38px;
          min-height: 24px;
          color: var(--json-muted);
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          font-size: 12px;
        }

        .is-match > .json-summary,
        .is-match.json-line {
          background: var(--json-match);
        }

        .json-visually-hidden {
          position: absolute;
          width: 1px;
          height: 1px;
          padding: 0;
          margin: -1px;
          overflow: hidden;
          clip: rect(0, 0, 0, 0);
          white-space: nowrap;
          border: 0;
        }

        @media (max-width: 700px) {
          body {
            padding: 12px;
          }

          .json-toolbar {
            align-items: stretch;
            flex-wrap: wrap;
            min-height: 0;
          }

          .json-title {
            width: 100%;
          }

          .json-search {
            width: 100%;
            min-width: 0;
            order: 2;
          }

          .json-button {
            flex: 1 1 auto;
          }

          .json-tree,
          .json-raw {
            padding: 14px 12px 18px;
          }
        }
      `;

      const shell = document.createElement("main");
      shell.className = "json-shell";
      shell.dataset.view = "tree";

      const toolbar = document.createElement("div");
      toolbar.className = "json-toolbar";

      const title = document.createElement("div");
      title.className = "json-title";
      const titleStrong = document.createElement("strong");
      titleStrong.textContent = "JSON";
      const titleMeta = document.createElement("span");
      titleMeta.textContent = `${compactPreview(rootValue)} - ${formatBytes(byteSize(jsonText))}`;
      title.append(titleStrong, titleMeta);

      const searchLabel = document.createElement("label");
      searchLabel.className = "json-visually-hidden";
      searchLabel.htmlFor = "wkdomains-json-search";
      searchLabel.textContent = "Search JSON";

      const search = document.createElement("input");
      search.id = "wkdomains-json-search";
      search.className = "json-search";
      search.type = "search";
      search.autocomplete = "off";
      search.placeholder = "Search";

      const button = (label, action) => {
        const element = document.createElement("button");
        element.className = "json-button";
        element.type = "button";
        element.textContent = label;
        element.addEventListener("click", action);
        return element;
      };

      const tree = document.createElement("section");
      tree.className = "json-tree";
      tree.setAttribute("aria-label", "JSON tree");
      tree.appendChild(makeNode(null, rootValue, 0));

      const raw = document.createElement("pre");
      raw.className = "json-raw";
      raw.textContent = prettyText;

      const expandAll = button("Expand all", () => {
        tree.querySelectorAll("details").forEach((details) => { details.open = true; });
      });

      const collapseAll = button("Collapse all", () => {
        tree.querySelectorAll("details").forEach((details) => { details.open = false; });
        const root = tree.querySelector("details");
        if (root) root.open = true;
      });

      const toggleRaw = button("Raw", () => {
        const isRaw = shell.dataset.view === "raw";
        shell.dataset.view = isRaw ? "tree" : "raw";
        toggleRaw.textContent = isRaw ? "Raw" : "Tree";
      });

      const copyRaw = button("Copy", () => {
        const done = () => {
          copyRaw.textContent = "Copied";
          window.setTimeout(() => { copyRaw.textContent = "Copy"; }, 1200);
        };

        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(prettyText).then(done).catch(() => {});
        }
      });

      search.addEventListener("input", () => {
        const query = search.value.trim().toLowerCase();
        tree.querySelectorAll(".is-match").forEach((node) => node.classList.remove("is-match"));
        if (!query) return;

        tree.querySelectorAll("[data-search-text]").forEach((node) => {
          if (!node.dataset.searchText.includes(query)) return;

          node.classList.add("is-match");
          let parent = node.parentElement;
          while (parent) {
            if (parent.tagName === "DETAILS") parent.open = true;
            parent = parent.parentElement;
          }
        });
      });

      toolbar.append(title, searchLabel, search, expandAll, collapseAll, toggleRaw, copyRaw);
      shell.append(toolbar, tree, raw);

      document.head.appendChild(style);
      document.title = document.title || "JSON";
      document.body.replaceChildren(shell);
      document.documentElement.classList.add("wkdomains-json-document");

      try {
        window.webkit.messageHandlers.wkdomainsRender.postMessage({
          pageURL: location.href,
          pageHost: location.hostname
        });
      } catch (_) {}
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
