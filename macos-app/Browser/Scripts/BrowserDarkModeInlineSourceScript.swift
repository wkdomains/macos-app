//
//  BrowserDarkModeInlineSourceScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeInlineSourceScript = #"""
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
        "[role='banner']",
        "[role='toolbar']",
        "[role='heading']",
        "[role='region'][aria-label]",
        "[role='form']",
        "header",
        "[class*='modal' i]",
        "[class*='dialog' i]",
        "[class*='popover' i]",
        "[class*='popup' i]",
        "[class*='drawer' i]",
        "[class*='header' i]",
        "[class*='panel' i]",
        "[class*='surface' i]",
        "[class*='sheet' i]",
        "[class*='titlebar' i]",
        "[class*='title-bar' i]",
        "[class*='toolbar' i]"
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

      const inlineCacheKeyFor = (element) => [
        ...INLINE_STYLE_ATTRS.map((attr) => {
          if (attr === "style") return `style=${inlineStyleSourceKeyForElement(element)}`;
          return `${attr}=${element.getAttribute(attr) || ""}`;
        }),
        ...(element && element.tagName && element.tagName.toUpperCase() === "BODY"
          ? LEGACY_BODY_STYLE_ATTRS.map((attr) => `${attr}=${element.getAttribute(attr) || ""}`)
          : [])
      ].join("\n");

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
        if (["banner", "toolbar", "heading"].includes(role)) return true;
        if (element.hasAttribute("popover") || element.getAttribute("aria-modal") === "true") return true;
        if (element.matches("main, article, dialog, form, header")) return true;

        const className = String(element.className || "");
        if (/\b(modal|dialog|popover|popup|drawer|panel|surface|sheet|editor|toolbar|titlebar|title-bar|header)\b/i.test(className)) {
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

      const svgFillModifierProperty = (element) => {
        if (!isSVGElementNode(element) || isSVGTextElementNode(element)) return "color";
        if (document.readyState !== "complete") return "color";
        const root = svgRootFor(element);
        if (!root) return "color";
        let rootIsSmall = false;
        if (svgRootSizeTestResults.has(root)) {
          rootIsSmall = svgRootSizeTestResults.get(root);
        } else {
          try {
            const rootBounds = root.getBoundingClientRect();
            rootIsSmall = rootBounds.width * rootBounds.height <= SMALL_SVG_THRESHOLD * SMALL_SVG_THRESHOLD;
          } catch (_) {
            rootIsSmall = true;
          }
          svgRootSizeTestResults.set(root, rootIsSmall);
        }
        if (rootIsSmall) return "color";
        try {
          const bounds = element.getBoundingClientRect();
          return bounds.width > SMALL_SVG_THRESHOLD || bounds.height > SMALL_SVG_THRESHOLD
            ? "background-color"
            : "color";
        } catch (_) {
          return "color";
        }
      };

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

    """#
}
