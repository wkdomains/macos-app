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
      const pendingRootApplySet = new Set();
      const pendingRootApplyQueue = [];
      const pendingRootApplyJobs = new Map();
      const pendingElementApplySet = new Set();
      const pendingElementApplyQueue = [];
      let rootApplyScheduled = false;
      let elementApplyScheduled = false;
      let lightSurfaceFallbacksApplied = 0;
      let lightSurfaceFallbacksCleared = 0;
      let priorityElementApplyBatches = 0;
      let priorityElementApplies = 0;
      const ROOT_APPLY_BUDGET_MS = 8;
      const ROOT_APPLY_STARTUP_BUDGET_MS = 4;
      const ROOT_APPLY_STARTUP_DELAY_MS = 32;
      const ROOT_APPLY_MAX_PER_SLICE = 8;
      const ROOT_APPLY_MAX_ELEMENTS_PER_SLICE = 96;
      const ROOT_APPLY_STARTUP_MAX_ELEMENTS_PER_SLICE = 48;
      const ELEMENT_APPLY_BUDGET_MS = 6;
      const ELEMENT_APPLY_MAX_PER_SLICE = 80;
      const ELEMENT_SUBTREE_QUEUE_LIMIT = 32;
      const LIGHT_SURFACE_ANCESTOR_LIMIT = 6;

      const rootApplyInStartupWindow = () => {
        try {
          return stylesheetSyncElapsedSinceInstall() < STARTUP_STYLE_SYNC_WINDOW_MS;
        } catch (_) {
          return false;
        }
      };

      const rootApplyBudgetMS = () => rootApplyInStartupWindow() ? ROOT_APPLY_STARTUP_BUDGET_MS : ROOT_APPLY_BUDGET_MS;
      const rootApplyElementLimit = () => rootApplyInStartupWindow()
        ? ROOT_APPLY_STARTUP_MAX_ELEMENTS_PER_SLICE
        : ROOT_APPLY_MAX_ELEMENTS_PER_SLICE;
      const rootApplyRescheduleDelay = () => rootApplyInStartupWindow() ? ROOT_APPLY_STARTUP_DELAY_MS : 16;
      const scheduleIdleTask = (callback, delay = 0, timeout = 250) => {
        if (delay > 0) {
          window.setTimeout(() => scheduleIdleTask(callback, 0, timeout), delay);
          return;
        }

        if (window.requestIdleCallback) {
          window.requestIdleCallback(callback, { timeout });
          return;
        }

        window.setTimeout(callback, 0);
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

      const removeGeneratedInlineVariables = (element) => {
        if (!element || !element.style) return;
        const properties = [];
        for (let index = 0; index < element.style.length; index += 1) {
          const property = element.style.item(index);
          if (isGeneratedDarkModeProperty(property)) {
            properties.push(property);
          }
        }
        for (const property of properties) {
          element.style.removeProperty(property);
        }
      };

      const captureComputedStyleSnapshot = (element) => {
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
      };

      const withElementOverridesDisabled = (element, action) => {
        if (!element || !element.style) return action();

        const savedAttributes = [];
        for (const attribute of ATTRIBUTES_OWNED_BY_DARK_MODE) {
          if (element.hasAttribute(attribute)) {
            savedAttributes.push([attribute, element.getAttribute(attribute)]);
          }
        }

        const savedProperties = [];
        for (let index = 0; index < element.style.length; index += 1) {
          const property = element.style.item(index);
          if (isGeneratedDarkModeProperty(property)) {
            savedProperties.push([
              property,
              element.style.getPropertyValue(property),
              element.style.getPropertyPriority(property)
            ]);
          }
        }

        if (savedAttributes.length === 0 && savedProperties.length === 0) {
          return action();
        }

        for (const [attribute] of savedAttributes) {
          element.removeAttribute(attribute);
        }
        for (const [property] of savedProperties) {
          element.style.removeProperty(property);
        }

        try {
          return action();
        } finally {
          for (const [property, value, priority] of savedProperties) {
            element.style.setProperty(property, value, priority);
          }
          for (const [attribute, value] of savedAttributes) {
            element.setAttribute(attribute, value || "");
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

      const hasMediaBackdrop = (element, style, scanDescendants = true) => {
        if (!element || !style) return false;
        if (shouldIgnoreImageAnalysis(element)) return false;

        const backgroundImage = style.backgroundImage || "";
        if (backgroundImage && backgroundImage !== "none" && !backgroundImage.includes("gradient")) {
          return true;
        }

        if (!scanDescendants) {
          return false;
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

      const CONTROL_SELECTOR = [
        "input",
        "textarea",
        "select",
        "button",
        "[contenteditable='true']",
        "[role='button']",
        "[role='combobox']",
        "[role='searchbox']",
        "[role='spinbutton']",
        "[role='switch']",
        "[role='textbox']"
      ].join(", ");
      const EDITABLE_CONTROL_SELECTOR = [
        "input",
        "textarea",
        "select",
        "[contenteditable='true']",
        "[role='combobox']",
        "[role='searchbox']",
        "[role='spinbutton']",
        "[role='textbox']"
      ].join(", ");
      const ACTION_SURFACE_SELECTOR = [
        "button",
        "[role='button']"
      ].join(", ");
      const LIGHT_SURFACE_SELECTOR = [
        "dialog",
        "[popover]",
        "[aria-modal='true']",
        "[role='dialog']",
        "[role='alertdialog']",
        "[role='region'][aria-label]",
        "[role='form']",
        "[class*='modal' i]",
        "[class*='dialog' i]",
        "[class*='popover' i]",
        "[class*='popup' i]",
        "[class*='drawer' i]",
        "[class*='panel' i]",
        "[class*='surface' i]",
        "[class*='sheet' i]"
      ].join(", ");
      const SVG_SELECTOR = Array.from(SVG_TAGS).map((tag) => tag.toLowerCase()).join(", ");
      const STYLE_OVERRIDE_SELECTOR = [INLINE_STYLE_SELECTOR, EDITABLE_CONTROL_SELECTOR, ACTION_SURFACE_SELECTOR, SVG_SELECTOR, LIGHT_SURFACE_SELECTOR].join(", ");
      const PRIORITY_STYLE_OVERRIDE_SELECTOR = [INLINE_STYLE_SELECTOR, EDITABLE_CONTROL_SELECTOR, ACTION_SURFACE_SELECTOR, LIGHT_SURFACE_SELECTOR].join(", ");
      const FORM_SURFACE_DESCENDANT_SELECTOR = [
        "input",
        "textarea",
        "[contenteditable='true']",
        "[role='combobox']",
        "[role='searchbox']",
        "[role='textbox']"
      ].join(", ");

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

        const source = withElementOverridesDisabled(element, () => captureComputedStyleSnapshot(element));

        sourceStyleCache.set(element, source);
        return source;
      };

      const inlineStyleSourceKeyFromDeclaration = (style) => {
        if (!style) return "";
        const parts = [];
        for (let index = 0; index < style.length; index += 1) {
          const property = style.item(index);
          if (!property || isGeneratedDarkModeProperty(property)) continue;
          parts.push(`${property}:${style.getPropertyValue(property)}!${style.getPropertyPriority(property)}`);
        }
        return parts.join(";");
      };

      const inlineStyleSourceKeyFromText = (styleText) => {
        if (!styleText) return "";
        const element = document.createElement("span");
        element.setAttribute("style", String(styleText || ""));
        return inlineStyleSourceKeyFromDeclaration(element.style);
      };

      const inlineStyleSourceKeyForElement = (element) => inlineStyleSourceKeyFromDeclaration(element && element.style);

      const inlineStyleMutationChangedSource = (element, oldValue) => (
        inlineStyleSourceKeyFromText(oldValue) !== inlineStyleSourceKeyForElement(element)
      );

      const inlineCacheKeyFor = (element) => INLINE_STYLE_ATTRS.map((attr) => {
        if (attr === "style") return `style=${inlineStyleSourceKeyForElement(element)}`;
        return `${attr}=${element.getAttribute(attr) || ""}`;
      }).join("\n");

      const isLightSurfaceCandidate = (element) => {
        if (!element || !element.matches || !element.tagName) return false;
        if (element === document.documentElement || element === document.body) return true;
        if (SKIP_TAGS.has(element.tagName.toUpperCase())) return false;

        const rect = visibleRectFor(element);
        if (rect.width < 24 || rect.height < 18 || rect.area < 900) return false;

        const role = String(element.getAttribute("role") || "").toLowerCase();
        if (["dialog", "alertdialog", "form"].includes(role)) return true;
        if (role === "region" && element.hasAttribute("aria-label")) return true;
        if (element.hasAttribute("popover") || element.getAttribute("aria-modal") === "true") return true;
        if (element.matches("dialog")) return true;

        const className = String(element.className || "");
        if (/\b(modal|dialog|popover|popup|drawer|panel|surface|sheet|compose|editor|toolbar)\b/i.test(className)) {
          return true;
        }

        return false;
      };

      const shouldApplyActionSurfaceFallback = (element) => {
        if (!element || !element.matches || !element.matches(ACTION_SURFACE_SELECTOR)) return false;
        if (!element.tagName || SKIP_TAGS.has(element.tagName.toUpperCase())) return false;
        const rect = visibleRectFor(element);
        if (rect.width < 28 || rect.height < 24 || rect.area < 1000) return false;
        if (rect.area > Math.max(1, innerWidth * innerHeight) * 0.12) return false;

        const style = captureSourceStyle(element) || getComputedStyle(element);
        if (!style || style.display === "none" || style.visibility === "hidden" || Number.parseFloat(style.opacity || "1") <= 0.02) return false;
        const sourceBackground = parseColor(style.backgroundColor);
        if (!sourceBackground || sourceBackground.a <= 0.08) return false;
        if (relativeLuminance(sourceBackground) <= 0.68) return false;
        return !hasMediaBackdrop(element, style, false);
      };

      const hasEditableDescendant = (element) => {
        if (!element || !element.querySelector) return false;
        try {
          return Boolean(element.querySelector(FORM_SURFACE_DESCENDANT_SELECTOR));
        } catch (_) {
          return false;
        }
      };

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
          if (!property || isGeneratedDarkModeProperty(property)) continue;
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

      const hasBackgroundInlineSource = (element) => {
        if (!element || !element.hasAttribute || !element.style) return false;
        if (
          element.hasAttribute("bgcolor")
          || element.hasAttribute("background")
        ) {
          return true;
        }

        for (let index = 0; index < element.style.length; index += 1) {
          const property = element.style.item(index);
          if (!property || isGeneratedDarkModeProperty(property)) continue;
          const lower = property.toLowerCase();
          if (lower === "background" || lower.includes("background")) {
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
        for (const type of ["bg", "text", "border"]) {
          for (const alias of wrappedVariableNames(type, property)) {
            element.style.removeProperty(alias);
          }
        }
        if (!Array.isArray(declarations)) return;
        for (const declaration of declarations) {
          element.style.setProperty(declaration.property, declaration.value);
        }
      };

      const applyComputedStyleFallback = (element, reason = "direct", options = {}) => {
        const tag = element.tagName.toUpperCase();
        const style = captureSourceStyle(element) || getComputedStyle(element);

        if (!SVG_TAGS.has(tag)) {
          const color = transformForeground(parseColor(style.color), element);
          setOverride(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", color);
        }

        const sourceBackground = parseColor(style.backgroundColor);
        const surfaceBackground = reason === "surface" && (!sourceBackground || sourceBackground.a <= 0.08)
          ? surfaceColorFor(element)
          : null;
        const background = surfaceBackground || sourceBackground;
        const backgroundLuminance = background ? relativeLuminance(background) : 0;
        const mediaBackdrop = hasMediaBackdrop(element, style, reason === "surface");
        const transformedBackground = mediaBackdrop ? null : transformBackground(background, element);

        if (mediaBackdrop) {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", "transparent");
        } else if (transformedBackground && background && (background.a > 0.08 || reason === "surface")) {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", transformedBackground);
          if (reason === "surface") lightSurfaceFallbacksApplied += 1;
        } else if (
          options.preserveBackgroundOverride
          && reason === "direct"
          && element.hasAttribute(BACKGROUND_ATTRIBUTE)
          && (!background || background.a <= 0.08)
        ) {
          // Keep explicit HTML/style background sources such as legacy bgcolor
          // when computed style sampling cannot see the original attribute color.
        } else {
          if (element.hasAttribute(BACKGROUND_ATTRIBUTE)) lightSurfaceFallbacksCleared += 1;
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", null);
        }

        if (!mediaBackdrop && style.backgroundImage && style.backgroundImage.includes("gradient") && backgroundLuminance > 0.46) {
          setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", replaceCSSColors(style.backgroundImage, modifyBackgroundColor));
        } else {
          setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", null);
        }

        const boxShadow = transformBoxShadow(style.boxShadow);
        setOverride(element, BOX_SHADOW_ATTRIBUTE, "--wkdomains-forced-dark-box-shadow", boxShadow && boxShadow !== style.boxShadow ? boxShadow : null);

        if (reason === "surface" && hasEditableDescendant(element)) {
          element.setAttribute(FORM_SURFACE_ATTRIBUTE, "");
        } else {
          element.removeAttribute(FORM_SURFACE_ATTRIBUTE);
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

      const shouldApplyLightSurfaceFallback = (element, forceCandidate = false) => {
        if (!forceCandidate && !isLightSurfaceCandidate(element)) return false;
        if (forceCandidate && (!element || !element.tagName || SKIP_TAGS.has(element.tagName.toUpperCase()))) return false;
        if (forceCandidate) {
          const rect = visibleRectFor(element);
          if (rect.width < 24 || rect.height < 18 || rect.area < 900) return false;
          if (rect.area > Math.max(1, innerWidth * innerHeight) * 0.55 && !isLightSurfaceCandidate(element)) return false;
        }
        const style = captureSourceStyle(element) || getComputedStyle(element);
        if (!style || style.display === "none" || style.visibility === "hidden" || Number.parseFloat(style.opacity || "1") <= 0.02) return false;
        if (hasMediaBackdrop(element, style)) return false;

        const sourceBackground = parseColor(style.backgroundColor);
        const surfaceBackground = (!sourceBackground || sourceBackground.a <= 0.08)
          ? surfaceColorFor(element)
          : sourceBackground;
        if (!surfaceBackground || surfaceBackground.a <= 0.08) return false;
        return relativeLuminance(surfaceBackground) > 0.68;
      };

      const applyLightSurfaceAncestors = (element) => {
        if (!element || !element.parentElement) return;
        let parent = element.parentElement;
        let depth = 0;
        while (parent && parent.nodeType === Node.ELEMENT_NODE && depth < LIGHT_SURFACE_ANCESTOR_LIMIT) {
          if (parent === document.documentElement || parent === document.body) break;
          if (shouldApplyLightSurfaceFallback(parent, true)) {
            applyComputedStyleFallback(parent, "surface");
          }
          parent = parent.parentElement;
          depth += 1;
        }
      };

      const clearInlineOverrides = (element) => {
        setOverride(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", null);
        setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", null);
        element.removeAttribute(FORM_SURFACE_ATTRIBUTE);
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
              const colorValue = hasCSSColor(value) ? replaceCSSColors(value, modifyBackgroundColor) : null;
              if (colorValue && colorValue !== value) {
                const shorthand = SHORTHAND_OVERRIDES.find((override) => override.css === "background");
                setOverride(element, shorthand.attr, shorthand.prop, colorValue);
              } else {
                setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", null);
              }
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
        const hasInlineBackground = hasBackgroundInlineSource(element);
        overrideInlineStyle(element);

        if (tag === "HTML" || tag === "BODY") {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", toThemeRGBA(themeBackgroundColor()));
          setOverride(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", toThemeRGBA(themeTextColor()));
          return;
        }

        const isSVGElement = SVG_TAGS.has(tag);
        const isEditableControl = element.matches(EDITABLE_CONTROL_SELECTOR);
        const needsActionFallback = !hasInlineColors && !isSVGElement && !isEditableControl
          ? shouldApplyActionSurfaceFallback(element)
          : false;
        const needsSurfaceFallback = !hasInlineColors && !isSVGElement && !isEditableControl && !needsActionFallback
          ? shouldApplyLightSurfaceFallback(element)
          : false;
        const shouldFallbackToComputedStyle = hasInlineColors
          || isSVGElement
          || isEditableControl
          || needsActionFallback
          || needsSurfaceFallback;
        if (!shouldFallbackToComputedStyle) {
          return;
        }

        applyComputedStyleFallback(
          element,
          needsSurfaceFallback || needsActionFallback ? "surface" : "direct",
          { preserveBackgroundOverride: hasInlineBackground }
        );
        if (isEditableControl) {
          applyLightSurfaceAncestors(element);
        }
      };

      const elementApplyIsConnected = (element) => {
        if (!element || element.nodeType !== Node.ELEMENT_NODE) return false;
        if (element === document.documentElement || element === document.body) return true;
        return element.isConnected !== false;
      };

      const scheduleQueuedElementApplies = (delay = 0) => {
        if (elementApplyScheduled) return;
        elementApplyScheduled = true;
        scheduleIdleTask(flushQueuedElementApplies, delay, 220);
      };

      const queueElementApply = (element, delay = 0) => {
        if (!element || element.nodeType !== Node.ELEMENT_NODE || pendingElementApplySet.has(element)) return false;
        pendingElementApplySet.add(element);
        pendingElementApplyQueue.push(element);
        scheduleQueuedElementApplies(delay);
        return true;
      };

      const queueElementSubtreeApply = (node, limit = ELEMENT_SUBTREE_QUEUE_LIMIT) => {
        if (!node) return 0;
        let queued = 0;
        const queueCandidate = (element) => {
          if (!element || queued >= limit || element.nodeType !== Node.ELEMENT_NODE) return;
          if (!element.matches || !element.matches(PRIORITY_STYLE_OVERRIDE_SELECTOR)) return;
          if (queueElementApply(element, 0)) queued += 1;
        };

        if (node.nodeType === Node.ELEMENT_NODE) {
          queueCandidate(node);
        }

        if (!node.querySelectorAll) return queued;
        try {
          for (const element of node.querySelectorAll(PRIORITY_STYLE_OVERRIDE_SELECTOR)) {
            queueCandidate(element);
            if (queued >= limit) break;
          }
        } catch (_) {}
        return queued;
      };

      const flushQueuedElementApplies = () => {
        const flushStartedAt = __wkdomainsDarkModeNow();
        elementApplyScheduled = false;
        if (pendingElementApplyQueue.length === 0) return;

        const started = performance.now();
        const wasApplying = applying;
        let applied = 0;
        applying = true;
        priorityElementApplyBatches += 1;

        try {
          while (pendingElementApplyQueue.length > 0) {
            const element = pendingElementApplyQueue.shift();
            pendingElementApplySet.delete(element);
            if (!elementApplyIsConnected(element)) continue;
            applyElement(element);
            applied += 1;
            priorityElementApplies += 1;
            if (
              applied >= ELEMENT_APPLY_MAX_PER_SLICE
              || performance.now() - started > ELEMENT_APPLY_BUDGET_MS
            ) {
              break;
            }
          }
        } finally {
          applying = wasApplying;
        }

        if (pendingElementApplyQueue.length > 0) {
          scheduleQueuedElementApplies(24);
        }
        __wkdomainsDarkModePerf(
          "flush-element-applies",
          flushStartedAt,
          `applied=${applied} remaining=${pendingElementApplyQueue.length} batches=${priorityElementApplyBatches}`,
          6
        );
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

      const rootApplyWalkerRoot = (root) => {
        if (!root) return null;
        if (root.nodeType === Node.DOCUMENT_NODE) return root.documentElement;
        return root;
      };

      const createRootApplyJob = (root) => ({
        root,
        initialized: false,
        elements: [],
        index: 0,
        done: false
      });

      const processRootApplyJob = (job, started) => {
        if (!job || job.done) return true;
        const root = job.root;
        if (!root || (root.host && !root.host.isConnected)) {
          job.done = true;
          return true;
        }

        if (!job.initialized) {
          job.initialized = true;
          if (root.nodeType === Node.DOCUMENT_NODE) {
            applyElement(document.documentElement);
            if (document.body) applyElement(document.body);
          } else if (root.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
            createShadowStaticStyleOverrides(root);
            renderAdoptedStyleSheets(root);
          } else if (root.nodeType === Node.ELEMENT_NODE) {
            applyElement(root);
          }

          const walkerRoot = rootApplyWalkerRoot(root);
          if (walkerRoot && walkerRoot.querySelectorAll) {
            try {
              job.elements = Array.from(walkerRoot.querySelectorAll(STYLE_OVERRIDE_SELECTOR));
            } catch (_) {
              job.elements = [];
            }
          }
        }

        let count = 0;
        while (job.index < job.elements.length) {
          const node = job.elements[job.index];
          job.index += 1;
          if (elementApplyIsConnected(node)) {
            applyElement(node);
          }
          count += 1;
          if (
            count >= rootApplyElementLimit()
            || performance.now() - started > rootApplyBudgetMS()
          ) {
            return false;
          }
        }

        job.done = true;
        return true;
      };

      const flushQueuedRootApplies = () => {
        const flushStartedAt = __wkdomainsDarkModeNow();
        rootApplyScheduled = false;
        if (pendingRootApplyQueue.length === 0) return;

        const started = performance.now();
        let count = 0;
        const wasApplying = applying;
        applying = true;

        try {
          while (pendingRootApplyQueue.length > 0) {
            const root = pendingRootApplyQueue.shift();
            if (!root || (root.host && !root.host.isConnected)) continue;
            let job = pendingRootApplyJobs.get(root);
            if (!job) {
              job = createRootApplyJob(root);
              pendingRootApplyJobs.set(root, job);
            }
            const done = processRootApplyJob(job, started);
            if (done) {
              pendingRootApplyJobs.delete(root);
              pendingRootApplySet.delete(root);
              count += 1;
            } else {
              pendingRootApplyQueue.unshift(root);
              break;
            }
            if (count >= ROOT_APPLY_MAX_PER_SLICE || performance.now() - started > rootApplyBudgetMS()) {
              break;
            }
          }
        } finally {
          applying = wasApplying;
        }

        if (pendingRootApplyQueue.length > 0) {
          scheduleQueuedRootApplies(rootApplyRescheduleDelay());
        }
        const activeRootJob = pendingRootApplyJobs.size > 0 ? pendingRootApplyJobs.values().next().value : null;
        __wkdomainsDarkModePerf(
          "flush-root-applies",
          flushStartedAt,
          `rootsDone=${count} remaining=${pendingRootApplyQueue.length} jobs=${pendingRootApplyJobs.size} active=${activeRootJob ? `${activeRootJob.index}/${activeRootJob.elements.length}` : "none"} startup=${rootApplyInStartupWindow()}`,
          6
        );
      };

      const scheduleQueuedRootApplies = (delay = 0) => {
        if (rootApplyScheduled) return;
        rootApplyScheduled = true;
        scheduleIdleTask(flushQueuedRootApplies, delay, 260);
      };

      const queueRootApply = (root, delay = 16) => {
        if (!root || pendingRootApplySet.has(root)) return;
        pendingRootApplySet.add(root);
        pendingRootApplyQueue.push(root);
        scheduleQueuedRootApplies(delay);
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
        watchRoot(root);
        queueRootApply(root);
        scheduleStyleSync(60);
      };

      const destroyInlineDOMState = () => {
        clearAllInlineOverrides(document);
        for (const root of Array.from(discoveredShadowRoots)) {
          clearAllInlineOverrides(root);
        }
        discoveredShadowRoots.clear();
        pendingRootApplySet.clear();
        pendingRootApplyQueue.splice(0);
        pendingRootApplyJobs.clear();
        pendingElementApplySet.clear();
        pendingElementApplyQueue.splice(0);
        rootApplyScheduled = false;
        elementApplyScheduled = false;
      };
    """#
}
