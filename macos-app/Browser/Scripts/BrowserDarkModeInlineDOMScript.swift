//
//  BrowserDarkModeInlineDOMScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeInlineDOMScript = #"""
      const discoveredShadowRoots = new Set();
      let sourceStyleCache = new WeakMap();
      const inlineStyleCache = new WeakMap();
      let elementApplyCache = new WeakMap();
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
      let elementApplyCacheVersion = 0;
      let elementApplyErrors = 0;
      let lastElementApplyError = "";
      let applyQueueWatchdogTimer = null;
      let applyQueueWatchdogTicks = 0;
      const ROOT_APPLY_BUDGET_MS = 8;
      const ROOT_APPLY_STARTUP_BUDGET_MS = 4;
      const ROOT_APPLY_STARTUP_DELAY_MS = 32;
      const ROOT_APPLY_MAX_PER_SLICE = 8;
      const ROOT_APPLY_MAX_ELEMENTS_PER_SLICE = 48;
      const ROOT_APPLY_STARTUP_MAX_ELEMENTS_PER_SLICE = 28;
      const ROOT_APPLY_MAX_SCANNED_PER_SLICE = 900;
      const ROOT_APPLY_STARTUP_MAX_SCANNED_PER_SLICE = 420;
      const ELEMENT_APPLY_BUDGET_MS = 3;
      const ELEMENT_APPLY_MAX_PER_SLICE = 32;
      const ELEMENT_SUBTREE_QUEUE_LIMIT = 32;
      const LIGHT_SURFACE_ANCESTOR_LIMIT = 6;
      const MEDIA_BACKDROP_SCAN_LIMIT = 48;
      const MEDIA_BACKDROP_SCAN_BUDGET_MS = 2.5;

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
      const rootApplyScanLimit = () => rootApplyInStartupWindow()
        ? ROOT_APPLY_STARTUP_MAX_SCANNED_PER_SLICE
        : ROOT_APPLY_MAX_SCANNED_PER_SLICE;
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

        let mediaElements = [];
        try {
          mediaElements = element.querySelectorAll("video,img,picture,canvas,iframe,object,embed");
        } catch (_) {
          mediaElements = [];
        }
        const scanStartedAt = __wkdomainsDarkModeNow();
        const maxMediaCount = Math.min(mediaElements.length, MEDIA_BACKDROP_SCAN_LIMIT);
        for (let index = 0; index < maxMediaCount; index += 1) {
          const media = mediaElements[index];
          if (index > 0 && __wkdomainsDarkModeNow() - scanStartedAt > MEDIA_BACKDROP_SCAN_BUDGET_MS) break;
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
        "main",
        "article",
        "form",
        "dialog",
        "[popover]",
        "[aria-modal='true']",
        "[role='main']",
        "[role='article']",
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
      const ROOT_STYLE_OVERRIDE_SELECTOR = INLINE_STYLE_SELECTOR;
      const PRIORITY_STYLE_OVERRIDE_SELECTOR = INLINE_STYLE_SELECTOR;
      const POST_LOAD_PRIORITY_STYLE_OVERRIDE_SELECTOR = [
        INLINE_STYLE_SELECTOR,
        LIGHT_SURFACE_SELECTOR
      ].join(", ");
      const shouldSkipElement = (element) => {
        if (!element || !element.tagName || SKIP_TAGS.has(element.tagName.toUpperCase())) return true;
        if (element.classList && element.classList.contains(INLINE_CLASS)) return true;
        return false;
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

      const elementApplyCacheKeyFor = (element) => [
        elementApplyCacheVersion,
        `${THEME.mode}:${THEME.brightness}:${THEME.contrast}:${THEME.grayscale}:${THEME.sepia}`,
        element.tagName || "",
        inlineCacheKeyFor(element),
        `class=${element.getAttribute("class") || ""}`,
        `role=${element.getAttribute("role") || ""}`,
        `type=${element.getAttribute("type") || ""}`,
        `hidden=${element.hasAttribute("hidden") ? "1" : "0"}`,
        `open=${element.hasAttribute("open") ? "1" : "0"}`,
        `popover=${element.getAttribute("popover") || ""}`,
        `disabled=${element.hasAttribute("disabled") ? "1" : "0"}`,
        `contenteditable=${element.getAttribute("contenteditable") || ""}`,
        `aria-hidden=${element.getAttribute("aria-hidden") || ""}`,
        `aria-expanded=${element.getAttribute("aria-expanded") || ""}`,
        `aria-modal=${element.getAttribute("aria-modal") || ""}`
      ].join("\n");

      const invalidateElementApplyCaches = () => {
        sourceStyleCache = new WeakMap();
        elementApplyCache = new WeakMap();
        elementApplyCacheVersion += 1;
      };

      const isLightSurfaceCandidate = (element) => {
        if (!element || !element.matches || !element.tagName) return false;
        if (element === document.documentElement || element === document.body) return true;
        if (SKIP_TAGS.has(element.tagName.toUpperCase())) return false;

        const rect = visibleRectFor(element);
        if (rect.width < 24 || rect.height < 18 || rect.area < 900) return false;

        const role = String(element.getAttribute("role") || "").toLowerCase();
        if (["main", "article", "dialog", "alertdialog", "form"].includes(role)) return true;
        if (role === "region" && element.hasAttribute("aria-label")) return true;
        if (element.hasAttribute("popover") || element.getAttribute("aria-modal") === "true") return true;
        if (element.matches("main, article, dialog, form")) return true;

        const className = String(element.className || "");
        if (/\b(modal|dialog|popover|popup|drawer|panel|surface|sheet|editor|toolbar)\b/i.test(className)) {
          return true;
        }

        return false;
      };

      const isSurfaceFallbackReason = (reason) => reason === "surface" || reason === "surface-child";

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

      const hasConstructor = (name) => typeof window[name] === "function";
      const isInstanceOfConstructor = (element, name) => (
        hasConstructor(name) && element instanceof window[name]
      );
      const isSVGElementNode = (element) => isInstanceOfConstructor(element, "SVGElement");
      const isSVGTextElementNode = (element) => isInstanceOfConstructor(element, "SVGTextElement");
      const isSVGLineElementNode = (element) => isInstanceOfConstructor(element, "SVGLineElement");

      const describeElementForTiming = (element, reason = "") => {
        try {
          const tag = (element && element.tagName ? element.tagName.toLowerCase() : "node");
          const id = element && element.id ? `#${String(element.id).slice(0, 32)}` : "";
          const className = element && element.className && typeof element.className === "string"
            ? `.${String(element.className).trim().replace(/\s+/g, ".").slice(0, 72)}`
            : "";
          return `${tag}${id}${className}${reason ? ` reason=${reason}` : ""}`;
        } catch (_) {
          return reason || "element";
        }
      };

      const applyComputedStyleFallback = (element, reason = "direct", options = {}) => {
        const tag = element.tagName.toUpperCase();
        const style = captureSourceStyle(element) || getComputedStyle(element);
        const isSurfaceReason = isSurfaceFallbackReason(reason);

        if (!SVG_TAGS.has(tag)) {
          const color = transformForeground(parseColor(style.color), element);
          setOverride(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", color);
        }

        const sourceBackground = parseColor(style.backgroundColor);
        const surfaceBackground = isSurfaceReason && (!sourceBackground || sourceBackground.a <= 0.08)
          ? surfaceColorFor(element)
          : null;
        const background = surfaceBackground || sourceBackground;
        const backgroundLuminance = background ? relativeLuminance(background) : 0;
        const mediaBackdrop = hasMediaBackdrop(element, style, isSurfaceReason);
        const transformedBackground = mediaBackdrop ? null : transformBackground(background, element);

        if (mediaBackdrop) {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", "transparent");
        } else if (transformedBackground && background && (background.a > 0.08 || isSurfaceReason)) {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", transformedBackground);
          if (isSurfaceReason) lightSurfaceFallbacksApplied += 1;
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

        if (isSurfaceReason) {
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

        if (reason === "surface" && options.applyDescendantFallbacks !== false) {
          applyLightSurfaceDescendants(element);
        }
      };

      const applyLightSurfaceDescendants = (element) => {
        if (!element || !element.children || element.children.length === 0) return;
        const hadSurfaceMarker = element.hasAttribute(FORM_SURFACE_ATTRIBUTE);
        if (hadSurfaceMarker) element.removeAttribute(FORM_SURFACE_ATTRIBUTE);
        try {
          const surfaceRect = visibleRectFor(element);
          if (surfaceRect.area <= 0) return;

          const candidates = [];
          const seen = new Set();
          const addCandidate = (candidate) => {
            if (!candidate || seen.has(candidate) || candidate === element) return;
            seen.add(candidate);
            candidates.push(candidate);
          };

          const directChildren = element.children;
          for (let index = 0; index < directChildren.length && candidates.length < 16; index += 1) {
            addCandidate(directChildren[index]);
          }

          if (element.querySelectorAll) {
            try {
              for (const candidate of element.querySelectorAll("header,[role='banner'],[role='toolbar'],[role='heading']")) {
                addCandidate(candidate);
                if (candidates.length >= 24) break;
              }
            } catch (_) {}
          }

          const started = performance.now();
          for (const candidate of candidates) {
            if (performance.now() - started > 2.5) break;
            if (!candidate.matches || shouldSkipElement(candidate)) continue;
            const rect = visibleRectFor(candidate);
            if (rect.width < 24 || rect.height < 14 || rect.area < 300) continue;
            if (rect.area > surfaceRect.area * 0.75) continue;
            if (!shouldApplyLightSurfaceFallback(candidate, true)) continue;
            applyComputedStyleFallback(candidate, "surface-child", { applyDescendantFallbacks: false });
          }
        } finally {
          if (hadSurfaceMarker) element.setAttribute(FORM_SURFACE_ATTRIBUTE, "");
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

        if (isSVGElementNode(element)) {
          if (element.hasAttribute("fill")) {
            const value = element.getAttribute("fill");
            if (value && value !== "none" && value !== "currentColor") {
              setInlineCustomProp(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", "fill", isSVGTextElementNode(element) ? "color" : "fill", value);
            }
          }
          if (element.hasAttribute("stop-color")) {
            setInlineCustomProp(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", "fill", "background-color", element.getAttribute("stop-color"));
          }
        }

        if (element.hasAttribute("stroke")) {
          setInlineCustomProp(element, STROKE_ATTRIBUTE, "--wkdomains-forced-dark-stroke", "stroke", isSVGLineElementNode(element) || isSVGTextElementNode(element) ? "border-color" : "color", element.getAttribute("stroke"));
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

        if (styleHasVariableData(element.style)) {
          queueInlineVariableUpdate(element.style);
        }

        inlineStyleCache.set(element, key);
      };

      const applyElement = (element) => {
        const applyStartedAt = __wkdomainsDarkModeNow();
        let timingReason = "skipped";
        if (!element || element.nodeType !== Node.ELEMENT_NODE) return;

        const cacheKey = elementApplyCacheKeyFor(element);
        if (elementApplyCache.get(element) === cacheKey) {
          timingReason = "cache";
          return;
        }

        if (shouldSkipElement(element)) {
          elementApplyCache.set(element, cacheKey);
          timingReason = "display-none";
          return;
        }

        const tag = element.tagName.toUpperCase();
        const hasInlineColors = hasColorInlineSource(element);
        const hasInlineBackground = hasBackgroundInlineSource(element);
        overrideInlineStyle(element);

        if (tag === "HTML" || tag === "BODY") {
          setOverride(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", toThemeRGBA(themeBackgroundColor()));
          setOverride(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", toThemeRGBA(themeTextColor()));
          elementApplyCache.set(element, cacheKey);
          timingReason = "root";
          return;
        }

        const isSVGElement = SVG_TAGS.has(tag);
        const isEditableControl = element.matches(EDITABLE_CONTROL_SELECTOR);
        const allowComputedFallback = document.readyState === "complete" && !rootApplyInStartupWindow();
        const needsActionFallback = allowComputedFallback && !hasInlineColors && !isSVGElement && !isEditableControl
          ? shouldApplyActionSurfaceFallback(element)
          : false;
        const needsSurfaceFallback = allowComputedFallback && !hasInlineColors && !isSVGElement && !isEditableControl && !needsActionFallback
          ? shouldApplyLightSurfaceFallback(element)
          : false;
        const shouldFallbackToComputedStyle = allowComputedFallback && (
          isSVGElement
          || needsActionFallback
          || needsSurfaceFallback
        );
        if (!shouldFallbackToComputedStyle) {
          elementApplyCache.set(element, cacheKey);
          timingReason = "inline-only";
          return;
        }

        timingReason = needsSurfaceFallback ? "surface" : (needsActionFallback ? "action" : "direct");
        applyComputedStyleFallback(
          element,
          needsSurfaceFallback ? "surface" : (needsActionFallback ? "action" : "direct"),
          { preserveBackgroundOverride: hasInlineBackground }
        );
        if (isEditableControl && hasInlineColors && allowComputedFallback) {
          applyLightSurfaceAncestors(element);
        }
        elementApplyCache.set(element, cacheKey);
        __wkdomainsDarkModePerf("apply-element", applyStartedAt, describeElementForTiming(element, timingReason), 18);
      };

      const safeApplyElement = (element) => {
        const startedAt = __wkdomainsDarkModeNow();
        try {
          applyElement(element);
          return true;
        } catch (error) {
          elementApplyErrors += 1;
          lastElementApplyError = `${describeElementForTiming(element)} ${error && error.message ? error.message : String(error)}`;
          try {
            elementApplyCache.set(element, elementApplyCacheKeyFor(element));
          } catch (_) {}
          if (elementApplyErrors <= 20 || elementApplyErrors % 50 === 0) {
            __wkdomainsDarkModePerf("apply-element-error", startedAt, lastElementApplyError, 0);
          }
          return false;
        }
      };

      const elementApplyIsConnected = (element) => {
        if (!element || element.nodeType !== Node.ELEMENT_NODE) return false;
        if (element === document.documentElement || element === document.body) return true;
        return element.isConnected !== false;
      };

      const priorityElementApplySelector = () => (
        pageLoadFired || document.readyState === "complete"
          ? POST_LOAD_PRIORITY_STYLE_OVERRIDE_SELECTOR
          : PRIORITY_STYLE_OVERRIDE_SELECTOR
      );

      const queuePostLoadSurfaceApplies = (root = document, limit = 64) => {
        if (!root || !root.querySelectorAll || !(pageLoadFired || document.readyState === "complete")) return 0;
        let queued = 0;
        try {
          for (const element of root.querySelectorAll(LIGHT_SURFACE_SELECTOR)) {
            if (queued >= limit) break;
            if (!element || element.nodeType !== Node.ELEMENT_NODE) continue;
            if (queueElementApply(element, 24)) queued += 1;
          }
        } catch (_) {}
        return queued;
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
        scheduleApplyQueueWatchdog(800);
        return true;
      };

      const queueElementSubtreeApply = (node, limit = ELEMENT_SUBTREE_QUEUE_LIMIT) => {
        if (!node) return 0;
        let queued = 0;
        const selector = priorityElementApplySelector();
        const queueCandidate = (element) => {
          if (!element || queued >= limit || element.nodeType !== Node.ELEMENT_NODE) return;
          if (!element.matches || !element.matches(selector)) return;
          if (queueElementApply(element, 0)) queued += 1;
        };

        if (node.nodeType === Node.ELEMENT_NODE) {
          queueCandidate(node);
        }

        if (!node.querySelectorAll) return queued;
        try {
          for (const element of node.querySelectorAll(selector)) {
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
            safeApplyElement(element);
            applied += 1;
            priorityElementApplies += 1;
            if (
              applied >= ELEMENT_APPLY_MAX_PER_SLICE
              || performance.now() - started > ELEMENT_APPLY_BUDGET_MS
            ) {
              break;
            }
          }
        } catch (error) {
          elementApplyErrors += 1;
          lastElementApplyError = `flush-element ${error && error.message ? error.message : String(error)}`;
          __wkdomainsDarkModePerf("apply-element-error", flushStartedAt, lastElementApplyError, 0);
        } finally {
          applying = wasApplying;
        }

        if (pendingElementApplyQueue.length > 0) {
          scheduleQueuedElementApplies(24);
          scheduleApplyQueueWatchdog(400);
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
          safeApplyElement(document.documentElement);
          if (document.body) safeApplyElement(document.body);
        } else if (root.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
          createShadowStaticStyleOverrides(root);
          renderAdoptedStyleSheets(root);
        } else if (root.nodeType === Node.ELEMENT_NODE) {
          if (root.matches && root.matches(ROOT_STYLE_OVERRIDE_SELECTOR)) {
            safeApplyElement(root);
          }
        }

        for (const element of root.querySelectorAll(ROOT_STYLE_OVERRIDE_SELECTOR)) {
          safeApplyElement(element);
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
        waitingForPageLoad: false,
        walker: null,
        fallbackElements: null,
        index: 0,
        matched: 0,
        scanned: 0,
        done: false
      });

      const initializeRootApplyWalker = (job, root) => {
        const walkerRoot = rootApplyWalkerRoot(root);
        if (!walkerRoot) return;
        if (walkerRoot.querySelectorAll) {
          try {
            job.fallbackElements = Array.from(walkerRoot.querySelectorAll(ROOT_STYLE_OVERRIDE_SELECTOR));
            return;
          } catch (_) {
            job.fallbackElements = [];
          }
        }
        if (document.createTreeWalker) {
          try {
            const showElement = window.NodeFilter ? NodeFilter.SHOW_ELEMENT : 1;
            job.walker = document.createTreeWalker(walkerRoot, showElement);
            return;
          } catch (_) {
            job.walker = null;
          }
        }
      };

      const nextRootApplyElement = (job, started) => {
        if (job.walker) {
          let node = job.walker.nextNode();
          let scannedThisSlice = 0;
          while (node) {
            job.scanned += 1;
            scannedThisSlice += 1;
            if (
              node.nodeType === Node.ELEMENT_NODE
              && node.matches
              && node.matches(ROOT_STYLE_OVERRIDE_SELECTOR)
            ) {
              job.matched += 1;
              return node;
            }
            if (
              scannedThisSlice >= rootApplyScanLimit()
              || performance.now() - started > rootApplyBudgetMS()
            ) {
              return undefined;
            }
            node = job.walker.nextNode();
          }
          return null;
        }

        if (job.fallbackElements) {
          while (job.index < job.fallbackElements.length) {
            const node = job.fallbackElements[job.index];
            job.index += 1;
            job.scanned += 1;
            job.matched += 1;
            return node;
          }
        }

        return null;
      };

      const processRootApplyJob = (job, started) => {
        if (!job || job.done) return true;
        const root = job.root;
        if (!root || (root.host && !root.host.isConnected)) {
          job.done = true;
          return true;
        }
        job.waitingForPageLoad = false;

        const shouldWaitForPageLoadBeforeRootScan = () => {
          if (pageLoadFired || elapsedSinceInstall() >= 7000) return false;
          if (root === document) return true;
          if (root.nodeType === Node.ELEMENT_NODE && root.matches && root.matches(ROOT_STYLE_OVERRIDE_SELECTOR)) {
            return false;
          }
          if (root.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
            return false;
          }
          return !!(root && root.querySelectorAll);
        };

        if (!job.initialized) {
          job.initialized = true;
          if (root.nodeType === Node.DOCUMENT_NODE) {
            safeApplyElement(document.documentElement);
            if (document.body) safeApplyElement(document.body);
          } else if (root.nodeType === Node.DOCUMENT_FRAGMENT_NODE && root.host) {
            createShadowStaticStyleOverrides(root);
            renderAdoptedStyleSheets(root);
          } else if (root.nodeType === Node.ELEMENT_NODE) {
            if (root.matches && root.matches(ROOT_STYLE_OVERRIDE_SELECTOR)) {
              safeApplyElement(root);
            }
          }

          if (shouldWaitForPageLoadBeforeRootScan()) {
            job.waitingForPageLoad = true;
            return false;
          }

          initializeRootApplyWalker(job, root);
        }

        if (shouldWaitForPageLoadBeforeRootScan() && !job.walker && !job.fallbackElements) {
          job.waitingForPageLoad = true;
          return false;
        }

        if (!job.walker && !job.fallbackElements) {
          initializeRootApplyWalker(job, root);
        }

        let count = 0;
        while (true) {
          const node = nextRootApplyElement(job, started);
          if (node === undefined) return false;
          if (!node) break;
          if (elementApplyIsConnected(node)) {
            safeApplyElement(node);
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
            let done = false;
            try {
              done = processRootApplyJob(job, started);
            } catch (error) {
              elementApplyErrors += 1;
              lastElementApplyError = `root-job ${error && error.message ? error.message : String(error)}`;
              __wkdomainsDarkModePerf("apply-element-error", flushStartedAt, lastElementApplyError, 0);
            }
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
        } catch (error) {
          elementApplyErrors += 1;
          lastElementApplyError = `flush-root ${error && error.message ? error.message : String(error)}`;
          __wkdomainsDarkModePerf("apply-element-error", flushStartedAt, lastElementApplyError, 0);
        } finally {
          applying = wasApplying;
        }

        if (pendingRootApplyQueue.length > 0) {
          const activeRootJob = pendingRootApplyJobs.size > 0 ? pendingRootApplyJobs.values().next().value : null;
          scheduleQueuedRootApplies(activeRootJob && activeRootJob.waitingForPageLoad ? 240 : rootApplyRescheduleDelay());
          scheduleApplyQueueWatchdog(400);
        }
        const activeRootJob = pendingRootApplyJobs.size > 0 ? pendingRootApplyJobs.values().next().value : null;
        __wkdomainsDarkModePerf(
          "flush-root-applies",
          flushStartedAt,
          `rootsDone=${count} remaining=${pendingRootApplyQueue.length} jobs=${pendingRootApplyJobs.size} active=${activeRootJob ? `matched=${activeRootJob.matched} scanned=${activeRootJob.scanned}` : "none"} startup=${rootApplyInStartupWindow()}`,
          6
        );
      };

      const scheduleQueuedRootApplies = (delay = 0) => {
        if (rootApplyScheduled) return;
        rootApplyScheduled = true;
        scheduleIdleTask(flushQueuedRootApplies, delay, 260);
      };

      const scheduleApplyQueueWatchdog = (delay = 500) => {
        if (applyQueueWatchdogTimer) return;
        applyQueueWatchdogTimer = window.setTimeout(() => {
          applyQueueWatchdogTimer = null;
          const needsElementFlush = pendingElementApplyQueue.length > 0 && !elementApplyScheduled;
          const needsRootFlush = pendingRootApplyQueue.length > 0 && !rootApplyScheduled;
          if (needsElementFlush) scheduleQueuedElementApplies(0);
          if (needsRootFlush) scheduleQueuedRootApplies(rootApplyRescheduleDelay());
          if (needsElementFlush || needsRootFlush) {
            applyQueueWatchdogTicks += 1;
            scheduleApplyQueueWatchdog(700);
          }
        }, Math.max(0, Number(delay) || 0));
      };

      const queueRootApply = (root, delay = 16) => {
        if (!root || pendingRootApplySet.has(root)) return;
        pendingRootApplySet.add(root);
        pendingRootApplyQueue.push(root);
        scheduleQueuedRootApplies(delay);
        scheduleApplyQueueWatchdog(800);
      };

      const clearCachedSourceFor = (node) => {
        if (node && node.nodeType === Node.ELEMENT_NODE) {
          sourceStyleCache.delete(node);
          inlineStyleCache.delete(node);
          elementApplyCache.delete(node);
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
