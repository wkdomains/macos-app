//
//  BrowserDarkModeScripts.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let renderInvalidationScript = """
    (() => {
      if (window.__wkdomainsRenderInstalled) return;
      window.__wkdomainsRenderInstalled = true;

      let timer;

      const post = (reason) => {
        try {
          window.webkit.messageHandlers.wkdomainsRender.postMessage({
            reason,
            pageURL: location.href
          });
        } catch (_) {}
      };

      const schedule = (reason) => {
        window.clearTimeout(timer);
        timer = window.setTimeout(() => post(reason), 180);
      };

      window.addEventListener("load", () => schedule("load"), { passive: true });
      window.addEventListener("pageshow", () => schedule("pageshow"), { passive: true });
      window.addEventListener("resize", () => schedule("resize"), { passive: true });
      window.addEventListener("scroll", () => schedule("scroll"), { passive: true, capture: true });
      document.addEventListener("readystatechange", () => schedule("readystatechange"));

      if (window.visualViewport) {
        window.visualViewport.addEventListener("resize", () => schedule("visualViewportResize"), { passive: true });
        window.visualViewport.addEventListener("scroll", () => schedule("visualViewportScroll"), { passive: true });
      }

      const observeDocument = () => {
        if (!document.documentElement || !window.MutationObserver) return;

        const observer = new MutationObserver(() => schedule("mutation"));
        observer.observe(document.documentElement, {
          attributes: true,
          attributeFilter: [
            "class",
            "hidden",
            "aria-hidden",
            "aria-expanded",
            "open",
            "src",
            "href"
          ],
          childList: true,
          characterData: true,
          subtree: true
        });
      };

      if (document.documentElement) {
        observeDocument();
      } else {
        document.addEventListener("DOMContentLoaded", observeDocument, { once: true });
      }

      schedule("install");
    })();
    """

    nonisolated private static func javaScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    static func forcedDarkModeScript(disabledSites: [String]) -> String {
        let disabledSiteList = disabledSites.map(javaScriptStringLiteral).joined(separator: ", ")

        return """
    (() => {
      if (window.__wkdomainsDarkModeInstalled) return;
      window.__wkdomainsDarkModeInstalled = true;

      const DISABLED_SITES = new Set([\(disabledSiteList)]);
      const STYLE_ID = "wkdomains-forced-dark-style";
      const ROOT_ATTRIBUTE = "data-wkdomains-forced-dark";
      const READY_ATTRIBUTE = "data-wkdomains-forced-dark-ready";
      const SAMPLING_ATTRIBUTE = "data-wkdomains-forced-dark-sampling";
      const COLOR_ATTRIBUTE = "data-wkdomains-forced-dark-color";
      const BACKGROUND_ATTRIBUTE = "data-wkdomains-forced-dark-bg";
      const BACKGROUND_IMAGE_ATTRIBUTE = "data-wkdomains-forced-dark-bg-image";
      const FILL_ATTRIBUTE = "data-wkdomains-forced-dark-fill";
      const STROKE_ATTRIBUTE = "data-wkdomains-forced-dark-stroke";
      const DEFAULT_BACKGROUND = { r: 24, g: 26, b: 27, a: 1 };
      const DEFAULT_TEXT = { r: 232, g: 230, b: 227, a: 1 };
      const MUTED_TEXT = { r: 157, g: 148, b: 136, a: 1 };
      const DEFAULT_BORDER = { r: 58, g: 63, b: 65, a: 1 };
      const SKIP_TAGS = new Set([
        "SCRIPT", "STYLE", "LINK", "META", "NOSCRIPT", "TITLE", "HEAD",
        "IMG", "PICTURE", "VIDEO", "CANVAS", "IFRAME", "EMBED", "OBJECT"
      ]);
      const SVG_TAGS = new Set([
        "SVG", "PATH", "CIRCLE", "RECT", "POLYGON", "POLYLINE", "LINE",
        "ELLIPSE", "USE", "G", "DEFS", "CLIPPATH", "MASK", "FILTER",
        "SYMBOL", "STOP", "LINEARGRADIENT", "RADIALGRADIENT"
      ]);
      const BORDER_OVERRIDES = [
        {
          js: "borderTopColor",
          css: "border-top-color",
          attr: "data-wkdomains-forced-dark-border-top",
          prop: "--wkdomains-forced-dark-border-top"
        },
        {
          js: "borderRightColor",
          css: "border-right-color",
          attr: "data-wkdomains-forced-dark-border-right",
          prop: "--wkdomains-forced-dark-border-right"
        },
        {
          js: "borderBottomColor",
          css: "border-bottom-color",
          attr: "data-wkdomains-forced-dark-border-bottom",
          prop: "--wkdomains-forced-dark-border-bottom"
        },
        {
          js: "borderLeftColor",
          css: "border-left-color",
          attr: "data-wkdomains-forced-dark-border-left",
          prop: "--wkdomains-forced-dark-border-left"
        },
        {
          js: "outlineColor",
          css: "outline-color",
          attr: "data-wkdomains-forced-dark-outline",
          prop: "--wkdomains-forced-dark-outline"
        },
        {
          js: "columnRuleColor",
          css: "column-rule-color",
          attr: "data-wkdomains-forced-dark-column-rule",
          prop: "--wkdomains-forced-dark-column-rule"
        },
        {
          js: "textDecorationColor",
          css: "text-decoration-color",
          attr: "data-wkdomains-forced-dark-text-decoration",
          prop: "--wkdomains-forced-dark-text-decoration"
        }
      ];

      const currentHost = String(location.hostname || "").toLowerCase().replace(/^\\.+|\\.+$/g, "");
      if (DISABLED_SITES.has(currentHost)) {
        return;
      }

      let forced = null;
      let scheduled = false;
      let applying = false;
      let observer = null;
      let readyFinalized = false;
      let readyFallbackTimer = null;
      let sourceStylesPrimed = false;
      const sourceStyleCache = new WeakMap();
      const installedAt = (() => {
        try { return performance.now(); } catch (_) { return Date.now(); }
      })();

      const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

      const parseComponent = (value, isAlpha = false) => {
        if (!value) return isAlpha ? 1 : 0;
        const token = String(value).trim();
        if (token.endsWith("%")) {
          const parsed = Number.parseFloat(token);
          if (!Number.isFinite(parsed)) return isAlpha ? 1 : 0;
          return isAlpha ? clamp(parsed / 100, 0, 1) : clamp(parsed * 2.55, 0, 255);
        }

        const parsed = Number.parseFloat(token);
        if (!Number.isFinite(parsed)) return isAlpha ? 1 : 0;
        if (isAlpha) return clamp(parsed, 0, 1);
        return clamp(parsed <= 1 ? parsed * 255 : parsed, 0, 255);
      };

      const parseColor = (value) => {
        if (!value || value === "transparent" || value === "none") return null;

        const text = String(value).trim().toLowerCase();
        const open = text.indexOf("(");
        const close = text.lastIndexOf(")");
        if (open < 0 || close <= open) return null;

        const functionName = text.slice(0, open);
        if (!functionName.includes("rgb") && !functionName.includes("color")) return null;

        const parts = text
          .slice(open + 1, close)
          .replaceAll(",", " ")
          .replaceAll("/", " ")
          .split(" ")
          .map((part) => part.trim())
          .filter(Boolean);

        const offset = functionName.includes("color") && Number.isNaN(Number.parseFloat(parts[0])) ? 1 : 0;
        if (parts.length - offset < 3) return null;

        return {
          r: parseComponent(parts[offset]),
          g: parseComponent(parts[offset + 1]),
          b: parseComponent(parts[offset + 2]),
          a: parseComponent(parts[offset + 3], true)
        };
      };

      const toRGBA = (color) => {
        const r = Math.round(clamp(color.r, 0, 255));
        const g = Math.round(clamp(color.g, 0, 255));
        const b = Math.round(clamp(color.b, 0, 255));
        const a = clamp(color.a == null ? 1 : color.a, 0, 1);
        return a >= 0.995
          ? `rgb(${r}, ${g}, ${b})`
          : `rgba(${r}, ${g}, ${b}, ${Math.round(a * 1000) / 1000})`;
      };

      const setOverride = (element, attribute, property, value) => {
        if (!value) {
          element.removeAttribute(attribute);
          element.style.removeProperty(property);
          return;
        }

        element.style.setProperty(property, value);
        element.setAttribute(attribute, "");
      };

      const relativeLuminance = (color) => {
        const channel = (value) => {
          const normalized = clamp(value, 0, 255) / 255;
          return normalized <= 0.03928
            ? normalized / 12.92
            : Math.pow((normalized + 0.055) / 1.055, 2.4);
        };

        return 0.2126 * channel(color.r)
          + 0.7152 * channel(color.g)
          + 0.0722 * channel(color.b);
      };

      const rgbToHSL = (color) => {
        const r = color.r / 255;
        const g = color.g / 255;
        const b = color.b / 255;
        const max = Math.max(r, g, b);
        const min = Math.min(r, g, b);
        let h = 0;
        let s = 0;
        const l = (max + min) / 2;

        if (max !== min) {
          const d = max - min;
          s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
          if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
          else if (max === g) h = (b - r) / d + 2;
          else h = (r - g) / d + 4;
          h *= 60;
        }

        return { h, s, l, a: color.a };
      };

      const hueToRGB = (p, q, t) => {
        let value = t;
        if (value < 0) value += 1;
        if (value > 1) value -= 1;
        if (value < 1 / 6) return p + (q - p) * 6 * value;
        if (value < 1 / 2) return q;
        if (value < 2 / 3) return p + (q - p) * (2 / 3 - value) * 6;
        return p;
      };

      const hslToRGB = ({ h, s, l, a }) => {
        if (s <= 0) {
          const gray = l * 255;
          return { r: gray, g: gray, b: gray, a };
        }

        const normalizedHue = ((h % 360) + 360) % 360 / 360;
        const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
        const p = 2 * l - q;

        return {
          r: hueToRGB(p, q, normalizedHue + 1 / 3) * 255,
          g: hueToRGB(p, q, normalizedHue) * 255,
          b: hueToRGB(p, q, normalizedHue - 1 / 3) * 255,
          a
        };
      };

      const mix = (a, b, amount) => ({
        r: a.r + (b.r - a.r) * amount,
        g: a.g + (b.g - a.g) * amount,
        b: a.b + (b.b - a.b) * amount,
        a: a.a + (b.a - a.a) * amount
      });

      const viewportShare = (element) => {
        try {
          const rect = element.getBoundingClientRect();
          const visibleWidth = clamp(Math.min(rect.right, innerWidth) - Math.max(rect.left, 0), 0, innerWidth);
          const visibleHeight = clamp(Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0), 0, innerHeight);
          return (visibleWidth * visibleHeight) / Math.max(1, innerWidth * innerHeight);
        } catch (_) {
          return 0;
        }
      };

      const visibleRectFor = (element) => {
        try {
          const rect = element.getBoundingClientRect();
          const width = clamp(Math.min(rect.right, innerWidth) - Math.max(rect.left, 0), 0, innerWidth);
          const height = clamp(Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0), 0, innerHeight);
          return { width, height, area: width * height };
        } catch (_) {
          return { width: 0, height: 0, area: 0 };
        }
      };

      const transformBackground = (color, element = null) => {
        if (!color || color.a < 0.05) return null;
        const luminance = relativeLuminance(color);
        if (luminance < 0.18) return toRGBA(color);

        const hsl = rgbToHSL(color);
        const neutral = hsl.s < 0.16 || (hsl.l > 0.76 && hsl.h > 35 && hsl.h < 90) || (hsl.l > 0.82 && hsl.h > 200 && hsl.h < 280);
        const largeSurface = element && viewportShare(element) > 0.24;

        if (!neutral && hsl.s > 0.55 && luminance < 0.42 && hsl.l < 0.58) {
          return toRGBA(color);
        }

        if (neutral && (largeSurface || luminance > 0.74)) {
          return toRGBA({ ...DEFAULT_BACKGROUND, a: color.a });
        }

        const lightness = clamp(0.11 + (1 - luminance) * 0.16, 0.11, 0.26);
        const transformed = neutral
          ? hslToRGB({ h: 212, s: 0.13, l: lightness, a: color.a })
          : hslToRGB({
              h: hsl.h,
              s: clamp(hsl.s * 0.88, 0.20, 0.78),
              l: hsl.l < 0.58 && hsl.s > 0.45
                ? clamp(hsl.l * 0.84, 0.36, 0.48)
                : (hsl.h > 40 && hsl.h < 85 ? lightness * 0.78 : lightness),
              a: color.a
            });

        return toRGBA(mix(transformed, DEFAULT_BACKGROUND, neutral ? 0.18 : 0.02));
      };

      const transformForeground = (color, element = null) => {
        if (!color || color.a < 0.05) return null;
        const luminance = relativeLuminance(color);
        if (luminance > 0.62) return toRGBA(color);

        const hsl = rgbToHSL(color);
        const linkLikeBlue = element
          && element.closest
          && element.closest("a")
          && hsl.h > 185
          && hsl.h < 265
          && hsl.s > 0.22;
        const neutral = linkLikeBlue || hsl.s < 0.18 || hsl.l < 0.14;
        const sourceLightness = clamp(hsl.l, 0, 1);
        const transformed = neutral
          ? hslToRGB({
              h: 36,
              s: 0.12,
              l: sourceLightness < 0.20 || linkLikeBlue
                ? 0.88
                : clamp(0.44 + (1 - sourceLightness) * 0.45, 0.56, 0.78),
              a: color.a
            })
          : hslToRGB({
              h: hsl.h > 205 && hsl.h < 245 ? 214 : hsl.h,
              s: clamp(hsl.s * 0.85, 0.28, 0.70),
              l: clamp(0.62 + (1 - luminance) * 0.22, 0.64, 0.86),
              a: color.a
            });

        return toRGBA(mix(transformed, neutral && sourceLightness > 0.36 ? MUTED_TEXT : DEFAULT_TEXT, neutral ? 0.12 : 0.08));
      };

      const transformBorder = (color) => {
        if (!color || color.a < 0.05) return null;
        const luminance = relativeLuminance(color);
        if (luminance < 0.22) return toRGBA(mix(color, DEFAULT_BORDER, 0.35));
        if (luminance > 0.72) return toRGBA(DEFAULT_BORDER);

        const hsl = rgbToHSL(color);
        return toRGBA(hslToRGB({
          h: hsl.s < 0.16 ? 212 : hsl.h,
          s: hsl.s < 0.16 ? 0.13 : clamp(hsl.s * 0.55, 0.12, 0.45),
          l: 0.25,
          a: color.a
        }));
      };

      const composite = (top, bottom) => {
        if (!top || top.a <= 0) return bottom;
        const alpha = top.a + bottom.a * (1 - top.a);
        if (alpha <= 0) return { r: 255, g: 255, b: 255, a: 1 };

        return {
          r: (top.r * top.a + bottom.r * bottom.a * (1 - top.a)) / alpha,
          g: (top.g * top.a + bottom.g * bottom.a * (1 - top.a)) / alpha,
          b: (top.b * top.a + bottom.b * bottom.a * (1 - top.a)) / alpha,
          a: alpha
        };
      };

      const surfaceColorFor = (element) => {
        const colors = [];
        let node = element;

        while (node && node.nodeType === Node.ELEMENT_NODE) {
          const color = parseColor(getComputedStyle(node).backgroundColor);
          if (color && color.a > 0) colors.push(color);
          node = node.parentElement;
        }

        let surface = { r: 255, g: 255, b: 255, a: 1 };
        for (let index = colors.length - 1; index >= 0; index -= 1) {
          surface = composite(colors[index], surface);
        }

        return surface;
      };

      const documentGeometryFor = (element) => {
        try {
          const scrollingElement = document.scrollingElement || document.documentElement || document.body;
          const pageWidth = Math.max(
            scrollingElement ? scrollingElement.scrollWidth || 0 : 0,
            document.documentElement ? document.documentElement.scrollWidth || 0 : 0,
            document.body ? document.body.scrollWidth || 0 : 0,
            innerWidth
          );
          const pageHeight = Math.max(
            scrollingElement ? scrollingElement.scrollHeight || 0 : 0,
            document.documentElement ? document.documentElement.scrollHeight || 0 : 0,
            document.body ? document.body.scrollHeight || 0 : 0,
            innerHeight
          );
          const rect = element.getBoundingClientRect();
          const left = clamp(rect.left + scrollX, 0, pageWidth);
          const right = clamp(rect.right + scrollX, 0, pageWidth);
          const top = clamp(rect.top + scrollY, 0, pageHeight);
          const bottom = clamp(rect.bottom + scrollY, 0, pageHeight);
          const width = Math.max(0, right - left);
          const height = Math.max(0, bottom - top);
          const area = width * height;
          const viewportArea = Math.max(1, innerWidth * innerHeight);
          const documentArea = Math.max(1, pageWidth * pageHeight);

          return {
            area,
            height,
            viewportAreaShare: area / viewportArea,
            documentAreaShare: area / documentArea,
            widthShare: width / Math.max(1, pageWidth)
          };
        } catch (_) {
          return null;
        }
      };

      const hasLargeLightDocumentSurface = () => {
        if (!document.documentElement || !document.body || innerWidth <= 0 || innerHeight <= 0) {
          return false;
        }

        const candidates = new Set([
          document.documentElement,
          document.body,
          ...document.querySelectorAll([
            "main",
            "section",
            "article",
            "aside",
            "header",
            "footer",
            "[class*='bg']",
            "[class*='section']",
            "[class*='component']",
            "[class*='container']",
            "[class*='wrapper']"
          ].join(","))
        ]);

        for (const element of candidates) {
          if (!element || SKIP_TAGS.has(element.tagName.toUpperCase())) continue;

          const style = getComputedStyle(element);
          if (style.display === "none" || style.visibility === "hidden" || Number.parseFloat(style.opacity || "1") <= 0.02) {
            continue;
          }

          const geometry = documentGeometryFor(element);
          if (!geometry || geometry.area <= 0) continue;

          const largeSurface = geometry.viewportAreaShare > 0.26
            || geometry.documentAreaShare > 0.045
            || (geometry.widthShare > 0.72 && geometry.height > 180);
          if (!largeSurface) continue;

          if (relativeLuminance(surfaceColorFor(element)) > 0.68) {
            return true;
          }
        }

        return false;
      };

      const isPageAlreadyDark = () => {
        if (!document.documentElement || !document.body || innerWidth <= 0 || innerHeight <= 0) {
          return false;
        }

        const rootStyle = getComputedStyle(document.documentElement);
        if (rootStyle.filter.includes("invert(1)")) return true;

        const columns = Math.min(4, Math.max(1, Math.ceil(innerWidth / 256)));
        const rows = Math.min(4, Math.max(1, Math.ceil(innerHeight / 256)));
        let darkCount = 0;
        let total = 0;
        let luminanceSum = 0;

        for (let row = 0; row < rows; row += 1) {
          for (let column = 0; column < columns; column += 1) {
            const x = Math.floor((column + 0.5) * innerWidth / columns);
            const y = Math.floor((row + 0.5) * innerHeight / rows);
            const element = document.elementFromPoint(x, y);
            if (!element) continue;

            const luminance = relativeLuminance(surfaceColorFor(element));
            luminanceSum += luminance;
            total += 1;
            if (luminance < 0.34) darkCount += 1;
          }
        }

        if (total === 0) return false;
        const average = luminanceSum / total;
        const darkShare = darkCount / total;
        return darkShare >= 0.65 && average < 0.42 && !hasLargeLightDocumentSurface();
      };

      const ensureBaseStyle = () => {
        if (!document.documentElement) return;
        document.documentElement.setAttribute(ROOT_ATTRIBUTE, "true");

        if (document.getElementById(STYLE_ID)) return;

        const style = document.createElement("style");
        style.id = STYLE_ID;
        style.textContent = `
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) {
            color-scheme: dark !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]),
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) body {
            background: ${toRGBA(DEFAULT_BACKGROUND)} !important;
            color: ${toRGBA(DEFAULT_TEXT)} !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) body * {
            transition-property: color, background-color, border-color, outline-color, box-shadow !important;
            transition-duration: 0s !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [${COLOR_ATTRIBUTE}] {
            color: var(--wkdomains-forced-dark-color) !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [${BACKGROUND_ATTRIBUTE}] {
            background-color: var(--wkdomains-forced-dark-bg) !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [${BACKGROUND_IMAGE_ATTRIBUTE}] {
            background-image: var(--wkdomains-forced-dark-bg-image) !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) header,
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) nav,
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="banner"],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) #site-header,
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .header-bg,
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .main_sub-navigation,
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="site-header" i],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="main-nav" i]:not(a):not(button):not(li):not(span),
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="sub-navigation" i],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="navigation" i]:not(a):not(button):not(li):not(span) {
            background-color: ${toRGBA(DEFAULT_BACKGROUND)} !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) header [${BACKGROUND_ATTRIBUTE}],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) nav [${BACKGROUND_ATTRIBUTE}],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="banner"] [${BACKGROUND_ATTRIBUTE}],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) #site-header [${BACKGROUND_ATTRIBUTE}],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .header-bg [${BACKGROUND_ATTRIBUTE}],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .main_sub-navigation [${BACKGROUND_ATTRIBUTE}],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="site-header" i] [${BACKGROUND_ATTRIBUTE}],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="main-nav" i] [${BACKGROUND_ATTRIBUTE}],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="sub-navigation" i] [${BACKGROUND_ATTRIBUTE}],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="navigation" i] [${BACKGROUND_ATTRIBUTE}] {
            background-color: var(--wkdomains-forced-dark-bg) !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [${FILL_ATTRIBUTE}] {
            fill: var(--wkdomains-forced-dark-fill) !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [${STROKE_ATTRIBUTE}] {
            stroke: var(--wkdomains-forced-dark-stroke) !important;
          }
          ${BORDER_OVERRIDES.map((override) => `:root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [${override.attr}] { ${override.css}: var(${override.prop}) !important; }`).join("\\n          ")}
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [bgcolor] :not(iframe):not(img):not(picture):not(video):not(canvas):not(svg):not(path):not([${BACKGROUND_ATTRIBUTE}]) {
            background-color: transparent !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input,
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) textarea,
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) select,
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) button {
            color-scheme: dark !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) ::selection {
            background: rgb(67, 91, 122) !important;
            color: rgb(246, 248, 250) !important;
          }
        `;

        (document.head || document.documentElement).appendChild(style);
      };

      const withFallbackDisabled = (action) => {
        const root = document.documentElement;
        const hadSamplingAttribute = root ? root.hasAttribute(SAMPLING_ATTRIBUTE) : false;

        if (root) {
          root.setAttribute(SAMPLING_ATTRIBUTE, "true");
        }

        try {
          return action();
        } finally {
          if (root && !hadSamplingAttribute) {
            root.removeAttribute(SAMPLING_ATTRIBUTE);
          }
        }
      };

      const removeBaseStyle = () => {
        if (!document.documentElement) return;
        document.documentElement.removeAttribute(ROOT_ATTRIBUTE);
        document.documentElement.removeAttribute(READY_ATTRIBUTE);
        document.documentElement.removeAttribute(SAMPLING_ATTRIBUTE);
        document.getElementById(STYLE_ID)?.remove();
      };

      const elapsedSinceInstall = () => {
        try { return performance.now() - installedAt; } catch (_) { return Date.now() - installedAt; }
      };

      const hasUsefulRenderedContent = () => {
        if (!document.body) return false;

        const text = (document.body.innerText || document.body.textContent || "").trim();
        if (text.length > 550) return true;

        const usefulElementCount = document.body.querySelectorAll("article, main, h1, h2, h3, p, li, td, a").length;
        if (usefulElementCount > 22) return true;

        const bodyHeight = Math.max(
          document.body.scrollHeight || 0,
          document.documentElement ? document.documentElement.scrollHeight || 0 : 0
        );

        return usefulElementCount > 6 && bodyHeight > Math.max(900, innerHeight * 1.25);
      };

      const finalizeReadyWhenUseful = () => {
        const root = document.documentElement;
        if (!root || readyFinalized) return;

        if (hasUsefulRenderedContent() || document.readyState !== "loading" || elapsedSinceInstall() > 650) {
          root.setAttribute(READY_ATTRIBUTE, "true");
          readyFinalized = true;
          if (readyFallbackTimer) {
            window.clearTimeout(readyFallbackTimer);
            readyFallbackTimer = null;
          }
          return;
        }

        if (!readyFallbackTimer) {
          readyFallbackTimer = window.setTimeout(() => {
            readyFallbackTimer = null;
            finalizeReadyWhenUseful();
          }, 45);
        }
      };

      const shouldSkipElement = (element) => {
        if (!element || SKIP_TAGS.has(element.tagName.toUpperCase())) return true;
        const style = getComputedStyle(element);
        return style.display === "none";
      };

      const isVisibleMedia = (element) => {
        if (!element) return false;
        const style = getComputedStyle(element);
        if (style.display === "none" || style.visibility === "hidden" || Number.parseFloat(style.opacity || "1") <= 0.02) {
          return false;
        }

        const rect = visibleRectFor(element);
        return rect.width >= 24 && rect.height >= 24 && rect.area > 0;
      };

      const hasMediaBackdrop = (element, style) => {
        if (!element || !style) return false;

        const backgroundImage = style.backgroundImage || "";
        if (backgroundImage && backgroundImage !== "none" && !backgroundImage.includes("gradient")) {
          return true;
        }

        if (element.tagName && ["A", "BUTTON", "INPUT", "TEXTAREA", "SELECT", "OPTION"].includes(element.tagName.toUpperCase())) {
          return false;
        }

        const elementRect = visibleRectFor(element);
        if (elementRect.area <= 0) return false;

        for (const media of element.querySelectorAll("video,img,picture,canvas,iframe,object,embed")) {
          if (!isVisibleMedia(media)) continue;

          const mediaRect = visibleRectFor(media);
          const elementCoverage = mediaRect.area / Math.max(1, elementRect.area);
          const viewportCoverage = mediaRect.area / Math.max(1, innerWidth * innerHeight);
          if (elementCoverage > 0.32 || viewportCoverage > 0.18) {
            return true;
          }
        }

        return false;
      };

      const captureSourceStyle = (element) => {
        if (!element || sourceStyleCache.has(element)) {
          return sourceStyleCache.get(element) || null;
        }

        const style = getComputedStyle(element);
        const source = {
          color: style.color,
          backgroundColor: style.backgroundColor,
          backgroundImage: style.backgroundImage,
          fill: style.fill,
          stroke: style.stroke
        };

        for (const override of BORDER_OVERRIDES) {
          source[override.js] = style[override.js];
        }

        sourceStyleCache.set(element, source);
        return source;
      };

      const primeSourceStyles = (root) => {
        if (!root || !root.querySelectorAll) return;

        if (root.nodeType === Node.DOCUMENT_NODE) {
          if (document.documentElement) captureSourceStyle(document.documentElement);
          if (document.body) captureSourceStyle(document.body);
        }

        for (const element of root.querySelectorAll("*")) {
          captureSourceStyle(element);
          if (element.shadowRoot) primeSourceStyles(element.shadowRoot);
        }
      };

      const applyElement = (element) => {
        if (shouldSkipElement(element)) return;

        const style = captureSourceStyle(element) || getComputedStyle(element);
        const tag = element.tagName.toUpperCase();

        if (tag === "HTML" || tag === "BODY") {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", toRGBA(DEFAULT_BACKGROUND));
          setOverride(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", toRGBA(DEFAULT_TEXT));
          return;
        }

        if (!SVG_TAGS.has(tag)) {
          const color = transformForeground(parseColor(style.color), element);
          setOverride(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", color);
        }

        const background = parseColor(style.backgroundColor);
        const backgroundLuminance = background ? relativeLuminance(background) : 0;
        const mediaBackdrop = hasMediaBackdrop(element, style);
        const transformedBackground = mediaBackdrop ? null : transformBackground(background, element);
        if (mediaBackdrop) {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", "transparent");
        } else if (transformedBackground && background.a > 0.08) {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", transformedBackground);
        } else {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", null);
        }

        if (!mediaBackdrop && style.backgroundImage && style.backgroundImage.includes("gradient") && backgroundLuminance > 0.46) {
          setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", "none");
        } else {
          setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", null);
        }

        for (const override of BORDER_OVERRIDES) {
          const border = transformBorder(parseColor(style[override.js]));
          setOverride(element, override.attr, override.prop, border);
        }

        if (SVG_TAGS.has(tag)) {
          const fill = parseColor(style.fill);
          const stroke = parseColor(style.stroke);
          if (fill && relativeLuminance(fill) < 0.52) {
            setOverride(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", transformForeground(fill, element));
          } else {
            setOverride(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", null);
          }
          if (stroke && relativeLuminance(stroke) < 0.52) {
            setOverride(element, STROKE_ATTRIBUTE, "--wkdomains-forced-dark-stroke", transformForeground(stroke, element));
          } else {
            setOverride(element, STROKE_ATTRIBUTE, "--wkdomains-forced-dark-stroke", null);
          }
        }
      };

      const applyRoot = (root) => {
        if (!root || !root.querySelectorAll) return;

        if (root.nodeType === Node.DOCUMENT_NODE) {
          applyElement(document.documentElement);
          if (document.body) applyElement(document.body);
        }

        for (const element of root.querySelectorAll("*")) {
          applyElement(element);
          if (element.shadowRoot) applyRoot(element.shadowRoot);
        }
      };

      const run = () => {
        scheduled = false;
        if (!document.documentElement || !document.body) return;

        if (forced !== true) {
          forced = !withFallbackDisabled(isPageAlreadyDark);
          if (!forced) {
            removeBaseStyle();
            stopObserving();
            return;
          }
        }

        applying = true;
        if (!sourceStylesPrimed) {
          withFallbackDisabled(() => primeSourceStyles(document));
          sourceStylesPrimed = true;
        }
        ensureBaseStyle();
        applyRoot(document);
        finalizeReadyWhenUseful();
        window.setTimeout(() => {
          applying = false;
        }, 0);
      };

      const schedule = (delay = 80) => {
        if (forced === false) return;
        if (scheduled) return;
        scheduled = true;
        window.setTimeout(run, delay);
      };

      const stopObserving = () => {
        if (!observer) return;
        observer.disconnect();
        observer = null;
      };

      const observe = () => {
        if (observer || !document.documentElement || !window.MutationObserver) {
          return;
        }

        observer = new MutationObserver(() => {
          if (!applying) schedule(0);
        });
        observer.observe(document.documentElement, {
          attributes: true,
          childList: true,
          subtree: true
        });
      };

      document.addEventListener("DOMContentLoaded", () => {
        observe();
        schedule(0);
      }, { once: true });
      window.addEventListener("load", () => schedule(40), { passive: true });
      window.addEventListener("pageshow", () => schedule(40), { passive: true });

      observe();
      if (document.readyState === "loading") {
        schedule(0);
      } else {
        schedule(0);
      }
    })();
    """
    }
}
