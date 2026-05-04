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
      const COLOR_ATTRIBUTE = "data-wkdomains-forced-dark-color";
      const BACKGROUND_ATTRIBUTE = "data-wkdomains-forced-dark-bg";
      const BACKGROUND_IMAGE_ATTRIBUTE = "data-wkdomains-forced-dark-bg-image";
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
      const INLINE_STYLE_SELECTOR = INLINE_STYLE_ATTRS.map((attr) => `[${attr}]`).join(", ");
      const BORDER_OVERRIDES = [
        { js: "borderTopColor", css: "border-top-color", attr: "data-wkdomains-forced-dark-border-top", prop: "--wkdomains-forced-dark-border-top" },
        { js: "borderRightColor", css: "border-right-color", attr: "data-wkdomains-forced-dark-border-right", prop: "--wkdomains-forced-dark-border-right" },
        { js: "borderBottomColor", css: "border-bottom-color", attr: "data-wkdomains-forced-dark-border-bottom", prop: "--wkdomains-forced-dark-border-bottom" },
        { js: "borderLeftColor", css: "border-left-color", attr: "data-wkdomains-forced-dark-border-left", prop: "--wkdomains-forced-dark-border-left" },
        { js: "outlineColor", css: "outline-color", attr: "data-wkdomains-forced-dark-outline", prop: "--wkdomains-forced-dark-outline" },
        { js: "columnRuleColor", css: "column-rule-color", attr: "data-wkdomains-forced-dark-column-rule", prop: "--wkdomains-forced-dark-column-rule" },
        { js: "textDecorationColor", css: "text-decoration-color", attr: "data-wkdomains-forced-dark-text-decoration", prop: "--wkdomains-forced-dark-text-decoration" }
      ];
      const ATTRIBUTES_OWNED_BY_DARK_MODE = [
        COLOR_ATTRIBUTE,
        BACKGROUND_ATTRIBUTE,
        BACKGROUND_IMAGE_ATTRIBUTE,
        FILL_ATTRIBUTE,
        STROKE_ATTRIBUTE,
        BOX_SHADOW_ATTRIBUTE,
        ...BORDER_OVERRIDES.map((override) => override.attr)
      ];
      const COLOR_RE = /(?:rgba?|hsla?|hwb|color)\([^)]*\)|#[0-9a-f]{3,8}\b|\b(?:aliceblue|antiquewhite|aqua|aquamarine|azure|beige|bisque|black|blue|brown|coral|crimson|cyan|fuchsia|gold|gray|green|grey|indigo|ivory|khaki|lavender|lime|magenta|maroon|navy|olive|orange|orchid|pink|plum|purple|red|salmon|silver|tan|teal|tomato|transparent|violet|white|yellow)\b/gi;
      const STYLE_SELECTOR = "style, link[rel*='stylesheet' i]:not([disabled])";
      const STYLE_SYNC_CLASS = "wkdomains-darkreader--sync";
      const SHADOW_STYLE_CLASS = "wkdomains-darkreader--shadow";
      const ADOPTED_STYLE_CLASS = "wkdomains-darkreader--adopted";
      const DARK_VAR_PREFIX = "--wkdomains-darkreader";
    """#
}
