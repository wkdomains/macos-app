//
//  BrowserDarkModeRuntimeDynamicScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeRuntimeDynamicScript = #"""
      const installShadowRootProxy = () => {
        if (siteFixFlag("disableShadowRootProxy")) return;
        shadowProxyActive = true;
        if (!Element.prototype.attachShadow || Element.prototype.__wkdomainsDarkModeShadowProxy) return;
        const nativeAttachShadow = Element.prototype.attachShadow;
        defineHiddenProperty(Element.prototype, "__wkdomainsDarkModeShadowProxy", true);
        rememberPropertyDescriptor(Element.prototype, "attachShadow");
        Element.prototype.attachShadow = function(init) {
          const root = nativeAttachShadow.call(this, init);
          if (shadowProxyActive) {
            window.setTimeout(() => discoverShadowRoot(root), 0);
          }
          return root;
        };
      };

      const installCustomElementRegistryProxy = () => {
        if (siteFixFlag("disableCustomElementRegistryProxy") || !siteFixFlag("enableCustomElementRegistryProxy")) return;
        if (!window.customElements || customElements.__wkdomainsDarkModeRegistryProxy) {
          customElementRegistryProxyActive = true;
          return;
        }
        const nativeDefine = customElements.define;
        try {
          defineHiddenProperty(customElements, "__wkdomainsDarkModeRegistryProxy", true);
          rememberPropertyDescriptor(customElements, "define");
          customElements.define = function(name, constructor, options) {
            const result = nativeDefine.call(this, name, constructor, options);
            if (customElementRegistryProxyActive) {
              window.setTimeout(() => discoverExistingShadowRoots(document), 0);
            }
            return result;
          };
          customElementRegistryProxyActive = true;
        } catch (_) {}
      };

      const run = () => {
        __wkdomainsDarkModeDebug("run-start");
        scheduled = false;
        if (!document.documentElement || !document.body) return;

        forced = true;

        applying = true;
        __wkdomainsDarkModeDebug("run-base-style");
        ensureBaseStyle();
        if (discoveredShadowRoots.size === 0) {
          scheduleShadowRootDiscovery(document, 0);
        }
        __wkdomainsDarkModeDebug("run-sync-styles");
        flushStyleSyncNow();
        ensureSiteFixStyle();
        tryInvertPDF();

        const roots = normalizeDirtyRoots();
        dirtyRoots.clear();
        __wkdomainsDarkModeDebug(`run-queue-roots:${roots.length}`);
        for (const root of roots) {
          queueRootApply(root, 0);
        }
        flushQueuedRootApplies();
        ensureSiteFixStyle();
        tryInvertPDF();

        finalizeReadyWhenUseful();
        __wkdomainsDarkModeDebug("run-end");
        window.setTimeout(() => {
          applying = false;
        }, 0);
      };

      const schedule = (delay = 80) => {
        if (forced === false) return;
        if (scheduled) return;
        scheduled = true;
        scheduledTimer = window.setTimeout(() => {
          scheduledTimer = null;
          run();
        }, delay);
      };

      const handleDOMReady = () => {
        __wkdomainsDarkModeDebug("dom-ready");
        watchRoot(document);
        dirtyRoots.add(document);
        scheduleStyleSync(0);
        schedule(0);
      };

      const handleWindowLoad = () => {
        __wkdomainsDarkModeDebug("window-load");
        dirtyRoots.add(document);
        scheduleStyleSync(0);
        schedule(40);
      };

      const handlePageShow = () => {
        __wkdomainsDarkModeDebug("page-show");
        dirtyRoots.add(document);
        scheduleStyleSync(0);
        schedule(40);
      };

      const handleVisibilityChange = () => {
        if (!documentIsVisible() || !hiddenMutationDeferred) return;
        hiddenMutationDeferred = false;
        scheduleShadowRootDiscovery(document, 80);
        scheduleStyleSync(80);
        schedule(80);
      };

      const installPageProxyBridge = () => {
        if (pageProxyBridgeInstalled) return;
        pageProxyBridgeInstalled = true;
        bridgeStatus.installed = true;

        const onPageProxyChange = (event) => {
          let kind = "";
          let definition = null;
          let definitions = [];
          let kinds = null;
          try {
            kind = String(event && event.detail && event.detail.kind || "");
            definition = event && event.detail && event.detail.definition || null;
            definitions = Array.isArray(event && event.detail && event.detail.definitions)
              ? event.detail.definitions
              : [];
            kinds = event && event.detail && event.detail.kinds || null;
          } catch (_) {}
          bridgeStatus.lastEvent = kind;
          try { bridgeStatus.lastEventAt = Math.round(performance.now()); } catch (_) {}
          bridgeStatus.events[kind] = (bridgeStatus.events[kind] || 0) + 1;

          if (kind === "batch" && kinds) {
            for (const [batchKind, count] of Object.entries(kinds)) {
              const normalizedCount = Number(count) || 0;
              bridgeStatus.events[batchKind] = (bridgeStatus.events[batchKind] || 0) + normalizedCount;
            }
          }

          if (kind === "register-property" && definition) {
            try { registerColorCustomPropertyDefinition(definition); } catch (_) {}
          }
          for (const registeredDefinition of definitions) {
            try { registerColorCustomPropertyDefinition(registeredDefinition); } catch (_) {}
          }

          const hasShadowChange = kind === "shadow-root"
            || kind === "custom-element"
            || !!(kinds && (kinds["shadow-root"] || kinds["custom-element"]));
          if (hasShadowChange) {
            scheduleShadowRootDiscovery(document, 60);
            schedule(40);
          }

          scheduleStyleSync(elapsedSinceInstall() < 2500 ? 80 : 0);
        };

        document.addEventListener(PAGE_PROXY_EVENT, onPageProxyChange);
        cleanupTasks.push(() => {
          document.removeEventListener(PAGE_PROXY_EVENT, onPageProxyChange);
          pageProxyBridgeInstalled = false;
          bridgeStatus.installed = false;
        });
      };

      const configurePageProxy = () => {
        const config = {
          disableStyleSheetsProxy: siteFixFlag("disableStyleSheetsProxy"),
          disableShadowRootProxy: siteFixFlag("disableShadowRootProxy"),
          disableCustomElementRegistryProxy: siteFixFlag("disableCustomElementRegistryProxy"),
          enableCustomElementRegistryProxy: siteFixFlag("enableCustomElementRegistryProxy")
        };
        bridgeStatus.config = config;
        bridgeStatus.configured = true;
        try {
          document.dispatchEvent(new CustomEvent(PAGE_PROXY_CONFIG_EVENT, {
            detail: config
          }));
        } catch (_) {}
      };

      const runDynamicStyle = () => {
        if (dynamicStyleStarted) return;
        dynamicStyleStarted = true;
        __wkdomainsDarkModeDebug("dynamic-start");
        installPageProxyBridge();
        configurePageProxy();
        installStylesheetProxy();
        __wkdomainsDarkModeDebug("dynamic-after-stylesheet-proxy");
        installShadowRootProxy();
        __wkdomainsDarkModeDebug("dynamic-after-shadow-proxy");
        installCustomElementRegistryProxy();
        __wkdomainsDarkModeDebug("dynamic-after-custom-elements");

        document.addEventListener("DOMContentLoaded", handleDOMReady, { once: true });
        window.addEventListener("load", handleWindowLoad, { passive: true });
        window.addEventListener("pageshow", handlePageShow, { passive: true });
        document.addEventListener("visibilitychange", handleVisibilityChange);
        __wkdomainsDarkModeDebug("dynamic-after-listeners");
        cleanupTasks.push(() => {
          document.removeEventListener("DOMContentLoaded", handleDOMReady);
          window.removeEventListener("load", handleWindowLoad);
          window.removeEventListener("pageshow", handlePageShow);
          document.removeEventListener("visibilitychange", handleVisibilityChange);
        });

        __wkdomainsDarkModeDebug("dynamic-before-watch-root");
        watchRoot(document);
        __wkdomainsDarkModeDebug("dynamic-after-watch-root");
        dirtyRoots.add(document);
        __wkdomainsDarkModeDebug("dynamic-before-schedule-style-sync");
        scheduleStyleSync(0);
        __wkdomainsDarkModeDebug("dynamic-before-schedule-run");
        schedule(0);
        __wkdomainsDarkModeDebug("dynamic-end");
      };
    """#
}
