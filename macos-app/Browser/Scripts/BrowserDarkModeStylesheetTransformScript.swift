//
//  BrowserDarkModeStylesheetTransformScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetTransformScript = #"""
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
    """#
}
