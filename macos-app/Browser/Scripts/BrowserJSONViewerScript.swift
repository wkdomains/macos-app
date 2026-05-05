//
//  BrowserJSONViewerScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
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

      const displayText = (value) => {
        const type = typeOf(value);
        if (type === "string") return value;
        if (type === "array" || type === "object") return compactPreview(value);
        return scalarText(value);
      };

      const titleText = (value) => {
        const type = typeOf(value);
        if (type === "array" || type === "object") {
          try {
            return JSON.stringify(value);
          } catch (_) {
            return compactPreview(value);
          }
        }
        return displayText(value);
      };

      const findRootList = (value) => {
        if (Array.isArray(value)) return { key: "root", rows: value };
        if (!value || typeof value !== "object") return null;

        const key = Object.keys(value).find((candidate) => Array.isArray(value[candidate]));
        if (!key) return null;
        return { key, rows: value[key] };
      };

      const listData = findRootList(rootValue);

      const inferColumns = (rows) => {
        const columns = [];
        const seen = new Set();
        rows.forEach((row) => {
          if (!row || typeof row !== "object" || Array.isArray(row)) return;
          Object.keys(row).forEach((key) => {
            if (seen.has(key)) return;
            seen.add(key);
            columns.push(key);
          });
        });
        return columns;
      };

      const listColumns = listData ? inferColumns(listData.rows) : [];

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

      const makeListTable = () => {
        const section = document.createElement("section");
        section.className = "json-list";
        section.setAttribute("aria-label", "JSON list");

        if (!listData || !listData.rows.length) {
          const empty = document.createElement("div");
          empty.className = "json-list-empty";
          empty.textContent = "No root array found";
          section.appendChild(empty);
          return section;
        }

        if (!listColumns.length) {
          const empty = document.createElement("div");
          empty.className = "json-list-empty";
          empty.textContent = `${listData.key} has ${listData.rows.length} items, but no object columns`;
          section.appendChild(empty);
          return section;
        }

        const caption = document.createElement("div");
        caption.className = "json-list-caption";
        caption.textContent = `${listData.key} - ${listData.rows.length} rows - ${listColumns.length} columns`;

        const scroller = document.createElement("div");
        scroller.className = "json-table-scroll";

        const table = document.createElement("table");
        table.className = "json-table";

        const thead = document.createElement("thead");
        const headerRow = document.createElement("tr");
        listColumns.forEach((key) => {
          const th = document.createElement("th");
          th.scope = "col";
          th.textContent = key;
          headerRow.appendChild(th);
        });
        thead.appendChild(headerRow);

        const tbody = document.createElement("tbody");
        listData.rows.forEach((row) => {
          const tr = document.createElement("tr");
          listColumns.forEach((key) => {
            const td = document.createElement("td");
            const value = row && typeof row === "object" && !Array.isArray(row) ? row[key] : undefined;
            const type = typeOf(value);
            td.className = `json-table-value is-${type}`;
            td.textContent = value === undefined ? "" : displayText(value);
            td.title = value === undefined ? "" : titleText(value);
            tr.appendChild(td);
          });
          tbody.appendChild(tr);
        });

        table.append(thead, tbody);
        scroller.appendChild(table);
        section.append(caption, scroller);
        return section;
      };

      const prettyText = (() => {
        try {
          return JSON.stringify(rootValue, null, 2);
        } catch (_) {
          return jsonText;
        }
      })();

      const cssText = `
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

        .json-button:disabled {
          cursor: default;
          opacity: 0.48;
        }

        .json-button:disabled:hover {
          background: var(--json-surface);
        }

        .json-button:focus-visible {
          outline: 3px solid color-mix(in srgb, var(--json-accent) 28%, transparent);
          outline-offset: 1px;
        }

        .json-tree,
        .json-raw,
        .json-list {
          padding: 18px 22px 24px;
          overflow-x: auto;
        }

        .json-raw {
          display: none;
          margin: 0;
          white-space: pre;
          line-height: 1.55;
        }

        .json-list {
          display: none;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }

        .json-shell[data-view="raw"] .json-tree,
        .json-shell[data-view="raw"] .json-list,
        .json-shell[data-view="list"] .json-tree,
        .json-shell[data-view="list"] .json-raw {
          display: none;
        }

        .json-shell[data-view="raw"] .json-raw {
          display: block;
        }

        .json-shell[data-view="list"] .json-list {
          display: block;
        }

        .json-list-caption {
          margin-bottom: 12px;
          color: var(--json-muted);
          font-size: 12px;
          font-weight: 600;
        }

        .json-table-scroll {
          overflow: auto;
          border: 1px solid var(--json-border);
          border-radius: 8px;
        }

        .json-table {
          width: max-content;
          min-width: 100%;
          border-collapse: separate;
          border-spacing: 0;
          font-size: 12px;
          line-height: 1.45;
        }

        .json-table th,
        .json-table td {
          width: 220px;
          min-width: 120px;
          max-width: 320px;
          padding: 8px 10px;
          border-right: 1px solid var(--json-border);
          border-bottom: 1px solid var(--json-border);
          overflow: hidden;
          text-align: left;
          text-overflow: ellipsis;
          white-space: nowrap;
          vertical-align: top;
        }

        .json-table th {
          position: sticky;
          top: 0;
          z-index: 1;
          background: color-mix(in srgb, var(--json-surface) 94%, var(--json-bg));
          color: var(--json-text);
          font-weight: 650;
        }

        .json-table th:last-child,
        .json-table td:last-child {
          border-right: 0;
        }

        .json-table tbody tr:last-child td {
          border-bottom: 0;
        }

        .json-table tbody tr:hover td {
          background: color-mix(in srgb, var(--json-accent) 6%, transparent);
        }

        .json-table-value.is-string { color: var(--json-string); }
        .json-table-value.is-number { color: var(--json-number); }
        .json-table-value.is-boolean { color: var(--json-boolean); font-weight: 650; }
        .json-table-value.is-null { color: var(--json-null); font-weight: 650; }
        .json-table-value.is-object,
        .json-table-value.is-array {
          color: var(--json-muted);
          font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
        }

        .json-list-empty {
          min-height: 160px;
          display: grid;
          place-items: center;
          color: var(--json-muted);
          font-size: 13px;
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
        .json-raw,
        .json-list {
            padding: 14px 12px 18px;
          }

          .json-table th,
          .json-table td {
            max-width: 220px;
          }
        }
      `;

      const installStyles = () => {
        try {
          if (window.CSSStyleSheet && "adoptedStyleSheets" in Document.prototype) {
            const sheet = new CSSStyleSheet();
            sheet.replaceSync(cssText);
            sheet.__wkdomainsJSONViewerStyleSheet = true;
            const currentSheets = Array.from(document.adoptedStyleSheets || [])
              .filter((existingSheet) => !existingSheet.__wkdomainsJSONViewerStyleSheet);
            document.adoptedStyleSheets = [...currentSheets, sheet];
            return;
          }
        } catch (_) {}

        try {
          const style = document.createElement("style");
          style.textContent = cssText;
          (document.head || document.documentElement).appendChild(style);
        } catch (_) {}
      };

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

      const list = makeListTable();

      const expandAll = button("Expand all", () => {
        tree.querySelectorAll("details").forEach((details) => { details.open = true; });
      });

      const collapseAll = button("Collapse all", () => {
        tree.querySelectorAll("details").forEach((details) => { details.open = false; });
        const root = tree.querySelector("details");
        if (root) root.open = true;
      });

      const toggleList = button("List", () => {
        const isList = shell.dataset.view === "list";
        shell.dataset.view = isList ? "tree" : "list";
        toggleList.textContent = isList ? "List" : "Tree";
        toggleRaw.textContent = "Raw";
      });
      toggleList.disabled = !listData || !listColumns.length;
      if (listData && listColumns.length) {
        toggleList.title = `Show ${listData.key} as a table`;
      } else {
        toggleList.title = "No root array with object rows found";
      }

      const toggleRaw = button("Raw", () => {
        const isRaw = shell.dataset.view === "raw";
        shell.dataset.view = isRaw ? "tree" : "raw";
        toggleRaw.textContent = isRaw ? "Raw" : "Tree";
        toggleList.textContent = "List";
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

      toolbar.append(title, searchLabel, search, expandAll, collapseAll, toggleList, toggleRaw, copyRaw);
      shell.append(toolbar, tree, raw, list);

      installStyles();
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

}
