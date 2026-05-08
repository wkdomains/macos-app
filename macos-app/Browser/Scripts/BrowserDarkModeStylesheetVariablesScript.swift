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
        const rootVarValues = new Map();
        const varRefs = new Map();
        const reverseVarRefs = new Map();
        const rulesQueue = new Set();
        const inlineQueue = [];
        let versionNumber = 0;
        let lastTypeSignature = "";
        let lastMatchedRuleLists = 0;
        let lastMatchedInlineStyles = 0;
        let lastVariableReferenceCount = 0;

        const clear = () => {
          varTypes.clear();
          varValues.clear();
          rootVarValues.clear();
          varRefs.clear();
          reverseVarRefs.clear();
          stylesheetCustomPropertyTypes.clear();
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
          if (!reverseVarRefs.has(ref)) reverseVarRefs.set(ref, new Set());
          reverseVarRefs.get(ref).add(owner);
        };

        const inspectVariable = (property, value, options = {}) => {
          if (!property || !property.startsWith("--")) return;
          const text = String(value || "").trim();
          varValues.set(property, text);
          if (options.rootScope) {
            rootVarValues.set(property, text);
          }
          const registeredType = customPropertyTypeFor(property);
          if (registeredType) {
            resolveType(property, registeredType);
          }

          if (text.includes("var(")) {
            forEachVarReference(text, (ref) => addVarRef(property, ref));
          }

          const hasColor = hasCSSColor(text);
          const hasColorLikeName = shouldTreatCustomPropertyAsRawColor(property);
          const hasNamedRawColor = parseRawColorValue(text) && hasColorLikeName;
          if (hasColor || /^\s*(rgb|hsl)a?\(/i.test(text) || hasNamedRawColor || (text.includes("var(") && hasColorLikeName)) {
            if (shouldTreatCustomPropertyAsBorder(property)) {
              resolveType(property, VAR_TYPE_BORDER);
            } else if (shouldTreatCustomPropertyAsText(property)) {
              resolveType(property, VAR_TYPE_TEXT);
            } else if (shouldTreatCustomPropertyAsBackground(property)) {
              resolveType(property, VAR_TYPE_BG);
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

        const inspectDeclarations = (style, options = {}) => {
          if (!style) return;
          iterateCSSDeclarations(style, (property, value) => {
            if (property.startsWith("--")) {
              inspectVariable(property, value, options);
            }
            inspectVarDependent(property, value);
          });
        };

        const selectorHasRootScope = (selectorText) => {
          const text = String(selectorText || "").toLowerCase();
          if (!text) return false;
          return text.split(",").some((selector) => {
            const trimmed = selector.trim();
            return trimmed === ":root"
              || trimmed === "html"
              || trimmed.startsWith(":root:")
              || trimmed.startsWith(":root[")
              || trimmed.startsWith(":root.")
              || trimmed.startsWith("html:")
              || trimmed.startsWith("html[")
              || trimmed.startsWith("html.");
          });
        };

        const inspectRules = (rules) => {
          if (!rules) return;
          for (let index = 0; index < rules.length; index += 1) {
            const rule = rules[index];
            try {
              if (rule.name && rule.syntax) {
                const syntax = String(rule.syntax || "");
                const initialValue = String(rule.initialValue || "");
                const isColorRegistration = syntax.includes("<color>")
                  || (shouldTreatCustomPropertyAsRawColor(rule.name) && (hasCSSColor(initialValue) || parseRawColorValue(initialValue)));
                if (isColorRegistration) {
                  stylesheetCustomPropertyTypes.set(rule.name, variableTypeNumberForProperty(rule.name, initialValue));
                }
                if (rule.initialValue) {
                  inspectVariable(rule.name, rule.initialValue);
                }
              }
              if (rule.style) {
                inspectDeclarations(rule.style, { rootScope: selectorHasRootScope(rule.selectorText) });
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
          const queue = [];
          const queued = new Set();
          const enqueue = (name) => {
            if (!name || queued.has(name)) return;
            queued.add(name);
            queue.push(name);
          };
          const assignType = (name, type) => {
            if (!name || !type) return;
            const before = varTypes.get(name) || 0;
            const next = before | type;
            if (next === before) return;
            varTypes.set(name, next);
            enqueue(name);
          };
          for (const [name, type] of varTypes) {
            if (type) enqueue(name);
          }
          let queueIndex = 0;
          while (queueIndex < queue.length) {
            const name = queue[queueIndex];
            queueIndex += 1;
            queued.delete(name);
            const type = varTypes.get(name) || 0;
            if (!type) continue;

            const refs = varRefs.get(name);
            if (refs) {
              for (const ref of refs) {
                assignType(ref, type);
              }
            }

            const owners = reverseVarRefs.get(name);
            if (owners) {
              for (const owner of owners) {
                const ownerValue = String(varValues.get(owner) || "");
                if (!shouldTreatCustomPropertyAsRawColor(owner) && (!ownerValue.includes("var(") || ownerValue.includes("url("))) continue;
                assignType(owner, type);
              }
            }
          }
        };

        const hashVariableName = (name) => {
          let hash = 2166136261;
          for (let index = 0; index < name.length; index += 1) {
            hash ^= name.charCodeAt(index);
            hash = Math.imul(hash, 16777619);
          }
          return hash >>> 0;
        };

        const updateVersion = () => {
          lastVariableReferenceCount = 0;
          for (const refs of varRefs.values()) {
            lastVariableReferenceCount += refs.size;
          }
          let signatureSum = 0;
          let signatureXor = 0;
          for (const [name, type] of varTypes) {
            const entryHash = (hashVariableName(name) ^ Math.imul(type, 2654435761)) >>> 0;
            signatureSum = (signatureSum + entryHash) >>> 0;
            signatureXor = (signatureXor ^ entryHash) >>> 0;
          }
          const nextSignature = `${varTypes.size}:${lastVariableReferenceCount}:${signatureSum}:${signatureXor}`;
          if (nextSignature !== lastTypeSignature) {
            lastTypeSignature = nextSignature;
            versionNumber += 1;
          }
        };

        const matchVariablesAndDependents = () => {
          lastMatchedRuleLists = rulesQueue.size;
          lastMatchedInlineStyles = inlineQueue.length;
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
          const pushDeclaration = (property, value) => {
            if (!property.startsWith("--")) return;
            const type = typesForVariable(property);
            if (!type) return;
            if (type & (VAR_TYPE_BG | VAR_TYPE_BG_IMG)) {
              const transformed = transformCustomPropertyValue(property, value, "bg", modifyBackgroundColor, true);
              if (transformed) {
                for (const alias of wrappedVariableNames("bg", property)) {
                  declarations.push([alias, transformed]);
                }
              }
            }
            if (type & VAR_TYPE_TEXT) {
              const transformed = transformCustomPropertyValue(property, value, "text", modifyForegroundColor, true);
              if (transformed) {
                for (const alias of wrappedVariableNames("text", property)) {
                  declarations.push([alias, transformed]);
                }
              }
            }
            if (type & VAR_TYPE_BORDER) {
              const transformed = transformCustomPropertyValue(property, value, "border", modifyBorderColor, true);
              if (transformed) {
                for (const alias of wrappedVariableNames("border", property)) {
                  declarations.push([alias, transformed]);
                }
              }
            }
          };

          for (const [property, value] of rootVarValues) {
            pushDeclaration(property, value);
          }

          const rootStyle = document.documentElement && document.documentElement.style;
          if (rootStyle) {
            iterateCSSDeclarations(rootStyle, pushDeclaration);
          }

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
          rootDeclarations,
          status: () => ({
            version: versionNumber,
            variables: varTypes.size,
            values: varValues.size,
            rootValues: rootVarValues.size,
            referenceOwners: varRefs.size,
            references: lastVariableReferenceCount,
            reverseReferenceOwners: reverseVarRefs.size,
            matchedRuleLists: lastMatchedRuleLists,
            matchedInlineStyles: lastMatchedInlineStyles
          })
        };
      })();
    """#
}
