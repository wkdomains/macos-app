//
//  BrowserDarkModeColorTransformScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeColorTransformScript = #"""
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
        return modifyColorWithCache("background", color, (value) => toThemeRGBA(hslToRGB(modifyBackgroundHSL(rgbToHSL(value)))));
      };

      const modifyForegroundColor = (color) => {
        if (!color || color.a < 0.05) return null;
        return modifyColorWithCache("text", color, (value) => toThemeRGBA(hslToRGB(modifyForegroundHSL(rgbToHSL(value)))));
      };

      const modifyBorderColor = (color) => {
        if (!color || color.a < 0.05) return null;
        return modifyColorWithCache("border", color, (value) => toThemeRGBA(hslToRGB(modifyBorderHSL(rgbToHSL(value)))));
      };

      const transformBackground = (color, element = null) => {
        if (!color || color.a < 0.05) return null;
        if (relativeLuminance(color) < 0.10) return toThemeRGBA(mix(color, themeBackgroundColor(), 0.18));
        return modifyBackgroundColor(color);
      };

      const transformForeground = (color) => {
        if (!color || color.a < 0.05) return null;
        if (relativeLuminance(color) > 0.62) return toThemeRGBA(color);
        return modifyForegroundColor(color);
      };

      const transformBorder = (color) => {
        if (!color || color.a < 0.05) return null;
        return modifyBorderColor(color);
      };

      const colorFunctionNameAt = (value, index) => {
        const previous = index > 0 ? value[index - 1] : "";
        if (previous && /[-_a-z0-9]/i.test(previous)) return null;
        for (const name of CSS_COLOR_FUNCTION_NAMES) {
          if (value.slice(index, index + name.length).toLowerCase() === name && value[index + name.length] === "(") {
            return name;
          }
        }
        return null;
      };

      const findMatchingParen = (value, openIndex) => {
        let depth = 0;
        for (let index = openIndex; index < value.length; index += 1) {
          const char = value[index];
          if (char === "(") depth += 1;
          else if (char === ")") {
            depth -= 1;
            if (depth === 0) return index;
          }
        }
        return -1;
      };

      const isInsideCSSURL = (value, index) => {
        const text = String(value || "").toLowerCase();
        let searchIndex = text.lastIndexOf("url(", index);
        while (searchIndex >= 0) {
          const close = findMatchingParen(text, searchIndex + 3);
          if (close < 0 || close >= index) return true;
          if (searchIndex === 0) break;
          searchIndex = text.lastIndexOf("url(", searchIndex - 1);
        }
        return false;
      };

      const replaceCSSColorFunctions = (value, transformer) => {
        const text = String(value || "");
        let result = "";
        let index = 0;
        while (index < text.length) {
          const name = colorFunctionNameAt(text, index);
          if (!name) {
            result += text[index];
            index += 1;
            continue;
          }

          const open = index + name.length;
          const close = findMatchingParen(text, open);
          if (close < 0) {
            result += text[index];
            index += 1;
            continue;
          }

          const token = text.slice(index, close + 1);
          const color = parseColor(token);
          result += color ? (transformer(color) || token) : token;
          index = close + 1;
        }
        return result;
      };

      const hasCSSColor = (value) => {
        if (!value) return false;
        const text = String(value);
        COLOR_LITERAL_RE.lastIndex = 0;
        let match = null;
        while ((match = COLOR_LITERAL_RE.exec(text))) {
          if (isColorLiteralToken(match[0]) && !isInsideCSSURL(text, match.index)) {
            COLOR_LITERAL_RE.lastIndex = 0;
            return true;
          }
        }
        COLOR_LITERAL_RE.lastIndex = 0;
        for (let index = 0; index < text.length; index += 1) {
          if (colorFunctionNameAt(text, index)) return true;
        }
        return false;
      };

      const replaceCSSColors = (value, transformer) => {
        if (!hasCSSColor(value)) return value;
        const withFunctions = replaceCSSColorFunctions(value, transformer);
        COLOR_LITERAL_RE.lastIndex = 0;
        return String(withFunctions).replace(COLOR_LITERAL_RE, (match, offset, source) => {
          if (!isColorLiteralToken(match)) return match;
          if (isInsideCSSURL(source, offset)) return match;
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
