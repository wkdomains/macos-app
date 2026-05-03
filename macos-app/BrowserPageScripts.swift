//
//  BrowserPageScripts.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

extension BrowserModel {
    static let xhrTrackingScript = """
    (() => {
      if (window.__wkdomainsXHRInstalled) return;
      window.__wkdomainsXHRInstalled = true;

      let nextID = 1;

      const post = (payload) => {
        try {
          window.webkit.messageHandlers.wkdomainsXHR.postMessage({
            pageURL: location.href,
            pageHost: location.hostname,
            ...payload
          });
        } catch (_) {}
      };

      const requestID = () => `${Date.now()}-${nextID++}`;

      const normalizeURL = (input) => {
        try {
          if (input instanceof Request) return input.url;
          if (input && typeof input === "object" && "href" in input) return input.href;
          return new URL(String(input), location.href).href;
        } catch (_) {
          return String(input);
        }
      };

      const byteSize = (text) => {
        try {
          if (window.TextEncoder) return new TextEncoder().encode(text).length;
        } catch (_) {}

        return String(text || "").length;
      };

      const valueType = (value) => {
        if (value === null) return "null";
        if (Array.isArray(value)) return "array";
        return typeof value;
      };

      const truncatedKeys = (object, limit = 20) => {
        if (!object || typeof object !== "object" || Array.isArray(object)) return [];

        const keys = Object.keys(object);
        if (keys.length <= limit) return keys;

        return keys.slice(0, limit).concat(`+${keys.length - limit} more`);
      };

      const isPlainObject = (value) => {
        return !!value && typeof value === "object" && !Array.isArray(value);
      };

      const hasOnlyKeys = (value, expectedKeys) => {
        if (!isPlainObject(value)) return false;

        const keys = Object.keys(value);
        if (keys.length !== expectedKeys.length) return false;

        return expectedKeys.every((key) => keys.includes(key));
      };

      const isCRUDObject = (value) => {
        return hasOnlyKeys(value, ["c", "r", "u", "d"])
          && ["c", "r", "u", "d"].every((key) => typeof value[key] === "boolean");
      };

      const isCapabilityObject = (value) => {
        return isPlainObject(value) && Object.prototype.hasOwnProperty.call(value, "included");
      };

      const collapsedObjectMap = (object) => {
        const keys = Object.keys(object);
        if (keys.length < 4) return undefined;

        const values = keys.map((key) => object[key]);

        if (values.every(isCRUDObject)) {
          return `object<crud permissions>[${truncatedKeys(object).join(",")}]`;
        }

        if (values.every(isCapabilityObject)) {
          return `object<capabilities>[${truncatedKeys(object).join(",")}]`;
        }

        return undefined;
      };

      const sampleScalar = (value) => {
        const type = valueType(value);

        if (type === "string") {
          const text = value.length > 80 ? `${value.slice(0, 80)}...` : value;
          return JSON.stringify(text);
        }

        if (type === "number" || type === "boolean" || type === "null") {
          return String(value);
        }

        return type;
      };

      const shapeForValue = (value, depth = 0) => {
        const type = valueType(value);

        if (type === "array") {
          const count = value.length;
          if (count === 0) return "array[0]";

          return `array[${count}]<${shapeForValue(value[0], depth + 1)}>`;
        }

        if (type !== "object") return sampleScalar(value);

        const collapsed = collapsedObjectMap(value);
        if (collapsed) return collapsed;

        const keys = truncatedKeys(value, depth === 0 ? 45 : 14);
        if (keys.length === 0) return "object{}";

        if (depth >= 3 || (depth > 0 && Object.keys(value).length > 14)) {
          return `object{${keys.join(",")}}`;
        }

        const fields = keys.map((key) => {
          if (key.startsWith("+") && key.endsWith(" more")) return key;
          return `${key}:${shapeForValue(value[key], depth + 1)}`;
        });

        return `object{${fields.join(",")}}`;
      };

      const summarizeJSON = (text) => {
        const summary = {
          responseBytes: typeof text === "string" ? byteSize(text) : undefined
        };

        if (typeof text !== "string" || text.length === 0) return summary;

        try {
          const jsonText = text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text;
          const value = JSON.parse(jsonText);
          const type = valueType(value);

          summary.jsonType = type;
          summary.jsonShape = shapeForValue(value);

          if (type === "array") {
            summary.jsonItems = value.length;
            return summary;
          }
        } catch (_) {}

        return summary;
      };

      const finishFetch = (id, response, url) => {
        const finishPayload = {
          event: "finish",
          id,
          status: response.status,
          responseURL: response.url || url
        };

        try {
          response.clone().text().then((text) => {
            post({ ...finishPayload, ...summarizeJSON(text) });
          }).catch(() => {
            post(finishPayload);
          });
        } catch (_) {
          post(finishPayload);
        }
      };

      const xhrResponseText = (xhr) => {
        try {
          if (!xhr.responseType || xhr.responseType === "text") return xhr.responseText;
          if (xhr.responseType === "json") return JSON.stringify(xhr.response);
        } catch (_) {}

        try {
          if (xhr.response instanceof ArrayBuffer) return { responseBytes: xhr.response.byteLength };
          if (xhr.response instanceof Blob) return { responseBytes: xhr.response.size };
        } catch (_) {}

        return undefined;
      };

      const originalFetch = window.fetch;
      if (typeof originalFetch === "function") {
        window.fetch = function(input, init) {
          const id = requestID();
          const method = (init && init.method) || (input && input.method) || "GET";
          const url = normalizeURL(input);

          post({ event: "start", id, kind: "fetch", method, url });

          return originalFetch.apply(this, arguments).then((response) => {
            finishFetch(id, response, url);
            return response;
          }).catch((error) => {
            post({
              event: "error",
              id,
              error: error && error.message ? error.message : String(error)
            });
            throw error;
          });
        };
      }

      const OriginalXHR = window.XMLHttpRequest;
      if (typeof OriginalXHR === "function") {
        const originalOpen = OriginalXHR.prototype.open;
        const originalSend = OriginalXHR.prototype.send;

        OriginalXHR.prototype.open = function(method, url) {
          this.__wkdomainsXHR = {
            method: method || "GET",
            url: normalizeURL(url)
          };

          return originalOpen.apply(this, arguments);
        };

        OriginalXHR.prototype.send = function() {
          const info = this.__wkdomainsXHR || {};
          const id = requestID();
          info.id = id;

          post({
            event: "start",
            id,
            kind: "xmlhttprequest",
            method: info.method || "GET",
            url: info.url || ""
          });

          this.addEventListener("loadend", () => {
            const body = xhrResponseText(this);
            const bodySummary = typeof body === "string"
              ? summarizeJSON(body)
              : (body || {});

            post({
              event: "finish",
              id,
              status: this.status,
              responseURL: this.responseURL || info.url || "",
              ...bodySummary
            });
          }, { once: true });

          this.addEventListener("error", () => {
            post({ event: "error", id, error: "XMLHttpRequest error" });
          }, { once: true });

          this.addEventListener("abort", () => {
            post({ event: "error", id, error: "XMLHttpRequest aborted" });
          }, { once: true });

          return originalSend.apply(this, arguments);
        };
      }
    })();
    """

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

    static let forcedDarkModeScript = """
    (() => {
      if (window.__wkdomainsDarkModeInstalled) return;
      window.__wkdomainsDarkModeInstalled = true;

      const STYLE_ID = "wkdomains-forced-dark-style";
      const ROOT_ATTRIBUTE = "data-wkdomains-forced-dark";
      const READY_ATTRIBUTE = "data-wkdomains-forced-dark-ready";
      const SAMPLING_ATTRIBUTE = "data-wkdomains-forced-dark-sampling";
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
      const BORDER_PROPERTIES = [
        "borderTopColor", "borderRightColor", "borderBottomColor", "borderLeftColor",
        "outlineColor", "columnRuleColor", "textDecorationColor"
      ];

      let forced = null;
      let scheduled = false;
      let applying = false;
      let observer = null;
      let readyFinalized = false;
      let readyFallbackTimer = null;
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

      const transformBackground = (color, element = null) => {
        if (!color || color.a < 0.05) return null;
        const luminance = relativeLuminance(color);
        if (luminance < 0.18) return toRGBA(color);

        const hsl = rgbToHSL(color);
        const neutral = hsl.s < 0.16 || (hsl.l > 0.76 && hsl.h > 35 && hsl.h < 90) || (hsl.l > 0.82 && hsl.h > 200 && hsl.h < 280);
        const largeSurface = element && viewportShare(element) > 0.24;

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
        return darkShare >= 0.65 && average < 0.42;
      };

      const ensureBaseStyle = () => {
        if (!document.documentElement) return;
        document.documentElement.setAttribute(ROOT_ATTRIBUTE, "true");

        if (document.getElementById(STYLE_ID)) return;

        const style = document.createElement("style");
        style.id = STYLE_ID;
        style.textContent = `
          :root[${ROOT_ATTRIBUTE}] {
            color-scheme: dark !important;
          }
          :root[${ROOT_ATTRIBUTE}],
          :root[${ROOT_ATTRIBUTE}] body {
            background: ${toRGBA(DEFAULT_BACKGROUND)} !important;
            color: ${toRGBA(DEFAULT_TEXT)} !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) body,
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) body :not(iframe):not(img):not(picture):not(video):not(canvas):not(svg):not(path) {
            background-color: ${toRGBA(DEFAULT_BACKGROUND)} !important;
            color: ${toRGBA(DEFAULT_TEXT)} !important;
            border-color: ${toRGBA(DEFAULT_BORDER)} !important;
            transition-property: color, background-color, border-color, outline-color, box-shadow !important;
            transition-duration: 0s !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) a {
            color: ${toRGBA(DEFAULT_TEXT)} !important;
          }
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [bgcolor] :not(iframe):not(img):not(picture):not(video):not(canvas):not(svg):not(path) {
            background-color: transparent !important;
          }
          :root[${ROOT_ATTRIBUTE}] input,
          :root[${ROOT_ATTRIBUTE}] textarea,
          :root[${ROOT_ATTRIBUTE}] select,
          :root[${ROOT_ATTRIBUTE}] button {
            color-scheme: dark !important;
          }
          :root[${ROOT_ATTRIBUTE}] ::selection {
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

      const applyElement = (element) => {
        if (shouldSkipElement(element)) return;

        const style = getComputedStyle(element);
        const tag = element.tagName.toUpperCase();

        if (tag === "HTML" || tag === "BODY") {
          element.style.setProperty("background-color", toRGBA(DEFAULT_BACKGROUND), "important");
          element.style.setProperty("color", toRGBA(DEFAULT_TEXT), "important");
          return;
        }

        if (!SVG_TAGS.has(tag)) {
          const color = transformForeground(parseColor(style.color), element);
          if (color) element.style.setProperty("color", color, "important");
        }

        const background = parseColor(style.backgroundColor);
        const backgroundLuminance = background ? relativeLuminance(background) : 0;
          const transformedBackground = transformBackground(background, element);
        if (transformedBackground && background.a > 0.08) {
          element.style.setProperty("background-color", transformedBackground, "important");
        }

        if (style.backgroundImage && style.backgroundImage.includes("gradient") && backgroundLuminance > 0.46) {
          element.style.setProperty("background-image", "none", "important");
        }

        for (const property of BORDER_PROPERTIES) {
          const border = transformBorder(parseColor(style[property]));
          if (border) element.style.setProperty(property, border, "important");
        }

        if (SVG_TAGS.has(tag)) {
          const fill = parseColor(style.fill);
          const stroke = parseColor(style.stroke);
          if (fill && relativeLuminance(fill) < 0.52) {
            element.style.setProperty("fill", transformForeground(fill, element), "important");
          }
          if (stroke && relativeLuminance(stroke) < 0.52) {
            element.style.setProperty("stroke", transformForeground(stroke, element), "important");
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
            return;
          }
        }

        applying = true;
        ensureBaseStyle();
        withFallbackDisabled(() => applyRoot(document));
        finalizeReadyWhenUseful();
        window.setTimeout(() => {
          applying = false;
        }, 0);
      };

      const schedule = (delay = 80) => {
        if (scheduled) return;
        scheduled = true;
        window.setTimeout(run, delay);
      };

      const observe = () => {
        if (observer || !document.documentElement || !window.MutationObserver) {
          return;
        }

        observer = new MutationObserver(() => {
          const nextDelay = forced === null ? 0 : 35;
          if (!applying) schedule(nextDelay);
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

      ensureBaseStyle();
      observe();
      if (document.readyState === "loading") {
        schedule(0);
      } else {
        schedule(0);
      }
    })();
    """

    static let consoleTrackingScript = """
    (() => {
      if (window.__wkdomainsConsoleInstalled) return;
      window.__wkdomainsConsoleInstalled = true;

      const stringify = (value) => {
        try {
          if (typeof value === "string") return value;
          if (value instanceof Error) return value.stack || value.message || String(value);
          if (value === undefined) return "undefined";
          return JSON.stringify(value);
        } catch (_) {
          try { return String(value); } catch (_) { return "[unprintable]"; }
        }
      };

      const post = (level, values, stack) => {
        const args = Array.from(values || []).map(stringify).map((text) => {
          if (text.length > 1200) return `${text.slice(0, 1200)}...`;
          return text;
        });

        try {
          window.webkit.messageHandlers.wkdomainsConsole.postMessage({
            level,
            arguments: args,
            message: args.join(" "),
            stack: stack || undefined,
            pageURL: location.href,
            pageHost: location.hostname
          });
        } catch (_) {}
      };

      ["debug", "error", "info", "log", "warn"].forEach((level) => {
        const original = console[level];
        if (typeof original !== "function") return;

        try {
          Object.defineProperty(console, level, {
            configurable: true,
            writable: true,
            value: function() {
              post(level, arguments);
              return original.apply(this, arguments);
            }
          });
        } catch (_) {
          console[level] = function() {
            post(level, arguments);
            return original.apply(this, arguments);
          };
        }
      });

      const originalAssert = console.assert;
      if (typeof originalAssert === "function") {
        try {
          Object.defineProperty(console, "assert", {
            configurable: true,
            writable: true,
            value: function(condition) {
              if (!condition) {
                post("error", Array.prototype.slice.call(arguments, 1));
              }

              return originalAssert.apply(this, arguments);
            }
          });
        } catch (_) {}
      }

      window.addEventListener("error", (event) => {
        post("error", [event.message || "Window error"], event.error && event.error.stack);
      });

      window.addEventListener("unhandledrejection", (event) => {
        post("error", ["Unhandled promise rejection", event.reason], event.reason && event.reason.stack);
      });

      document.addEventListener("securitypolicyviolation", (event) => {
        post("warn", [
          "Content Security Policy violation",
          event.violatedDirective,
          event.blockedURI
        ]);
      });
    })();
    """
}
