//
//  BrowserDarkModeStylesheetTransformScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetTransformScript = #"""
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
          return !!(rule && typeof rule.conditionText === "string" && safeCSSRuleList(rule) && !rule.media);
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
          return !!(rule && rule.name && safeCSSRuleList(rule) && !rule.syntax);
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
            const prefix = conditionText ? `@supports ${conditionText}` : "";
            return prefix ? `${prefix} {\n${childRules}\n}` : childRules;
          }

          if (isLayerRule(rule)) {
            const childRules = convertCSSRules(rule.cssRules, depth + 1, seenRuleLists);
            if (!childRules) return "";
            const name = String(rule.name || "").trim();
            const prefix = name ? `@layer ${name}` : "@layer";
            return prefix ? `${prefix} {\n${childRules}\n}` : "";
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

      const CSS_RULE_CONVERSION_ASYNC_THRESHOLD = 180;
      const CSS_RULE_CONVERSION_BUDGET_MS = 7;
      const CSS_RULE_CONVERSION_MAX_PER_SLICE = 24;

      const shouldConvertCSSRulesAsync = (rules) => {
        const length = Number(rules && rules.length) || 0;
        return length >= CSS_RULE_CONVERSION_ASYNC_THRESHOLD;
      };

      const convertCSSRulesAsync = (rules, callback) => {
        if (!rules) {
          callback("");
          return () => {};
        }

        const seenRuleLists = new WeakSet();
        if (seenRuleLists.has(rules)) {
          callback("");
          return () => {};
        }
        seenRuleLists.add(rules);

        const chunks = [];
        const length = Number(rules.length) || 0;
        let index = 0;
        let cancelled = false;

        const now = () => {
          try { return performance.now(); } catch (_) { return Date.now(); }
        };

        const step = () => {
          if (cancelled) return;
          const started = now();
          let convertedInSlice = 0;

          while (index < length) {
            const converted = convertCSSRule(rules[index], 0, seenRuleLists);
            if (converted) chunks.push(converted);
            index += 1;
            convertedInSlice += 1;

            if (
              convertedInSlice >= CSS_RULE_CONVERSION_MAX_PER_SLICE
              || now() - started >= CSS_RULE_CONVERSION_BUDGET_MS
            ) {
              break;
            }
          }

          if (cancelled) return;
          if (index < length) {
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
    """#
}
