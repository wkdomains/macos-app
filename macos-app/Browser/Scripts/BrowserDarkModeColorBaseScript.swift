//
//  BrowserDarkModeColorBaseScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeColorBaseScript = #"""
      const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
      const scale = (value, inLow, inHigh, outLow, outHigh) => outLow + ((value - inLow) / (inHigh - inLow)) * (outHigh - outLow);
      const colorParseCache = new Map();
      const modifiedColorCache = new Map();
      const registeredColors = new Map();
      let registeredColorStyleUpdateScheduled = false;
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
    """#
}
