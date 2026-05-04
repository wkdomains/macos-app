//
//  BrowserDarkModeColorScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeColorScript = #"""
      const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
      const scale = (value, inLow, inHigh, outLow, outHigh) => outLow + ((value - inLow) / (inHigh - inLow)) * (outHigh - outLow);
      const colorParseCache = new Map();
      const colorProbe = document.createElement("span");

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

      const parseRGBLike = (value) => {
        if (!value || value === "transparent" || value === "none" || value === "currentcolor") return null;

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

      const normalizeColor = (value) => {
        if (!value) return null;
        const text = String(value).trim().toLowerCase();
        if (!text || text.includes("var(") || text.includes("calc(") || text === "currentcolor") return null;
        if (colorParseCache.has(text)) return colorParseCache.get(text);

        let normalized = null;
        try {
          colorProbe.style.color = "";
          colorProbe.style.color = text;
          normalized = colorProbe.style.color || null;
        } catch (_) {}

        colorParseCache.set(text, normalized);
        return normalized;
      };

      const parseColor = (value) => {
        const normalized = normalizeColor(value);
        return normalized ? parseRGBLike(normalized) : parseRGBLike(value);
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

        return { h, s, l, a: color.a == null ? 1 : color.a };
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

      const backgroundPole = rgbToHSL(DEFAULT_BACKGROUND);
      const foregroundPole = rgbToHSL(DEFAULT_TEXT);
      const borderPole = rgbToHSL(DEFAULT_BORDER);

      const modifyBackgroundHSL = ({ h, s, l, a }) => {
        const isDark = l < 0.5;
        const isBlue = h > 200 && h < 280;
        const isNeutral = s < 0.12 || (l > 0.8 && isBlue);
        if (isDark) {
          const lx = scale(l, 0, 0.5, 0, 0.4);
          return isNeutral ? { h: backgroundPole.h, s: backgroundPole.s, l: lx, a } : { h, s, l: lx, a };
        }

        let hx = h;
        let lx = scale(l, 0.5, 1, 0.4, backgroundPole.l);
        if (isNeutral) {
          return { h: backgroundPole.h, s: backgroundPole.s, l: lx, a };
        }

        const isYellow = h > 60 && h < 180;
        if (isYellow) {
          hx = h > 120 ? scale(h, 120, 180, 135, 180) : scale(h, 60, 120, 60, 105);
        }
        if (hx > 40 && hx < 80) {
          lx *= 0.75;
        }
        return { h: hx, s: clamp(s * 0.9, 0, 0.82), l: lx, a };
      };

      const modifyForegroundHSL = ({ h, s, l, a }) => {
        const isLight = l > 0.5;
        const isNeutral = l < 0.2 || s < 0.24;
        const isBlue = !isNeutral && h > 205 && h < 245;
        const minLightness = 0.55;

        if (isLight) {
          const lx = scale(l, 0.5, 1, minLightness, foregroundPole.l);
          if (isNeutral) {
            return { h: foregroundPole.h, s: foregroundPole.s, l: lx, a };
          }
          return { h: isBlue ? scale(h, 205, 245, 205, 220) : h, s, l: lx, a };
        }

        if (isNeutral) {
          return {
            h: foregroundPole.h,
            s: foregroundPole.s,
            l: scale(l, 0, 0.5, foregroundPole.l, minLightness),
            a
          };
        }

        return {
          h: isBlue ? scale(h, 205, 245, 205, 220) : h,
          s: clamp(s * 0.9, 0.20, 0.80),
          l: scale(l, 0, 0.5, foregroundPole.l, Math.min(1, minLightness + 0.05)),
          a
        };
      };

      const modifyBorderHSL = ({ h, s, l, a }) => {
        const isDark = l < 0.5;
        const isNeutral = l < 0.2 || s < 0.24;
        let hx = h;
        let sx = s;

        if (isNeutral) {
          hx = isDark ? foregroundPole.h : backgroundPole.h;
          sx = isDark ? foregroundPole.s : backgroundPole.s;
        }

        return { h: hx, s: sx, l: scale(l, 0, 1, 0.5, borderPole.l), a };
      };

      const modifyBackgroundColor = (color) => {
        if (!color || color.a < 0.05) return null;
        return toRGBA(hslToRGB(modifyBackgroundHSL(rgbToHSL(color))));
      };

      const modifyForegroundColor = (color) => {
        if (!color || color.a < 0.05) return null;
        return toRGBA(hslToRGB(modifyForegroundHSL(rgbToHSL(color))));
      };

      const modifyBorderColor = (color) => {
        if (!color || color.a < 0.05) return null;
        return toRGBA(hslToRGB(modifyBorderHSL(rgbToHSL(color))));
      };

      const transformBackground = (color, element = null) => {
        if (!color || color.a < 0.05) return null;
        if (relativeLuminance(color) < 0.10) return toRGBA(mix(color, DEFAULT_BACKGROUND, 0.18));
        return modifyBackgroundColor(color);
      };

      const transformForeground = (color) => {
        if (!color || color.a < 0.05) return null;
        if (relativeLuminance(color) > 0.62) return toRGBA(color);
        return modifyForegroundColor(color);
      };

      const transformBorder = (color) => {
        if (!color || color.a < 0.05) return null;
        return modifyBorderColor(color);
      };

      const replaceCSSColors = (value, transformer) => {
        if (!value || !COLOR_RE.test(value)) {
          COLOR_RE.lastIndex = 0;
          return value;
        }
        COLOR_RE.lastIndex = 0;
        return String(value).replace(COLOR_RE, (match) => {
          const color = parseColor(match);
          return color ? (transformer(color) || match) : match;
        });
      };

      const transformBoxShadow = (value) => {
        if (!value || value === "none") return null;
        return replaceCSSColors(value, modifyBackgroundColor);
      };
    """#
}
