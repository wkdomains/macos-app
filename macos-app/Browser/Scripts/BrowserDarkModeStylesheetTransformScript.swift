//
//  BrowserDarkModeStylesheetTransformScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetTransformScript = #"""
      const isStylesheetSVGElement = (element) => (
        typeof window.SVGElement === "function" && element instanceof window.SVGElement
      );

      const transformCustomPropertyValue = (property, value, type, transformer, allowRawColor = false) => {
        if (!value || isGeneratedDarkModeProperty(property)) return null;
        if (String(value).includes("var(")) {
          const rewritten = replaceCSSVariableReferences(value, type);
          const transformedFallbacks = replaceCSSColors(rewritten, transformer);
          return transformedFallbacks === value ? rewritten : transformedFallbacks;
        }

        if (!hasCSSColor(value)) {
          return allowRawColor ? replaceRawColorValue(value, transformer) : null;
        }
        const transformed = replaceCSSColors(value, transformer);
        return transformed === value ? null : transformed;
      };

      const replaceCSSVariableReferences = (value, type) => {
        const text = String(value || "");
        if (!text.includes("var(")) return value;

        const transformer = type === "bg"
          ? modifyBackgroundColor
          : (type === "border" ? modifyBorderColor : modifyForegroundColor);
        let result = "";
        let index = 0;
        let changed = false;

        while (index < text.length) {
          const reference = readCSSVariableReferenceAt(text, index);
          if (!reference) {
            result += text[index];
            index += 1;
            continue;
          }

          const wrapped = wrappedVariableName(type, reference.name);
          if (!reference.fallback) {
            result += `var(${wrapped}, var(${reference.name}))`;
            changed = true;
            index = reference.end;
            continue;
          }

          const fallbackValue = replaceCSSVariableReferences(reference.fallback.trim(), type);
          const colorFallback = replaceCSSColors(fallbackValue, transformer);
          const modifiedFallback = colorFallback === fallbackValue
            ? (replaceRawColorValue(fallbackValue, transformer) || colorFallback)
            : colorFallback;
          result += `var(${wrapped}, ${modifiedFallback})`;
          changed = true;
          index = reference.end;
        }

        return changed ? result : value;
      };

      const transformVariableDependentValue = (property, value) => {
        if (!value || !value.includes("var(")) return null;
        const type = cssVariableTypeForProperty(property);
        const transformed = replaceCSSVariableReferences(value, type);
        return transformed === value ? null : transformed;
      };

      const transformCustomPropertyDeclarations = (property, value) => {
        if (!value || isGeneratedDarkModeProperty(property)) return null;
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

        const pushAliases = (type, value) => {
          for (const alias of wrappedVariableNames(type, property)) {
            declarations.push({ property: alias, value });
          }
        };

        if (bgValue) pushAliases("bg", bgValue);
        if (textValue) pushAliases("text", textValue);
        if (borderValue) pushAliases("border", borderValue);

        return declarations.length > 0 ? declarations : null;
      };

      const transformCSSValue = (property, value, ownerElement = null) => {
        if (!property || !value) return null;
        const prop = property.toLowerCase();
        const text = String(value).trim();
        if (!text || text === "inherit" || text === "initial" || text === "unset") return null;

        if (prop === "color-scheme") {
          return "dark";
        }

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
          const isLargeSVGPaint = ownerElement && isStylesheetSVGElement(ownerElement) && prop === "fill";
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
          if (!hasCSSColor(text)) {
            return null;
          }
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

      const convertCSSPropertyRule = (rule) => {
        const name = String(rule.name || "");
        const syntax = String(rule.syntax || "");
        const sourceValue = String(rule.initialValue || "").trim();
        if (!name.startsWith("--") || !syntax.includes("<color>") || !sourceValue) return "";

        const inferredTypes = variablesStore.typesForVariable(name) || variableTypeNumberForProperty(name, sourceValue);
        const inherited = rule.inherits === false ? "false" : "true";
        const serializedSyntax = JSON.stringify(syntax || "<color>");
        const chunks = [];
        const emit = (bit, type, transformer) => {
          if ((inferredTypes & bit) === 0) return;
          const transformed = transformCustomPropertyValue(name, sourceValue, type, transformer, true);
          if (!transformed) return;
          for (const alias of wrappedVariableNames(type, name)) {
            chunks.push([
              `@property ${alias} {`,
              `  syntax: ${serializedSyntax};`,
              `  inherits: ${inherited};`,
              `  initial-value: ${transformed};`,
              "}"
            ].join("\n"));
          }
        };

        emit(VAR_TYPE_BG | VAR_TYPE_BG_IMG, "bg", modifyBackgroundColor);
        emit(VAR_TYPE_TEXT, "text", modifyForegroundColor);
        emit(VAR_TYPE_BORDER, "border", modifyBorderColor);
        return chunks.join("\n");
      };

      const ignoredMedia = [
        "aural",
        "braille",
        "embossed",
        "handheld",
        "print",
        "projection",
        "speech",
        "tty",
        "tv"
      ];

      const safeCSSRuleList = (rule) => {
        try {
          return rule && rule.cssRules ? rule.cssRules : null;
        } catch (_) {
          return null;
        }
      };

      const safeMediaText = (rule) => {
        try {
          return rule && rule.media ? String(rule.media.mediaText || rule.media || "") : "";
        } catch (_) {
          return "";
        }
      };

      const safeRuleText = (rule) => {
        try {
          return rule && rule.cssText ? String(rule.cssText || "") : "";
        } catch (_) {
          return "";
        }
      };

      const ruleConstructorName = (rule) => {
        try {
          return rule && rule.constructor ? String(rule.constructor.name || "") : "";
        } catch (_) {
          return "";
        }
      };

      const groupRulePrefix = (rule, fallback = "") => {
        const cssText = safeRuleText(rule);
        const brace = cssText.indexOf("{");
        if (brace > 0) {
          return cssText.slice(0, brace).trim();
        }
        return fallback;
      };

      const mediaRuleApplies = (rule) => {
        const mediaText = safeMediaText(rule).toLowerCase();
        if (!mediaText) return true;
        const parts = mediaText.split(",").map((part) => part.trim()).filter(Boolean);
        if (parts.length === 0) return true;
        const hasScreenOrAll = parts.some((part) => part.startsWith("screen") || part.startsWith("all") || part.startsWith("("));
        const hasOnlyIgnored = parts.every((part) => ignoredMedia.some((ignored) => part.startsWith(ignored)));
        return hasScreenOrAll || !hasOnlyIgnored;
      };

      const isStyleRule = (rule) => {
        try {
          return !!(rule && rule.selectorText && rule.style);
        } catch (_) {
          return false;
        }
      };

      const isKeyframeRule = (rule) => {
        try {
          return !!(rule && rule.keyText && rule.style);
        } catch (_) {
          return false;
        }
      };

      const isImportRule = (rule) => {
        try {
          return !!(rule && rule.href && rule.styleSheet);
        } catch (_) {
          return false;
        }
      };

      const isMediaRule = (rule) => {
        try {
          return !!(rule && rule.media && safeCSSRuleList(rule));
        } catch (_) {
          return false;
        }
      };

      const isSupportsRule = (rule) => {
        try {
          if (!rule || !safeCSSRuleList(rule) || rule.media) return false;
          const name = ruleConstructorName(rule);
          if (name === "CSSSupportsRule") return true;
          return groupRulePrefix(rule).toLowerCase().startsWith("@supports");
        } catch (_) {
          return false;
        }
      };

      const isPropertyRule = (rule) => {
        try {
          return !!(rule && rule.name && rule.syntax);
        } catch (_) {
          return false;
        }
      };

      const isLayerRule = (rule) => {
        try {
          if (!rule || !safeCSSRuleList(rule) || rule.syntax) return false;
          const name = ruleConstructorName(rule);
          if (name === "CSSLayerBlockRule") return true;
          return groupRulePrefix(rule).toLowerCase().startsWith("@layer");
        } catch (_) {
          return false;
        }
      };

      const isContainerRule = (rule) => {
        try {
          if (!rule || !safeCSSRuleList(rule)) return false;
          const name = ruleConstructorName(rule);
          if (name === "CSSContainerRule") return true;
          return groupRulePrefix(rule).toLowerCase().startsWith("@container");
        } catch (_) {
          return false;
        }
      };

      const isScopeRule = (rule) => {
        try {
          if (!rule || !safeCSSRuleList(rule)) return false;
          const name = ruleConstructorName(rule);
          if (name === "CSSScopeRule") return true;
          return groupRulePrefix(rule).toLowerCase().startsWith("@scope");
        } catch (_) {
          return false;
        }
      };

      const convertCSSRule = (rule, depth, seenRuleLists) => {
        try {
          if (isPropertyRule(rule)) {
            return convertCSSPropertyRule(rule);
          }

          if (isStyleRule(rule)) {
            if (shouldIgnoreCSSSelector(rule.selectorText)) return "";
            const declarations = buildModifiedDeclarations(rule.style);
            return declarations.length > 0 ? `${rule.selectorText} {\n${declarations.join("\n")}\n}` : "";
          }

          if (isKeyframeRule(rule)) {
            const declarations = buildModifiedDeclarations(rule.style);
            return declarations.length > 0 ? `${rule.keyText} {\n${declarations.join("\n")}\n}` : "";
          }

          if (isImportRule(rule)) {
            return convertCSSRules(rule.styleSheet.cssRules, depth + 1, seenRuleLists);
          }

          if (isMediaRule(rule)) {
            if (!mediaRuleApplies(rule)) return "";
            const childRules = convertCSSRules(rule.cssRules, depth + 1, seenRuleLists);
            if (!childRules) return "";
            const mediaText = safeMediaText(rule);
            const prefix = mediaText ? `@media ${mediaText}` : "";
            return prefix ? `${prefix} {\n${childRules}\n}` : childRules;
          }

          if (isSupportsRule(rule)) {
            const conditionText = String(rule.conditionText || "");
            if (window.CSS && CSS.supports && conditionText && !CSS.supports(conditionText)) return "";
            const childRules = convertCSSRules(rule.cssRules, depth + 1, seenRuleLists);
            if (!childRules) return "";
            const prefix = conditionText ? `@supports ${conditionText}` : groupRulePrefix(rule);
            return prefix ? `${prefix} {\n${childRules}\n}` : childRules;
          }

          if (isLayerRule(rule)) {
            const childRules = convertCSSRules(rule.cssRules, depth + 1, seenRuleLists);
            if (!childRules) return "";
            const name = String(rule.name || "").trim();
            const prefix = name ? `@layer ${name}` : "@layer";
            return prefix ? `${prefix} {\n${childRules}\n}` : "";
          }

          if (isContainerRule(rule) || isScopeRule(rule)) {
            const childRules = convertCSSRules(rule.cssRules, depth + 1, seenRuleLists);
            if (!childRules) return "";
            const prefix = groupRulePrefix(rule);
            return prefix ? `${prefix} {\n${childRules}\n}` : "";
          }

          const genericGroupRules = safeCSSRuleList(rule);
          if (genericGroupRules) {
            const childRules = convertCSSRules(genericGroupRules, depth + 1, seenRuleLists);
            if (!childRules) return "";
            const prefix = groupRulePrefix(rule);
            return prefix ? `${prefix} {\n${childRules}\n}` : childRules;
          }
        } catch (_) {}

        return "";
      };

      const convertCSSRules = (rules, depth = 0, seenRuleLists = new WeakSet()) => {
        if (!rules) return "";
        if (depth > 8) return "";
        if (seenRuleLists.has(rules)) return "";
        seenRuleLists.add(rules);
        const chunks = [];
        const length = Number(rules.length) || 0;
        if (depth === 0) __wkdomainsDarkModeDebug(`convert-rules-start:${length}`);
        for (let index = 0; index < length; index += 1) {
          if (depth === 0 && index % 10 === 0) __wkdomainsDarkModeDebug(`convert-rule:${index}`);
          const converted = convertCSSRule(rules[index], depth, seenRuleLists);
          if (converted) chunks.push(converted);
        }
        if (depth === 0) __wkdomainsDarkModeDebug(`convert-rules-end:${chunks.length}`);
        return chunks.join("\n");
      };

      const convertCSSLeafRule = (rule) => {
        try {
          if (isPropertyRule(rule)) {
            return convertCSSPropertyRule(rule);
          }

          if (isStyleRule(rule)) {
            if (shouldIgnoreCSSSelector(rule.selectorText)) return "";
            const declarations = buildModifiedDeclarations(rule.style);
            return declarations.length > 0 ? `${rule.selectorText} {\n${declarations.join("\n")}\n}` : "";
          }

          if (isKeyframeRule(rule)) {
            const declarations = buildModifiedDeclarations(rule.style);
            return declarations.length > 0 ? `${rule.keyText} {\n${declarations.join("\n")}\n}` : "";
          }
        } catch (_) {}

        return null;
      };

      const cssRuleGroupDetails = (rule) => {
        try {
          if (isImportRule(rule)) {
            return { rules: safeCSSRuleList(rule.styleSheet), prefix: "", suffix: "" };
          }

          if (isMediaRule(rule)) {
            if (!mediaRuleApplies(rule)) return null;
            const mediaText = safeMediaText(rule);
            const prefix = mediaText ? `@media ${mediaText}` : "";
            return {
              rules: safeCSSRuleList(rule),
              prefix: prefix ? `${prefix} {\n` : "",
              suffix: prefix ? "\n}" : ""
            };
          }

          if (isSupportsRule(rule)) {
            const conditionText = String(rule.conditionText || "");
            if (window.CSS && CSS.supports && conditionText && !CSS.supports(conditionText)) return null;
            const prefix = conditionText ? `@supports ${conditionText}` : groupRulePrefix(rule);
            return {
              rules: safeCSSRuleList(rule),
              prefix: prefix ? `${prefix} {\n` : "",
              suffix: prefix ? "\n}" : ""
            };
          }

          if (isLayerRule(rule)) {
            const name = String(rule.name || "").trim();
            const prefix = name ? `@layer ${name}` : "@layer";
            return {
              rules: safeCSSRuleList(rule),
              prefix: prefix ? `${prefix} {\n` : "",
              suffix: prefix ? "\n}" : ""
            };
          }

          if (isContainerRule(rule) || isScopeRule(rule)) {
            const prefix = groupRulePrefix(rule);
            return {
              rules: safeCSSRuleList(rule),
              prefix: prefix ? `${prefix} {\n` : "",
              suffix: prefix ? "\n}" : ""
            };
          }

          const genericGroupRules = safeCSSRuleList(rule);
          if (genericGroupRules) {
            const prefix = groupRulePrefix(rule);
            return {
              rules: genericGroupRules,
              prefix: prefix ? `${prefix} {\n` : "",
              suffix: prefix ? "\n}" : ""
            };
          }
        } catch (_) {}

        return null;
      };

      const CSS_RULE_CONVERSION_ASYNC_THRESHOLD = 180;
      const CSS_ADOPTED_RULE_CONVERSION_ASYNC_THRESHOLD = 80;
      const CSS_RULE_CONVERSION_BUDGET_MS = 7;
      const CSS_RULE_CONVERSION_MAX_PER_SLICE = 24;
      const CSS_STARTUP_RULE_CONVERSION_ASYNC_THRESHOLD = 48;

      const cssRuleListLength = (rules) => Number(rules && rules.length) || 0;

      const effectiveCSSRuleConversionAsyncThreshold = (threshold = CSS_RULE_CONVERSION_ASYNC_THRESHOLD) => {
        if (stylesheetSyncElapsedSinceInstall() < STARTUP_STYLE_SYNC_WINDOW_MS) {
          return Math.min(threshold, CSS_STARTUP_RULE_CONVERSION_ASYNC_THRESHOLD);
        }
        return threshold;
      };

      const shouldConvertCSSRulesAsync = (rules) => {
        return cssRuleListLength(rules) >= effectiveCSSRuleConversionAsyncThreshold();
      };

      const cssRuleListsLength = (ruleLists) => {
        let total = 0;
        for (const rules of ruleLists || []) {
          total += cssRuleListLength(rules);
        }
        return total;
      };

      const shouldConvertCSSRuleListsAsync = (ruleLists, threshold = CSS_RULE_CONVERSION_ASYNC_THRESHOLD) => {
        return cssRuleListsLength(ruleLists) >= effectiveCSSRuleConversionAsyncThreshold(threshold);
      };

      const convertCSSRuleListsAsync = (ruleLists, callback) => {
        const lists = (ruleLists || []).filter(Boolean);
        if (lists.length === 0) {
          callback("");
          return () => {};
        }

        const chunks = [];
        let listIndex = 0;
        let stack = [];
        let seenRuleLists = new WeakSet();
        let cancelled = false;

        const now = () => {
          try { return performance.now(); } catch (_) { return Date.now(); }
        };

        const startNextList = () => {
          stack = [];
          seenRuleLists = new WeakSet();
          while (listIndex < lists.length) {
            const rules = lists[listIndex];
            listIndex += 1;
            if (!rules || seenRuleLists.has(rules)) continue;
            seenRuleLists.add(rules);
            stack.push({
              rules,
              index: 0,
              depth: 0,
              chunks: [],
              prefix: "",
              suffix: ""
            });
            return;
          }
        };

        const finishFrame = () => {
          const frame = stack.pop();
          if (!frame) return;
          const body = frame.chunks.join("\n");
          if (!body) return;
          const css = frame.prefix ? `${frame.prefix}${body}${frame.suffix}` : body;
          if (stack.length > 0) {
            stack[stack.length - 1].chunks.push(css);
          } else {
            chunks.push(css);
          }
        };

        startNextList();

        const step = () => {
          if (cancelled) return;
          const started = now();
          let convertedInSlice = 0;

          while (stack.length > 0) {
            const frame = stack[stack.length - 1];
            const length = cssRuleListLength(frame.rules);

            if (frame.index >= length) {
              finishFrame();
              if (stack.length === 0) {
                startNextList();
              }
              continue;
            }

            const rule = frame.rules[frame.index];
            frame.index += 1;
            convertedInSlice += 1;

            const leaf = convertCSSLeafRule(rule);
            if (leaf !== null) {
              if (leaf) frame.chunks.push(leaf);
            } else if (frame.depth < 8) {
              const group = cssRuleGroupDetails(rule);
              if (group && group.rules && !seenRuleLists.has(group.rules)) {
                seenRuleLists.add(group.rules);
                stack.push({
                  rules: group.rules,
                  index: 0,
                  depth: frame.depth + 1,
                  chunks: [],
                  prefix: group.prefix,
                  suffix: group.suffix
                });
              }
            }

            if (
              convertedInSlice >= CSS_RULE_CONVERSION_MAX_PER_SLICE
              || now() - started >= CSS_RULE_CONVERSION_BUDGET_MS
            ) {
              break;
            }
          }

          if (cancelled) return;
          if (stack.length > 0) {
            window.setTimeout(step, 0);
            return;
          }

          callback(chunks.join("\n"));
        };

        window.setTimeout(step, 0);
        return () => {
          cancelled = true;
        };
      };

      const convertCSSRulesAsync = (rules, callback) => convertCSSRuleListsAsync([rules], callback);

      const hashString = (value) => {
        const text = String(value || "");
        let hash = 2166136261;
        for (let index = 0; index < text.length; index += 1) {
          hash ^= text.charCodeAt(index);
          hash = Math.imul(hash, 16777619);
        }
        return (hash >>> 0).toString(36);
      };

      const cssRuleListSignature = (rules) => {
        const length = cssRuleListLength(rules);
        if (!length) return "0";
        const sampleIndexes = new Set();
        const sampleEdgeCount = Math.min(8, length);
        for (let index = 0; index < sampleEdgeCount; index += 1) {
          sampleIndexes.add(index);
          sampleIndexes.add(length - 1 - index);
        }
        if (length > 16) {
          sampleIndexes.add(Math.floor(length / 2));
        }

        const samples = [];
        for (const index of Array.from(sampleIndexes).sort((a, b) => a - b)) {
          const text = safeRuleText(rules[index]);
          samples.push(`${index}:${hashString(text.slice(0, 512))}:${text.length}`);
        }
        return `${length}:${samples.join("|")}`;
      };

    """#
}
