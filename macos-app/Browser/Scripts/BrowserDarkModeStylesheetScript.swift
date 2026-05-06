//
//  BrowserDarkModeStylesheetScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetScript = #"""
      const styleManagers = new WeakMap();
      const adoptedStyleManagers = new WeakMap();
      const managedStyleElements = new Set();
      const managedAdoptedRoots = new Set();
      let stylesheetSyncScheduled = false;
      let stylesheetSyncTimer = null;
      let stylesheetProxyActive = false;
      let loadingStylesCounter = 0;
      const loadingStyles = new Set();
      const loadingStyleIDsByElement = new WeakMap();
      const loadingStyleListenersByElement = new WeakMap();
      let fallbackWasCleared = false;

      const cssURLMatchesPattern = (url, pattern) => {
        const value = String(url || "");
        const text = String(pattern || "");
        if (!value || !text) return false;
        if (value.includes(text)) return true;
        try {
          const escaped = text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replaceAll("\\*", ".*");
          return new RegExp(`^${escaped}$`).test(value);
        } catch (_) {
          return false;
        }
      };

      const shouldIgnoreCSSURL = (url) => ignoredCSSURLPatterns.some((pattern) => cssURLMatchesPattern(url, pattern));

      const shouldManageStyle = (element) => {
        if (!element || !element.matches || !element.matches(STYLE_SELECTOR)) return false;
        if (element.classList.contains(INLINE_CLASS) || element.classList.contains("darkreader") || element.classList.contains("stylus")) return false;
        const media = String(element.media || "").toLowerCase();
        if (media.includes("print") || media.includes("speech")) return false;
        if (element instanceof HTMLLinkElement && (!element.href || element.disabled || shouldIgnoreCSSURL(element.href))) return false;
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

      const fallbackStyleElement = () => (
        findStaticStyle("wkdomains-darkreader--fallback", document)
        || createOrUpdateStyle("wkdomains-darkreader--fallback", document)
      );

      const ensureFallbackStyleText = () => {
        const fallbackStyle = fallbackStyleElement();
        fallbackStyle.id = STYLE_ID;
        if (!fallbackStyle.textContent) {
          fallbackStyle.textContent = getFallbackStyle();
        }
        injectStaticStyle(fallbackStyle, null, "fallback");
        fallbackWasCleared = false;
      };

      const cleanFallbackStyle = () => {
        if (loadingStyles.size > 0) return;
        const fallbackStyle = fallbackStyleElement();
        fallbackStyle.textContent = "";
        fallbackWasCleared = true;
      };

      const loadingIDForElement = (element) => {
        let id = loadingStyleIDsByElement.get(element);
        if (!id) {
          id = ++loadingStylesCounter;
          loadingStyleIDsByElement.set(element, id);
        }
        return id;
      };

      const markStyleLoading = (element) => {
        if (!element) return;
        const id = loadingIDForElement(element);
        loadingStyles.add(id);
        ensureFallbackStyleText();

        if (element instanceof HTMLLinkElement && !loadingStyleListenersByElement.has(element)) {
          const done = () => {
            markStyleLoaded(element);
            scheduleStyleSync(0);
          };
          element.addEventListener("load", done, { once: true });
          element.addEventListener("error", done, { once: true });
          loadingStyleListenersByElement.set(element, done);
        }
      };

      const markStyleLoaded = (element) => {
        if (!element) return;
        const id = loadingStyleIDsByElement.get(element);
        if (id) {
          loadingStyles.delete(id);
        }
        if (loadingStyles.size === 0 && document.readyState !== "loading") {
          cleanFallbackStyle();
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

      const shouldTreatCustomPropertyAsRawColor = (property) => {
        const prop = String(property || "").toLowerCase();
        return prop.includes("color")
          || prop.includes("colour")
          || prop.includes("background")
          || prop.includes("bg")
          || prop.includes("surface")
          || prop.includes("canvas")
          || prop.includes("border")
          || prop.includes("outline")
          || prop.includes("divider")
          || prop.includes("fill")
          || prop.includes("stroke")
          || prop.includes("text")
          || prop.includes("content")
          || prop.includes("tone")
          || prop.includes("neutral")
          || prop.includes("primary")
          || prop.includes("secondary")
          || prop.includes("accent")
          || prop.includes("brand")
          || prop.includes("link");
      };

      const varReferenceRegex = /var\(\s*(--[-_a-zA-Z0-9]+)\s*(?:,\s*([^()]*|\([^)]*\)))?\)/g;
      const wrappedVariableName = (type, name) => `${DARK_VAR_PREFIX}-${type}-${name.slice(2)}`;
      const VAR_TYPE_BG = 1 << 0;
      const VAR_TYPE_TEXT = 1 << 1;
      const VAR_TYPE_BORDER = 1 << 2;
      const VAR_TYPE_BG_IMG = 1 << 3;

      const cssVariableTypeForProperty = (property) => {
        const prop = property.toLowerCase();
        if (prop.startsWith("--")) {
          if (shouldTreatCustomPropertyAsBackground(prop)) return "bg";
          if (shouldTreatCustomPropertyAsBorder(prop)) return "border";
          return "text";
        }
        if (prop.startsWith("background") || prop === "box-shadow" || prop === "text-shadow") {
          return "bg";
        }
        if (prop === "fill" || prop === "stroke" || prop === "stop-color") {
          return "text";
        }
        if (prop.includes("border") || prop === "outline" || prop === "outline-color" || prop === "column-rule" || prop === "column-rule-color" || prop === "text-decoration-color" || prop === "stroke") {
          return "border";
        }
        return "text";
      };

      const shouldTransformVariableDependentProperty = (property) => {
        const prop = String(property || "").toLowerCase();
        return prop === "color"
          || prop === "-webkit-text-fill-color"
          || prop === "text-emphasis-color"
          || prop === "caret-color"
          || prop === "fill"
          || prop === "stroke"
          || prop === "stop-color"
          || prop === "box-shadow"
          || prop === "text-shadow"
          || prop === "outline"
          || prop === "outline-color"
          || prop === "column-rule"
          || prop === "column-rule-color"
          || prop === "text-decoration-color"
          || prop.startsWith("background")
          || prop.startsWith("border")
          || (prop.includes("color") && prop !== "-webkit-print-color-adjust");
      };

      const variableTypeNumberForProperty = (property, value = "") => {
        const prop = String(property || "").toLowerCase();
        if (prop === "background-image") return VAR_TYPE_BG_IMG;
        if (prop === "background" && /url\(|gradient\(/i.test(String(value || ""))) return VAR_TYPE_BG_IMG;
        switch (cssVariableTypeForProperty(prop)) {
        case "bg":
          return VAR_TYPE_BG;
        case "border":
          return VAR_TYPE_BORDER;
        default:
          return VAR_TYPE_TEXT;
        }
      };

      const forEachVarReference = (value, iterate) => {
        if (!value || !String(value).includes("var(")) return;
        String(value).replace(varReferenceRegex, (match, name, fallback) => {
          iterate(name, fallback || "");
          if (fallback && fallback.includes("var(")) {
            forEachVarReference(fallback, iterate);
          }
          return match;
        });
      };

      const variablesStore = (() => {
        const varTypes = new Map();
        const varValues = new Map();
        const varRefs = new Map();
        const rulesQueue = new Set();
        const inlineQueue = [];
        let versionNumber = 0;
        let lastTypeSignature = "";

        const clear = () => {
          varTypes.clear();
          varValues.clear();
          varRefs.clear();
          rulesQueue.clear();
          inlineQueue.splice(0);
        };

        const resolveType = (name, type) => {
          if (!name || !type) return;
          varTypes.set(name, (varTypes.get(name) || 0) | type);
        };

        const addRulesForMatching = (rules) => {
          if (rules) rulesQueue.add(rules);
        };

        const addInlineStyleForMatching = (style) => {
          if (style) inlineQueue.push(style);
        };

        const addVarRef = (owner, ref) => {
          if (!owner || !ref) return;
          if (!varRefs.has(owner)) varRefs.set(owner, new Set());
          varRefs.get(owner).add(ref);
        };

        const inspectVariable = (property, value) => {
          if (!property || !property.startsWith("--")) return;
          const text = String(value || "").trim();
          varValues.set(property, text);

          if (text.includes("var(")) {
            forEachVarReference(text, (ref) => addVarRef(property, ref));
          }

          COLOR_RE.lastIndex = 0;
          const hasColor = COLOR_RE.test(text);
          COLOR_RE.lastIndex = 0;
          const hasColorLikeName = shouldTreatCustomPropertyAsRawColor(property);
          const hasNamedRawColor = parseRawColorValue(text) && hasColorLikeName;
          if (hasColor || /^\s*(rgb|hsl)a?\(/i.test(text) || hasNamedRawColor || (text.includes("var(") && hasColorLikeName)) {
            if (shouldTreatCustomPropertyAsBackground(property)) {
              resolveType(property, VAR_TYPE_BG);
            } else if (shouldTreatCustomPropertyAsBorder(property)) {
              resolveType(property, VAR_TYPE_BORDER);
            } else {
              resolveType(property, VAR_TYPE_TEXT);
            }
          }

          if (text.includes("url(") || text.includes("gradient(")) {
            resolveType(property, VAR_TYPE_BG_IMG);
          }
        };

        const inspectVarDependent = (property, value) => {
          if (!value || !String(value).includes("var(")) return;
          if (!property.startsWith("--") && !shouldTransformVariableDependentProperty(property)) return;
          const type = property.startsWith("--")
            ? 0
            : variableTypeNumberForProperty(property, value);
          forEachVarReference(value, (ref) => {
            if (property.startsWith("--")) {
              addVarRef(property, ref);
            } else {
              resolveType(ref, type);
            }
          });
        };

        const inspectDeclarations = (style) => {
          if (!style) return;
          iterateCSSDeclarations(style, (property, value) => {
            if (property.startsWith("--")) {
              inspectVariable(property, value);
            }
            inspectVarDependent(property, value);
          });
        };

        const inspectRules = (rules) => {
          if (!rules) return;
          for (let index = 0; index < rules.length; index += 1) {
            const rule = rules[index];
            try {
              if (rule.style) {
                inspectDeclarations(rule.style);
              }
              if (rule.cssRules) {
                inspectRules(rule.cssRules);
              }
              if (rule.type === CSSRule.IMPORT_RULE && rule.styleSheet) {
                inspectRules(rule.styleSheet.cssRules);
              }
            } catch (_) {}
          }
        };

        const propagateTypes = () => {
          let changed = true;
          let guard = 0;
          while (changed && guard < 16) {
            changed = false;
            guard += 1;
            for (const [owner, refs] of varRefs) {
              const ownerType = varTypes.get(owner) || 0;
              if (!ownerType) continue;
              for (const ref of refs) {
                const before = varTypes.get(ref) || 0;
                const next = before | ownerType;
                if (next !== before) {
                  varTypes.set(ref, next);
                  changed = true;
                }
              }
            }
          }
        };

        const updateVersion = () => {
          const nextSignature = Array.from(varTypes.entries())
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([name, type]) => `${name}:${type}`)
            .join("|");
          if (nextSignature !== lastTypeSignature) {
            lastTypeSignature = nextSignature;
            versionNumber += 1;
          }
        };

        const matchVariablesAndDependents = () => {
          for (const rules of rulesQueue) inspectRules(rules);
          for (const style of inlineQueue) inspectDeclarations(style);
          rulesQueue.clear();
          inlineQueue.splice(0);
          propagateTypes();
          updateVersion();
        };

        const typesForVariable = (name) => varTypes.get(name) || 0;
        const isVarType = (name, type) => (typesForVariable(name) & type) !== 0;

        const rootDeclarations = () => {
          const declarations = [];
          const rootStyle = document.documentElement && document.documentElement.style;
          if (!rootStyle) return declarations;

          iterateCSSDeclarations(rootStyle, (property, value) => {
            if (!property.startsWith("--")) return;
            const type = typesForVariable(property);
            if (!type) return;
            if (type & (VAR_TYPE_BG | VAR_TYPE_BG_IMG)) {
              const transformed = transformCustomPropertyValue(property, value, "bg", modifyBackgroundColor, true);
              if (transformed) declarations.push([wrappedVariableName("bg", property), transformed]);
            }
            if (type & VAR_TYPE_TEXT) {
              const transformed = transformCustomPropertyValue(property, value, "text", modifyForegroundColor, true);
              if (transformed) declarations.push([wrappedVariableName("text", property), transformed]);
            }
            if (type & VAR_TYPE_BORDER) {
              const transformed = transformCustomPropertyValue(property, value, "border", modifyBorderColor, true);
              if (transformed) declarations.push([wrappedVariableName("border", property), transformed]);
            }
          });

          return declarations;
        };

        return {
          clear,
          addRulesForMatching,
          addInlineStyleForMatching,
          matchVariablesAndDependents,
          typesForVariable,
          isVarType,
          version: () => versionNumber,
          rootDeclarations
        };
      })();

      const transformCustomPropertyValue = (property, value, type, transformer, allowRawColor = false) => {
        if (!value || property.startsWith(DARK_VAR_PREFIX)) return null;
        if (String(value).includes("var(")) {
          const rewritten = replaceCSSVariableReferences(value, type);
          const transformedFallbacks = replaceCSSColors(rewritten, transformer);
          return transformedFallbacks === value ? rewritten : transformedFallbacks;
        }

        COLOR_RE.lastIndex = 0;
        if (!COLOR_RE.test(value)) {
          COLOR_RE.lastIndex = 0;
          return allowRawColor ? replaceRawColorValue(value, transformer) : null;
        }
        COLOR_RE.lastIndex = 0;
        const transformed = replaceCSSColors(value, transformer);
        return transformed === value ? null : transformed;
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
          const colorFallback = replaceCSSColors(fallbackValue, transformer);
          const modifiedFallback = colorFallback === fallbackValue
            ? (replaceRawColorValue(fallbackValue, transformer) || colorFallback)
            : colorFallback;
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
        const inferredTypes = variablesStore.typesForVariable(property);

        const allowRawColor = inferredTypes !== 0 || shouldTreatCustomPropertyAsRawColor(property);
        const makeValue = (type, transformer) => {
          return transformCustomPropertyValue(property, value, type, transformer, allowRawColor);
        };

        const shouldEmitFallbackTypes = inferredTypes === 0;
        const bgValue = (shouldEmitFallbackTypes || (inferredTypes & (VAR_TYPE_BG | VAR_TYPE_BG_IMG))) ? makeValue("bg", modifyBackgroundColor) : null;
        const textValue = (shouldEmitFallbackTypes || (inferredTypes & VAR_TYPE_TEXT)) ? makeValue("text", modifyForegroundColor) : null;
        const borderValue = (shouldEmitFallbackTypes || (inferredTypes & VAR_TYPE_BORDER)) ? makeValue("border", modifyBorderColor) : null;

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

        if (text.includes("var(") && shouldTransformVariableDependentProperty(prop)) {
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

      const hashString = (value) => {
        const text = String(value || "");
        let hash = 2166136261;
        for (let index = 0; index < text.length; index += 1) {
          hash ^= text.charCodeAt(index);
          hash = Math.imul(hash, 16777619);
        }
        return (hash >>> 0).toString(36);
      };

      const signatureForRules = (rules) => {
        if (!rules) return "no-rules";
        const parts = [rules.length, variablesStore.version()];
        for (let index = 0; index < rules.length; index += 1) {
          try {
            parts.push(hashString(rules[index].cssText));
          } catch (_) {
            parts.push("x");
          }
        }
        return parts.join(":");
      };

      const renderStyleManager = (element) => {
        const rules = safeGetRules(element.sheet);
        if (!rules) {
          markStyleLoading(element);
          return;
        }
        markStyleLoaded(element);

        let manager = styleManagers.get(element);
        if (!manager) {
          const syncStyle = element instanceof SVGStyleElement
            ? document.createElementNS("http://www.w3.org/2000/svg", "style")
            : document.createElement("style");
          syncStyle.classList.add(INLINE_CLASS, "darkreader", STYLE_SYNC_CLASS);
          syncStyle.media = "screen";
          manager = { syncStyle, signature: "", observer: null };
          styleManagers.set(element, manager);
          managedStyleElements.add(element);

          if (window.MutationObserver) {
            manager.observer = new MutationObserver(() => scheduleStyleSync(0));
            const isLink = element instanceof HTMLLinkElement;
            manager.observer.observe(element, {
              attributes: true,
              attributeFilter: isLink ? ["href", "media", "disabled"] : ["media", "disabled"],
              childList: !isLink,
              subtree: !isLink,
              characterData: !isLink
            });
          }
        }

        const signature = `${signatureForRules(rules)}:${hashString(element.textContent || "")}:${element.href || ""}`;
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
        if (!root || !root.adoptedStyleSheets) return;
        if (!root.adoptedStyleSheets.length) {
          const existing = adoptedStyleManagers.get(root);
          if (existing) {
            existing.style.remove();
            adoptedStyleManagers.delete(root);
            managedAdoptedRoots.delete(root);
          }
          return;
        }
        let manager = adoptedStyleManagers.get(root);
        if (!manager) {
          const style = document.createElement("style");
          style.classList.add(INLINE_CLASS, "darkreader", ADOPTED_STYLE_CLASS);
          style.media = "screen";
          manager = { style, signature: "" };
          adoptedStyleManagers.set(root, manager);
          managedAdoptedRoots.add(root);
        }

        const chunks = [];
        const signature = [];
        for (const sheet of root.adoptedStyleSheets) {
          const rules = safeGetRules(sheet);
          if (!rules) continue;
          signature.push(signatureForRules(rules));
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

      const collectAdoptedStyleSheetRules = (root) => {
        if (!root || !root.adoptedStyleSheets || !root.adoptedStyleSheets.length) return;
        for (const sheet of root.adoptedStyleSheets) {
          variablesStore.addRulesForMatching(safeGetRules(sheet));
        }
      };

      const updateRootVariableStyle = () => {
        if (!document.documentElement) return;
        const rootVarsStyle = createOrUpdateStyle("wkdomains-darkreader--root-vars", document);
        const declarations = variablesStore.rootDeclarations();
        rootVarsStyle.textContent = declarations.length > 0
          ? `:root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) {\n${declarations.map(([property, value]) => `  ${property}: ${value};`).join("\n")}\n}`
          : "";
      };

      const removeStyleManager = (element) => {
        const manager = styleManagers.get(element);
        const listener = loadingStyleListenersByElement.get(element);
        if (listener && element instanceof HTMLLinkElement) {
          element.removeEventListener("load", listener);
          element.removeEventListener("error", listener);
          loadingStyleListenersByElement.delete(element);
        }
        markStyleLoaded(element);
        if (manager) {
          if (manager.observer) manager.observer.disconnect();
          manager.syncStyle.remove();
          styleManagers.delete(element);
        }
        managedStyleElements.delete(element);
      };

      const pruneStyleManagers = () => {
        for (const element of Array.from(managedStyleElements)) {
          if (!element.isConnected) {
            removeStyleManager(element);
          }
        }
      };

      const removeAdoptedStyleManager = (root) => {
        const manager = adoptedStyleManagers.get(root);
        if (manager) {
          manager.style.remove();
          adoptedStyleManagers.delete(root);
        }
        managedAdoptedRoots.delete(root);
      };

      const pruneAdoptedStyleManagers = () => {
        for (const root of Array.from(managedAdoptedRoots)) {
          if (root !== document && root.host && !root.host.isConnected) {
            removeAdoptedStyleManager(root);
          }
        }
      };

      const destroyStyleManagers = () => {
        for (const element of Array.from(managedStyleElements)) {
          removeStyleManager(element);
        }
        loadingStyles.clear();
        for (const root of Array.from(managedAdoptedRoots)) {
          removeAdoptedStyleManager(root);
        }
        for (const style of document.querySelectorAll(`style.${STYLE_SYNC_CLASS}, style.${ADOPTED_STYLE_CLASS}`)) {
          style.remove();
        }
      };

      const getStylesheetSyncRoots = () => {
        const roots = [document];
        for (const root of Array.from(discoveredShadowRoots)) {
          if (!root) continue;
          if (root.host && !root.host.isConnected) {
            discoveredShadowRoots.delete(root);
            removeAdoptedStyleManager(root);
            continue;
          }
          roots.push(root);
        }
        return roots;
      };

      const collectVariableInputs = (root) => {
        const styles = getManageableStyles(root);
        for (const style of styles) {
          variablesStore.addRulesForMatching(safeGetRules(style.sheet));
        }
        collectAdoptedStyleSheetRules(root);
        if (root === document && document.documentElement) {
          variablesStore.addInlineStyleForMatching(document.documentElement.style);
        }
        return styles;
      };

      const renderManageableStyles = (root, styles) => {
        for (const style of styles) {
          renderStyleManager(style);
        }
        renderAdoptedStyleSheets(root);
      };

      const syncAllStyles = () => {
        pruneStyleManagers();
        pruneAdoptedStyleManagers();
        variablesStore.clear();

        const roots = getStylesheetSyncRoots();
        const stylesByRoot = new Map();
        for (const root of roots) {
          stylesByRoot.set(root, collectVariableInputs(root));
        }

        variablesStore.matchVariablesAndDependents();
        updateRootVariableStyle();

        for (const root of roots) {
          renderManageableStyles(root, stylesByRoot.get(root) || []);
        }

        if (loadingStyles.size === 0 && document.readyState !== "loading") {
          cleanFallbackStyle();
        }
      };

      const updateManageableStyles = () => {
        syncAllStyles();
      };

      const scheduleStyleSync = (delay = 30) => {
        if (stylesheetSyncScheduled) return;
        stylesheetSyncScheduled = true;
        stylesheetSyncTimer = window.setTimeout(() => {
          stylesheetSyncScheduled = false;
          stylesheetSyncTimer = null;
          syncAllStyles();
          ensureSiteFixStyle();
        }, delay);
      };

      const cancelStyleSync = () => {
        if (stylesheetSyncTimer) {
          window.clearTimeout(stylesheetSyncTimer);
          stylesheetSyncTimer = null;
        }
        stylesheetSyncScheduled = false;
      };

      const installStylesheetProxy = () => {
        if (siteFixFlag("disableStyleSheetsProxy")) return;
        if (!window.CSSStyleSheet) return;
        stylesheetProxyActive = true;
        if (CSSStyleSheet.prototype.__wkdomainsDarkModeProxy) return;
        const proto = CSSStyleSheet.prototype;
        const nativeInsertRule = proto.insertRule;
        const nativeDeleteRule = proto.deleteRule;
        const nativeAddRule = proto.addRule;
        const nativeRemoveRule = proto.removeRule;
        const nativeReplace = proto.replace;
        const nativeReplaceSync = proto.replaceSync;
        const isOwnGeneratedCSS = (text) => {
          const value = String(text || "");
          return value.includes(DARK_VAR_PREFIX)
            || value.includes("--wkdomains-forced-dark")
            || value.includes(INLINE_CLASS)
            || value.includes(STYLE_SYNC_CLASS)
            || value.includes(ADOPTED_STYLE_CLASS);
        };

        Object.defineProperty(proto, "__wkdomainsDarkModeProxy", { value: true, configurable: true });
        if (nativeInsertRule) {
          proto.insertRule = function(rule, index) {
            const result = nativeInsertRule.call(this, rule, index);
            if (stylesheetProxyActive && !isOwnGeneratedCSS(rule)) scheduleStyleSync(0);
            return result;
          };
        }
        if (nativeDeleteRule) {
          proto.deleteRule = function(index) {
            const result = nativeDeleteRule.call(this, index);
            if (stylesheetProxyActive) scheduleStyleSync(0);
            return result;
          };
        }
        if (nativeAddRule) {
          proto.addRule = function(selector, style, index) {
            const result = nativeAddRule.call(this, selector, style, index);
            if (stylesheetProxyActive && !isOwnGeneratedCSS(`${selector || ""}{${style || ""}}`)) scheduleStyleSync(0);
            return result;
          };
        }
        if (nativeRemoveRule) {
          proto.removeRule = function(index) {
            const result = nativeRemoveRule.call(this, index);
            if (stylesheetProxyActive) scheduleStyleSync(0);
            return result;
          };
        }
        if (nativeReplace) {
          proto.replace = function(text) {
            return nativeReplace.call(this, text).then((sheet) => {
              if (stylesheetProxyActive && !isOwnGeneratedCSS(text)) scheduleStyleSync(0);
              return sheet;
            });
          };
        }
        if (nativeReplaceSync) {
          proto.replaceSync = function(text) {
            const result = nativeReplaceSync.call(this, text);
            if (stylesheetProxyActive && !isOwnGeneratedCSS(text)) scheduleStyleSync(0);
            return result;
          };
        }

        if (window.CSSStyleDeclaration && !CSSStyleDeclaration.prototype.__wkdomainsDarkModeProxy) {
          const declarationProto = CSSStyleDeclaration.prototype;
          const nativeSetProperty = declarationProto.setProperty;
          const nativeRemoveProperty = declarationProto.removeProperty;
          Object.defineProperty(declarationProto, "__wkdomainsDarkModeProxy", { value: true, configurable: true });

          declarationProto.setProperty = function(property, value, priority) {
            const result = nativeSetProperty.call(this, property, value, priority);
            if (!stylesheetProxyActive) return result;
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
            if (!stylesheetProxyActive) return result;
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
          Object.defineProperty(rootProto, "__wkdomainsDarkModeAdoptedProxy", { value: true, configurable: true });
          Object.defineProperty(rootProto, "adoptedStyleSheets", {
            configurable: true,
            enumerable: descriptor.enumerable,
            get() {
              return descriptor.get.call(this);
            },
            set(value) {
              descriptor.set.call(this, value);
              if (stylesheetProxyActive) scheduleStyleSync(0);
            }
          });
        };

        patchAdoptedStyleSheets(Document.prototype);
        if (window.ShadowRoot) {
          patchAdoptedStyleSheets(ShadowRoot.prototype);
        }
      };

      const stopStylesheetProxy = () => {
        stylesheetProxyActive = false;
      };
    """#
}
