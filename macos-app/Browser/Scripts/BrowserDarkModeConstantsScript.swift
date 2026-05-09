//
//  BrowserDarkModeConstantsScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeConstantsScript = #"""
      const STYLE_ID = "wkdomains-forced-dark-style";
      const ROOT_ATTRIBUTE = "data-wkdomains-forced-dark";
      const READY_ATTRIBUTE = "data-wkdomains-forced-dark-ready";
      const SAMPLING_ATTRIBUTE = "data-wkdomains-forced-dark-sampling";
      const DARKREADER_MODE_ATTRIBUTE = "data-darkreader-mode";
      const DARKREADER_SCHEME_ATTRIBUTE = "data-darkreader-scheme";
      const COLOR_ATTRIBUTE = "data-wkdomains-forced-dark-color";
      const BACKGROUND_ATTRIBUTE = "data-wkdomains-forced-dark-bg";
      const FORM_SURFACE_ATTRIBUTE = "data-wkdomains-forced-dark-form-surface";
      const BACKGROUND_IMAGE_ATTRIBUTE = "data-wkdomains-forced-dark-bg-image";
      const LEGACY_BACKGROUND_ATTRIBUTE = "data-wkdomains-forced-dark-legacy-bg";
      const LEGACY_DESCENDANT_COLOR_ATTRIBUTE = "data-wkdomains-forced-dark-legacy-descendant-color";
      const LEGACY_TEXT_ATTRIBUTE = "data-wkdomains-forced-dark-legacy-text";
      const LEGACY_LINK_ATTRIBUTE = "data-wkdomains-forced-dark-legacy-link";
      const LEGACY_VISITED_LINK_ATTRIBUTE = "data-wkdomains-forced-dark-legacy-vlink";
      const LEGACY_ACTIVE_LINK_ATTRIBUTE = "data-wkdomains-forced-dark-legacy-alink";
      const IMAGE_FILTER_ATTRIBUTE = "data-wkdomains-forced-dark-image-filter";
      const FILL_ATTRIBUTE = "data-wkdomains-forced-dark-fill";
      const STROKE_ATTRIBUTE = "data-wkdomains-forced-dark-stroke";
      const BOX_SHADOW_ATTRIBUTE = "data-wkdomains-forced-dark-box-shadow";
      const INLINE_CLASS = "wkdomains-darkreader";
      const DEFAULT_BACKGROUND = { r: 24, g: 26, b: 27, a: 1 };
      const DEFAULT_TEXT = { r: 232, g: 230, b: 227, a: 1 };
      const MUTED_TEXT = { r: 157, g: 148, b: 136, a: 1 };
      const DEFAULT_BORDER = { r: 58, g: 63, b: 65, a: 1 };
      const THEME = {
        mode: 1,
        brightness: 100,
        contrast: 100,
        sepia: 0,
        grayscale: 0,
        darkSchemeBackgroundColor: "#181a1b",
        darkSchemeTextColor: "#e8e6e3",
        lightSchemeBackgroundColor: "#ffffff",
        lightSchemeTextColor: "#000000"
      };
      const SKIP_TAGS = new Set([
        "SCRIPT", "STYLE", "LINK", "META", "NOSCRIPT", "TITLE", "HEAD",
        "IMG", "PICTURE", "VIDEO", "CANVAS", "IFRAME", "EMBED", "OBJECT"
      ]);
      const SVG_TAGS = new Set([
        "SVG", "PATH", "CIRCLE", "RECT", "POLYGON", "POLYLINE", "LINE",
        "ELLIPSE", "USE", "G", "DEFS", "CLIPPATH", "MASK", "FILTER",
        "SYMBOL", "STOP", "LINEARGRADIENT", "RADIALGRADIENT", "TEXT", "TSPAN"
      ]);
      const INLINE_STYLE_ATTRS = ["style", "fill", "stop-color", "stroke", "bgcolor", "color", "background"];
      const LEGACY_BODY_STYLE_ATTRS = ["text", "link", "vlink", "alink"];
      const INLINE_STYLE_SELECTOR = [
        ...INLINE_STYLE_ATTRS.map((attr) => `[${attr}]`),
        ...LEGACY_BODY_STYLE_ATTRS.map((attr) => `body[${attr}]`)
      ].join(", ");
      const BORDER_OVERRIDES = [
        { js: "borderTopColor", css: "border-top-color", attr: "data-wkdomains-forced-dark-border-top", prop: "--wkdomains-forced-dark-border-top" },
        { js: "borderRightColor", css: "border-right-color", attr: "data-wkdomains-forced-dark-border-right", prop: "--wkdomains-forced-dark-border-right" },
        { js: "borderBottomColor", css: "border-bottom-color", attr: "data-wkdomains-forced-dark-border-bottom", prop: "--wkdomains-forced-dark-border-bottom" },
        { js: "borderLeftColor", css: "border-left-color", attr: "data-wkdomains-forced-dark-border-left", prop: "--wkdomains-forced-dark-border-left" },
        { js: "outlineColor", css: "outline-color", attr: "data-wkdomains-forced-dark-outline", prop: "--wkdomains-forced-dark-outline" },
        { js: "columnRuleColor", css: "column-rule-color", attr: "data-wkdomains-forced-dark-column-rule", prop: "--wkdomains-forced-dark-column-rule" },
        { js: "textDecorationColor", css: "text-decoration-color", attr: "data-wkdomains-forced-dark-text-decoration", prop: "--wkdomains-forced-dark-text-decoration" }
      ];
      const SHORTHAND_OVERRIDES = [
        { css: "background", attr: "data-wkdomains-forced-dark-bg-short", prop: "--wkdomains-forced-dark-bg-short" },
        { css: "border", attr: "data-wkdomains-forced-dark-border-short", prop: "--wkdomains-forced-dark-border-short" },
        { css: "border-top", attr: "data-wkdomains-forced-dark-border-top-short", prop: "--wkdomains-forced-dark-border-top-short" },
        { css: "border-right", attr: "data-wkdomains-forced-dark-border-right-short", prop: "--wkdomains-forced-dark-border-right-short" },
        { css: "border-bottom", attr: "data-wkdomains-forced-dark-border-bottom-short", prop: "--wkdomains-forced-dark-border-bottom-short" },
        { css: "border-left", attr: "data-wkdomains-forced-dark-border-left-short", prop: "--wkdomains-forced-dark-border-left-short" },
        { css: "outline", attr: "data-wkdomains-forced-dark-outline-short", prop: "--wkdomains-forced-dark-outline-short" },
        { css: "column-rule", attr: "data-wkdomains-forced-dark-column-rule-short", prop: "--wkdomains-forced-dark-column-rule-short" }
      ];
      const ATTRIBUTES_OWNED_BY_DARK_MODE = [
        COLOR_ATTRIBUTE,
        BACKGROUND_ATTRIBUTE,
        FORM_SURFACE_ATTRIBUTE,
        BACKGROUND_IMAGE_ATTRIBUTE,
        LEGACY_BACKGROUND_ATTRIBUTE,
        LEGACY_DESCENDANT_COLOR_ATTRIBUTE,
        LEGACY_TEXT_ATTRIBUTE,
        LEGACY_LINK_ATTRIBUTE,
        LEGACY_VISITED_LINK_ATTRIBUTE,
        LEGACY_ACTIVE_LINK_ATTRIBUTE,
        IMAGE_FILTER_ATTRIBUTE,
        FILL_ATTRIBUTE,
        STROKE_ATTRIBUTE,
        BOX_SHADOW_ATTRIBUTE,
        ...BORDER_OVERRIDES.map((override) => override.attr),
        ...SHORTHAND_OVERRIDES.map((override) => override.attr)
      ];
      const STYLE_SELECTOR = "style, link[rel*='stylesheet' i]:not([disabled])";
      const STYLE_SYNC_CLASS = "wkdomains-darkreader--sync";
      const SHADOW_STYLE_CLASS = "wkdomains-darkreader--shadow";
      const ADOPTED_STYLE_CLASS = "wkdomains-darkreader--adopted";
      const DARK_VAR_PREFIX = "--wkdomains-darkreader";
      const PAGE_PROXY_EVENT = "__wkdomains__darkModePageProxyChange";
      const PAGE_PROXY_CONFIG_EVENT = "__wkdomains__darkModePageProxyConfig";
      const PAGE_PROXY_CLEANUP_EVENT = "__wkdomains__darkModePageProxyCleanup";
      const isGeneratedDarkModeProperty = (property) => {
        const name = String(property || "");
        return name.startsWith(DARK_VAR_PREFIX)
          || name.startsWith("--darkreader-bg--")
          || name.startsWith("--darkreader-text--")
          || name.startsWith("--darkreader-border--")
          || name.startsWith("--wkdomains-forced-dark");
      };
      const DARKREADER_META_NAME = "darkreader";
      const DARKREADER_LOCK_META_NAME = "darkreader-lock";
      const INSTANCE_ID = (() => {
        try {
          const bytes = new Uint32Array(2);
          crypto.getRandomValues(bytes);
          return `${Date.now().toString(36)}-${bytes[0].toString(36)}${bytes[1].toString(36)}`;
        } catch (_) {
          return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
        }
      })();
      const STATIC_STYLE_CLASSES = [
        "wkdomains-darkreader--fallback",
        "wkdomains-darkreader--user-agent",
        "wkdomains-darkreader--invert",
        "wkdomains-darkreader--inline",
        "wkdomains-darkreader--variables",
        "wkdomains-darkreader--root-vars",
        "wkdomains-darkreader--structural",
        "wkdomains-darkreader--site-fixes",
        "wkdomains-darkreader--pdf"
      ];
      let staticStyleMap = new WeakMap();
      const nodePositionWatchers = new Map();
      const shadowRootsWithOverrides = new Set();
      const cleanupTasks = [];
      let metaObserver = null;
      let headObserver = null;
      let interceptorAttempts = 2;
      let pipListenerRegistered = false;
      let dynamicStyleStarted = false;
      let themeColorObserver = null;
      const originalMetaThemeColors = new WeakMap();
      const prototypeRestoreTasks = [];
      const savedPropertyDescriptors = new WeakMap();

      const rememberPropertyDescriptor = (target, property) => {
        if (!target || !property) return null;
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
        return Object.getOwnPropertyDescriptor(target, property) || null;
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
    """#
}
