//
//  BrowserElementXRayInspectionScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
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
}
