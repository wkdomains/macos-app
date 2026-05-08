//
//  BrowserDarkModeStylesheetProxyScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetProxyScript = #"""
      const nativeRegisterProperty = window.CSS && CSS.registerProperty;
      const registeredWrappedCustomProperties = new Set();

      const registerWrappedCustomProperties = (definition) => {
        if (!nativeRegisterProperty || !definition || !definition.name || !definition.initialValue) return;
        const name = String(definition.name || "");
        const syntax = String(definition.syntax || "");
        const sourceValue = String(definition.initialValue || "").trim();
        const isColorRegistration = syntax.includes("<color>")
          || (shouldTreatCustomPropertyAsRawColor(name) && (hasCSSColor(sourceValue) || parseRawColorValue(sourceValue)));
        if (!name.startsWith("--") || !isColorRegistration || !sourceValue) return;

        const entries = [
          ["bg", modifyBackgroundColor],
          ["text", modifyForegroundColor],
          ["border", modifyBorderColor]
        ];
        for (const [type, transformer] of entries) {
          const transformed = transformCustomPropertyValue(name, sourceValue, type, transformer, true) || sourceValue;
          for (const wrappedName of wrappedVariableNames(type, name)) {
            if (registeredWrappedCustomProperties.has(wrappedName)) continue;
            try {
              nativeRegisterProperty.call(CSS, {
                name: wrappedName,
                syntax,
                inherits: definition.inherits !== false,
                initialValue: transformed
              });
              registeredWrappedCustomProperties.add(wrappedName);
            } catch (_) {}
          }
        }
      };

      const registerColorCustomPropertyDefinition = (definition) => {
        if (!definition || !definition.name) return;
        const name = String(definition.name || "");
        const syntax = String(definition.syntax || "");
        const sourceValue = String(definition.initialValue || "").trim();
        const isColorRegistration = syntax.includes("<color>")
          || (shouldTreatCustomPropertyAsRawColor(name) && (hasCSSColor(sourceValue) || parseRawColorValue(sourceValue)));
        if (!name.startsWith("--") || !isColorRegistration) return;
        registeredCustomPropertyTypes.set(name, variableTypeNumberForProperty(name, definition.initialValue || ""));
        registerWrappedCustomProperties(definition);
        scheduleStartupAwareStyleSync(0);
      };

      const installStylesheetProxy = () => {
        __wkdomainsDarkModeDebug("proxy-install-start");
        if (siteFixFlag("disableStyleSheetsProxy")) {
          __wkdomainsDarkModeDebug("proxy-install-disabled");
          return;
        }
        if (!window.CSSStyleSheet) {
          __wkdomainsDarkModeDebug("proxy-install-no-cssstylesheet");
          return;
        }
        stylesheetProxyActive = true;
        if (CSSStyleSheet.prototype.__wkdomainsDarkModeProxy) {
          __wkdomainsDarkModeDebug("proxy-install-already");
          return;
        }
        const proto = CSSStyleSheet.prototype;
        const nativeInsertRule = proto.insertRule;
        const nativeDeleteRule = proto.deleteRule;
        const nativeAddRule = proto.addRule;
        const nativeRemoveRule = proto.removeRule;
        const nativeReplace = proto.replace;
        const nativeReplaceSync = proto.replaceSync;
        const adoptedSheetOwners = new WeakMap();
        const adoptedSheetsByRoot = new WeakMap();
        const adoptedDeclarationSheets = new WeakMap();
        const adoptedSheetsSourceProxies = new WeakMap();
        const adoptedSheetsProxySources = new WeakMap();
        const isOwnGeneratedCSS = (text) => {
          const value = String(text || "");
          return value.includes(DARK_VAR_PREFIX)
            || value.includes("--darkreader-bg--")
            || value.includes("--darkreader-text--")
            || value.includes("--darkreader-border--")
            || value.includes("--wkdomains-forced-dark")
            || value.includes(INLINE_CLASS)
            || value.includes(STYLE_SYNC_CLASS)
            || value.includes(ADOPTED_STYLE_CLASS);
        };
        const isOwnGeneratedSheet = (sheet) => {
          const owner = sheet && sheet.ownerNode;
          return owner && owner.classList && owner.classList.contains(INLINE_CLASS);
        };
        const rememberRuleDeclarations = (rules, sheet) => {
          if (!rules || !sheet) return;
          for (let index = 0; index < rules.length; index += 1) {
            const rule = rules[index];
            try {
              if (rule.style) adoptedDeclarationSheets.set(rule.style, sheet);
              if (rule.cssRules) {
                rememberRuleDeclarations(rule.cssRules, sheet);
              }
            } catch (_) {}
          }
        };
        const rememberAdoptedSheetRules = (sheet) => {
          rememberRuleDeclarations(safeGetRules(sheet), sheet);
        };
        const forgetAdoptedSheetOwners = (root) => {
          const previous = adoptedSheetsByRoot.get(root);
          if (!previous) return;
          for (const sheet of previous) {
            const owners = adoptedSheetOwners.get(sheet);
            if (owners) owners.delete(root);
          }
          adoptedSheetsByRoot.delete(root);
        };
        const rememberAdoptedSheetOwners = (root, sheets) => {
          if (!root || !Array.isArray(sheets)) return;
          forgetAdoptedSheetOwners(root);
          adoptedSheetsByRoot.set(root, Array.from(sheets));
          for (const sheet of sheets) {
            if (!adoptedSheetOwners.has(sheet)) adoptedSheetOwners.set(sheet, new Set());
            adoptedSheetOwners.get(sheet).add(root);
            rememberAdoptedSheetRules(sheet);
          }
        };
        const dispatchSheetEvent = (target, eventName) => {
          try {
            target.dispatchEvent(new CustomEvent(eventName));
          } catch (_) {}
        };
        const reportAdoptedSheetChange = (sheet) => {
          markAdoptedSheetChanged(sheet);
          const owners = adoptedSheetOwners.get(sheet);
          let dispatched = false;
          if (owners) {
            for (const root of Array.from(owners)) {
              if (root !== document && root.host && !root.host.isConnected) {
                owners.delete(root);
                continue;
              }
              if (adoptedStyleManagers.has(root)) {
                dispatchSheetEvent(root, ADOPTED_STYLE_CHANGE_EVENT);
                dispatched = true;
              }
            }
          }
          if (!dispatched) {
            scheduleStartupAwareStyleSync(120);
          }
        };
        const reportSheetChange = (sheet) => {
          if (!sheet || isOwnGeneratedSheet(sheet)) return;
          let dispatchedToOwner = false;
          if (sheet.ownerNode && !isOwnGeneratedCSS(sheet.ownerNode.className || "")) {
            dispatchSheetEvent(sheet.ownerNode, STYLE_UPDATE_EVENT);
            dispatchedToOwner = true;
          }
          if (adoptedSheetOwners.has(sheet)) {
            reportAdoptedSheetChange(sheet);
            return;
          }
          if (!dispatchedToOwner) {
            scheduleStartupAwareStyleSync(120);
          }
        };
        const reportSheetChangeAsync = (sheet, promise) => {
          if (promise && promise instanceof Promise) {
            promise.then(() => reportSheetChange(sheet), () => {});
          } else {
            reportSheetChange(sheet);
          }
        };
        const reportAdoptedSheetsChange = (root, sheets) => {
          rememberAdoptedSheetOwners(root, sheets);
          if (adoptedStyleManagers.has(root)) {
            dispatchSheetEvent(root, ADOPTED_STYLES_CHANGE_EVENT);
          } else {
            scheduleStartupAwareStyleSync(120);
          }
        };
        const proxyAdoptedSheetsArray = (root, source) => {
          if (!Array.isArray(source)) return source;
          if (adoptedSheetsProxySources.has(source)) return source;
          if (adoptedSheetsSourceProxies.has(source)) return adoptedSheetsSourceProxies.get(source);
          const proxy = new Proxy(source, {
            deleteProperty(target, property) {
              const result = delete target[property];
              reportAdoptedSheetsChange(root, target);
              return result;
            },
            set(target, property, value) {
              target[property] = value;
              if (property !== "length" || target.length >= 0) {
                reportAdoptedSheetsChange(root, target);
              }
              return true;
            }
          });
          adoptedSheetsSourceProxies.set(source, proxy);
          adoptedSheetsProxySources.set(proxy, source);
          return proxy;
        };

        defineHiddenProperty(proto, "__wkdomainsDarkModeProxy", true);
        __wkdomainsDarkModeDebug("proxy-patch-cssstylesheet");
        if (nativeInsertRule) {
          rememberPropertyDescriptor(proto, "insertRule");
          proto.insertRule = function(rule, index) {
            const result = nativeInsertRule.call(this, rule, index);
            if (stylesheetProxyActive && !isOwnGeneratedCSS(rule)) reportSheetChange(this);
            return result;
          };
        }
        if (nativeDeleteRule) {
          rememberPropertyDescriptor(proto, "deleteRule");
          proto.deleteRule = function(index) {
            const result = nativeDeleteRule.call(this, index);
            if (stylesheetProxyActive) reportSheetChange(this);
            return result;
          };
        }
        if (nativeAddRule) {
          rememberPropertyDescriptor(proto, "addRule");
          proto.addRule = function(selector, style, index) {
            const result = nativeAddRule.call(this, selector, style, index);
            if (stylesheetProxyActive && !isOwnGeneratedCSS(`${selector || ""}{${style || ""}}`)) reportSheetChange(this);
            return result;
          };
        }
        if (nativeRemoveRule) {
          rememberPropertyDescriptor(proto, "removeRule");
          proto.removeRule = function(index) {
            const result = nativeRemoveRule.call(this, index);
            if (stylesheetProxyActive) reportSheetChange(this);
            return result;
          };
        }
        if (nativeReplace) {
          rememberPropertyDescriptor(proto, "replace");
          proto.replace = function(text) {
            const result = nativeReplace.call(this, text);
            if (stylesheetProxyActive && !isOwnGeneratedCSS(text)) reportSheetChangeAsync(this, result);
            return result;
          };
        }
        if (nativeReplaceSync) {
          rememberPropertyDescriptor(proto, "replaceSync");
          proto.replaceSync = function(text) {
            const result = nativeReplaceSync.call(this, text);
            if (stylesheetProxyActive && !isOwnGeneratedCSS(text)) reportSheetChange(this);
            return result;
          };
        }

        if (window.CSSStyleDeclaration && !CSSStyleDeclaration.prototype.__wkdomainsDarkModeProxy) {
          __wkdomainsDarkModeDebug("proxy-patch-declarations");
          const declarationProto = CSSStyleDeclaration.prototype;
          const nativeSetProperty = declarationProto.setProperty;
          const nativeRemoveProperty = declarationProto.removeProperty;
          const cssTextDescriptor = Object.getOwnPropertyDescriptor(declarationProto, "cssText");
          defineHiddenProperty(declarationProto, "__wkdomainsDarkModeProxy", true);

          const reportDeclarationChange = (declaration, property) => {
            const propertyName = property ? String(property) : "";
            if (isGeneratedDarkModeProperty(propertyName)) {
              return;
            }
            const adoptedSheet = adoptedDeclarationSheets.get(declaration);
            if (adoptedSheet) {
              reportAdoptedSheetChange(adoptedSheet);
              return;
            }
            const parentSheet = declaration && declaration.parentRule && declaration.parentRule.parentStyleSheet;
            if (parentSheet) {
              reportSheetChange(parentSheet);
              return;
            }
          };

          rememberPropertyDescriptor(declarationProto, "setProperty");
          declarationProto.setProperty = function(property, value, priority) {
            const result = nativeSetProperty.call(this, property, value, priority);
            if (!stylesheetProxyActive) return result;
            reportDeclarationChange(this, property);
            return result;
          };

          rememberPropertyDescriptor(declarationProto, "removeProperty");
          declarationProto.removeProperty = function(property) {
            const result = nativeRemoveProperty.call(this, property);
            if (!stylesheetProxyActive) return result;
            reportDeclarationChange(this, property);
            return result;
          };

          if (cssTextDescriptor && cssTextDescriptor.set) {
            rememberPropertyDescriptor(declarationProto, "cssText");
            Object.defineProperty(declarationProto, "cssText", {
              configurable: true,
              enumerable: cssTextDescriptor.enumerable,
              get: cssTextDescriptor.get ? function() { return cssTextDescriptor.get.call(this); } : undefined,
              set(value) {
                const result = cssTextDescriptor.set.call(this, value);
                if (stylesheetProxyActive) reportDeclarationChange(this, "cssText");
                return result;
              }
            });
          }
        }

        if (window.CSSStyleRule && !CSSStyleRule.prototype.__wkdomainsDarkModeRuleProxy) {
          const ruleProto = CSSStyleRule.prototype;
          const selectorTextDescriptor = Object.getOwnPropertyDescriptor(ruleProto, "selectorText");
          if (selectorTextDescriptor && selectorTextDescriptor.set) {
            defineHiddenProperty(ruleProto, "__wkdomainsDarkModeRuleProxy", true);
            rememberPropertyDescriptor(ruleProto, "selectorText");
            Object.defineProperty(ruleProto, "selectorText", {
              configurable: true,
              enumerable: selectorTextDescriptor.enumerable,
              get: selectorTextDescriptor.get ? function() { return selectorTextDescriptor.get.call(this); } : undefined,
              set(value) {
                const result = selectorTextDescriptor.set.call(this, value);
                if (stylesheetProxyActive) reportSheetChange(this.parentStyleSheet);
                return result;
              }
            });
          }
        }

        if (window.CSSKeyframesRule && !CSSKeyframesRule.prototype.__wkdomainsDarkModeKeyframesProxy) {
          const keyframesProto = CSSKeyframesRule.prototype;
          const nativeAppendRule = keyframesProto.appendRule;
          const nativeDeleteKeyframeRule = keyframesProto.deleteRule;
          defineHiddenProperty(keyframesProto, "__wkdomainsDarkModeKeyframesProxy", true);
          if (nativeAppendRule) {
            rememberPropertyDescriptor(keyframesProto, "appendRule");
            keyframesProto.appendRule = function(rule) {
              const result = nativeAppendRule.call(this, rule);
              if (stylesheetProxyActive && !isOwnGeneratedCSS(rule)) reportSheetChange(this.parentStyleSheet);
              return result;
            };
          }
          if (nativeDeleteKeyframeRule) {
            rememberPropertyDescriptor(keyframesProto, "deleteRule");
            keyframesProto.deleteRule = function(key) {
              const result = nativeDeleteKeyframeRule.call(this, key);
              if (stylesheetProxyActive) reportSheetChange(this.parentStyleSheet);
              return result;
            };
          }
        }

        if (nativeRegisterProperty && !CSS.__wkdomainsDarkModeRegisterPropertyProxy) {
          try {
            __wkdomainsDarkModeDebug("proxy-patch-register-property");
            defineHiddenProperty(CSS, "__wkdomainsDarkModeRegisterPropertyProxy", true);
            rememberPropertyDescriptor(CSS, "registerProperty");
            CSS.registerProperty = function(definition) {
              const result = nativeRegisterProperty.call(this, definition);
              try {
                registerColorCustomPropertyDefinition(definition);
              } catch (_) {}
              return result;
            };
          } catch (_) {}
        }

        const patchGroupingRulePrototype = (constructorName) => {
          const constructor = window[constructorName];
          if (!constructor || !constructor.prototype || constructor.prototype.__wkdomainsDarkModeGroupingProxy) return;
          const groupingProto = constructor.prototype;
          const nativeGroupInsertRule = groupingProto.insertRule;
          const nativeGroupDeleteRule = groupingProto.deleteRule;
          if (!nativeGroupInsertRule && !nativeGroupDeleteRule) return;
          __wkdomainsDarkModeDebug(`proxy-patch-grouping:${constructorName}`);
          defineHiddenProperty(groupingProto, "__wkdomainsDarkModeGroupingProxy", true);

          if (nativeGroupInsertRule) {
            rememberPropertyDescriptor(groupingProto, "insertRule");
            groupingProto.insertRule = function(rule, index) {
              const result = nativeGroupInsertRule.call(this, rule, index);
              if (stylesheetProxyActive && !isOwnGeneratedCSS(rule)) {
                reportSheetChange(this.parentStyleSheet);
              }
              return result;
            };
          }

          if (nativeGroupDeleteRule) {
            rememberPropertyDescriptor(groupingProto, "deleteRule");
            groupingProto.deleteRule = function(index) {
              const result = nativeGroupDeleteRule.call(this, index);
              if (stylesheetProxyActive) {
                reportSheetChange(this.parentStyleSheet);
              }
              return result;
            };
          }
        };

        const patchGroupingRuleProxy = () => {
          for (const constructorName of [
            "CSSGroupingRule",
            "CSSMediaRule",
            "CSSSupportsRule",
            "CSSLayerBlockRule",
            "CSSContainerRule",
            "CSSScopeRule"
          ]) {
            patchGroupingRulePrototype(constructorName);
          }
        };

        const patchAdoptedStyleSheets = (rootProto) => {
          if (!rootProto || rootProto.__wkdomainsDarkModeAdoptedProxy) return;
          const descriptor = Object.getOwnPropertyDescriptor(rootProto, "adoptedStyleSheets");
          if (!descriptor || !descriptor.set || !descriptor.get) return;
          __wkdomainsDarkModeDebug("proxy-patch-adopted");
          defineHiddenProperty(rootProto, "__wkdomainsDarkModeAdoptedProxy", true);
          rememberPropertyDescriptor(rootProto, "adoptedStyleSheets");
          Object.defineProperty(rootProto, "adoptedStyleSheets", {
            configurable: true,
            enumerable: descriptor.enumerable,
            get() {
              const source = descriptor.get.call(this);
              rememberAdoptedSheetOwners(this, source);
              return proxyAdoptedSheetsArray(this, source);
            },
            set(value) {
              if (adoptedSheetsProxySources.has(value)) {
                value = adoptedSheetsProxySources.get(value);
              }
              descriptor.set.call(this, value);
              if (stylesheetProxyActive) reportAdoptedSheetsChange(this, value);
            }
          });
        };

        patchGroupingRuleProxy();
        patchAdoptedStyleSheets(Document.prototype);
        if (window.ShadowRoot) {
          patchAdoptedStyleSheets(ShadowRoot.prototype);
        }
        __wkdomainsDarkModeDebug("proxy-install-end");
      };

      const stopStylesheetProxy = () => {
        stylesheetProxyActive = false;
      };
    """#
}
