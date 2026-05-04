//
//  BrowserDarkModeStylesheetScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetScript = #"""
      const styleManagers = new WeakMap();
      const adoptedStyleManagers = new WeakMap();
      let stylesheetSyncScheduled = false;

      const shouldManageStyle = (element) => {
        if (!element || !element.matches || !element.matches(STYLE_SELECTOR)) return false;
        if (element.classList.contains(INLINE_CLASS) || element.classList.contains("darkreader") || element.classList.contains("stylus")) return false;
        const media = String(element.media || "").toLowerCase();
        if (media.includes("print") || media.includes("speech")) return false;
        if (element instanceof HTMLLinkElement && (!element.href || element.disabled)) return false;
        return true;
      };

      const getManageableStyles = (root, results = []) => {
        if (!root) return results;
        if (shouldManageStyle(root)) {
          results.push(root);
          return results;
        }
        if (root.querySelectorAll) {
          for (const element of root.querySelectorAll(STYLE_SELECTOR)) {
            if (shouldManageStyle(element)) results.push(element);
          }
        }
        return results;
      };

      const safeGetRules = (sheet) => {
        try {
          return sheet && sheet.cssRules ? sheet.cssRules : null;
        } catch (_) {
          return null;
        }
      };

      const shorthandVarDependentProperties = [
        "background",
        "border",
        "border-color",
        "border-bottom",
        "border-left",
        "border-right",
        "border-top",
        "outline",
        "outline-color"
      ];

      const escapeRegExp = (value) => String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

      const iterateCSSDeclarations = (style, iterate) => {
        const cssText = style.cssText || "";
        const seen = new Set();
        const emit = (property, value) => {
          const prop = String(property || "").trim();
          const val = String(value || "").trim();
          if (!prop || !val || seen.has(prop)) return;
          seen.add(prop);
          iterate(prop, val);
        };

        if (cssText.includes("var(")) {
          for (const property of shorthandVarDependentProperties) {
            let value = "";
            try {
              value = style.getPropertyValue(property);
            } catch (_) {}
            if (value && value.includes("var(")) {
              emit(property, value);
              continue;
            }

            const match = cssText.match(new RegExp(`${escapeRegExp(property)}\\s*:\\s*([^;]+)`));
            if (match && match[1] && match[1].includes("var(")) {
              emit(property, match[1]);
            }
          }
        }

        if ((cssText.includes("background-color: ;") || cssText.includes("background-image: ;") || cssText.includes("background:")) && !style.getPropertyValue("background")) {
          const match = cssText.match(/background\s*:\s*([^;]+)/);
          if (match && match[1]) {
            emit("background", match[1]);
          }
        }

        for (let index = 0; index < style.length; index += 1) {
          const property = style.item(index);
          emit(property, style.getPropertyValue(property));
        }
      };

      const shouldTreatCustomPropertyAsBackground = (property) => (
        property.includes("bg")
        || property.includes("background")
        || property.includes("surface")
        || property.includes("container")
        || property.includes("canvas")
        || property.includes("fill")
      );

      const shouldTreatCustomPropertyAsBorder = (property) => (
        property.includes("border")
        || property.includes("outline")
        || property.includes("divider")
        || property.includes("stroke")
        || property.includes("shadow")
      );

      const varReferenceRegex = /var\(\s*(--[-_a-zA-Z0-9]+)\s*(?:,\s*([^()]*|\([^)]*\)))?\)/g;
      const wrappedVariableName = (type, name) => `${DARK_VAR_PREFIX}-${type}-${name.slice(2)}`;

      const cssVariableTypeForProperty = (property) => {
        const prop = property.toLowerCase();
        if (prop.startsWith("--")) {
          if (shouldTreatCustomPropertyAsBackground(prop)) return "bg";
          if (shouldTreatCustomPropertyAsBorder(prop)) return "border";
          return "text";
        }
        if (prop.startsWith("background") || prop === "box-shadow" || prop === "text-shadow" || prop === "fill" || prop === "stop-color") {
          return "bg";
        }
        if (prop.includes("border") || prop === "outline" || prop === "outline-color" || prop === "column-rule" || prop === "column-rule-color" || prop === "text-decoration-color" || prop === "stroke") {
          return "border";
        }
        return "text";
      };

      const replaceCSSVariableReferences = (value, type) => {
        if (!value || !value.includes("var(")) return value;
        return value.replace(varReferenceRegex, (match, name, fallback) => {
          const wrapped = wrappedVariableName(type, name);
          if (!fallback) {
            return `var(${wrapped}, var(${name}))`;
          }

          const fallbackValue = fallback.trim();
          const transformer = type === "bg"
            ? modifyBackgroundColor
            : (type === "border" ? modifyBorderColor : modifyForegroundColor);
          const modifiedFallback = replaceCSSColors(fallbackValue, transformer);
          return `var(${wrapped}, ${modifiedFallback})`;
        });
      };

      const transformVariableDependentValue = (property, value) => {
        if (!value || !value.includes("var(")) return null;
        const type = cssVariableTypeForProperty(property);
        const transformed = replaceCSSVariableReferences(value, type);
        return transformed === value ? null : transformed;
      };

      const transformCustomPropertyDeclarations = (property, value) => {
        if (!value || property.startsWith(DARK_VAR_PREFIX)) return null;
        const declarations = [];

        const makeValue = (type, transformer) => {
          if (value.includes("var(")) {
            const rewritten = replaceCSSVariableReferences(value, type);
            const transformedFallbacks = replaceCSSColors(rewritten, transformer);
            return transformedFallbacks === value ? null : transformedFallbacks;
          }

          if (!COLOR_RE.test(value)) {
            COLOR_RE.lastIndex = 0;
            return null;
          }
          COLOR_RE.lastIndex = 0;
          const transformed = replaceCSSColors(value, transformer);
          return transformed === value ? null : transformed;
        };

        const bgValue = makeValue("bg", modifyBackgroundColor);
        const textValue = makeValue("text", modifyForegroundColor);
        const borderValue = makeValue("border", modifyBorderColor);

        if (bgValue) declarations.push({ property: wrappedVariableName("bg", property), value: bgValue });
        if (textValue) declarations.push({ property: wrappedVariableName("text", property), value: textValue });
        if (borderValue) declarations.push({ property: wrappedVariableName("border", property), value: borderValue });

        return declarations.length > 0 ? declarations : null;
      };

      const transformCSSValue = (property, value, ownerElement = null) => {
        if (!property || !value) return null;
        const prop = property.toLowerCase();
        const text = String(value).trim();
        if (!text || text === "inherit" || text === "initial" || text === "unset") return null;

        if (prop.startsWith("--")) {
          return transformCustomPropertyDeclarations(prop, text);
        }

        if (text.includes("var(")) {
          const variableValue = transformVariableDependentValue(prop, text);
          if (variableValue) return variableValue;
        }

        if (prop === "color" || prop === "-webkit-text-fill-color" || prop === "text-emphasis-color" || prop === "caret-color") {
          const color = parseColor(text);
          return color ? transformForeground(color) : null;
        }

        if (prop === "fill" || prop === "stroke" || prop === "stop-color") {
          const color = parseColor(text);
          const isLargeSVGPaint = ownerElement && ownerElement instanceof SVGElement && prop === "fill";
          return color ? (isLargeSVGPaint ? transformBackground(color) : transformForeground(color)) : null;
        }

        if (prop === "background-color") {
          const color = parseColor(text);
          return color ? transformBackground(color, ownerElement) : null;
        }

        if (prop === "border-color" || (prop.startsWith("border") && prop.endsWith("color")) || prop === "outline-color" || prop === "column-rule-color" || prop === "text-decoration-color") {
          const color = parseColor(text);
          return color ? transformBorder(color) : null;
        }

        if (prop.includes("color") && prop !== "-webkit-print-color-adjust") {
          const transformer = prop.includes("background")
            ? modifyBackgroundColor
            : ((prop.includes("border") || prop.includes("outline") || prop.includes("decoration") || prop.includes("column-rule") || prop.includes("stroke")) ? modifyBorderColor : modifyForegroundColor);
          const transformed = replaceCSSColors(text, transformer);
          return transformed === text ? null : transformed;
        }

        if (prop === "box-shadow" || prop === "text-shadow") {
          return transformBoxShadow(text);
        }

        if (prop === "background-image") {
          if (text.includes("gradient")) {
            return replaceCSSColors(text, modifyBackgroundColor);
          }
          if ((ownerElement === document.documentElement || ownerElement === document.body) && text.includes("url(")) {
            return "none";
          }
          return null;
        }

        if (prop === "background" || prop.startsWith("border") || prop === "outline" || prop === "column-rule") {
          if (!COLOR_RE.test(text)) {
            COLOR_RE.lastIndex = 0;
            return null;
          }
          COLOR_RE.lastIndex = 0;
          const transformer = prop === "background" ? modifyBackgroundColor : modifyBorderColor;
          return replaceCSSColors(text, transformer);
        }

        return null;
      };

      const buildModifiedDeclarations = (style, ownerElement = null) => {
        const declarations = [];

        iterateCSSDeclarations(style, (property, value) => {
          const modified = transformCSSValue(property, value, ownerElement);
          if (!modified || modified === value) return;
          const priority = style.getPropertyPriority(property) ? " !important" : "";
          if (Array.isArray(modified)) {
            for (const declaration of modified) {
              declarations.push(`  ${declaration.property}: ${declaration.value}${priority};`);
            }
          } else {
            declarations.push(`  ${property}: ${modified}${priority};`);
          }
        });

        return declarations;
      };

      const convertCSSRule = (rule) => {
        try {
          if (rule.type === CSSRule.STYLE_RULE) {
            const declarations = buildModifiedDeclarations(rule.style);
            return declarations.length > 0 ? `${rule.selectorText} {\n${declarations.join("\n")}\n}` : "";
          }

          if (rule.type === CSSRule.IMPORT_RULE && rule.styleSheet) {
            return convertCSSRules(rule.styleSheet.cssRules);
          }

          if (rule.type === CSSRule.MEDIA_RULE || rule.type === CSSRule.SUPPORTS_RULE || (rule.cssRules && rule.cssText && rule.cssText.startsWith("@"))) {
            const childRules = convertCSSRules(rule.cssRules);
            if (!childRules) return "";
            const open = rule.cssText.indexOf("{");
            const prefix = open > 0 ? rule.cssText.slice(0, open).trim() : "";
            return prefix ? `${prefix} {\n${childRules}\n}` : "";
          }
        } catch (_) {}

        return "";
      };

      const convertCSSRules = (rules) => {
        if (!rules) return "";
        const chunks = [];
        for (let index = 0; index < rules.length; index += 1) {
          const converted = convertCSSRule(rules[index]);
          if (converted) chunks.push(converted);
        }
        return chunks.join("\n");
      };

      const renderStyleManager = (element) => {
        const rules = safeGetRules(element.sheet);
        if (!rules) return;

        let manager = styleManagers.get(element);
        if (!manager) {
          const syncStyle = element instanceof SVGStyleElement
            ? document.createElementNS("http://www.w3.org/2000/svg", "style")
            : document.createElement("style");
          syncStyle.classList.add(INLINE_CLASS, STYLE_SYNC_CLASS);
          syncStyle.media = "screen";
          manager = { syncStyle, signature: "", observer: null };
          styleManagers.set(element, manager);

          if (window.MutationObserver) {
            manager.observer = new MutationObserver(() => scheduleStyleSync(0));
            manager.observer.observe(element, {
              attributes: true,
              childList: true,
              subtree: true,
              characterData: true
            });
          }
        }

        const signature = `${rules.length}:${element.textContent ? element.textContent.length : ""}:${element.href || ""}`;
        if (manager.signature === signature && manager.syncStyle.textContent) {
          if (manager.syncStyle.parentNode !== element.parentNode && element.parentNode) {
            element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
          }
          return;
        }

        const css = convertCSSRules(rules);
        manager.signature = signature;
        manager.syncStyle.textContent = css;

        if (!css) {
          manager.syncStyle.remove();
          return;
        }

        if (element.parentNode && manager.syncStyle.parentNode !== element.parentNode) {
          element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
        } else if (element.parentNode && manager.syncStyle.previousSibling !== element) {
          element.parentNode.insertBefore(manager.syncStyle, element.nextSibling);
        }
      };

      const renderAdoptedStyleSheets = (root) => {
        if (!root || !root.adoptedStyleSheets || !root.adoptedStyleSheets.length) return;
        let manager = adoptedStyleManagers.get(root);
        if (!manager) {
          const style = document.createElement("style");
          style.classList.add(INLINE_CLASS, ADOPTED_STYLE_CLASS);
          style.media = "screen";
          manager = { style, signature: "" };
          adoptedStyleManagers.set(root, manager);
        }

        const chunks = [];
        const signature = [];
        for (const sheet of root.adoptedStyleSheets) {
          const rules = safeGetRules(sheet);
          if (!rules) continue;
          signature.push(rules.length);
          const css = convertCSSRules(rules);
          if (css) chunks.push(css);
        }

        const nextSignature = signature.join(",");
        if (manager.signature !== nextSignature) {
          manager.signature = nextSignature;
          manager.style.textContent = chunks.join("\n");
        }

        if (manager.style.textContent && manager.style.parentNode !== root) {
          try {
            root.insertBefore(manager.style, root.firstChild);
          } catch (_) {
            root.appendChild(manager.style);
          }
        }
      };

      const updateManageableStyles = (root = document) => {
        for (const style of getManageableStyles(root)) {
          renderStyleManager(style);
        }
        renderAdoptedStyleSheets(root);
      };

      const scheduleStyleSync = (delay = 30) => {
        if (stylesheetSyncScheduled) return;
        stylesheetSyncScheduled = true;
        window.setTimeout(() => {
          stylesheetSyncScheduled = false;
          updateManageableStyles(document);
          for (const root of discoveredShadowRoots) {
            updateManageableStyles(root);
          }
          ensureSiteFixStyle();
        }, delay);
      };

      const installStylesheetProxy = () => {
        if (!window.CSSStyleSheet || CSSStyleSheet.prototype.__wkdomainsDarkModeProxy) return;
        const proto = CSSStyleSheet.prototype;
        const nativeInsertRule = proto.insertRule;
        const nativeDeleteRule = proto.deleteRule;
        const nativeReplace = proto.replace;
        const nativeReplaceSync = proto.replaceSync;

        Object.defineProperty(proto, "__wkdomainsDarkModeProxy", { value: true });
        if (nativeInsertRule) {
          proto.insertRule = function(rule, index) {
            const result = nativeInsertRule.call(this, rule, index);
            scheduleStyleSync(0);
            return result;
          };
        }
        if (nativeDeleteRule) {
          proto.deleteRule = function(index) {
            const result = nativeDeleteRule.call(this, index);
            scheduleStyleSync(0);
            return result;
          };
        }
        if (nativeReplace) {
          proto.replace = function(text) {
            return nativeReplace.call(this, text).then((sheet) => {
              scheduleStyleSync(0);
              return sheet;
            });
          };
        }
        if (nativeReplaceSync) {
          proto.replaceSync = function(text) {
            const result = nativeReplaceSync.call(this, text);
            scheduleStyleSync(0);
            return result;
          };
        }

        if (window.CSSStyleDeclaration && !CSSStyleDeclaration.prototype.__wkdomainsDarkModeProxy) {
          const declarationProto = CSSStyleDeclaration.prototype;
          const nativeSetProperty = declarationProto.setProperty;
          const nativeRemoveProperty = declarationProto.removeProperty;
          Object.defineProperty(declarationProto, "__wkdomainsDarkModeProxy", { value: true });

          declarationProto.setProperty = function(property, value, priority) {
            const result = nativeSetProperty.call(this, property, value, priority);
            const propertyName = property ? String(property) : "";
            if (propertyName.startsWith(DARK_VAR_PREFIX) || propertyName.startsWith("--wkdomains-forced-dark")) {
              return result;
            }
            if (this.parentRule || propertyName.startsWith("--")) {
              scheduleStyleSync(0);
            }
            return result;
          };

          declarationProto.removeProperty = function(property) {
            const result = nativeRemoveProperty.call(this, property);
            const propertyName = property ? String(property) : "";
            if (propertyName.startsWith(DARK_VAR_PREFIX) || propertyName.startsWith("--wkdomains-forced-dark")) {
              return result;
            }
            if (this.parentRule || propertyName.startsWith("--")) {
              scheduleStyleSync(0);
            }
            return result;
          };
        }

        const patchAdoptedStyleSheets = (rootProto) => {
          if (!rootProto || rootProto.__wkdomainsDarkModeAdoptedProxy) return;
          const descriptor = Object.getOwnPropertyDescriptor(rootProto, "adoptedStyleSheets");
          if (!descriptor || !descriptor.set || !descriptor.get) return;
          Object.defineProperty(rootProto, "__wkdomainsDarkModeAdoptedProxy", { value: true });
          Object.defineProperty(rootProto, "adoptedStyleSheets", {
            configurable: true,
            enumerable: descriptor.enumerable,
            get() {
              return descriptor.get.call(this);
            },
            set(value) {
              descriptor.set.call(this, value);
              scheduleStyleSync(0);
            }
          });
        };

        patchAdoptedStyleSheets(Document.prototype);
        if (window.ShadowRoot) {
          patchAdoptedStyleSheets(ShadowRoot.prototype);
        }
      };
    """#
}
