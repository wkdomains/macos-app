//
//  BrowserDarkModeStylesheetVariablesScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetVariablesScript = #"""
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
    """#
}
