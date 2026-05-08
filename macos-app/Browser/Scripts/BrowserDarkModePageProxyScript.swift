//
//  BrowserDarkModePageProxyScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static func forcedDarkModePageProxyScript(disabledSites: [String]) -> String {
        let disabledSiteList = disabledSites.map(javaScriptStringLiteral).joined(separator: ", ")
        let debugLoggingEnabled = BrowserDebugLogging.darkModeScriptEnabled ? "true" : "false"

        return #"""
    (() => {
      if (window.__wkdomainsDarkModePageProxyInstalled) return;
      window.__wkdomainsDarkModePageProxyInstalled = true;
      const __wkdomainsDarkModeDebugEnabled = \#(debugLoggingEnabled);
      const __wkdomainsDarkModeDebug = (phase) => {
        if (!__wkdomainsDarkModeDebugEnabled) return;
        try {
          console.debug("[wkdomains-dark-proxy]", phase, location.href, Math.round(performance.now()));
        } catch (_) {}
      };

      const DISABLED_SITES = new Set([\#(disabledSiteList)]);
      const currentHost = String(location.hostname || "").toLowerCase().replace(/^\.+|\.+$/g, "");
      const disabledSiteMatches = (site) => {
        const normalizedSite = String(site || "").toLowerCase().replace(/^\.+|\.+$/g, "");
        return currentHost === normalizedSite || currentHost.endsWith(`.${normalizedSite}`);
      };
      if (Array.from(DISABLED_SITES).some(disabledSiteMatches)) {
        __wkdomainsDarkModeDebug("disabled-site");
        return;
      }

      const DARK_VAR_PREFIX = "--wkdomains-darkreader";
      const INLINE_CLASS = "wkdomains-darkreader";
      const STYLE_SYNC_CLASS = "wkdomains-darkreader--sync";
      const ADOPTED_STYLE_CLASS = "wkdomains-darkreader--adopted";
      const PAGE_PROXY_EVENT = "__wkdomains__darkModePageProxyChange";
      const PAGE_PROXY_CONFIG_EVENT = "__wkdomains__darkModePageProxyConfig";
      const PAGE_PROXY_CLEANUP_EVENT = "__wkdomains__darkModePageProxyCleanup";
      const STYLE_UPDATE_EVENT = "__darkreader__updateSheet";
      const ADOPTED_STYLE_CHANGE_EVENT = "__darkreader__adoptedStyleSheetChange";
      const ADOPTED_STYLES_CHANGE_EVENT = "__darkreader__adoptedStyleSheetsChange";
      const ADOPTED_DECLARATION_CHANGE_EVENT = "__darkreader__adoptedStyleDeclarationChange";
      const cleanupTasks = [];
      const prototypeRestoreTasks = [];
      const savedPropertyDescriptors = new WeakMap();
      let active = true;
      let configured = false;
      let lastConfig = {};
      const proxyStatus = {
        installed: true,
        active: true,
        configured: false,
        stylesheetProxy: false,
        shadowRootProxy: false,
        customElementRegistryProxy: false,
        changes: Object.create(null),
        lastChange: "",
        lastChangeAt: 0
      };

      const rememberPropertyDescriptor = (target, property) => {
        if (!target || !property) return;
        let descriptors = savedPropertyDescriptors.get(target);
        if (!descriptors) {
          descriptors = new Map();
          savedPropertyDescriptors.set(target, descriptors);
        }
        if (!descriptors.has(property)) {
          descriptors.set(property, Object.getOwnPropertyDescriptor(target, property) || null);
        }
        prototypeRestoreTasks.push(() => {
          try {
            const saved = descriptors.get(property);
            if (saved) {
              Object.defineProperty(target, property, saved);
            } else {
              delete target[property];
            }
          } catch (_) {}
        });
      };

      const defineHiddenProperty = (target, property, value) => {
        try {
          rememberPropertyDescriptor(target, property);
          Object.defineProperty(target, property, {
            value,
            configurable: true,
            enumerable: false,
            writable: true
          });
        } catch (_) {}
      };

      const restorePrototypePatches = () => {
        const tasks = prototypeRestoreTasks.splice(0).reverse();
        for (const restore of tasks) {
          try { restore(); } catch (_) {}
        }
      };

      const dispatch = (target, name, detail) => {
        if (!target || !active) return;
        try {
          target.dispatchEvent(new CustomEvent(name, { detail }));
        } catch (_) {}
      };

      const reportGlobalChange = (kind, detail = {}) => {
        proxyStatus.lastChange = String(kind || "");
        try { proxyStatus.lastChangeAt = Math.round(performance.now()); } catch (_) {}
        proxyStatus.changes[proxyStatus.lastChange] = (proxyStatus.changes[proxyStatus.lastChange] || 0) + 1;
        dispatch(document, PAGE_PROXY_EVENT, { kind, ...detail });
      };

      const exposeStatus = () => {
        try {
          Object.defineProperty(window, "__wkdomainsDarkModePageProxyStatus", {
            configurable: true,
            enumerable: false,
            value() {
              return {
                installed: proxyStatus.installed,
                active: proxyStatus.active,
                configured: proxyStatus.configured,
                stylesheetProxy: proxyStatus.stylesheetProxy,
                shadowRootProxy: proxyStatus.shadowRootProxy,
                customElementRegistryProxy: proxyStatus.customElementRegistryProxy,
                lastChange: proxyStatus.lastChange,
                lastChangeAt: proxyStatus.lastChangeAt,
                changes: { ...proxyStatus.changes },
                config: { ...lastConfig }
              };
            }
          });
        } catch (_) {}
      };

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

      const safeGetRules = (sheet) => {
        try { return sheet && sheet.cssRules || null; } catch (_) { return null; }
      };

      const installStylesheetProxy = () => {
        if (!window.CSSStyleSheet || CSSStyleSheet.prototype.__wkdomainsDarkModePageProxy) return;
        proxyStatus.stylesheetProxy = true;

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

        const rememberRuleDeclarations = (rules, sheet) => {
          if (!rules || !sheet) return;
          for (let index = 0; index < rules.length; index += 1) {
            const rule = rules[index];
            try {
              if (rule.style) adoptedDeclarationSheets.set(rule.style, sheet);
              if (rule.cssRules) rememberRuleDeclarations(rule.cssRules, sheet);
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

        const reportAdoptedSheetChange = (sheet) => {
          const owners = adoptedSheetOwners.get(sheet);
          if (owners) {
            for (const root of Array.from(owners)) {
              if (root !== document && root.host && !root.host.isConnected) {
                owners.delete(root);
                continue;
              }
              dispatch(root, ADOPTED_STYLE_CHANGE_EVENT);
            }
          }
          reportGlobalChange("adopted-sheet");
        };

        const reportSheetChange = (sheet) => {
          if (!sheet || isOwnGeneratedSheet(sheet)) return;
          if (sheet.ownerNode && !isOwnGeneratedCSS(sheet.ownerNode.className || "")) {
            dispatch(sheet.ownerNode, STYLE_UPDATE_EVENT);
          }
          if (adoptedSheetOwners.has(sheet) || !sheet.ownerNode) {
            reportAdoptedSheetChange(sheet);
            return;
          }
          reportGlobalChange("sheet");
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
          dispatch(root, ADOPTED_STYLES_CHANGE_EVENT);
          reportGlobalChange("adopted-sheets");
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

        defineHiddenProperty(proto, "__wkdomainsDarkModePageProxy", true);

        if (nativeInsertRule) {
          rememberPropertyDescriptor(proto, "insertRule");
          proto.insertRule = function(rule, index) {
            const result = nativeInsertRule.call(this, rule, index);
            if (active && !isOwnGeneratedCSS(rule)) reportSheetChange(this);
            return result;
          };
        }
        if (nativeDeleteRule) {
          rememberPropertyDescriptor(proto, "deleteRule");
          proto.deleteRule = function(index) {
            const result = nativeDeleteRule.call(this, index);
            if (active) reportSheetChange(this);
            return result;
          };
        }
        if (nativeAddRule) {
          rememberPropertyDescriptor(proto, "addRule");
          proto.addRule = function(selector, style, index) {
            const result = nativeAddRule.call(this, selector, style, index);
            if (active && !isOwnGeneratedCSS(`${selector || ""}{${style || ""}}`)) reportSheetChange(this);
            return result;
          };
        }
        if (nativeRemoveRule) {
          rememberPropertyDescriptor(proto, "removeRule");
          proto.removeRule = function(index) {
            const result = nativeRemoveRule.call(this, index);
            if (active) reportSheetChange(this);
            return result;
          };
        }
        if (nativeReplace) {
          rememberPropertyDescriptor(proto, "replace");
          proto.replace = function(text) {
            const result = nativeReplace.call(this, text);
            if (active && !isOwnGeneratedCSS(text)) reportSheetChangeAsync(this, result);
            return result;
          };
        }
        if (nativeReplaceSync) {
          rememberPropertyDescriptor(proto, "replaceSync");
          proto.replaceSync = function(text) {
            const result = nativeReplaceSync.call(this, text);
            if (active && !isOwnGeneratedCSS(text)) reportSheetChange(this);
            return result;
          };
        }

        if (window.CSSStyleDeclaration && !CSSStyleDeclaration.prototype.__wkdomainsDarkModePageProxy) {
          const declarationProto = CSSStyleDeclaration.prototype;
          const nativeSetProperty = declarationProto.setProperty;
          const nativeRemoveProperty = declarationProto.removeProperty;
          defineHiddenProperty(declarationProto, "__wkdomainsDarkModePageProxy", true);

          const reportDeclarationChange = (declaration, property) => {
            const propertyName = String(property || "");
            if (propertyName.startsWith(DARK_VAR_PREFIX) || propertyName.startsWith("--darkreader-") || propertyName.startsWith("--wkdomains-forced-dark")) {
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
            if (propertyName.startsWith("--")) {
              reportGlobalChange("declaration");
            }
          };

          rememberPropertyDescriptor(declarationProto, "setProperty");
          declarationProto.setProperty = function(property, value, priority) {
            const result = nativeSetProperty.call(this, property, value, priority);
            if (active) reportDeclarationChange(this, property);
            return result;
          };

          rememberPropertyDescriptor(declarationProto, "removeProperty");
          declarationProto.removeProperty = function(property) {
            const result = nativeRemoveProperty.call(this, property);
            if (active) reportDeclarationChange(this, property);
            return result;
          };
        }

        if (nativeRegisterProperty && !CSS.__wkdomainsDarkModePageProxyRegisterProperty) {
          try {
            defineHiddenProperty(CSS, "__wkdomainsDarkModePageProxyRegisterProperty", true);
            rememberPropertyDescriptor(CSS, "registerProperty");
            CSS.registerProperty = function(definition) {
              const result = nativeRegisterProperty.call(this, definition);
              try {
                if (definition && definition.name && String(definition.syntax || "").includes("<color>")) {
                  reportGlobalChange("register-property", {
                    definition: {
                      name: String(definition.name || ""),
                      syntax: String(definition.syntax || ""),
                      inherits: definition.inherits !== false,
                      initialValue: String(definition.initialValue || "")
                    }
                  });
                }
              } catch (_) {}
              return result;
            };
          } catch (_) {}
        }

        const patchGroupingRuleProxy = () => {
          if (!window.CSSGroupingRule || CSSGroupingRule.prototype.__wkdomainsDarkModePageProxy) return;
          const groupingProto = CSSGroupingRule.prototype;
          const nativeGroupInsertRule = groupingProto.insertRule;
          const nativeGroupDeleteRule = groupingProto.deleteRule;
          if (!nativeGroupInsertRule && !nativeGroupDeleteRule) return;
          defineHiddenProperty(groupingProto, "__wkdomainsDarkModePageProxy", true);

          if (nativeGroupInsertRule) {
            rememberPropertyDescriptor(groupingProto, "insertRule");
            groupingProto.insertRule = function(rule, index) {
              const result = nativeGroupInsertRule.call(this, rule, index);
              if (active && !isOwnGeneratedCSS(rule)) reportSheetChange(this.parentStyleSheet);
              return result;
            };
          }

          if (nativeGroupDeleteRule) {
            rememberPropertyDescriptor(groupingProto, "deleteRule");
            groupingProto.deleteRule = function(index) {
              const result = nativeGroupDeleteRule.call(this, index);
              if (active) reportSheetChange(this.parentStyleSheet);
              return result;
            };
          }
        };

        const patchAdoptedStyleSheets = (rootProto) => {
          if (!rootProto || rootProto.__wkdomainsDarkModePageProxyAdopted) return;
          const descriptor = Object.getOwnPropertyDescriptor(rootProto, "adoptedStyleSheets");
          if (!descriptor || !descriptor.set || !descriptor.get) return;
          defineHiddenProperty(rootProto, "__wkdomainsDarkModePageProxyAdopted", true);
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
              if (active) reportAdoptedSheetsChange(this, value);
            }
          });
        };

        patchGroupingRuleProxy();
        patchAdoptedStyleSheets(Document.prototype);
        if (window.ShadowRoot) {
          patchAdoptedStyleSheets(ShadowRoot.prototype);
        }
      };

      const installShadowRootProxy = () => {
        if (!Element.prototype.attachShadow || Element.prototype.__wkdomainsDarkModePageProxyShadow) return;
        proxyStatus.shadowRootProxy = true;
        const nativeAttachShadow = Element.prototype.attachShadow;
        defineHiddenProperty(Element.prototype, "__wkdomainsDarkModePageProxyShadow", true);
        rememberPropertyDescriptor(Element.prototype, "attachShadow");
        Element.prototype.attachShadow = function(init) {
          const root = nativeAttachShadow.call(this, init);
          if (active) {
            window.setTimeout(() => reportGlobalChange("shadow-root"), 0);
          }
          return root;
        };
      };

      const installCustomElementRegistryProxy = () => {
        if (!window.customElements || customElements.__wkdomainsDarkModePageProxyRegistry) return;
        const nativeDefine = customElements.define;
        if (!nativeDefine) return;
        proxyStatus.customElementRegistryProxy = true;
        try {
          defineHiddenProperty(customElements, "__wkdomainsDarkModePageProxyRegistry", true);
          rememberPropertyDescriptor(customElements, "define");
          customElements.define = function(name, constructor, options) {
            const result = nativeDefine.call(this, name, constructor, options);
            if (active) {
              window.setTimeout(() => reportGlobalChange("custom-element"), 0);
            }
            return result;
          };
        } catch (_) {}
      };

      const applyConfig = (event) => {
        if (!active || configured) return;
        configured = true;

        let config = {};
        try {
          config = event && event.detail || {};
        } catch (_) {}
        lastConfig = {
          disableStyleSheetsProxy: config.disableStyleSheetsProxy === true,
          disableShadowRootProxy: config.disableShadowRootProxy === true,
          disableCustomElementRegistryProxy: config.disableCustomElementRegistryProxy === true,
          enableCustomElementRegistryProxy: config.enableCustomElementRegistryProxy === true
        };

        if (!config.disableStyleSheetsProxy) {
          installStylesheetProxy();
        }
        if (!config.disableShadowRootProxy) {
          installShadowRootProxy();
        }
        if (config.enableCustomElementRegistryProxy && !config.disableCustomElementRegistryProxy) {
          installCustomElementRegistryProxy();
        }

        proxyStatus.configured = true;
        reportGlobalChange("configured");
        __wkdomainsDarkModeDebug("configured");
      };

      const cleanup = () => {
        if (!active) return;
        active = false;
        proxyStatus.active = false;
        restorePrototypePatches();
        const tasks = cleanupTasks.splice(0);
        for (const task of tasks) {
          try { task(); } catch (_) {}
        }
        try { delete window.__wkdomainsDarkModePageProxyInstalled; } catch (_) {
          window.__wkdomainsDarkModePageProxyInstalled = false;
        }
      };

      document.addEventListener(PAGE_PROXY_CONFIG_EVENT, applyConfig);
      document.addEventListener(PAGE_PROXY_CLEANUP_EVENT, cleanup);
      document.addEventListener("__darkreader__cleanUp", cleanup);
      cleanupTasks.push(() => document.removeEventListener(PAGE_PROXY_CONFIG_EVENT, applyConfig));
      cleanupTasks.push(() => document.removeEventListener(PAGE_PROXY_CLEANUP_EVENT, cleanup));
      cleanupTasks.push(() => document.removeEventListener("__darkreader__cleanUp", cleanup));

      exposeStatus();
      __wkdomainsDarkModeDebug("waiting-config");
    })();
    """#
    }
}
