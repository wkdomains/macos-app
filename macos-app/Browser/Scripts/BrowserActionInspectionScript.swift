//
//  BrowserActionInspectionScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static func actionInspectionScript(arguments: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return """
        JSON.stringify((() => {
          const args = __WKDOMAINS_ACTION_ARGS__;
          const state = window.__wkdomainsSnapshotRefs || null;
          const action = String(args.type || args.action || "").trim().toLowerCase();
          const ref = typeof args.ref === "string" ? args.ref.trim() : "";
          const selector = typeof args.selector === "string" ? args.selector.trim() : "";
          const text = typeof args.text === "string" ? args.text.trim() : "";
          const name = typeof args.name === "string" ? args.name.trim() : "";
          const role = typeof args.role === "string" ? args.role.trim().toLowerCase() : "";
          const targetText = typeof args.targetText === "string" ? args.targetText.trim() : "";
          const targetName = typeof args.targetName === "string" ? args.targetName.trim() : "";
          const exact = args.exact !== false;
          const value = args.value == null ? "" : String(args.value);
          const key = args.key == null ? "Enter" : String(args.key);
          const direction = typeof args.direction === "string" ? args.direction.trim().toLowerCase() : "";
          const behavior = args.behavior === "smooth" ? "smooth" : "instant";
          const amount = Number.isFinite(Number(args.amount)) ? Number(args.amount) : null;
          const x = Number.isFinite(Number(args.x)) ? Number(args.x) : null;
          const y = Number.isFinite(Number(args.y)) ? Number(args.y) : null;
          const beforeURL = location.href;

          const truncate = (text, limit = 160) => {
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

          const labelFor = (element) => {
            if (!element) return null;
            const aria = element.getAttribute("aria-label");
            if (aria) return truncate(aria);
            const labelledBy = element.getAttribute("aria-labelledby");
            if (labelledBy) {
              const text = labelledBy.split(/\\s+/)
                .map((id) => document.getElementById(id))
                .filter(Boolean)
                .map((node) => node.innerText || node.textContent || "")
                .join(" ");
              if (text) return truncate(text);
            }
            if (element.id) {
              const label = document.querySelector(`label[for="${CSS.escape(element.id)}"]`);
              if (label) return truncate(label.innerText || label.textContent);
            }
            const wrappedLabel = element.closest("label");
            if (wrappedLabel) return truncate(wrappedLabel.innerText || wrappedLabel.textContent);
            const tag = element.tagName.toLowerCase();
            const type = (element.getAttribute("type") || "").toLowerCase();
            if (tag === "input" && ["button", "submit", "reset"].includes(type) && element.value) return truncate(element.value);
            const imageAlt = element.matches("img") ? element.getAttribute("alt") : element.querySelector("img[alt]")?.getAttribute("alt");
            return truncate(element.innerText || element.textContent || element.getAttribute("placeholder") || element.getAttribute("title") || imageAlt || element.getAttribute("name") || "");
          };

          const roleFor = (element) => {
            const explicit = element.getAttribute("role");
            if (explicit) return explicit.toLowerCase();
            const tag = element.tagName.toLowerCase();
            const type = (element.getAttribute("type") || "").toLowerCase();
            if (tag === "a" && element.hasAttribute("href")) return "link";
            if (tag === "button" || type === "button" || type === "submit" || type === "reset") return "button";
            if (tag === "textarea") return "textbox";
            if (tag === "select") return "combobox";
            if (tag === "input") {
              if (type === "checkbox") return "checkbox";
              if (type === "radio") return "radio";
              if (type === "range") return "slider";
              if (type === "search") return "searchbox";
              return "textbox";
            }
            if (tag === "summary") return "button";
            if (tag === "form") return "form";
            return tag;
          };

          const isVisible = (element) => {
            if (!element || !element.getBoundingClientRect) return false;
            const style = getComputedStyle(element);
            if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0
              && rect.bottom >= 0
              && rect.right >= 0
              && rect.top <= (window.innerHeight || document.documentElement.clientHeight)
              && rect.left <= (window.innerWidth || document.documentElement.clientWidth);
          };

          const normalized = (value) => String(value || "").replace(/\\s+/g, " ").trim().toLowerCase();
          const wordsFor = (value) => normalized(value).replace(/[^a-z0-9]+/g, " ").trim().split(/\\s+/).filter(Boolean);

          const matchesText = (candidate, expected) => {
            const candidateText = normalized(candidate);
            const expectedText = normalized(expected);
            if (!expectedText) return true;
            return exact ? candidateText === expectedText : candidateText.includes(expectedText);
          };

          const textScore = (candidate, expected) => {
            const candidateText = normalized(candidate);
            const expectedText = normalized(expected);
            if (!expectedText) return 0;
            if (!candidateText) return -20;
            if (candidateText === expectedText) return 120;
            if (candidateText.includes(expectedText)) return 95;
            if (expectedText.includes(candidateText)) return 70;
            if (candidateText.startsWith(expectedText) || expectedText.startsWith(candidateText)) return 68;

            const candidateWords = wordsFor(candidateText);
            const expectedWords = wordsFor(expectedText);
            if (expectedWords.length > 0 && expectedWords.every((word) => candidateWords.includes(word))) return 72;
            const overlap = expectedWords.filter((word) => candidateWords.includes(word)).length;
            const overlapScore = expectedWords.length > 0 ? Math.round((overlap / expectedWords.length) * 55) : 0;

            const left = candidateText.slice(0, 80);
            const right = expectedText.slice(0, 80);
            const rows = Array.from({ length: right.length + 1 }, (_, index) => index);
            for (let i = 1; i <= left.length; i += 1) {
              let previous = rows[0];
              rows[0] = i;
              for (let j = 1; j <= right.length; j += 1) {
                const saved = rows[j];
                rows[j] = Math.min(
                  rows[j] + 1,
                  rows[j - 1] + 1,
                  previous + (left[i - 1] === right[j - 1] ? 0 : 1)
                );
                previous = saved;
              }
            }
            const distance = rows[right.length] || 0;
            const maxLength = Math.max(left.length, right.length, 1);
            const similarity = Math.round((1 - distance / maxLength) * 45);
            return Math.max(overlapScore, similarity);
          };

          const nameValuesFor = (element) => [
            labelFor(element),
            element.innerText || element.textContent || "",
            element.getAttribute("placeholder") || "",
            element.getAttribute("title") || "",
            element.matches("input, textarea, select") ? element.value : "",
            element.getAttribute("name") || "",
            element.id || ""
          ];

          const shouldRedactElementValue = (element) => {
            if (!element || !element.matches("input, textarea, select")) return false;
            const type = (element.getAttribute("type") || "").toLowerCase();
            if (["password", "hidden"].includes(type)) return true;
            const haystack = [
              element.id,
              element.getAttribute("name"),
              element.getAttribute("autocomplete"),
              element.getAttribute("aria-label"),
              element.getAttribute("placeholder"),
              labelFor(element)
            ].join(" ");
            return /(password|passcode|otp|one[-\\s]?time|2fa|mfa|code|token|secret|session|auth)/i.test(haystack);
          };

          const matchesName = (element, expected) => {
            if (!expected) return true;
            return nameValuesFor(element).some((value) => matchesText(value, expected));
          };

          const summaryFor = (element) => {
            if (!element || !element.tagName) return null;
            return {
              tag: element.tagName.toLowerCase(),
              type: element.getAttribute("type") || null,
              id: element.id || null,
              name: element.getAttribute("name") || null,
              role: roleFor(element),
              label: labelFor(element),
              text: truncate(element.innerText || element.textContent || "", 120),
              value: element.matches("input, textarea, select") ? (shouldRedactElementValue(element) && element.value ? "[redacted]" : truncate(element.value, 80)) : null,
              disabled: !!(element.disabled || element.getAttribute("aria-disabled") === "true"),
              rect: rectFor(element)
            };
          };

          const fail = (message) => ({
            ok: false,
            action,
            error: message,
            ref: ref || null,
            selector: selector || null,
            text: text || targetText || null,
            name: name || targetName || null,
            role: role || null,
            url: location.href,
            activeElement: summaryFor(document.activeElement)
          });

          if (!action) return fail("Missing action type.");

          const byRef = ref && state && state.elements ? state.elements.get(ref) : null;
          let bySelector = null;
          if (!byRef && selector) {
            try {
              bySelector = document.querySelector(selector);
            } catch (error) {
              return fail(`Invalid selector: ${error.message || error}`);
            }
          }

          const queryTarget = () => {
            const expectedText = text || targetText;
            const expectedName = name || targetName;
            if (!expectedText && !expectedName && !role) return null;

            const selectorList = [
              "a[href]",
              "button",
              "input:not([type='hidden'])",
              "textarea",
              "select",
              "summary",
              "[contenteditable='true']",
              "[role='button']",
              "[role='link']",
              "[role='menuitem']",
              "[role='tab']",
              "[role='checkbox']",
              "[role='radio']",
              "[role='switch']",
              "[role='textbox']",
              "[role='combobox']",
              "[role='searchbox']"
            ].join(",");

            const allCandidates = Array.from(document.querySelectorAll(selectorList)).filter(isVisible);
            const rankedCandidates = allCandidates
              .map((element) => {
                const elementRole = roleFor(element);
                const roleScore = !role ? 0 : (elementRole === role ? 40 : -45);
                const bestNameScore = expectedName
                  ? Math.max(...nameValuesFor(element).map((value) => textScore(value, expectedName)))
                  : 0;
                const textCandidate = element.innerText || element.textContent || labelFor(element);
                const bestTextScore = expectedText ? textScore(textCandidate, expectedText) : 0;
                const disabledPenalty = (element.disabled || element.getAttribute("aria-disabled") === "true") ? 15 : 0;
                return {
                  element,
                  score: roleScore + bestNameScore + bestTextScore - disabledPenalty,
                  roleMatched: role ? elementRole === role : null,
                  nameMatched: expectedName ? matchesName(element, expectedName) : null,
                  textMatched: expectedText ? matchesText(textCandidate, expectedText) : null
                };
              })
              .sort((left, right) => right.score - left.score);

            const candidates = rankedCandidates
              .filter((candidate) => candidate.roleMatched !== false)
              .map((candidate) => candidate.element)
              .filter((element) => matchesName(element, expectedName))
              .filter((element) => !expectedText || matchesText(element.innerText || element.textContent || labelFor(element), expectedText));

            const nearMatches = rankedCandidates.slice(0, 10).map((candidate) => ({
              ...summaryFor(candidate.element),
              score: candidate.score,
              matched: {
                role: candidate.roleMatched,
                name: candidate.nameMatched,
                text: candidate.textMatched
              }
            }));

            if (candidates.length === 0) return { element: null, candidates: nearMatches, nearMatches };
            return {
              element: candidates[0],
              candidates: candidates.slice(0, 8).map(summaryFor),
              nearMatches
            };
          };

          const byQuery = (!byRef && !bySelector) ? queryTarget() : null;
          const usesActiveElement = args.active === true || (!ref && !selector && !text && !name && !role && !targetText && !targetName && action === "press");
          const target = usesActiveElement ? document.activeElement : (byRef || bySelector || byQuery?.element);
          const scrollPosition = () => {
            const scrolling = document.scrollingElement || document.documentElement;
            return {
              x: Math.round(window.scrollX || scrolling.scrollLeft || 0),
              y: Math.round(window.scrollY || scrolling.scrollTop || 0),
              maxX: Math.max(0, Math.round(scrolling.scrollWidth - window.innerWidth)),
              maxY: Math.max(0, Math.round(scrolling.scrollHeight - window.innerHeight)),
              viewportWidth: window.innerWidth,
              viewportHeight: window.innerHeight,
              documentWidth: scrolling.scrollWidth,
              documentHeight: scrolling.scrollHeight
            };
          };

          const scrollPage = (element) => {
            const before = scrollPosition();
            if (element && element !== document.body && element !== document.documentElement) {
              try {
                element.scrollIntoView({ block: args.block || "center", inline: args.inline || "nearest", behavior });
              } catch (_) {
                element.scrollIntoView();
              }
              return { before, after: scrollPosition(), mode: "element" };
            }

            const scrolling = document.scrollingElement || document.documentElement;
            const viewportStep = Math.max(120, Math.round((window.innerHeight || 720) * 0.82));
            const step = amount == null ? viewportStep : amount;
            let deltaX = x == null ? 0 : x;
            let deltaY = y == null ? 0 : y;

            if (direction === "up") deltaY = -step;
            if (direction === "down" || (!direction && x == null && y == null)) deltaY = step;
            if (direction === "left") deltaX = -step;
            if (direction === "right") deltaX = step;
            if (direction === "top") deltaY = -before.y;
            if (direction === "bottom") deltaY = before.maxY - before.y;

            window.scrollBy({ left: deltaX, top: deltaY, behavior });
            return { before, after: scrollPosition(), mode: "page", deltaX, deltaY };
          };

          if (action === "scroll") {
            try {
              const scroll = scrollPage(target);
              return {
                ok: true,
                action,
                ref: ref || null,
                selector: selector || null,
                text: text || targetText || null,
                name: name || targetName || null,
                role: role || null,
                targetStrategy: byRef ? "ref" : bySelector ? "selector" : byQuery?.element ? "query" : null,
                candidates: byQuery?.candidates || [],
                nearMatches: byQuery?.nearMatches || [],
                beforeURL,
                url: location.href,
                scroll,
                target: target ? summaryFor(target) : null,
                activeElement: summaryFor(document.activeElement)
              };
            } catch (error) {
              return fail(error && error.message ? error.message : String(error));
            }
          }

          if (!target || target === document.body || target === document.documentElement) {
            const failure = fail("Target element was not found. Provide ref, selector, text/name/role, or active:true for press.");
            if (byQuery) failure.candidates = byQuery.candidates;
            if (byQuery?.nearMatches) failure.nearMatches = byQuery.nearMatches;
            return failure;
          }

          const focusElement = (element) => {
            if (!element) return;
            try {
              element.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
            } catch (_) {
              element.scrollIntoView();
            }
            if (typeof element.focus === "function") {
              try {
                element.focus({ preventScroll: true });
              } catch (_) {
                element.focus();
              }
            }
          };

          const dispatchInput = (element, data) => {
            try {
              element.dispatchEvent(new InputEvent("input", {
                bubbles: true,
                cancelable: true,
                data,
                inputType: "insertReplacementText"
              }));
            } catch (_) {
              element.dispatchEvent(new Event("input", { bubbles: true, cancelable: true }));
            }
            element.dispatchEvent(new Event("change", { bubbles: true }));
          };

          const setNativeValue = (element, nextValue) => {
            const tag = element.tagName.toLowerCase();
            const prototype = tag === "textarea" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
            if (descriptor && descriptor.set) {
              descriptor.set.call(element, nextValue);
            } else {
              element.value = nextValue;
            }
          };

          const fillElement = (element, nextValue) => {
            focusElement(element);
            if (element.isContentEditable) {
              element.textContent = nextValue;
              dispatchInput(element, nextValue);
              return;
            }
            if (element.matches("input, textarea")) {
              setNativeValue(element, nextValue);
              dispatchInput(element, nextValue);
              return;
            }
            throw new Error("Target is not fillable.");
          };

          const selectElement = (element, nextValue) => {
            focusElement(element);
            if (!element.matches("select")) throw new Error("Target is not a select.");
            element.value = nextValue;
            element.dispatchEvent(new Event("input", { bubbles: true }));
            element.dispatchEvent(new Event("change", { bubbles: true }));
          };

          const submitFrom = (element) => {
            const form = element.matches("form") ? element : element.form || element.closest("form");
            if (!form) throw new Error("No form is associated with the target.");
            if (typeof form.requestSubmit === "function") {
              form.requestSubmit(element.matches("button, input[type='submit']") ? element : undefined);
            } else {
              form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
            }
          };

          const pressKey = (element, nextKey) => {
            focusElement(element);
            const eventInit = {
              key: nextKey,
              code: nextKey === "Enter" ? "Enter" : nextKey,
              bubbles: true,
              cancelable: true
            };
            const keydownAllowed = element.dispatchEvent(new KeyboardEvent("keydown", eventInit));
            element.dispatchEvent(new KeyboardEvent("keyup", eventInit));

            if (nextKey === "Enter" && keydownAllowed && element.form) {
              submitFrom(element);
            }
          };

          try {
            if (action === "focus") {
              focusElement(target);
            } else if (action === "click") {
              focusElement(target);
              target.click();
            } else if (action === "fill" || action === "setvalue") {
              fillElement(target, value);
            } else if (action === "clear") {
              fillElement(target, "");
            } else if (action === "select") {
              selectElement(target, value);
            } else if (action === "submit") {
              submitFrom(target);
            } else if (action === "press") {
              pressKey(target, key);
            } else {
              return fail(`Unsupported action: ${action}`);
            }
          } catch (error) {
            return fail(error && error.message ? error.message : String(error));
          }

          return {
            ok: true,
            action,
            ref: ref || null,
            selector: selector || null,
            text: text || targetText || null,
            name: name || targetName || null,
            role: role || null,
            targetStrategy: byRef ? "ref" : bySelector ? "selector" : byQuery?.element ? "query" : usesActiveElement ? "active" : null,
            candidates: byQuery?.candidates || [],
            nearMatches: byQuery?.nearMatches || [],
            beforeURL,
            url: location.href,
            target: summaryFor(target),
            activeElement: summaryFor(document.activeElement)
          };
        })())
        """.replacingOccurrences(of: "__WKDOMAINS_ACTION_ARGS__", with: json)
    }
}
