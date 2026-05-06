//
//  BrowserDarkModeStylesheetProxyScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetProxyScript = #"""
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
