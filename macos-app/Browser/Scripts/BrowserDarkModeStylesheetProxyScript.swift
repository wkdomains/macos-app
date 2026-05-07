//
//  BrowserDarkModeStylesheetProxyScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetProxyScript = #"""
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
        const nativeRegisterProperty = window.CSS && CSS.registerProperty;
        const adoptedSheetOwners = new WeakMap();
        const adoptedSheetsByRoot = new WeakMap();
        const adoptedDeclarationSheets = new WeakMap();
        const adoptedSheetsSourceProxies = new WeakMap();
        const adoptedSheetsProxySources = new WeakMap();
        const registeredWrappedCustomProperties = new Set();
        const isOwnGeneratedCSS = (text) => {
          const value = String(text || "");
          return value.includes(DARK_VAR_PREFIX)
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
          const owners = adoptedSheetOwners.get(sheet);
          if (owners) {
            for (const root of Array.from(owners)) {
              if (root !== document && root.host && !root.host.isConnected) {
                owners.delete(root);
                continue;
              }
              dispatchSheetEvent(root, ADOPTED_STYLE_CHANGE_EVENT);
            }
          }
          scheduleStyleSync(0);
        };
        const reportSheetChange = (sheet) => {
          if (!sheet || isOwnGeneratedSheet(sheet)) return;
          if (sheet.ownerNode && !isOwnGeneratedCSS(sheet.ownerNode.className || "")) {
            dispatchSheetEvent(sheet.ownerNode, STYLE_UPDATE_EVENT);
          }
          if (adoptedSheetOwners.has(sheet)) {
            reportAdoptedSheetChange(sheet);
            return;
          }
          scheduleStyleSync(0);
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
          dispatchSheetEvent(root, ADOPTED_STYLES_CHANGE_EVENT);
          scheduleStyleSync(0);
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
          defineHiddenProperty(declarationProto, "__wkdomainsDarkModeProxy", true);

          rememberPropertyDescriptor(declarationProto, "setProperty");
          declarationProto.setProperty = function(property, value, priority) {
            const result = nativeSetProperty.call(this, property, value, priority);
            if (!stylesheetProxyActive) return result;
            const propertyName = property ? String(property) : "";
            if (propertyName.startsWith(DARK_VAR_PREFIX) || propertyName.startsWith("--wkdomains-forced-dark")) {
              return result;
            }
            const adoptedSheet = adoptedDeclarationSheets.get(this);
            if (adoptedSheet) {
              reportAdoptedSheetChange(adoptedSheet);
              return result;
            }
            if (this.parentRule || propertyName.startsWith("--")) {
              scheduleStyleSync(0);
            }
            return result;
          };

          rememberPropertyDescriptor(declarationProto, "removeProperty");
          declarationProto.removeProperty = function(property) {
            const result = nativeRemoveProperty.call(this, property);
            if (!stylesheetProxyActive) return result;
            const propertyName = property ? String(property) : "";
            if (propertyName.startsWith(DARK_VAR_PREFIX) || propertyName.startsWith("--wkdomains-forced-dark")) {
              return result;
            }
            const adoptedSheet = adoptedDeclarationSheets.get(this);
            if (adoptedSheet) {
              reportAdoptedSheetChange(adoptedSheet);
              return result;
            }
            if (this.parentRule || propertyName.startsWith("--")) {
              scheduleStyleSync(0);
            }
            return result;
          };
        }

        const registerWrappedCustomProperties = (definition) => {
          if (!nativeRegisterProperty || !definition || !definition.name || !definition.initialValue) return;
          const name = String(definition.name || "");
          const syntax = String(definition.syntax || "");
          const sourceValue = String(definition.initialValue || "").trim();
          if (!name.startsWith("--") || !syntax.includes("<color>") || !sourceValue) return;

          const entries = [
            ["bg", modifyBackgroundColor],
            ["text", modifyForegroundColor],
            ["border", modifyBorderColor]
          ];
          for (const [type, transformer] of entries) {
            const wrappedName = wrappedVariableName(type, name);
            if (registeredWrappedCustomProperties.has(wrappedName)) continue;
            const transformed = transformCustomPropertyValue(name, sourceValue, type, transformer, true) || sourceValue;
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
        };

        if (nativeRegisterProperty && !CSS.__wkdomainsDarkModeRegisterPropertyProxy) {
          try {
            __wkdomainsDarkModeDebug("proxy-patch-register-property");
            defineHiddenProperty(CSS, "__wkdomainsDarkModeRegisterPropertyProxy", true);
            rememberPropertyDescriptor(CSS, "registerProperty");
            CSS.registerProperty = function(definition) {
              const result = nativeRegisterProperty.call(this, definition);
              try {
                if (definition && definition.name && String(definition.syntax || "").includes("<color>")) {
                  registeredCustomPropertyTypes.set(definition.name, variableTypeNumberForProperty(definition.name, definition.initialValue || ""));
                  registerWrappedCustomProperties(definition);
                  scheduleStyleSync(0);
                }
              } catch (_) {}
              return result;
            };
          } catch (_) {}
        }

        const patchGroupingRuleProxy = () => {
          if (!window.CSSGroupingRule || CSSGroupingRule.prototype.__wkdomainsDarkModeProxy) return;
          __wkdomainsDarkModeDebug("proxy-patch-grouping");
          const groupingProto = CSSGroupingRule.prototype;
          const nativeGroupInsertRule = groupingProto.insertRule;
          const nativeGroupDeleteRule = groupingProto.deleteRule;
          if (!nativeGroupInsertRule && !nativeGroupDeleteRule) return;
          defineHiddenProperty(groupingProto, "__wkdomainsDarkModeProxy", true);

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
