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
      const COLOR_LITERAL_RE = /#[0-9a-f]{3,8}\b|\b[a-z][-_a-z0-9]*\b/gi;
      const CSS_COLOR_FUNCTION_NAMES = [
        "color-mix",
        "light-dark",
        "oklab",
        "oklch",
        "rgba",
        "rgb",
        "hsla",
        "hsl",
        "hwb",
        "lab",
        "lch",
        "color"
      ];
      const NAMED_COLORS = {
        aliceblue: { r: 240, g: 248, b: 255, a: 1 },
        antiquewhite: { r: 250, g: 235, b: 215, a: 1 },
        aqua: { r: 0, g: 255, b: 255, a: 1 },
        aquamarine: { r: 127, g: 255, b: 212, a: 1 },
        azure: { r: 240, g: 255, b: 255, a: 1 },
        beige: { r: 245, g: 245, b: 220, a: 1 },
        bisque: { r: 255, g: 228, b: 196, a: 1 },
        black: { r: 0, g: 0, b: 0, a: 1 },
        blue: { r: 0, g: 0, b: 255, a: 1 },
        brown: { r: 165, g: 42, b: 42, a: 1 },
        coral: { r: 255, g: 127, b: 80, a: 1 },
        crimson: { r: 220, g: 20, b: 60, a: 1 },
        cyan: { r: 0, g: 255, b: 255, a: 1 },
        fuchsia: { r: 255, g: 0, b: 255, a: 1 },
        gold: { r: 255, g: 215, b: 0, a: 1 },
        gray: { r: 128, g: 128, b: 128, a: 1 },
        green: { r: 0, g: 128, b: 0, a: 1 },
        grey: { r: 128, g: 128, b: 128, a: 1 },
        indigo: { r: 75, g: 0, b: 130, a: 1 },
        ivory: { r: 255, g: 255, b: 240, a: 1 },
        khaki: { r: 240, g: 230, b: 140, a: 1 },
        lavender: { r: 230, g: 230, b: 250, a: 1 },
        lime: { r: 0, g: 255, b: 0, a: 1 },
        magenta: { r: 255, g: 0, b: 255, a: 1 },
        maroon: { r: 128, g: 0, b: 0, a: 1 },
        navy: { r: 0, g: 0, b: 128, a: 1 },
        olive: { r: 128, g: 128, b: 0, a: 1 },
        orange: { r: 255, g: 165, b: 0, a: 1 },
        orchid: { r: 218, g: 112, b: 214, a: 1 },
        pink: { r: 255, g: 192, b: 203, a: 1 },
        plum: { r: 221, g: 160, b: 221, a: 1 },
        purple: { r: 128, g: 0, b: 128, a: 1 },
        red: { r: 255, g: 0, b: 0, a: 1 },
        salmon: { r: 250, g: 128, b: 114, a: 1 },
        silver: { r: 192, g: 192, b: 192, a: 1 },
        tan: { r: 210, g: 180, b: 140, a: 1 },
        teal: { r: 0, g: 128, b: 128, a: 1 },
        tomato: { r: 255, g: 99, b: 71, a: 1 },
        transparent: { r: 0, g: 0, b: 0, a: 0 },
        violet: { r: 238, g: 130, b: 238, a: 1 },
        white: { r: 255, g: 255, b: 255, a: 1 },
        yellow: { r: 255, g: 255, b: 0, a: 1 }
      };
      const CSS_NAMED_COLOR_KEYWORDS = new Set([
        "aliceblue", "antiquewhite", "aqua", "aquamarine", "azure",
        "beige", "bisque", "black", "blanchedalmond", "blue", "blueviolet", "brown", "burlywood",
        "cadetblue", "chartreuse", "chocolate", "coral", "cornflowerblue", "cornsilk", "crimson", "cyan",
        "darkblue", "darkcyan", "darkgoldenrod", "darkgray", "darkgreen", "darkgrey", "darkkhaki", "darkmagenta",
        "darkolivegreen", "darkorange", "darkorchid", "darkred", "darksalmon", "darkseagreen", "darkslateblue",
        "darkslategray", "darkslategrey", "darkturquoise", "darkviolet", "deeppink", "deepskyblue", "dimgray",
        "dimgrey", "dodgerblue", "firebrick", "floralwhite", "forestgreen", "fuchsia",
        "gainsboro", "ghostwhite", "gold", "goldenrod", "gray", "green", "greenyellow", "grey",
        "honeydew", "hotpink", "indianred", "indigo", "ivory",
        "khaki", "lavender", "lavenderblush", "lawngreen", "lemonchiffon", "lightblue", "lightcoral",
        "lightcyan", "lightgoldenrodyellow", "lightgray", "lightgreen", "lightgrey", "lightpink", "lightsalmon",
        "lightseagreen", "lightskyblue", "lightslategray", "lightslategrey", "lightsteelblue", "lightyellow",
        "lime", "limegreen", "linen",
        "magenta", "maroon", "mediumaquamarine", "mediumblue", "mediumorchid", "mediumpurple", "mediumseagreen",
        "mediumslateblue", "mediumspringgreen", "mediumturquoise", "mediumvioletred", "midnightblue", "mintcream",
        "mistyrose", "moccasin",
        "navajowhite", "navy",
        "oldlace", "olive", "olivedrab", "orange", "orangered", "orchid",
        "palegoldenrod", "palegreen", "paleturquoise", "palevioletred", "papayawhip", "peachpuff", "peru",
        "pink", "plum", "powderblue", "purple",
        "rebeccapurple", "red", "rosybrown", "royalblue",
        "saddlebrown", "salmon", "sandybrown", "seagreen", "seashell", "sienna", "silver", "skyblue",
        "slateblue", "slategray", "slategrey", "snow", "springgreen", "steelblue",
        "tan", "teal", "thistle", "tomato", "transparent", "turquoise",
        "violet",
        "wheat", "white", "whitesmoke",
        "yellow", "yellowgreen"
      ]);

      const isColorLiteralToken = (token) => {
        const value = String(token || "").trim().toLowerCase();
        return value.startsWith("#") || CSS_NAMED_COLOR_KEYWORDS.has(value);
      };

      const parseComponent = (value, isAlpha = false, scaleUnitInterval = false) => {
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
        return clamp(scaleUnitInterval && parsed <= 1 ? parsed * 255 : parsed, 0, 255);
      };

      const parseUnitColorComponent = (value) => {
        const token = String(value || "").trim().toLowerCase();
        if (token === "none") return 0;
        const parsed = Number.parseFloat(token);
        if (!Number.isFinite(parsed)) return 0;
        return token.endsWith("%") ? clamp(parsed / 100, 0, 1) : clamp(parsed, 0, 1);
      };

      const parseRGBLike = (value) => {
        if (!value || value === "transparent" || value === "none" || value === "currentcolor") return null;

        const text = String(value).trim().toLowerCase();
        const open = text.indexOf("(");
        const close = text.lastIndexOf(")");
        if (open < 0 || close <= open) return null;

        const functionName = text.slice(0, open);
        if (!["rgb", "rgba"].includes(functionName)) return null;

        const parts = text
          .slice(open + 1, close)
          .replaceAll(",", " ")
          .replaceAll("/", " ")
          .split(" ")
          .map((part) => part.trim())
          .filter(Boolean);

        if (parts.length < 3) return null;

        return {
          r: parseComponent(parts[0]),
          g: parseComponent(parts[1]),
          b: parseComponent(parts[2]),
          a: parseComponent(parts[3], true)
        };
      };

      const parseHue = (value) => {
        const token = String(value || "").trim().toLowerCase();
        const parsed = Number.parseFloat(token);
        if (!Number.isFinite(parsed)) return 0;
        if (token.endsWith("turn")) return parsed * 360;
        if (token.endsWith("rad")) return parsed * 180 / Math.PI;
        if (token.endsWith("grad")) return parsed * 0.9;
        return parsed;
      };

      const parseHSLLike = (value) => {
        if (!value) return null;
        const text = String(value).trim().toLowerCase();
        const match = text.match(/^hsla?\((.*)\)$/);
        if (!match) return null;
        const parts = match[1]
          .replaceAll(",", " ")
          .replaceAll("/", " ")
          .split(" ")
          .map((part) => part.trim())
          .filter(Boolean);
        if (parts.length < 3) return null;
        return hslToRGB({
          h: parseHue(parts[0]),
          s: clamp(Number.parseFloat(parts[1]) / 100, 0, 1),
          l: clamp(Number.parseFloat(parts[2]) / 100, 0, 1),
          a: parseComponent(parts[3], true)
        });
      };

      const parseHWBLike = (value) => {
        if (!value) return null;
        const text = String(value).trim().toLowerCase();
        const match = text.match(/^hwb\((.*)\)$/);
        if (!match) return null;
        const parts = match[1]
          .replaceAll(",", " ")
          .replaceAll("/", " ")
          .split(" ")
          .map((part) => part.trim())
          .filter(Boolean);
        if (parts.length < 3) return null;
        const hueColor = hslToRGB({ h: parseHue(parts[0]), s: 1, l: 0.5, a: 1 });
        let white = clamp(Number.parseFloat(parts[1]) / 100, 0, 1);
        let black = clamp(Number.parseFloat(parts[2]) / 100, 0, 1);
        if (white + black > 1) {
          const total = white + black;
          white /= total;
          black /= total;
        }
        const factor = 1 - white - black;
        return {
          r: hueColor.r * factor + white * 255,
          g: hueColor.g * factor + white * 255,
          b: hueColor.b * factor + white * 255,
          a: parseComponent(parts[3], true)
        };
      };

      const parseColorFunctionTokens = (value, names) => {
        if (!value) return null;
        const text = String(value).trim().toLowerCase();
        const open = text.indexOf("(");
        const close = text.lastIndexOf(")");
        if (open < 0 || close <= open) return null;
        const name = text.slice(0, open);
        if (!names.includes(name)) return null;
        const tokens = text
          .slice(open + 1, close)
          .replaceAll(",", " ")
          .replaceAll("/", " ")
          .split(/\s+/)
          .map((part) => part.trim())
          .filter(Boolean);
        return { name, tokens };
      };

      const parseLightness = (token, scaleValue) => {
        const value = String(token || "").trim().toLowerCase();
        if (value === "none") return 0;
        const parsed = Number.parseFloat(value);
        if (!Number.isFinite(parsed)) return 0;
        return value.endsWith("%") ? clamp(parsed / 100, 0, 1) * scaleValue : parsed;
      };

      const parseAxis = (token, percentScale = 1) => {
        const value = String(token || "").trim().toLowerCase();
        if (value === "none") return 0;
        const parsed = Number.parseFloat(value);
        if (!Number.isFinite(parsed)) return 0;
        return value.endsWith("%") ? parsed / 100 * percentScale : parsed;
      };

      const linearRGBToSRGB = (value) => {
        const channel = value <= 0.0031308
          ? 12.92 * value
          : 1.055 * Math.pow(Math.max(0, value), 1 / 2.4) - 0.055;
        return clamp(channel * 255, 0, 255);
      };

      const sRGBToLinear = (value) => {
        const normalized = clamp(value, 0, 1);
        return normalized <= 0.04045
          ? normalized / 12.92
          : Math.pow((normalized + 0.055) / 1.055, 2.4);
      };

      const xyzD50ToSRGB = ({ x, y, z, a }) => {
        const x65 = 0.9555766 * x - 0.0230393 * y + 0.0631636 * z;
        const y65 = -0.0282895 * x + 1.0099416 * y + 0.0210077 * z;
        const z65 = 0.0122982 * x - 0.0204830 * y + 1.3299098 * z;
        return {
          r: linearRGBToSRGB(3.2404542 * x65 - 1.5371385 * y65 - 0.4985314 * z65),
          g: linearRGBToSRGB(-0.9692660 * x65 + 1.8760108 * y65 + 0.0415560 * z65),
          b: linearRGBToSRGB(0.0556434 * x65 - 0.2040259 * y65 + 1.0572252 * z65),
          a
        };
      };

      const labToSRGB = ({ l, a: axisA, b: axisB, alpha }) => {
        const fy = (l + 16) / 116;
        const fx = fy + axisA / 500;
        const fz = fy - axisB / 200;
        const delta = 6 / 29;
        const convert = (value) => value > delta
          ? value * value * value
          : 3 * delta * delta * (value - 4 / 29);
        return xyzD50ToSRGB({
          x: 0.96422 * convert(fx),
          y: convert(fy),
          z: 0.82521 * convert(fz),
          a: alpha
        });
      };

      const oklabToSRGB = ({ l, a: axisA, b: axisB, alpha }) => {
        const lPrime = l + 0.3963377774 * axisA + 0.2158037573 * axisB;
        const mPrime = l - 0.1055613458 * axisA - 0.0638541728 * axisB;
        const sPrime = l - 0.0894841775 * axisA - 1.2914855480 * axisB;
        const lCube = lPrime * lPrime * lPrime;
        const mCube = mPrime * mPrime * mPrime;
        const sCube = sPrime * sPrime * sPrime;
        return {
          r: linearRGBToSRGB(4.0767416621 * lCube - 3.3077115913 * mCube + 0.2309699292 * sCube),
          g: linearRGBToSRGB(-1.2684380046 * lCube + 2.6097574011 * mCube - 0.3413193965 * sCube),
          b: linearRGBToSRGB(-0.0041960863 * lCube - 0.7034186147 * mCube + 1.7076147010 * sCube),
          a: alpha
        };
      };

      const xyzD65ToSRGB = ({ x, y, z, a }) => ({
        r: linearRGBToSRGB(3.2404542 * x - 1.5371385 * y - 0.4985314 * z),
        g: linearRGBToSRGB(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z),
        b: linearRGBToSRGB(0.0556434 * x - 0.2040259 * y + 1.0572252 * z),
        a
      });

      const parseColorSpaceFunction = (value) => {
        const parsed = parseColorFunctionTokens(value, ["color"]);
        if (!parsed || parsed.tokens.length < 4) return null;
        const space = parsed.tokens[0];
        const c1 = parseUnitColorComponent(parsed.tokens[1]);
        const c2 = parseUnitColorComponent(parsed.tokens[2]);
        const c3 = parseUnitColorComponent(parsed.tokens[3]);
        const alpha = parseComponent(parsed.tokens[4], true);

        if (space === "srgb") {
          return { r: c1 * 255, g: c2 * 255, b: c3 * 255, a: alpha };
        }
        if (space === "srgb-linear") {
          return {
            r: linearRGBToSRGB(c1),
            g: linearRGBToSRGB(c2),
            b: linearRGBToSRGB(c3),
            a: alpha
          };
        }
        if (space === "display-p3") {
          const r = sRGBToLinear(c1);
          const g = sRGBToLinear(c2);
          const b = sRGBToLinear(c3);
          return xyzD65ToSRGB({
            x: 0.48657095 * r + 0.26566769 * g + 0.19821729 * b,
            y: 0.22897456 * r + 0.69173852 * g + 0.07928691 * b,
            z: 0.00000000 * r + 0.04511338 * g + 1.04394437 * b,
            a: alpha
          });
        }
        return null;
      };

      const parseLabLike = (value) => {
        const parsed = parseColorFunctionTokens(value, ["lab", "oklab"]);
        if (!parsed || parsed.tokens.length < 3) return null;
        if (parsed.name === "oklab") {
          return oklabToSRGB({
            l: clamp(parseLightness(parsed.tokens[0], 1), 0, 1),
            a: parseAxis(parsed.tokens[1], 0.4),
            b: parseAxis(parsed.tokens[2], 0.4),
            alpha: parseComponent(parsed.tokens[3], true)
          });
        }
        return labToSRGB({
          l: clamp(parseLightness(parsed.tokens[0], 100), 0, 100),
          a: parseAxis(parsed.tokens[1], 125),
          b: parseAxis(parsed.tokens[2], 125),
          alpha: parseComponent(parsed.tokens[3], true)
        });
      };

      const parseLCHLike = (value) => {
        const parsed = parseColorFunctionTokens(value, ["lch", "oklch"]);
        if (!parsed || parsed.tokens.length < 3) return null;
        const hue = parseHue(parsed.tokens[2]) * Math.PI / 180;
        if (parsed.name === "oklch") {
          const chroma = parseAxis(parsed.tokens[1], 0.4);
          return oklabToSRGB({
            l: clamp(parseLightness(parsed.tokens[0], 1), 0, 1),
            a: chroma * Math.cos(hue),
            b: chroma * Math.sin(hue),
            alpha: parseComponent(parsed.tokens[3], true)
          });
        }
        const chroma = parseAxis(parsed.tokens[1], 150);
        return labToSRGB({
          l: clamp(parseLightness(parsed.tokens[0], 100), 0, 100),
          a: chroma * Math.cos(hue),
          b: chroma * Math.sin(hue),
          alpha: parseComponent(parsed.tokens[3], true)
        });
      };

      const parseHexColor = (value) => {
        const match = String(value || "").trim().toLowerCase().match(/^#([0-9a-f]{3,8})$/);
        if (!match) return null;
        let hex = match[1];
        if (hex.length === 3 || hex.length === 4) {
          hex = Array.from(hex).map((char) => `${char}${char}`).join("");
        }
        if (hex.length !== 6 && hex.length !== 8) return null;
        return {
          r: Number.parseInt(hex.slice(0, 2), 16),
          g: Number.parseInt(hex.slice(2, 4), 16),
          b: Number.parseInt(hex.slice(4, 6), 16),
          a: hex.length === 8 ? Number.parseInt(hex.slice(6, 8), 16) / 255 : 1
        };
      };

      const RAW_COLOR_RE = /^\s*(-?(?:\d+|\d*\.\d+)%?)\s*(?:,|\s)\s*(-?(?:\d+|\d*\.\d+)%?)\s*(?:,|\s)\s*(-?(?:\d+|\d*\.\d+)%?)(?:\s*(?:\/|,)\s*(-?(?:\d+|\d*\.\d+)%?))?\s*$/;

      const parseRawColorValue = (value) => {
        if (!value || String(value).includes("var(") || String(value).includes("calc(")) return null;
        const match = String(value).trim().match(RAW_COLOR_RE);
        if (!match) return null;
        return {
          r: parseComponent(match[1]),
          g: parseComponent(match[2]),
          b: parseComponent(match[3]),
          a: parseComponent(match[4], true)
        };
      };

      const splitTopLevelCSSArguments = (value) => {
        const result = [];
        let start = 0;
        let depth = 0;
        const text = String(value || "");
        for (let index = 0; index < text.length; index += 1) {
          const char = text[index];
          if (char === "(") depth += 1;
          else if (char === ")") depth = Math.max(0, depth - 1);
          else if (char === "," && depth === 0) {
            result.push(text.slice(start, index).trim());
            start = index + 1;
          }
        }
        result.push(text.slice(start).trim());
        return result.filter(Boolean);
      };

      const findTopLevelCSSComma = (value) => {
        const text = String(value || "");
        let depth = 0;
        for (let index = 0; index < text.length; index += 1) {
          const char = text[index];
          if (char === "(") depth += 1;
          else if (char === ")") depth = Math.max(0, depth - 1);
          else if (char === "," && depth === 0) return index;
        }
        return -1;
      };

      const parseColorWithOptionalPercent = (value) => {
        const text = String(value || "").trim();
        const percent = text.match(/\s+(-?(?:\d+|\d*\.\d+)%)\s*$/);
        const colorText = percent ? text.slice(0, percent.index).trim() : text;
        const color = parseColor(colorText);
        if (!color) return null;
        return {
          color,
          weight: percent ? clamp(Number.parseFloat(percent[1]) / 100, 0, 1) : null
        };
      };

      const parseColorMix = (value) => {
        const text = String(value || "").trim();
        const match = text.match(/^color-mix\(([\s\S]*)\)$/i);
        if (!match) return null;
        const body = match[1].trim();
        if (!body.toLowerCase().startsWith("in ")) return null;
        const colorStart = findTopLevelCSSComma(body);
        if (colorStart < 0) return null;
        const parts = splitTopLevelCSSArguments(body.slice(colorStart + 1));
        if (parts.length < 2) return null;
        const first = parseColorWithOptionalPercent(parts[0]);
        const second = parseColorWithOptionalPercent(parts[1]);
        if (!first || !second) return null;
        const firstWeight = first.weight == null && second.weight == null
          ? 0.5
          : (first.weight == null ? 1 - second.weight : first.weight);
        const secondWeight = second.weight == null ? 1 - firstWeight : second.weight;
        const total = Math.max(0.0001, firstWeight + secondWeight);
        return mix(first.color, second.color, secondWeight / total);
      };

      const parseLightDark = (value) => {
        const text = String(value || "").trim();
        const match = text.match(/^light-dark\(([\s\S]*)\)$/i);
        if (!match) return null;
        const parts = splitTopLevelCSSArguments(match[1]);
        if (parts.length < 2) return null;
        return parseColor(parts[1]) || parseColor(parts[0]);
      };

      const replaceRawColorValue = (value, transformer) => {
        const color = parseRawColorValue(value);
        if (!color) return null;
        const transformed = transformer(color);
        if (!transformed) return null;
        const parsed = parseColor(transformed);
        if (!parsed) return transformed;
        const alpha = color.a == null ? 1 : color.a;
        const rawText = String(value || "");
        const r = Math.round(parsed.r);
        const g = Math.round(parsed.g);
        const b = Math.round(parsed.b);
        if (rawText.includes(",") && !rawText.includes("/")) {
          return alpha >= 0.995
            ? `${r}, ${g}, ${b}`
            : `${r}, ${g}, ${b}, ${Math.round(alpha * 1000) / 1000}`;
        }
        return alpha >= 0.995
          ? `${r} ${g} ${b}`
          : `${r} ${g} ${b} / ${Math.round(alpha * 1000) / 1000}`;
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
        const text = String(value || "").trim().toLowerCase();
        const hex = parseHexColor(text);
        if (hex) return hex;
        if (NAMED_COLORS[text]) return NAMED_COLORS[text];
        const hsl = parseHSLLike(text);
        if (hsl) return hsl;
        const hwb = parseHWBLike(text);
        if (hwb) return hwb;
        const lab = parseLabLike(text);
        if (lab) return lab;
        const lch = parseLCHLike(text);
        if (lch) return lch;
        const colorSpace = parseColorSpaceFunction(text);
        if (colorSpace) return colorSpace;
        const mixed = parseColorMix(text);
        if (mixed) return mixed;
        const lightDark = parseLightDark(text);
        if (lightDark) return lightDark;
        const normalized = normalizeColor(value);
        if (normalized) {
          const parsed = parseRGBLike(normalized) || parseHSLLike(normalized) || parseHWBLike(normalized) || parseLabLike(normalized) || parseLCHLike(normalized) || parseColorSpaceFunction(normalized) || parseHexColor(normalized) || NAMED_COLORS[String(normalized).trim().toLowerCase()];
          if (parsed) return parsed;
        }
        return parseRGBLike(value);
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
