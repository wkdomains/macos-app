//
//  BrowserDarkModeInlineDOMScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeInlineDOMScript = #"""
      const discoveredShadowRoots = new Set();
      const sourceStyleCache = new WeakMap();
      const inlineStyleCache = new WeakMap();

      const setOverride = (element, attribute, property, value) => {
        if (!value) {
          element.removeAttribute(attribute);
          element.style.removeProperty(property);
          return;
        }

        element.style.setProperty(property, value);
        element.setAttribute(attribute, "");
      };

      const removeGeneratedInlineVariables = (element) => {
        if (!element || !element.style) return;
        const properties = [];
        for (let index = 0; index < element.style.length; index += 1) {
          const property = element.style.item(index);
          if (property && property.startsWith(DARK_VAR_PREFIX)) {
            properties.push(property);
          }
        }
        for (const property of properties) {
          element.style.removeProperty(property);
        }
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

      const viewportShare = (element) => {
        const rect = visibleRectFor(element);
        return rect.area / Math.max(1, innerWidth * innerHeight);
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
          node = node.parentElement || (node.getRootNode && node.getRootNode().host) || null;
        }

        let surface = { r: 255, g: 255, b: 255, a: 1 };
        for (let index = colors.length - 1; index >= 0; index -= 1) {
          surface = composite(colors[index], surface);
        }

        return surface;
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
        if (shouldIgnoreImageAnalysis(element)) return false;

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
          if (shouldIgnoreImageAnalysis(media)) continue;

          const mediaRect = visibleRectFor(media);
          const elementCoverage = mediaRect.area / Math.max(1, elementRect.area);
          const viewportCoverage = mediaRect.area / Math.max(1, innerWidth * innerHeight);
          if (elementCoverage > 0.32 || viewportCoverage > 0.18) {
            return true;
          }
        }

        return false;
      };

      const CONTROL_SELECTOR = "input, textarea, select, button, [contenteditable='true'], [role='textbox']";
      const SVG_SELECTOR = Array.from(SVG_TAGS).map((tag) => tag.toLowerCase()).join(", ");
      const STYLE_OVERRIDE_SELECTOR = [INLINE_STYLE_SELECTOR, CONTROL_SELECTOR, SVG_SELECTOR].join(", ");

      const shouldSkipElement = (element) => {
        if (!element || !element.tagName || SKIP_TAGS.has(element.tagName.toUpperCase())) return true;
        if (element.classList && element.classList.contains(INLINE_CLASS)) return true;
        const style = getComputedStyle(element);
        return style.display === "none";
      };

      const captureSourceStyle = (element) => {
        if (!element || sourceStyleCache.has(element)) {
          return sourceStyleCache.get(element) || null;
        }

        const source = withFallbackDisabled(() => {
          const style = getComputedStyle(element);
          const captured = {
            color: style.color,
            backgroundColor: style.backgroundColor,
            backgroundImage: style.backgroundImage,
            boxShadow: style.boxShadow,
            fill: style.fill,
            stroke: style.stroke
          };

          for (const override of BORDER_OVERRIDES) {
            captured[override.js] = style[override.js];
          }

          return captured;
        });

        sourceStyleCache.set(element, source);
        return source;
      };

      const inlineCacheKeyFor = (element) => INLINE_STYLE_ATTRS.map((attr) => `${attr}=${element.getAttribute(attr) || ""}`).join("\n");

      const hasColorInlineSource = (element) => {
        if (!element || !element.hasAttribute || !element.style) return false;
        if (
          element.hasAttribute("bgcolor")
          || element.hasAttribute("color")
          || element.hasAttribute("background")
          || element.hasAttribute("fill")
          || element.hasAttribute("stroke")
          || element.hasAttribute("stop-color")
        ) {
          return true;
        }

        for (let index = 0; index < element.style.length; index += 1) {
          const property = element.style.item(index);
          if (!property || property.startsWith(DARK_VAR_PREFIX) || property.startsWith("--wkdomains-forced-dark")) continue;
          const lower = property.toLowerCase();
          if (
            lower.startsWith("--")
            || lower.includes("color")
            || lower.includes("background")
            || lower.includes("border")
            || lower.includes("shadow")
            || lower === "fill"
            || lower === "stroke"
            || lower === "outline"
            || lower === "column-rule"
          ) {
            return true;
          }
        }

        return false;
      };

      const setInlineCustomProp = (element, attribute, property, cssProperty, sourceProperty, sourceValue) => {
        const value = transformCSSValue(sourceProperty || cssProperty, sourceValue, element);
        setOverride(element, attribute, property, value);
      };

      const setInlineVariableOverrides = (element, property, sourceValue) => {
        const declarations = transformCSSValue(property, sourceValue, element);
        element.style.removeProperty(wrappedVariableName("bg", property));
        element.style.removeProperty(wrappedVariableName("text", property));
        element.style.removeProperty(wrappedVariableName("border", property));
        if (!Array.isArray(declarations)) return;
        for (const declaration of declarations) {
          element.style.setProperty(declaration.property, declaration.value);
        }
      };

      const clearInlineOverrides = (element) => {
        setOverride(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", null);
        setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", null);
        setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", null);
        setOverride(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", null);
        setOverride(element, STROKE_ATTRIBUTE, "--wkdomains-forced-dark-stroke", null);
        setOverride(element, BOX_SHADOW_ATTRIBUTE, "--wkdomains-forced-dark-box-shadow", null);
        for (const override of BORDER_OVERRIDES) {
          setOverride(element, override.attr, override.prop, null);
        }
        for (const override of SHORTHAND_OVERRIDES) {
          setOverride(element, override.attr, override.prop, null);
        }
        removeGeneratedInlineVariables(element);
      };

      const clearAllInlineOverrides = (root = document) => {
        if (!root || !root.querySelectorAll) return;
        const selector = [...ATTRIBUTES_OWNED_BY_DARK_MODE.map((attr) => `[${attr}]`), "[style]"].join(", ");
        const elements = [];
        if (root.nodeType === Node.DOCUMENT_NODE) {
          if (document.documentElement) elements.push(document.documentElement);
          if (document.body) elements.push(document.body);
        } else if (root.nodeType === Node.ELEMENT_NODE) {
          elements.push(root);
        }
        try {
          elements.push(...root.querySelectorAll(selector));
        } catch (_) {}
        for (const element of elements) {
          clearInlineOverrides(element);
        }
      };

      const overrideInlineStyle = (element) => {
        if (!element || !element.getAttribute || !element.style) return;
        const key = inlineCacheKeyFor(element);
        if (inlineStyleCache.get(element) === key) return;

        if (shouldIgnoreInlineStyle(element)) {
          clearInlineOverrides(element);
          inlineStyleCache.set(element, key);
          return;
        }

        if (element.hasAttribute("bgcolor")) {
          let value = element.getAttribute("bgcolor") || "";
          if (/^[0-9a-f]{3}$/i.test(value) || /^[0-9a-f]{6}$/i.test(value)) value = `#${value}`;
          setInlineCustomProp(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", "background-color", "background-color", value);
        }

        if ((element === document.documentElement || element === document.body) && element.hasAttribute("background")) {
          setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", "none");
        }

        if (element.hasAttribute("color") && element.rel !== "mask-icon") {
          let value = element.getAttribute("color") || "";
          if (/^[0-9a-f]{3}$/i.test(value) || /^[0-9a-f]{6}$/i.test(value)) value = `#${value}`;
          setInlineCustomProp(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", "color", "color", value);
        }

        if (element instanceof SVGElement) {
          if (element.hasAttribute("fill")) {
            const value = element.getAttribute("fill");
            if (value && value !== "none" && value !== "currentColor") {
              setInlineCustomProp(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", "fill", element instanceof SVGTextElement ? "color" : "fill", value);
            }
          }
          if (element.hasAttribute("stop-color")) {
            setInlineCustomProp(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", "fill", "background-color", element.getAttribute("stop-color"));
          }
        }

        if (element.hasAttribute("stroke")) {
          setInlineCustomProp(element, STROKE_ATTRIBUTE, "--wkdomains-forced-dark-stroke", "stroke", element instanceof SVGLineElement || element instanceof SVGTextElement ? "border-color" : "color", element.getAttribute("stroke"));
        }

        for (let index = 0; index < element.style.length; index += 1) {
          const property = element.style.item(index);
          const value = element.style.getPropertyValue(property);
          const lower = property.toLowerCase();
          if (property.startsWith("--")) {
            setInlineVariableOverrides(element, property, value);
          } else if (lower === "color" || lower === "-webkit-text-fill-color" || lower === "caret-color") {
            setInlineCustomProp(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", "color", property, value);
          } else if (lower === "background-color") {
            setInlineCustomProp(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", "background-color", property, value);
          } else if (lower === "background") {
            const transformed = transformCSSValue(property, value, element);
            if (transformed) {
              const shorthand = SHORTHAND_OVERRIDES.find((override) => override.css === "background");
              setOverride(element, shorthand.attr, shorthand.prop, transformed);
            } else {
              COLOR_RE.lastIndex = 0;
              const match = COLOR_RE.exec(value);
              COLOR_RE.lastIndex = 0;
              const color = match ? parseColor(match[0]) : null;
              setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", color ? transformBackground(color, element) : null);
              if (value.includes("gradient")) {
                setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", replaceCSSColors(value, modifyBackgroundColor));
              }
            }
          } else if (lower === "background-image") {
            const transformed = transformCSSValue(property, value, element);
            setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", transformed);
          } else if (lower === "fill") {
            setInlineCustomProp(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", "fill", property, value);
          } else if (lower === "stroke") {
            setInlineCustomProp(element, STROKE_ATTRIBUTE, "--wkdomains-forced-dark-stroke", "stroke", property, value);
          } else if (lower === "box-shadow") {
            setInlineCustomProp(element, BOX_SHADOW_ATTRIBUTE, "--wkdomains-forced-dark-box-shadow", "box-shadow", property, value);
          } else {
            for (const override of SHORTHAND_OVERRIDES) {
              if (lower === override.css) {
                setInlineCustomProp(element, override.attr, override.prop, override.css, property, value);
              }
            }
            for (const override of BORDER_OVERRIDES) {
              if (lower === override.css) {
                setInlineCustomProp(element, override.attr, override.prop, override.css, property, value);
              }
            }
          }
        }

        inlineStyleCache.set(element, key);
      };

      const applyElement = (element) => {
        if (!element || element.nodeType !== Node.ELEMENT_NODE || shouldSkipElement(element)) return;

        const tag = element.tagName.toUpperCase();
        const hasInlineColors = hasColorInlineSource(element);
        overrideInlineStyle(element);

        if (tag === "HTML" || tag === "BODY") {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", toRGBA(DEFAULT_BACKGROUND));
          setOverride(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", toRGBA(DEFAULT_TEXT));
          return;
        }

        let style = null;
        const shouldFallbackToComputedStyle = hasInlineColors
          || SVG_TAGS.has(tag)
          || element.matches(CONTROL_SELECTOR);
        if (!shouldFallbackToComputedStyle) {
          return;
        }

        style = style || captureSourceStyle(element) || getComputedStyle(element);

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
          setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", replaceCSSColors(style.backgroundImage, modifyBackgroundColor));
        } else {
          setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", null);
        }

        const boxShadow = transformBoxShadow(style.boxShadow);
        setOverride(element, BOX_SHADOW_ATTRIBUTE, "--wkdomains-forced-dark-box-shadow", boxShadow && boxShadow !== style.boxShadow ? boxShadow : null);

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
        } else if (root.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
          createShadowStaticStyleOverrides(root);
          renderAdoptedStyleSheets(root);
        } else if (root.nodeType === Node.ELEMENT_NODE) {
          applyElement(root);
        }

        for (const element of root.querySelectorAll(STYLE_OVERRIDE_SELECTOR)) {
          applyElement(element);
        }
      };

      const clearCachedSourceFor = (node) => {
        if (node && node.nodeType === Node.ELEMENT_NODE) {
          sourceStyleCache.delete(node);
          inlineStyleCache.delete(node);
        }
      };

      const discoverShadowRoot = (root) => {
        if (!root || discoveredShadowRoots.has(root)) return;
        discoveredShadowRoots.add(root);
        createShadowStaticStyleOverrides(root);
        applyRoot(root);
        scheduleStyleSync(0);
        watchRoot(root);
      };

      const destroyInlineDOMState = () => {
        clearAllInlineOverrides(document);
        for (const root of Array.from(discoveredShadowRoots)) {
          clearAllInlineOverrides(root);
        }
        discoveredShadowRoots.clear();
      };
    """#
}
