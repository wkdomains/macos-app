//
//  BrowserWaitInspectionScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static func waitInspectionScript(arguments: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return """
        JSON.stringify((() => {
          const waitFor = __WKDOMAINS_WAIT_ARGS__;
          const truncate = (text, limit = 180) => {
            const value = String(text || "").replace(/\\s+/g, " ").trim();
            return value.length > limit ? `${value.slice(0, limit)}...` : value;
          };
          const rectFor = (element) => {
            if (!element || !element.getBoundingClientRect) return null;
            const rect = element.getBoundingClientRect();
            return {
              x: Math.round(rect.x),
              y: Math.round(rect.y),
              width: Math.round(rect.width),
              height: Math.round(rect.height),
              top: Math.round(rect.top),
              right: Math.round(rect.right),
              bottom: Math.round(rect.bottom),
              left: Math.round(rect.left)
            };
          };
          const visible = (element) => {
            if (!element || !element.getBoundingClientRect) return false;
            const style = getComputedStyle(element);
            if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0;
          };
          const elementSummary = (element) => element ? {
            tag: element.tagName.toLowerCase(),
            id: element.id || null,
            role: element.getAttribute("role") || null,
            type: element.getAttribute("type") || null,
            label: truncate(element.getAttribute("aria-label") || element.innerText || element.textContent || element.getAttribute("placeholder") || element.getAttribute("title")),
            value: element.matches("input, textarea, select") ? truncate(element.value, 120) : null,
            visible: visible(element),
            rect: rectFor(element)
          } : null;
          const result = {
            ok: true,
            matched: [],
            url: location.href,
            title: document.title || null,
            readyState: document.readyState,
            checkedAt: new Date().toISOString()
          };
          const fail = (reason, extra = {}) => ({
            ...result,
            ok: false,
            reason,
            ...extra
          });

          if (!waitFor || typeof waitFor !== "object") {
            return result;
          }

          if (waitFor.url && location.href !== String(waitFor.url)) {
            return fail("url", { expectedURL: String(waitFor.url) });
          }
          if (waitFor.urlContains && !location.href.includes(String(waitFor.urlContains))) {
            return fail("urlContains", { expectedURLContains: String(waitFor.urlContains) });
          }
          if (waitFor.titleContains && !(document.title || "").includes(String(waitFor.titleContains))) {
            return fail("titleContains", { expectedTitleContains: String(waitFor.titleContains) });
          }
          if (waitFor.readyState && document.readyState !== String(waitFor.readyState)) {
            return fail("readyState", { expectedReadyState: String(waitFor.readyState) });
          }
          if (waitFor.text || waitFor.textIncludes) {
            const expectedText = String(waitFor.text || waitFor.textIncludes);
            const text = document.body ? document.body.innerText || document.body.textContent || "" : "";
            if (!text.includes(expectedText)) {
              return fail("text", { expectedText: expectedText });
            }
          }
          if (waitFor.selector) {
            let element = null;
            try {
              element = document.querySelector(String(waitFor.selector));
            } catch (error) {
              return fail("selector", { selector: String(waitFor.selector), error: error.message || String(error) });
            }
            if (!element || (waitFor.visible !== false && !visible(element))) {
              return fail("selector", { selector: String(waitFor.selector), element: elementSummary(element) });
            }
            result.element = elementSummary(element);
          }
          if (waitFor.selectorGone) {
            let element = null;
            try {
              element = document.querySelector(String(waitFor.selectorGone));
            } catch (error) {
              return fail("selectorGone", { selectorGone: String(waitFor.selectorGone), error: error.message || String(error) });
            }
            if (element && visible(element)) {
              return fail("selectorGone", { selectorGone: String(waitFor.selectorGone), element: elementSummary(element) });
            }
          }

          return result;
        })())
        """.replacingOccurrences(of: "__WKDOMAINS_WAIT_ARGS__", with: json)
    }
}
