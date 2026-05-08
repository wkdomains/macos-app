//
//  BrowserDarkModeInlineStateScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeInlineStateScript = #"""
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
        if (backgroundImage && backgroundImage !== "none" && /(?:^|,)\s*(?:-webkit-)?(?:cross-fade|image-set)\(/i.test(backgroundImage)) {
          return true;
        }
        if (backgroundImage && backgroundImage !== "none" && backgroundImage.includes("url(")) {
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
    """#
}
