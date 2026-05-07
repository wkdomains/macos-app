//
//  BrowserDarkModeStylesheetStateScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetStateScript = #"""
      const styleManagers = new WeakMap();
      const adoptedStyleManagers = new WeakMap();
      const managedStyleElements = new Set();
      const managedAdoptedRoots = new Set();
      const adoptedStyleListenersByRoot = new WeakMap();
      let stylesheetSyncScheduled = false;
      let stylesheetSyncTimer = null;
      let stylesheetSyncNeeded = true;
      let stylesheetProxyActive = false;
      let loadingStylesCounter = 0;
      const loadingStyles = new Set();
      const loadingStyleIDsByElement = new WeakMap();
      const loadingStyleListenersByElement = new WeakMap();
      const loadingStyleTimeoutsByElement = new WeakMap();
      const unavailableStyleElements = new WeakSet();
      const registeredCustomPropertyTypes = new Map();
      let fallbackWasCleared = false;
      const LOADING_STYLE_TIMEOUT = 3500;
      const STYLE_UPDATE_EVENT = "__darkreader__updateSheet";
      const ADOPTED_STYLE_CHANGE_EVENT = "__darkreader__adoptedStyleSheetChange";
      const ADOPTED_STYLES_CHANGE_EVENT = "__darkreader__adoptedStyleSheetsChange";
      const ADOPTED_DECLARATION_CHANGE_EVENT = "__darkreader__adoptedStyleDeclarationChange";

      const withStylesheetProxyDisabled = (callback) => {
        const wasActive = stylesheetProxyActive;
        stylesheetProxyActive = false;
        try {
          return callback();
        } finally {
          stylesheetProxyActive = wasActive;
        }
      };

      const cssURLMatchesPattern = (url, pattern) => {
        const value = String(url || "");
        const text = String(pattern || "");
        if (!value || !text) return false;
        if (value.includes(text)) return true;
        try {
          const escaped = text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replaceAll("\\*", ".*");
          return new RegExp(`^${escaped}$`).test(value);
        } catch (_) {
          return false;
        }
      };

      const shouldIgnoreCSSURL = (url) => ignoredCSSURLPatterns.some((pattern) => cssURLMatchesPattern(url, pattern));

      const shouldManageStyle = (element) => {
        if (!element || !element.matches || !element.matches(STYLE_SELECTOR)) return false;
        if (element.classList.contains(INLINE_CLASS) || element.classList.contains("darkreader") || element.classList.contains("stylus")) return false;
        const media = String(element.media || "").toLowerCase();
        if (media.includes("print") || media.includes("speech")) return false;
        if (element instanceof HTMLLinkElement && (!element.href || element.disabled || shouldIgnoreCSSURL(element.href))) return false;
        return true;
      };

      const getManageableStyles = (root, results = []) => {
        if (!root) return results;
        if (shouldManageStyle(root)) {
          results.push(root);
          return results;
        }
        if (root.querySelectorAll) {
          for (const element of root.querySelectorAll(STYLE_SELECTOR)) {
            if (shouldManageStyle(element)) results.push(element);
          }
        }
        return results;
      };

      const getRulesOrError = (sheet) => {
        try {
          if (!sheet) return { rules: null, error: null };
          return { rules: sheet.cssRules || null, error: null };
        } catch (error) {
          return { rules: null, error };
        }
      };

      const safeGetRules = (sheet) => getRulesOrError(sheet).rules;

      const getStyleElementRulesOrError = (element) => {
        let sheet = null;
        try {
          sheet = element ? element.sheet : null;
        } catch (error) {
          return { rules: null, error, hasSheet: false };
        }

        const result = getRulesOrError(sheet);
        return {
          rules: result.rules,
          error: result.error,
          hasSheet: !!sheet
        };
      };

      const styleRulesAreStillLoading = (element, access) => {
        if (!element) return false;
        if (!access.rules && !access.error && document.readyState === "loading") return true;
        if (element instanceof HTMLLinkElement) {
          if (!access.hasSheet) return true;
          const message = String(access.error && access.error.message || "").toLowerCase();
          return message.includes("loading");
        }
        return document.readyState === "loading" && !access.hasSheet;
      };

      const fallbackStyleElement = () => (
        findStaticStyle("wkdomains-darkreader--fallback", document)
        || createOrUpdateStyle("wkdomains-darkreader--fallback", document)
      );

      const ensureFallbackStyleText = () => {
        const fallbackStyle = fallbackStyleElement();
        fallbackStyle.id = STYLE_ID;
        if (!fallbackStyle.textContent) {
          fallbackStyle.textContent = getFallbackStyle();
        }
        injectStaticStyle(fallbackStyle, null, "fallback");
        fallbackWasCleared = false;
      };

      const cleanFallbackStyle = () => {
        if (loadingStyles.size > 0) return;
        const fallbackStyle = fallbackStyleElement();
        fallbackStyle.textContent = "";
        fallbackWasCleared = true;
      };

      const loadingIDForElement = (element) => {
        let id = loadingStyleIDsByElement.get(element);
        if (!id) {
          id = ++loadingStylesCounter;
          loadingStyleIDsByElement.set(element, id);
        }
        return id;
      };

      const isStyleLoading = (element) => {
        const id = loadingStyleIDsByElement.get(element);
        return !!id && loadingStyles.has(id);
      };

      const markStyleLoading = (element) => {
        if (!element) return;
        unavailableStyleElements.delete(element);
        const id = loadingIDForElement(element);
        loadingStyles.add(id);
        ensureFallbackStyleText();

        if (element instanceof HTMLLinkElement && !loadingStyleListenersByElement.has(element)) {
          const done = () => {
            element.removeEventListener("load", done);
            element.removeEventListener("error", done);
            loadingStyleListenersByElement.delete(element);
            markStyleLoaded(element);
            scheduleStyleSync(0);
          };
          element.addEventListener("load", done, { once: true });
          element.addEventListener("error", done, { once: true });
          loadingStyleListenersByElement.set(element, done);
        }

        if (!loadingStyleTimeoutsByElement.has(element)) {
          const timeout = window.setTimeout(() => {
            loadingStyleTimeoutsByElement.delete(element);
            markStyleUnavailable(element);
            scheduleStyleSync(0);
          }, LOADING_STYLE_TIMEOUT);
          loadingStyleTimeoutsByElement.set(element, timeout);
        }
      };

      const markStyleLoaded = (element) => {
        if (!element) return;
        const id = loadingStyleIDsByElement.get(element);
        if (id) {
          loadingStyles.delete(id);
        }
        const listener = loadingStyleListenersByElement.get(element);
        if (listener && element instanceof HTMLLinkElement) {
          element.removeEventListener("load", listener);
          element.removeEventListener("error", listener);
          loadingStyleListenersByElement.delete(element);
        }
        const timeout = loadingStyleTimeoutsByElement.get(element);
        if (timeout) {
          window.clearTimeout(timeout);
          loadingStyleTimeoutsByElement.delete(element);
        }
        if (loadingStyles.size === 0 && document.readyState !== "loading") {
          cleanFallbackStyle();
        }
      };

      const markStyleUnavailable = (element) => {
        if (!element) return;
        unavailableStyleElements.add(element);
        markStyleLoaded(element);
      };

      const markStyleAccessible = (element) => {
        if (!element) return;
        unavailableStyleElements.delete(element);
        markStyleLoaded(element);
      };

      const shorthandVarDependentProperties = [
        "background",
        "border",
        "border-color",
        "border-bottom",
        "border-left",
        "border-right",
        "border-top",
        "outline",
        "outline-color"
      ];

      const escapeRegExp = (value) => String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

      const iterateCSSDeclarations = (style, iterate) => {
        const cssText = style.cssText || "";
        const seen = new Set();
        const emit = (property, value) => {
          const prop = String(property || "").trim();
          const val = String(value || "").trim();
          if (!prop || !val || seen.has(prop)) return;
          seen.add(prop);
          iterate(prop, val);
        };

        if (cssText.includes("var(")) {
          for (const property of shorthandVarDependentProperties) {
            let value = "";
            try {
              value = style.getPropertyValue(property);
            } catch (_) {}
            if (value && value.includes("var(")) {
              emit(property, value);
              continue;
            }

            const match = cssText.match(new RegExp(`${escapeRegExp(property)}\\s*:\\s*([^;]+)`));
            if (match && match[1] && match[1].includes("var(")) {
              emit(property, match[1]);
            }
          }
        }

        if ((cssText.includes("background-color: ;") || cssText.includes("background-image: ;")) && !style.getPropertyValue("background")) {
          const match = cssText.match(/background\s*:\s*([^;]+)/);
          if (match && match[1]) {
            emit("background", match[1]);
          }
        }

        for (let index = 0; index < style.length; index += 1) {
          const property = style.item(index);
          emit(property, style.getPropertyValue(property));
        }
      };

      const shouldTreatCustomPropertyAsBackground = (property) => (
        property.includes("bg")
        || property.includes("background")
        || property.includes("surface")
        || property.includes("container")
        || property.includes("canvas")
        || property.includes("fill")
      );

      const shouldTreatCustomPropertyAsBorder = (property) => (
        property.includes("border")
        || property.includes("outline")
        || property.includes("divider")
        || property.includes("stroke")
        || property.includes("shadow")
      );

      const shouldTreatCustomPropertyAsRawColor = (property) => {
        const prop = String(property || "").toLowerCase();
        return prop.includes("color")
          || prop.includes("colour")
          || prop.includes("background")
          || prop.includes("bg")
          || prop.includes("surface")
          || prop.includes("canvas")
          || prop.includes("border")
          || prop.includes("outline")
          || prop.includes("divider")
          || prop.includes("fill")
          || prop.includes("stroke")
          || prop.includes("text")
          || prop.includes("content")
          || prop.includes("tone")
          || prop.includes("neutral")
          || prop.includes("primary")
          || prop.includes("secondary")
          || prop.includes("accent")
          || prop.includes("brand")
          || prop.includes("link");
      };

      const wrappedVariableName = (type, name) => `${DARK_VAR_PREFIX}-${type}-${name.slice(2)}`;
      const VAR_TYPE_BG = 1 << 0;
      const VAR_TYPE_TEXT = 1 << 1;
      const VAR_TYPE_BORDER = 1 << 2;
      const VAR_TYPE_BG_IMG = 1 << 3;

      const cssVariableTypeForProperty = (property) => {
        const prop = property.toLowerCase();
        if (prop.startsWith("--")) {
          if (shouldTreatCustomPropertyAsBackground(prop)) return "bg";
          if (shouldTreatCustomPropertyAsBorder(prop)) return "border";
          return "text";
        }
        if (prop.startsWith("background") || prop === "box-shadow" || prop === "text-shadow") {
          return "bg";
        }
        if (prop === "fill" || prop === "stroke" || prop === "stop-color") {
          return "text";
        }
        if (prop.includes("border") || prop === "outline" || prop === "outline-color" || prop === "column-rule" || prop === "column-rule-color" || prop === "text-decoration-color" || prop === "stroke") {
          return "border";
        }
        return "text";
      };

      const shouldTransformVariableDependentProperty = (property) => {
        const prop = String(property || "").toLowerCase();
        return prop === "color"
          || prop === "-webkit-text-fill-color"
          || prop === "text-emphasis-color"
          || prop === "caret-color"
          || prop === "fill"
          || prop === "stroke"
          || prop === "stop-color"
          || prop === "box-shadow"
          || prop === "text-shadow"
          || prop === "outline"
          || prop === "outline-color"
          || prop === "column-rule"
          || prop === "column-rule-color"
          || prop === "text-decoration-color"
          || prop.startsWith("background")
          || prop.startsWith("border")
          || (prop.includes("color") && prop !== "-webkit-print-color-adjust");
      };

      const variableTypeNumberForProperty = (property, value = "") => {
        const prop = String(property || "").toLowerCase();
        if (prop === "background-image") return VAR_TYPE_BG_IMG;
        if (prop === "background" && /url\(|gradient\(/i.test(String(value || ""))) return VAR_TYPE_BG_IMG;
        switch (cssVariableTypeForProperty(prop)) {
        case "bg":
          return VAR_TYPE_BG;
        case "border":
          return VAR_TYPE_BORDER;
        default:
          return VAR_TYPE_TEXT;
        }
      };

      const findTopLevelComma = (value) => {
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

      const readCSSVariableReferenceAt = (value, index) => {
        const text = String(value || "");
        const previous = index > 0 ? text[index - 1] : "";
        if (previous && /[-_a-z0-9]/i.test(previous)) return null;
        if (text.slice(index, index + 4).toLowerCase() !== "var(") return null;

        const open = index + 3;
        const close = findMatchingParen(text, open);
        if (close < 0) return null;

        const body = text.slice(open + 1, close).trim();
        const comma = findTopLevelComma(body);
        const name = (comma < 0 ? body : body.slice(0, comma)).trim();
        if (!/^--[-_a-zA-Z0-9]+$/.test(name)) return null;

        return {
          name,
          fallback: comma < 0 ? "" : body.slice(comma + 1).trim(),
          start: index,
          end: close + 1,
          token: text.slice(index, close + 1)
        };
      };

      const forEachVarReference = (value, iterate) => {
        const text = String(value || "");
        if (!text.includes("var(")) return;

        let index = 0;
        while (index < text.length) {
          const reference = readCSSVariableReferenceAt(text, index);
          if (!reference) {
            index += 1;
            continue;
          }

          iterate(reference.name, reference.fallback || "");
          if (reference.fallback && reference.fallback.includes("var(")) {
            forEachVarReference(reference.fallback, iterate);
          }
          index = reference.end;
        }
      };
    """#
}
