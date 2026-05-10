//
//  BrowserSnapshotInspectionScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let snapshotInspectionScript = """
    (() => {
      const MAX_ELEMENTS = 160;
      const MAX_TEXT = 180;
      const root = document.documentElement;
      const viewport = window.visualViewport || {};
      const state = window.__wkdomainsSnapshotRefs || {
        next: 0,
        refs: new WeakMap(),
        elements: new Map()
      };
      if (!state.elements) state.elements = new Map();
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

        const ref = state.refs.get(element);
        state.elements.set(ref, element);
        return ref;
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
        if (tag === "dialog") return "dialog";
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
          modal: element.getAttribute("aria-modal") === "true" ? true : null,
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
        "dialog",
        "form",
        "table",
        "[contenteditable='true']",
        "[aria-modal='true']",
        "[role='alertdialog']",
        "[role='button']",
        "[role='dialog']",
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
}
