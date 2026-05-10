//
//  BrowserInspectionScripts.swift
//  macos-app
//
//  Created by aa on 5/2/26.
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

    static let layoutDiagnosticsInspectionScript = """
    (() => {
      const MAX_ITEMS = 80;
      const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
      const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
      const doc = document.documentElement;
      const body = document.body;

      const truncate = (value, limit = 160) => {
        const text = String(value || "").replace(/\\s+/g, " ").trim();
        return text.length > limit ? `${text.slice(0, limit)}...` : text;
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
        return rect.bottom >= 0 && rect.right >= 0 && rect.top <= viewportHeight && rect.left <= viewportWidth;
      };

      const labelFor = (element) => truncate(
        element.getAttribute("aria-label")
          || element.innerText
          || element.textContent
          || element.getAttribute("title")
          || element.getAttribute("placeholder")
          || element.tagName.toLowerCase(),
        100
      );

      const selectorHintFor = (element) => {
        if (element.id) return `#${element.id}`;
        const testID = element.getAttribute("data-testid") || element.getAttribute("data-test") || element.getAttribute("data-cy");
        if (testID) return `[data-testid="${testID}"]`;
        const name = element.getAttribute("name");
        if (name) return `${element.tagName.toLowerCase()}[name="${name}"]`;
        return element.tagName.toLowerCase();
      };

      const summaryFor = (element, extra = {}) => ({
        tag: element.tagName.toLowerCase(),
        role: element.getAttribute("role") || null,
        label: labelFor(element),
        selectorHint: selectorHintFor(element),
        rect: rectFor(element),
        ...extra
      });

      const all = Array.from(document.querySelectorAll("body *")).filter(isVisible);
      const interactiveSelector = [
        "a[href]",
        "button",
        "input:not([type='hidden'])",
        "textarea",
        "select",
        "summary",
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
      const interactive = Array.from(document.querySelectorAll(interactiveSelector)).filter(isVisible);

      const outsideViewport = all
        .filter((element) => {
          const rect = element.getBoundingClientRect();
          return rect.left < -1 || rect.right > viewportWidth + 1 || rect.top < -1 || rect.bottom > viewportHeight + 1;
        })
        .slice(0, MAX_ITEMS)
        .map((element) => summaryFor(element));

      const clipped = all
        .filter((element) => {
          const style = getComputedStyle(element);
          const clipsX = ["hidden", "clip", "auto", "scroll"].includes(style.overflowX);
          const clipsY = ["hidden", "clip", "auto", "scroll"].includes(style.overflowY);
          return (clipsX && element.scrollWidth > element.clientWidth + 1)
            || (clipsY && element.scrollHeight > element.clientHeight + 1);
        })
        .slice(0, MAX_ITEMS)
        .map((element) => summaryFor(element, {
          scrollWidth: element.scrollWidth,
          clientWidth: element.clientWidth,
          scrollHeight: element.scrollHeight,
          clientHeight: element.clientHeight,
          overflowX: getComputedStyle(element).overflowX,
          overflowY: getComputedStyle(element).overflowY
        }));

      const smallTapTargets = interactive
        .filter((element) => {
          const rect = element.getBoundingClientRect();
          return rect.width < 44 || rect.height < 44;
        })
        .slice(0, MAX_ITEMS)
        .map((element) => summaryFor(element));

      const fixedOrSticky = all
        .filter((element) => {
          const position = getComputedStyle(element).position;
          return position === "fixed" || position === "sticky";
        })
        .slice(0, 40);

      const intersections = [];
      for (let i = 0; i < fixedOrSticky.length; i += 1) {
        for (let j = i + 1; j < fixedOrSticky.length; j += 1) {
          const a = fixedOrSticky[i].getBoundingClientRect();
          const b = fixedOrSticky[j].getBoundingClientRect();
          const width = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left));
          const height = Math.max(0, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top));
          const area = width * height;
          if (area >= 64) {
            intersections.push({
              area: Math.round(area),
              first: summaryFor(fixedOrSticky[i], { position: getComputedStyle(fixedOrSticky[i]).position }),
              second: summaryFor(fixedOrSticky[j], { position: getComputedStyle(fixedOrSticky[j]).position })
            });
          }
        }
      }

      return JSON.stringify({
        url: location.href,
        title: document.title || null,
        generatedAt: new Date().toISOString(),
        viewport: {
          width: Math.round(viewportWidth),
          height: Math.round(viewportHeight),
          scrollX: Math.round(window.scrollX || 0),
          scrollY: Math.round(window.scrollY || 0),
          devicePixelRatio: window.devicePixelRatio || 1
        },
        document: {
          scrollWidth: doc ? doc.scrollWidth : null,
          clientWidth: doc ? doc.clientWidth : null,
          scrollHeight: doc ? doc.scrollHeight : null,
          clientHeight: doc ? doc.clientHeight : null,
          bodyScrollWidth: body ? body.scrollWidth : null,
          bodyClientWidth: body ? body.clientWidth : null,
          hasHorizontalOverflow: !!doc && doc.scrollWidth > doc.clientWidth + 1
        },
        counts: {
          visibleElements: all.length,
          interactiveElements: interactive.length,
          outsideViewport: outsideViewport.length,
          clipped: clipped.length,
          smallTapTargets: smallTapTargets.length,
          fixedOrSticky: fixedOrSticky.length,
          fixedOrStickyOverlaps: intersections.length
        },
        outsideViewport,
        clipped,
        smallTapTargets,
        fixedOrStickyOverlaps: intersections.slice(0, 30)
      });
    })();
    """

    static func elementXRayInspectionScript(ref: String) -> String? {
      guard
        let refData = try? JSONEncoder().encode(ref),
        let refJSON = String(data: refData, encoding: .utf8)
      else {
        return nil
      }

      return """
      (() => {
        const targetRef = \(refJSON);
        const state = window.__wkdomainsSnapshotRefs;
        const element = state && state.elements && state.elements.get(targetRef);
        const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
        const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;

        const truncate = (value, limit = 220) => {
          const text = String(value || "").replace(/\\s+/g, " ").trim();
          return text.length > limit ? `${text.slice(0, limit)}...` : text;
        };

        const rectFor = (node) => {
          const rect = node.getBoundingClientRect();
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

        const attrsFor = (node) => {
          const attrs = {};
          for (const attr of Array.from(node.attributes || [])) {
            if (/^(id|class|role|aria-|data-|name|type|href|src|alt|title|placeholder|disabled|required)/.test(attr.name)) {
              attrs[attr.name] = truncate(attr.value, 260);
            }
          }
          return attrs;
        };

        const selectorHintFor = (node) => {
          if (node.id) return `#${CSS.escape(node.id)}`;
          const testID = node.getAttribute("data-testid") || node.getAttribute("data-test") || node.getAttribute("data-cy");
          if (testID) return `[data-testid="${CSS.escape(testID)}"]`;
          const name = node.getAttribute("name");
          if (name) return `${node.tagName.toLowerCase()}[name="${CSS.escape(name)}"]`;
          return node.tagName.toLowerCase();
        };

        const cssPathFor = (node) => {
          const parts = [];
          let current = node;
          while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.body) {
            let part = current.tagName.toLowerCase();
            if (current.id) {
              part += `#${CSS.escape(current.id)}`;
              parts.unshift(part);
              break;
            }
            const parent = current.parentElement;
            if (parent) {
              const siblings = Array.from(parent.children).filter((child) => child.tagName === current.tagName);
              if (siblings.length > 1) {
                part += `:nth-of-type(${siblings.indexOf(current) + 1})`;
              }
            }
            parts.unshift(part);
            current = parent;
          }
          return parts.join(" > ");
        };

        const colorParts = (value) => {
          const match = String(value || "").match(/rgba?\\(([^)]+)\\)/);
          if (!match) return null;
          const parts = match[1].split(",").map((part) => Number.parseFloat(part.trim()));
          if (parts.length < 3 || parts.some((part, index) => index < 3 && Number.isNaN(part))) return null;
          return { r: parts[0], g: parts[1], b: parts[2], a: parts.length > 3 && !Number.isNaN(parts[3]) ? parts[3] : 1 };
        };

        const luminance = (color) => {
          const channel = (value) => {
            const v = value / 255;
            return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
          };
          return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
        };

        const contrastRatio = (fg, bg) => {
          if (!fg || !bg || fg.a === 0 || bg.a === 0) return null;
          const left = luminance(fg);
          const right = luminance(bg);
          const lighter = Math.max(left, right);
          const darker = Math.min(left, right);
          return Math.round(((lighter + 0.05) / (darker + 0.05)) * 100) / 100;
        };

        const nearestBackgroundColor = (node) => {
          let current = node;
          while (current && current.nodeType === Node.ELEMENT_NODE) {
            const background = getComputedStyle(current).backgroundColor;
            const parsed = colorParts(background);
            if (parsed && parsed.a > 0) return background;
            current = current.parentElement;
          }
          return getComputedStyle(document.body || document.documentElement).backgroundColor;
        };

        const roleFor = (node) => {
          const explicit = node.getAttribute("role");
          if (explicit) return explicit;
          const tag = node.tagName.toLowerCase();
          const type = (node.getAttribute("type") || "").toLowerCase();
          if (tag === "a" && node.hasAttribute("href")) return "link";
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
          return tag;
        };

        const accessibleNameFor = (node) => {
          const aria = node.getAttribute("aria-label");
          if (aria) return truncate(aria, 180);
          const labelledBy = node.getAttribute("aria-labelledby");
          if (labelledBy) {
            const text = labelledBy.split(/\\s+/).map((id) => document.getElementById(id))
              .filter(Boolean)
              .map((label) => label.innerText || label.textContent)
              .join(" ");
            if (text) return truncate(text, 180);
          }
          if (node.id) {
            const label = document.querySelector(`label[for="${CSS.escape(node.id)}"]`);
            if (label) return truncate(label.innerText || label.textContent, 180);
          }
          const wrappingLabel = node.closest("label");
          if (wrappingLabel) return truncate(wrappingLabel.innerText || wrappingLabel.textContent, 180);
          return truncate(node.innerText || node.textContent || node.getAttribute("title") || node.getAttribute("placeholder"), 180) || null;
        };

        const explicitSourceHintFor = (node) => {
          const rawSource = node.getAttribute("data-wk-source") || node.getAttribute("data-source") || node.getAttribute("data-testid-source");
          const component = node.getAttribute("data-wk-component") || node.getAttribute("data-component") || null;
          if (!rawSource && !component) return null;

          let fileName = rawSource || null;
          let lineNumber = null;
          let columnNumber = null;
          if (rawSource) {
            const match = rawSource.match(/^(.*?)(?::(\\d+))?(?::(\\d+))?$/);
            if (match) {
              fileName = match[1] || rawSource;
              lineNumber = match[2] ? Number(match[2]) : null;
              columnNumber = match[3] ? Number(match[3]) : null;
            }
          }

          return {
            framework: node.getAttribute("data-wk-framework") || null,
            component,
            fileName,
            lineNumber,
            columnNumber,
            note: "Explicit DOM source metadata."
          };
        };

        const sourceHintFor = (node) => {
          const explicit = explicitSourceHintFor(node);
          if (explicit) return explicit;

          const key = Object.keys(node).find((name) => name.startsWith("__reactFiber$") || name.startsWith("__reactInternalInstance$"));
          const fiber = key ? node[key] : null;
          let current = fiber;
          while (current) {
            const source = current._debugSource || current._debugOwner?._debugSource;
            const ownerName = current._debugOwner?.elementType?.name || current._debugOwner?.type?.name || current.elementType?.name || current.type?.name || null;
            if (source || ownerName) {
              return {
                framework: "react",
                component: ownerName,
                fileName: source?.fileName || null,
                lineNumber: source?.lineNumber || null,
                columnNumber: source?.columnNumber || null,
                note: source ? "React development source metadata." : "React fiber owner name only; file metadata unavailable."
              };
            }
            current = current.return;
          }
          return {
            framework: null,
            component: null,
            fileName: null,
            lineNumber: null,
            columnNumber: null,
            note: "No framework source metadata found on this element."
          };
        };

        const nodeSummary = (node) => {
          const style = getComputedStyle(node);
          return {
            tag: node.tagName.toLowerCase(),
            role: roleFor(node),
            label: accessibleNameFor(node),
            selectorHint: selectorHintFor(node),
            cssPath: cssPathFor(node),
            attrs: attrsFor(node),
            rect: rectFor(node),
            layout: {
              display: style.display,
              position: style.position,
              zIndex: style.zIndex,
              overflowX: style.overflowX,
              overflowY: style.overflowY,
              opacity: style.opacity,
              visibility: style.visibility
            }
          };
        };

        if (!element) {
          return JSON.stringify({
            ref: targetRef,
            found: false,
            error: "Element ref not found. Call /api/v1/snapshot first and use a current ref."
          });
        }

        const style = getComputedStyle(element);
        const backgroundColor = nearestBackgroundColor(element);
        const color = style.color;
        const rect = element.getBoundingClientRect();
        const ancestors = [];
        let parent = element.parentElement;
        while (parent && ancestors.length < 8) {
          ancestors.push(nodeSummary(parent));
          parent = parent.parentElement;
        }

        const siblings = Array.from(element.parentElement?.children || [])
          .filter((node) => node !== element)
          .slice(0, 10)
          .map(nodeSummary);

        return JSON.stringify({
          ref: targetRef,
          found: true,
          url: location.href,
          title: document.title || null,
          generatedAt: new Date().toISOString(),
          element: nodeSummary(element),
          accessibility: {
            role: roleFor(element),
            name: accessibleNameFor(element),
            disabled: !!(element.disabled || element.getAttribute("aria-disabled") === "true"),
            expanded: element.getAttribute("aria-expanded"),
            selected: element.getAttribute("aria-selected"),
            checked: typeof element.checked === "boolean" ? element.checked : null,
            required: !!(element.required || element.hasAttribute("required")),
            focused: document.activeElement === element
          },
          box: {
            inViewport: rect.bottom >= 0 && rect.right >= 0 && rect.top <= viewportHeight && rect.left <= viewportWidth,
            scrollWidth: element.scrollWidth,
            clientWidth: element.clientWidth,
            scrollHeight: element.scrollHeight,
            clientHeight: element.clientHeight,
            offsetWidth: element.offsetWidth,
            offsetHeight: element.offsetHeight
          },
          computedStyle: {
            display: style.display,
            position: style.position,
            zIndex: style.zIndex,
            color,
            backgroundColor,
            fontFamily: style.fontFamily,
            fontSize: style.fontSize,
            fontWeight: style.fontWeight,
            lineHeight: style.lineHeight,
            letterSpacing: style.letterSpacing,
            textAlign: style.textAlign,
            whiteSpace: style.whiteSpace,
            overflowX: style.overflowX,
            overflowY: style.overflowY,
            opacity: style.opacity,
            visibility: style.visibility,
            pointerEvents: style.pointerEvents
          },
          contrast: {
            foreground: color,
            background: backgroundColor,
            ratio: contrastRatio(colorParts(color), colorParts(backgroundColor))
          },
          sourceHint: sourceHintFor(element),
          ancestors,
          siblings
        });
      })();
      """
    }

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

    static func actionInspectionScript(arguments: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return """
        JSON.stringify((() => {
          const args = __WKDOMAINS_ACTION_ARGS__;
          const state = window.__wkdomainsSnapshotRefs || null;
          const action = String(args.type || args.action || "").trim().toLowerCase();
          const ref = typeof args.ref === "string" ? args.ref.trim() : "";
          const selector = typeof args.selector === "string" ? args.selector.trim() : "";
          const text = typeof args.text === "string" ? args.text.trim() : "";
          const name = typeof args.name === "string" ? args.name.trim() : "";
          const role = typeof args.role === "string" ? args.role.trim().toLowerCase() : "";
          const targetText = typeof args.targetText === "string" ? args.targetText.trim() : "";
          const targetName = typeof args.targetName === "string" ? args.targetName.trim() : "";
          const exact = args.exact !== false;
          const value = args.value == null ? "" : String(args.value);
          const key = args.key == null ? "Enter" : String(args.key);
          const beforeURL = location.href;

          const truncate = (text, limit = 160) => {
            const value = String(text || "").replace(/\\s+/g, " ").trim();
            return value.length > limit ? `${value.slice(0, limit)}...` : value;
          };

          const rectFor = (element) => {
            if (!element || !element.getBoundingClientRect) return null;
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

          const labelFor = (element) => {
            if (!element) return null;
            const aria = element.getAttribute("aria-label");
            if (aria) return truncate(aria);
            const labelledBy = element.getAttribute("aria-labelledby");
            if (labelledBy) {
              const text = labelledBy.split(/\\s+/)
                .map((id) => document.getElementById(id))
                .filter(Boolean)
                .map((node) => node.innerText || node.textContent || "")
                .join(" ");
              if (text) return truncate(text);
            }
            if (element.id) {
              const label = document.querySelector(`label[for="${CSS.escape(element.id)}"]`);
              if (label) return truncate(label.innerText || label.textContent);
            }
            const wrappedLabel = element.closest("label");
            if (wrappedLabel) return truncate(wrappedLabel.innerText || wrappedLabel.textContent);
            return truncate(element.innerText || element.textContent || element.getAttribute("placeholder") || element.getAttribute("title") || "");
          };

          const roleFor = (element) => {
            const explicit = element.getAttribute("role");
            if (explicit) return explicit.toLowerCase();
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
            return tag;
          };

          const isVisible = (element) => {
            if (!element || !element.getBoundingClientRect) return false;
            const style = getComputedStyle(element);
            if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0
              && rect.bottom >= 0
              && rect.right >= 0
              && rect.top <= (window.innerHeight || document.documentElement.clientHeight)
              && rect.left <= (window.innerWidth || document.documentElement.clientWidth);
          };

          const normalized = (value) => String(value || "").replace(/\\s+/g, " ").trim().toLowerCase();
          const matchesText = (candidate, expected) => {
            const candidateText = normalized(candidate);
            const expectedText = normalized(expected);
            if (!expectedText) return true;
            return exact ? candidateText === expectedText : candidateText.includes(expectedText);
          };

          const matchesName = (element, expected) => {
            if (!expected) return true;
            const values = [
              labelFor(element),
              element.innerText || element.textContent || "",
              element.getAttribute("placeholder") || "",
              element.getAttribute("title") || ""
            ];
            return values.some((value) => matchesText(value, expected));
          };

          const summaryFor = (element) => {
            if (!element || !element.tagName) return null;
            return {
              tag: element.tagName.toLowerCase(),
              type: element.getAttribute("type") || null,
              id: element.id || null,
              name: element.getAttribute("name") || null,
              role: roleFor(element),
              label: labelFor(element),
              text: truncate(element.innerText || element.textContent || "", 120),
              value: element.matches("input, textarea, select") ? truncate(element.value, 80) : null,
              disabled: !!(element.disabled || element.getAttribute("aria-disabled") === "true"),
              rect: rectFor(element)
            };
          };

          const fail = (message) => ({
            ok: false,
            action,
            error: message,
            ref: ref || null,
            selector: selector || null,
            text: text || targetText || null,
            name: name || targetName || null,
            role: role || null,
            url: location.href,
            activeElement: summaryFor(document.activeElement)
          });

          if (!action) return fail("Missing action type.");

          const byRef = ref && state && state.elements ? state.elements.get(ref) : null;
          let bySelector = null;
          if (!byRef && selector) {
            try {
              bySelector = document.querySelector(selector);
            } catch (error) {
              return fail(`Invalid selector: ${error.message || error}`);
            }
          }

          const queryTarget = () => {
            const expectedText = text || targetText;
            const expectedName = name || targetName;
            if (!expectedText && !expectedName && !role) return null;

            const selectorList = [
              "a[href]",
              "button",
              "input:not([type='hidden'])",
              "textarea",
              "select",
              "summary",
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
              "[role='searchbox']"
            ].join(",");

            const candidates = Array.from(document.querySelectorAll(selectorList))
              .filter(isVisible)
              .filter((element) => !role || roleFor(element) === role)
              .filter((element) => matchesName(element, expectedName))
              .filter((element) => !expectedText || matchesText(element.innerText || element.textContent || labelFor(element), expectedText));

            if (candidates.length === 0) return { element: null, candidates: [] };
            return {
              element: candidates[0],
              candidates: candidates.slice(0, 8).map(summaryFor)
            };
          };

          const byQuery = (!byRef && !bySelector) ? queryTarget() : null;
          const usesActiveElement = args.active === true || (!ref && !selector && !text && !name && !role && !targetText && !targetName && action === "press");
          const target = usesActiveElement ? document.activeElement : (byRef || bySelector || byQuery?.element);

          if (!target || target === document.body || target === document.documentElement) {
            const failure = fail("Target element was not found. Provide ref, selector, text/name/role, or active:true for press.");
            if (byQuery) failure.candidates = byQuery.candidates;
            return failure;
          }

          const focusElement = (element) => {
            if (!element) return;
            try {
              element.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
            } catch (_) {
              element.scrollIntoView();
            }
            if (typeof element.focus === "function") {
              try {
                element.focus({ preventScroll: true });
              } catch (_) {
                element.focus();
              }
            }
          };

          const dispatchInput = (element, data) => {
            try {
              element.dispatchEvent(new InputEvent("input", {
                bubbles: true,
                cancelable: true,
                data,
                inputType: "insertReplacementText"
              }));
            } catch (_) {
              element.dispatchEvent(new Event("input", { bubbles: true, cancelable: true }));
            }
            element.dispatchEvent(new Event("change", { bubbles: true }));
          };

          const setNativeValue = (element, nextValue) => {
            const tag = element.tagName.toLowerCase();
            const prototype = tag === "textarea" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
            if (descriptor && descriptor.set) {
              descriptor.set.call(element, nextValue);
            } else {
              element.value = nextValue;
            }
          };

          const fillElement = (element, nextValue) => {
            focusElement(element);
            if (element.isContentEditable) {
              element.textContent = nextValue;
              dispatchInput(element, nextValue);
              return;
            }
            if (element.matches("input, textarea")) {
              setNativeValue(element, nextValue);
              dispatchInput(element, nextValue);
              return;
            }
            throw new Error("Target is not fillable.");
          };

          const selectElement = (element, nextValue) => {
            focusElement(element);
            if (!element.matches("select")) throw new Error("Target is not a select.");
            element.value = nextValue;
            element.dispatchEvent(new Event("input", { bubbles: true }));
            element.dispatchEvent(new Event("change", { bubbles: true }));
          };

          const submitFrom = (element) => {
            const form = element.matches("form") ? element : element.form || element.closest("form");
            if (!form) throw new Error("No form is associated with the target.");
            if (typeof form.requestSubmit === "function") {
              form.requestSubmit(element.matches("button, input[type='submit']") ? element : undefined);
            } else {
              form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
            }
          };

          const pressKey = (element, nextKey) => {
            focusElement(element);
            const eventInit = {
              key: nextKey,
              code: nextKey === "Enter" ? "Enter" : nextKey,
              bubbles: true,
              cancelable: true
            };
            const keydownAllowed = element.dispatchEvent(new KeyboardEvent("keydown", eventInit));
            element.dispatchEvent(new KeyboardEvent("keyup", eventInit));

            if (nextKey === "Enter" && keydownAllowed && element.form) {
              submitFrom(element);
            }
          };

          try {
            if (action === "focus") {
              focusElement(target);
            } else if (action === "click") {
              focusElement(target);
              target.click();
            } else if (action === "fill" || action === "setvalue") {
              fillElement(target, value);
            } else if (action === "clear") {
              fillElement(target, "");
            } else if (action === "select") {
              selectElement(target, value);
            } else if (action === "submit") {
              submitFrom(target);
            } else if (action === "press") {
              pressKey(target, key);
            } else {
              return fail(`Unsupported action: ${action}`);
            }
          } catch (error) {
            return fail(error && error.message ? error.message : String(error));
          }

          return {
            ok: true,
            action,
            ref: ref || null,
            selector: selector || null,
            text: text || targetText || null,
            name: name || targetName || null,
            role: role || null,
            targetStrategy: byRef ? "ref" : bySelector ? "selector" : byQuery?.element ? "query" : usesActiveElement ? "active" : null,
            candidates: byQuery?.candidates || [],
            beforeURL,
            url: location.href,
            target: summaryFor(target),
            activeElement: summaryFor(document.activeElement)
          };
        })())
        """.replacingOccurrences(of: "__WKDOMAINS_ACTION_ARGS__", with: json)
    }

    static func waitInspectionScript(arguments: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return """
        JSON.stringify((() => {
          const waitFor = __WKDOMAINS_WAIT_ARGS__;
          const truncate = (text, limit = 180) => {
            const value = String(text || "").replace(/\\s+/g, " ").trim();
            return value.length > limit ? `${value.slice(0, limit)}...` : value;
          };
          const rectFor = (element) => {
            if (!element || !element.getBoundingClientRect) return null;
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
          const visible = (element) => {
            if (!element || !element.getBoundingClientRect) return false;
            const style = getComputedStyle(element);
            if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0;
          };
          const elementSummary = (element) => element ? {
            tag: element.tagName.toLowerCase(),
            id: element.id || null,
            role: element.getAttribute("role") || null,
            type: element.getAttribute("type") || null,
            label: truncate(element.getAttribute("aria-label") || element.innerText || element.textContent || element.getAttribute("placeholder") || element.getAttribute("title")),
            value: element.matches("input, textarea, select") ? truncate(element.value, 120) : null,
            visible: visible(element),
            rect: rectFor(element)
          } : null;
          const result = {
            ok: true,
            matched: [],
            url: location.href,
            title: document.title || null,
            readyState: document.readyState,
            checkedAt: new Date().toISOString()
          };
          const fail = (reason, extra = {}) => ({
            ...result,
            ok: false,
            reason,
            ...extra
          });

          if (!waitFor || typeof waitFor !== "object") {
            return result;
          }

          if (waitFor.url && location.href !== String(waitFor.url)) {
            return fail("url", { expectedURL: String(waitFor.url) });
          }
          if (waitFor.urlContains && !location.href.includes(String(waitFor.urlContains))) {
            return fail("urlContains", { expectedURLContains: String(waitFor.urlContains) });
          }
          if (waitFor.titleContains && !(document.title || "").includes(String(waitFor.titleContains))) {
            return fail("titleContains", { expectedTitleContains: String(waitFor.titleContains) });
          }
          if (waitFor.readyState && document.readyState !== String(waitFor.readyState)) {
            return fail("readyState", { expectedReadyState: String(waitFor.readyState) });
          }
          if (waitFor.text || waitFor.textIncludes) {
            const expectedText = String(waitFor.text || waitFor.textIncludes);
            const text = document.body ? document.body.innerText || document.body.textContent || "" : "";
            if (!text.includes(expectedText)) {
              return fail("text", { expectedText: expectedText });
            }
          }
          if (waitFor.selector) {
            let element = null;
            try {
              element = document.querySelector(String(waitFor.selector));
            } catch (error) {
              return fail("selector", { selector: String(waitFor.selector), error: error.message || String(error) });
            }
            if (!element || (waitFor.visible !== false && !visible(element))) {
              return fail("selector", { selector: String(waitFor.selector), element: elementSummary(element) });
            }
            result.element = elementSummary(element);
          }
          if (waitFor.selectorGone) {
            let element = null;
            try {
              element = document.querySelector(String(waitFor.selectorGone));
            } catch (error) {
              return fail("selectorGone", { selectorGone: String(waitFor.selectorGone), error: error.message || String(error) });
            }
            if (element && visible(element)) {
              return fail("selectorGone", { selectorGone: String(waitFor.selectorGone), element: elementSummary(element) });
            }
          }

          return result;
        })())
        """.replacingOccurrences(of: "__WKDOMAINS_WAIT_ARGS__", with: json)
    }
}
