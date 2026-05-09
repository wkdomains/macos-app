//
//  BrowserInspectionScripts.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

extension BrowserModel {
    static let snapshotInspectionScript = """
    (() => {
      const MAX_ELEMENTS = 160;
      const MAX_TEXT = 180;
      const root = document.documentElement;
      const viewport = window.visualViewport || {};
      const state = window.__wkdomainsSnapshotRefs || {
        next: 0,
        refs: new WeakMap()
      };
      window.__wkdomainsSnapshotRefs = state;

      const truncate = (value, limit = MAX_TEXT) => {
        const text = String(value || "").replace(/\\s+/g, " ").trim();
        return text.length > limit ? `${text.slice(0, limit)}...` : text;
      };

      const refFor = (element) => {
        if (!state.refs.has(element)) {
          state.refs.set(element, `@e${state.next}`);
          state.next += 1;
        }

        return state.refs.get(element);
      };

      const rectFor = (element) => {
        const rect = element.getBoundingClientRect();
        return {
          x: Math.round(rect.x),
          y: Math.round(rect.y),
          width: Math.round(rect.width),
          height: Math.round(rect.height),
          top: Math.round(rect.top),
          right: Math.round(rect.right),
          bottom: Math.round(rect.bottom),
          left: Math.round(rect.left)
        };
      };

      const isVisible = (element) => {
        if (!element || !element.getBoundingClientRect) return false;
        const style = getComputedStyle(element);
        if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
        const rect = element.getBoundingClientRect();
        if (rect.width < 1 || rect.height < 1) return false;
        return rect.bottom >= 0
          && rect.right >= 0
          && rect.top <= (window.innerHeight || document.documentElement.clientHeight)
          && rect.left <= (window.innerWidth || document.documentElement.clientWidth);
      };

      const attr = (element, name) => {
        const value = element.getAttribute(name);
        return value === null || value === "" ? null : truncate(value, 220);
      };

      const textFromIDList = (ids) => ids.split(/\\s+/)
        .map((id) => document.getElementById(id))
        .filter(Boolean)
        .map((element) => truncate(element.innerText || element.textContent, 80))
        .filter(Boolean)
        .join(" ");

      const labelFor = (element) => {
        const aria = attr(element, "aria-label");
        if (aria) return aria;

        const labelledBy = attr(element, "aria-labelledby");
        if (labelledBy) {
          const text = textFromIDList(labelledBy);
          if (text) return text;
        }

        if (element.id) {
          const label = document.querySelector(`label[for="${CSS.escape(element.id)}"]`);
          if (label) {
            const text = truncate(label.innerText || label.textContent, 120);
            if (text) return text;
          }
        }

        const wrappingLabel = element.closest("label");
        if (wrappingLabel) {
          const text = truncate(wrappingLabel.innerText || wrappingLabel.textContent, 120);
          if (text) return text;
        }

        return null;
      };

      const roleFor = (element) => {
        const explicitRole = attr(element, "role");
        if (explicitRole) return explicitRole;

        const tag = element.tagName.toLowerCase();
        const type = (element.getAttribute("type") || "").toLowerCase();
        if (tag === "a" && element.hasAttribute("href")) return "link";
        if (tag === "button" || type === "button" || type === "submit" || type === "reset") return "button";
        if (tag === "textarea") return "textbox";
        if (tag === "select") return "combobox";
        if (tag === "input") {
          if (type === "checkbox") return "checkbox";
          if (type === "radio") return "radio";
          if (type === "range") return "slider";
          if (type === "search") return "searchbox";
          return "textbox";
        }
        if (tag === "summary") return "button";
        if (tag === "form") return "form";
        if (tag === "table") return "table";

        return tag;
      };

      const valueFor = (element) => {
        const tag = element.tagName.toLowerCase();
        const type = (element.getAttribute("type") || "").toLowerCase();
        if (tag !== "input" && tag !== "textarea" && tag !== "select") return null;
        if (type === "password") return element.value ? "[redacted]" : "";
        if (type === "email") {
          const value = element.value || "";
          const at = value.indexOf("@");
          if (at > 1) return `${value.slice(0, 1)}***${value.slice(at)}`;
          return value ? "[redacted]" : "";
        }
        if (type === "tel" || type === "number") return element.value ? "[present]" : "";
        return truncate(element.value || "", 120);
      };

      const optionSummary = (select) => Array.from(select.options || [])
        .slice(0, 20)
        .map((option) => ({
          text: truncate(option.text, 80),
          value: truncate(option.value, 80),
          selected: option.selected
        }));

      const selectorHintFor = (element) => {
        if (element.id) return `#${element.id}`;
        const testID = attr(element, "data-testid") || attr(element, "data-test") || attr(element, "data-cy");
        if (testID) return `[data-testid="${testID}"]`;
        const name = attr(element, "name");
        if (name) return `${element.tagName.toLowerCase()}[name="${name}"]`;
        return element.tagName.toLowerCase();
      };

      const elementSummary = (element) => {
        const tag = element.tagName.toLowerCase();
        const text = truncate(element.innerText || element.textContent || "");
        const label = labelFor(element) || attr(element, "title") || attr(element, "placeholder") || text || null;
        const form = element.form || (tag === "form" ? element : element.closest("form"));

        return {
          ref: refFor(element),
          tag,
          role: roleFor(element),
          label,
          text,
          type: attr(element, "type"),
          name: attr(element, "name"),
          placeholder: attr(element, "placeholder"),
          value: valueFor(element),
          href: element.href || null,
          action: element.action || null,
          method: element.method ? element.method.toUpperCase() : null,
          disabled: !!(element.disabled || element.getAttribute("aria-disabled") === "true"),
          required: !!(element.required || element.hasAttribute("required")),
          checked: typeof element.checked === "boolean" ? element.checked : null,
          selected: element.getAttribute("aria-selected") === "true" ? true : null,
          expanded: element.getAttribute("aria-expanded"),
          options: tag === "select" ? optionSummary(element) : null,
          formRef: form ? refFor(form) : null,
          selectorHint: selectorHintFor(element),
          rect: rectFor(element)
        };
      };

      const selectors = [
        "a[href]",
        "button",
        "input:not([type='hidden'])",
        "textarea",
        "select",
        "summary",
        "form",
        "table",
        "[contenteditable='true']",
        "[role='button']",
        "[role='link']",
        "[role='menuitem']",
        "[role='tab']",
        "[role='checkbox']",
        "[role='radio']",
        "[role='switch']",
        "[role='textbox']",
        "[role='combobox']",
        "[role='searchbox']",
        "[role='slider']"
      ].join(",");

      const elements = Array.from(document.querySelectorAll(selectors))
        .filter(isVisible)
        .sort((left, right) => {
          const leftRect = left.getBoundingClientRect();
          const rightRect = right.getBoundingClientRect();
          return (leftRect.top - rightRect.top) || (leftRect.left - rightRect.left);
        })
        .slice(0, MAX_ELEMENTS)
        .map(elementSummary);

      return JSON.stringify({
        url: location.href,
        title: document.title || null,
        generatedAt: new Date().toISOString(),
        readyState: document.readyState,
        refPrefix: "@e",
        refCount: state.next,
        viewport: {
          width: Math.round(viewport.width || window.innerWidth || 0),
          height: Math.round(viewport.height || window.innerHeight || 0),
          scrollX: Math.round(window.scrollX || 0),
          scrollY: Math.round(window.scrollY || 0),
          devicePixelRatio: window.devicePixelRatio || 1
        },
        activeRef: document.activeElement && document.activeElement !== document.body ? refFor(document.activeElement) : null,
        elements
      });
    })();
    """

    static let pageInspectionScript = """
    (() => {
      const canonical = document.querySelector('link[rel="canonical"]');
      const description = document.querySelector('meta[name="description"], meta[property="og:description"]');
      const robots = document.querySelector('meta[name="robots"]');
      const viewport = window.visualViewport || {};

      return JSON.stringify({
        url: location.href,
        title: document.title || null,
        host: location.hostname,
        origin: location.origin,
        path: location.pathname,
        canonicalURL: canonical ? canonical.href : null,
        description: description ? description.content : null,
        robots: robots ? robots.content : null,
        language: document.documentElement ? document.documentElement.lang || null : null,
        viewport: {
          width: Math.round(viewport.width || window.innerWidth || 0),
          height: Math.round(viewport.height || window.innerHeight || 0),
          scrollX: Math.round(window.scrollX || 0),
          scrollY: Math.round(window.scrollY || 0),
          devicePixelRatio: window.devicePixelRatio || 1
        }
      });
    })();
    """

    static let domInspectionScript = """
    (() => {
      const MAX_TEXT = 6000;
      const MAX_ITEMS = 80;

      const truncate = (value, limit = 300) => {
        const text = String(value || "").replace(/\\s+/g, " ").trim();
        return text.length > limit ? `${text.slice(0, limit)}...` : text;
      };

      const rectFor = (element) => {
        const rect = element.getBoundingClientRect();
        return {
          x: Math.round(rect.x),
          y: Math.round(rect.y),
          width: Math.round(rect.width),
          height: Math.round(rect.height)
        };
      };

      const isVisible = (element) => {
        if (!element || !element.getBoundingClientRect) return false;
        const style = getComputedStyle(element);
        if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
        const rect = element.getBoundingClientRect();
        if (rect.width < 1 || rect.height < 1) return false;
        return rect.bottom >= 0
          && rect.right >= 0
          && rect.top <= (window.innerHeight || document.documentElement.clientHeight)
          && rect.left <= (window.innerWidth || document.documentElement.clientWidth);
      };

      const attrs = (element, names) => {
        const output = {};
        names.forEach((name) => {
          const value = element.getAttribute(name);
          if (value !== null && value !== "") output[name] = truncate(value, 180);
        });
        return output;
      };

      const elementSummary = (element) => ({
        tag: element.tagName.toLowerCase(),
        role: element.getAttribute("role") || null,
        text: truncate(element.innerText || element.textContent || element.value || element.getAttribute("aria-label")),
        ariaLabel: element.getAttribute("aria-label") || null,
        name: element.getAttribute("name") || null,
        type: element.getAttribute("type") || null,
        placeholder: element.getAttribute("placeholder") || null,
        href: element.href || null,
        action: element.action || null,
        method: element.method || null,
        importantAttributes: attrs(element, ["id", "class", "data-testid", "data-test", "data-cy", "aria-controls", "aria-expanded", "aria-selected", "disabled", "required"]),
        rect: rectFor(element)
      });

      const visible = (selector) => Array.from(document.querySelectorAll(selector))
        .filter(isVisible)
        .slice(0, MAX_ITEMS)
        .map(elementSummary);

      const formSummary = (form) => ({
        tag: "form",
        text: truncate(form.innerText, 500),
        action: form.action || null,
        method: (form.method || "get").toUpperCase(),
        importantAttributes: attrs(form, ["id", "class", "data-testid", "data-test", "aria-label"]),
        fields: Array.from(form.querySelectorAll("input, textarea, select, button"))
          .filter(isVisible)
          .slice(0, 40)
          .map((field) => ({
            tag: field.tagName.toLowerCase(),
            type: field.getAttribute("type") || null,
            name: field.getAttribute("name") || null,
            text: truncate(field.innerText || field.value || field.getAttribute("aria-label") || field.getAttribute("placeholder")),
            ariaLabel: field.getAttribute("aria-label") || null,
            placeholder: field.getAttribute("placeholder") || null,
            required: field.hasAttribute("required"),
            disabled: field.hasAttribute("disabled")
          }))
      });

      const tableSummary = (table) => {
        const headers = Array.from(table.querySelectorAll("th")).slice(0, 20).map((cell) => truncate(cell.innerText, 80));
        const rows = Array.from(table.querySelectorAll("tr")).slice(0, 6).map((row) => (
          Array.from(row.querySelectorAll("th, td")).slice(0, 8).map((cell) => truncate(cell.innerText, 80))
        )).filter((row) => row.length > 0);

        return {
          tag: "table",
          caption: truncate((table.querySelector("caption") || {}).innerText),
          headers,
          sampleRows: rows,
          rowCount: table.querySelectorAll("tr").length,
          rect: rectFor(table)
        };
      };

      const active = document.activeElement && document.activeElement !== document.body
        ? elementSummary(document.activeElement)
        : null;

      const visibleText = truncate(document.body ? document.body.innerText : "", MAX_TEXT);

      return JSON.stringify({
        url: location.href,
        title: document.title || null,
        visibleText,
        activeElement: active,
        headings: visible("h1, h2, h3, h4, h5, h6"),
        controls: visible("button, [role='button'], input, textarea, select, summary, [contenteditable='true']"),
        links: visible("a[href]"),
        forms: Array.from(document.querySelectorAll("form")).filter(isVisible).slice(0, 20).map(formSummary),
        tables: Array.from(document.querySelectorAll("table")).filter(isVisible).slice(0, 20).map(tableSummary),
        landmarks: visible("main, nav, header, footer, aside, section, [role='main'], [role='navigation'], [role='banner'], [role='contentinfo'], [role='complementary'], [role='region']")
      });
    })();
    """

    static let linksInspectionScript = """
    (() => {
      const truncate = (value, limit = 240) => {
        const text = String(value || "").replace(/\\s+/g, " ").trim();
        return text.length > limit ? `${text.slice(0, limit)}...` : text;
      };

      const absolute = (value) => {
        try { return new URL(value, location.href).href; } catch (_) { return value || null; }
      };

      const anchors = Array.from(document.querySelectorAll("a[href]")).slice(0, 300).map((anchor) => ({
        text: truncate(anchor.innerText || anchor.getAttribute("aria-label") || anchor.title),
        href: anchor.href,
        rel: anchor.rel || null,
        target: anchor.target || null,
        ariaLabel: anchor.getAttribute("aria-label") || null
      }));

      const forms = Array.from(document.querySelectorAll("form")).slice(0, 80).map((form) => ({
        text: truncate(form.innerText, 400),
        action: form.action || location.href,
        method: (form.method || "get").toUpperCase(),
        fields: Array.from(form.querySelectorAll("input, textarea, select, button")).slice(0, 60).map((field) => ({
          tag: field.tagName.toLowerCase(),
          type: field.getAttribute("type") || null,
          name: field.getAttribute("name") || null,
          placeholder: field.getAttribute("placeholder") || null,
          ariaLabel: field.getAttribute("aria-label") || null,
          text: truncate(field.innerText || field.value)
        }))
      }));

      const scripts = Array.from(document.scripts).slice(0, 200).map((script) => ({
        src: script.src || null,
        type: script.type || null,
        async: script.async,
        defer: script.defer
      }));

      const linkTags = Array.from(document.querySelectorAll("link[href]")).slice(0, 200).map((link) => ({
        rel: link.rel || null,
        href: absolute(link.getAttribute("href")),
        type: link.type || null,
        as: link.as || null
      }));

      return JSON.stringify({
        url: location.href,
        anchors,
        forms,
        scripts,
        linkTags
      });
    })();
    """
}
