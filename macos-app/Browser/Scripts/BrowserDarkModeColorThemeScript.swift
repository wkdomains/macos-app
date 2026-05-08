//
//  BrowserDarkModeColorThemeScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeColorThemeScript = #"""
      const toRGBA = (color) => {
        const r = Math.round(clamp(color.r, 0, 255));
        const g = Math.round(clamp(color.g, 0, 255));
        const b = Math.round(clamp(color.b, 0, 255));
        const a = clamp(color.a == null ? 1 : color.a, 0, 1);
        return a >= 0.995
          ? `rgb(${r}, ${g}, ${b})`
          : `rgba(${r}, ${g}, ${b}, ${Math.round(a * 1000) / 1000})`;
      };

      const themeNumber = (key, fallback, min, max) => {
        const parsed = Number(THEME && THEME[key]);
        if (!Number.isFinite(parsed)) return fallback;
        return clamp(parsed, min, max);
      };

      const themeColor = (key, fallback) => parseColor(THEME && THEME[key]) || fallback;
      const themeBackgroundColor = () => themeColor("darkSchemeBackgroundColor", DEFAULT_BACKGROUND);
      const themeTextColor = () => themeColor("darkSchemeTextColor", DEFAULT_TEXT);
      const themeBorderColor = () => {
        const background = themeBackgroundColor();
        const text = themeTextColor();
        return mix(background, text, 0.18);
      };
      const themeSelectionBackgroundColor = () => {
        const background = themeBackgroundColor();
        const text = themeTextColor();
        return mix(background, text, 0.34);
      };
      const themeSelectionTextColor = () => themeTextColor();

      const themeFilterCacheKey = () => [
        themeNumber("brightness", 100, 50, 150),
        themeNumber("contrast", 100, 50, 150),
        themeNumber("sepia", 0, 0, 100),
        themeNumber("grayscale", 0, 0, 100)
      ].join(":");

      const themeInversionFilterValue = (contrastOffset = 0, maxContrast = 200) => {
        const filters = [];
        if (Number(THEME.mode) === 1) {
          filters.push("invert(100%) hue-rotate(180deg)");
        }
        const brightness = themeNumber("brightness", 100, 50, 150);
        const contrast = clamp(themeNumber("contrast", 100, 50, 150) + contrastOffset, 0, maxContrast);
        const grayscale = themeNumber("grayscale", 0, 0, 100);
        const sepia = themeNumber("sepia", 0, 0, 100);
        if (brightness !== 100) filters.push(`brightness(${brightness}%)`);
        if (contrast !== 100) filters.push(`contrast(${contrast}%)`);
        if (grayscale !== 0) filters.push(`grayscale(${grayscale}%)`);
        if (sepia !== 0) filters.push(`sepia(${sepia}%)`);
        return filters.length > 0 ? filters.join(" ") : null;
      };

      const applyThemeColorAdjustments = (color) => {
        if (!color) return null;
        const brightness = themeNumber("brightness", 100, 50, 150) / 100;
        const contrast = themeNumber("contrast", 100, 50, 150) / 100;
        const sepia = themeNumber("sepia", 0, 0, 100) / 100;
        const grayscale = themeNumber("grayscale", 0, 0, 100) / 100;

        let r = clamp(color.r, 0, 255);
        let g = clamp(color.g, 0, 255);
        let b = clamp(color.b, 0, 255);

        if (grayscale > 0) {
          const gray = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          r = r * (1 - grayscale) + gray * grayscale;
          g = g * (1 - grayscale) + gray * grayscale;
          b = b * (1 - grayscale) + gray * grayscale;
        }

        if (sepia > 0) {
          const sr = clamp(0.393 * r + 0.769 * g + 0.189 * b, 0, 255);
          const sg = clamp(0.349 * r + 0.686 * g + 0.168 * b, 0, 255);
          const sb = clamp(0.272 * r + 0.534 * g + 0.131 * b, 0, 255);
          r = r * (1 - sepia) + sr * sepia;
          g = g * (1 - sepia) + sg * sepia;
          b = b * (1 - sepia) + sb * sepia;
        }

        r = ((r / 255 - 0.5) * contrast + 0.5) * 255 * brightness;
        g = ((g / 255 - 0.5) * contrast + 0.5) * 255 * brightness;
        b = ((b / 255 - 0.5) * contrast + 0.5) * 255 * brightness;

        return {
          r: clamp(r, 0, 255),
          g: clamp(g, 0, 255),
          b: clamp(b, 0, 255),
          a: color.a == null ? 1 : color.a
        };
      };

      const toThemeRGBA = (color) => toRGBA(applyThemeColorAdjustments(color));

      const themeDebugStatus = () => ({
        mode: THEME.mode,
        brightness: themeNumber("brightness", 100, 50, 150),
        contrast: themeNumber("contrast", 100, 50, 150),
        sepia: themeNumber("sepia", 0, 0, 100),
        grayscale: themeNumber("grayscale", 0, 0, 100),
        darkSchemeBackgroundColor: THEME.darkSchemeBackgroundColor,
        darkSchemeTextColor: THEME.darkSchemeTextColor
      });

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

      const colorCacheKey = (color) => {
        const r = Math.round(clamp(color.r, 0, 255));
        const g = Math.round(clamp(color.g, 0, 255));
        const b = Math.round(clamp(color.b, 0, 255));
        const a = Math.round(clamp(color.a == null ? 1 : color.a, 0, 1) * 1000);
        return `${r},${g},${b},${a}`;
      };

      const colorVariableID = (color) => {
        const channel = (value) => Math.round(clamp(value, 0, 255)).toString(16).padStart(2, "0");
        const alpha = Math.round(clamp(color.a == null ? 1 : color.a, 0, 1) * 255);
        return `${channel(color.r)}${channel(color.g)}${channel(color.b)}${alpha < 255 ? channel(alpha) : ""}`;
      };

      const scheduleRegisteredColorStyleUpdate = () => {
        if (registeredColorStyleUpdateScheduled) return;
        registeredColorStyleUpdateScheduled = true;
        queueMicrotask(() => {
          registeredColorStyleUpdateScheduled = false;
          try {
            const style = findStaticStyle("wkdomains-darkreader--variables", document);
            if (style) style.textContent = getVariablesStyle();
          } catch (_) {}
        });
      };

      const registeredColorDeclarations = () => {
        const declarations = [];
        for (const registered of registeredColors.values()) {
          for (const key of ["background", "text", "border"]) {
            const entry = registered[key];
            if (entry) declarations.push(`  ${entry.variable}: ${entry.value};`);
          }
        }
        return declarations;
      };

      const registeredColorStats = () => {
        let background = 0;
        let text = 0;
        let border = 0;
        for (const registered of registeredColors.values()) {
          if (registered.background) background += 1;
          if (registered.text) text += 1;
          if (registered.border) border += 1;
        }
        return { unique: registeredColors.size, background, text, border };
      };

      const modifyColorWithCache = (type, color, modifier) => {
        if (!color) return null;
        const key = `${themeFilterCacheKey()}:${type}:${colorCacheKey(color)}`;
        if (modifiedColorCache.has(key)) return modifiedColorCache.get(key);

        const value = modifier(color);
        if (!value) {
          modifiedColorCache.set(key, null);
          return null;
        }

        const sourceKey = colorCacheKey(color);
        let registered = registeredColors.get(sourceKey);
        if (!registered) {
          registered = { parsed: { ...color } };
          registeredColors.set(sourceKey, registered);
        }

        const variable = `--darkreader-${type}-${colorVariableID(color)}`;
        registered[type] = { variable, value };
        const result = `var(${variable}, ${value})`;
        modifiedColorCache.set(key, result);
        scheduleRegisteredColorStyleUpdate();
        return result;
      };

      const backgroundPole = rgbToHSL(themeBackgroundColor());
      const foregroundPole = rgbToHSL(themeTextColor());
      const borderPole = rgbToHSL(themeBorderColor());
    """#
}
