//
//  BrowserDarkModeInlineApplyScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeInlineApplyScript = #"""
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
          if (scheduleSVGImageAnalysisIfNeeded(element)) {
            setOverride(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", null);
            setOverride(element, STROKE_ATTRIBUTE, "--wkdomains-forced-dark-stroke", null);
            return;
          }
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
        element.removeAttribute(LEGACY_BACKGROUND_ATTRIBUTE);
        if (element && element.style) element.style.removeProperty("--wkdomains-forced-dark-legacy-color");
        setOverride(element, LEGACY_TEXT_ATTRIBUTE, "--wkdomains-forced-dark-legacy-text-color", null);
        setOverride(element, LEGACY_LINK_ATTRIBUTE, "--wkdomains-forced-dark-legacy-link-color", null);
        setOverride(element, LEGACY_VISITED_LINK_ATTRIBUTE, "--wkdomains-forced-dark-legacy-vlink-color", null);
        setOverride(element, LEGACY_ACTIVE_LINK_ATTRIBUTE, "--wkdomains-forced-dark-legacy-alink-color", null);
        setOverride(element, IMAGE_FILTER_ATTRIBUTE, "--wkdomains-forced-dark-image-filter", null);
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
        if (element.parentElement && element.parentElement.dataset && element.parentElement.dataset.nodeViewContent) {
          return;
        }
        if (inlineElementsLastChanges.has(element)) {
          if (Date.now() - inlineElementsLastChanges.get(element) < INLINE_LOOP_DETECTION_THRESHOLD_MS) {
            inlineElementsLoopCycles.set(element, (inlineElementsLoopCycles.get(element) || 0) + 1);
          } else {
            inlineElementsLoopCycles.delete(element);
          }
          if ((inlineElementsLoopCycles.get(element) || 0) >= INLINE_LOOP_MAX_CYCLES) {
            return;
          }
        }
        const key = inlineCacheKeyFor(element);
        if (inlineStyleCache.get(element) === key) return;

        if (shouldIgnoreInlineStyle(element)) {
          clearInlineOverrides(element);
          inlineStyleCache.set(element, key);
          return;
        }

        const normalizeLegacyColorValue = (value) => {
          const text = String(value || "").trim();
          if (/^[0-9a-f]{3}$/i.test(text) || /^[0-9a-f]{4}$/i.test(text) || /^[0-9a-f]{6}$/i.test(text) || /^[0-9a-f]{8}$/i.test(text)) return `#${text}`;
          return text;
        };

        const setLegacyBackgroundTextFallback = (element, sourceColorValue) => {
          const sourceBackground = parseColor(sourceColorValue);
          const transformedBackground = sourceBackground ? parseColor(transformBackground(sourceBackground, element)) : null;
          const sourceStyle = captureSourceStyle(element) || getComputedStyle(element);
          const sourceColor = parseColor(sourceStyle.color) || DEFAULT_TEXT;
          const transformedColor = transformForeground(sourceColor) || toThemeRGBA(themeTextColor());
          element.setAttribute(LEGACY_BACKGROUND_ATTRIBUTE, "");
          if (
            transformedBackground
            && relativeLuminance(transformedBackground) < 0.48
            && relativeLuminance(sourceColor) < 0.56
          ) {
            element.style.setProperty("--wkdomains-forced-dark-legacy-color", transformedColor);
          } else {
            element.style.removeProperty("--wkdomains-forced-dark-legacy-color");
          }
        };

        if (element.hasAttribute("bgcolor")) {
          const value = normalizeLegacyColorValue(element.getAttribute("bgcolor") || "");
          setInlineCustomProp(element, BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", "background-color", "background-color", value);
          setLegacyBackgroundTextFallback(element, value);
        } else {
          element.removeAttribute(LEGACY_BACKGROUND_ATTRIBUTE);
          element.style.removeProperty("--wkdomains-forced-dark-legacy-color");
        }

        if (element.tagName && element.tagName.toUpperCase() === "BODY") {
          const legacyBodyColorAttrs = [
            ["text", LEGACY_TEXT_ATTRIBUTE, "--wkdomains-forced-dark-legacy-text-color"],
            ["link", LEGACY_LINK_ATTRIBUTE, "--wkdomains-forced-dark-legacy-link-color"],
            ["vlink", LEGACY_VISITED_LINK_ATTRIBUTE, "--wkdomains-forced-dark-legacy-vlink-color"],
            ["alink", LEGACY_ACTIVE_LINK_ATTRIBUTE, "--wkdomains-forced-dark-legacy-alink-color"]
          ];
          for (const [sourceAttribute, markerAttribute, customProperty] of legacyBodyColorAttrs) {
            const value = element.hasAttribute(sourceAttribute)
              ? transformCSSValue("color", normalizeLegacyColorValue(element.getAttribute(sourceAttribute) || ""), element)
              : null;
            setOverride(element, markerAttribute, customProperty, value);
          }
        }

        if ((element === document.documentElement || element === document.body) && element.hasAttribute("background")) {
          setOverride(element, BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", "none");
        }

        if (element.hasAttribute("color") && element.rel !== "mask-icon") {
          let value = element.getAttribute("color") || "";
          if (/^[0-9a-f]{3}$/i.test(value) || /^[0-9a-f]{6}$/i.test(value)) value = `#${value}`;
          else if (/^#?[0-9a-f]{4}$/i.test(value)) {
            const hex = value.startsWith("#") ? value.slice(1) : value;
            value = `#${hex}00`;
          }
          setInlineCustomProp(element, COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", "color", "color", value);
        }

        if (isSVGElementNode(element)) {
          if (element.hasAttribute("fill")) {
            const value = element.getAttribute("fill");
            if (value && value !== "none" && value !== "currentColor") {
              setInlineCustomProp(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", "fill", svgFillModifierProperty(element), value);
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
            setInlineCustomProp(element, FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", "fill", isSVGElementNode(element) ? svgFillModifierProperty(element) : property, value);
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
        inlineElementsLastChanges.set(element, Date.now());
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
    """#
}
