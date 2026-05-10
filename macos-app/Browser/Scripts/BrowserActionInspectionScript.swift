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
          const scrollStyle = typeof args.style === "string" ? args.style.trim().toLowerCase() : "";
          const amount = Number.isFinite(Number(args.amount)) ? Number(args.amount) : null;
          const durationMs = Number.isFinite(Number(args.durationMs))
            ? Math.min(Math.max(Number(args.durationMs), 0), 120000)
            : 0;
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

          const visibleScrollItems = () => {
            const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
            const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
            const selectorList = [
              "main > section",
              "main > article",
              "section",
              "article",
              "[data-section]",
              "h1",
              "h2",
              "h3"
            ].join(",");
            return Array.from(document.querySelectorAll(selectorList))
              .map((node) => {
                if (!node || !node.getBoundingClientRect) return null;
                const rect = node.getBoundingClientRect();
                const style = getComputedStyle(node);
                if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return null;
                const visibleTop = Math.max(rect.top, 0);
                const visibleBottom = Math.min(rect.bottom, viewportHeight);
                const visibleLeft = Math.max(rect.left, 0);
                const visibleRight = Math.min(rect.right, viewportWidth);
                const visibleHeight = Math.max(0, visibleBottom - visibleTop);
                const visibleWidth = Math.max(0, visibleRight - visibleLeft);
                if (visibleHeight < 24 || visibleWidth < Math.min(260, viewportWidth * 0.25)) return null;
                const tag = node.tagName.toLowerCase();
                const text = truncate(node.innerText || node.textContent || node.getAttribute("aria-label") || "", 220);
                if (!text && !/^h[1-3]$/.test(tag)) return null;
                return {
                  tag,
                  id: node.id || null,
                  text,
                  top: Math.round(rect.top),
                  bottom: Math.round(rect.bottom),
                  height: Math.round(rect.height),
                  visibleHeight: Math.round(visibleHeight),
                  visibleRatio: rect.height > 0 ? Number(Math.min(1, visibleHeight / rect.height).toFixed(3)) : 0
                };
              })
              .filter(Boolean)
              .sort((left, right) => right.visibleHeight - left.visibleHeight)
              .slice(0, 8);
          };

          const recordScrollSample = (trace, event, extra = {}) => {
            if (!trace) return;
            const visible = visibleScrollItems();
            const dominant = visible[0] || null;
            trace.samples.push({
              event,
              elapsedMs: Math.round(performance.now() - trace.startedAtPerformance),
              at: new Date().toISOString(),
              position: scrollPosition(),
              dominant,
              visible,
              ...extra
            });
            trace.sampleCount = trace.samples.length;
            trace.current = trace.samples[trace.samples.length - 1] || null;
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

            if (durationMs > 0) {
              if (window.__wkdomainsAutoScrollFrame) {
                window.cancelAnimationFrame(window.__wkdomainsAutoScrollFrame);
                window.__wkdomainsAutoScrollFrame = null;
              }
              if (Array.isArray(window.__wkdomainsAutoScrollTimers)) {
                window.__wkdomainsAutoScrollTimers.forEach((timer) => window.clearTimeout(timer));
              }
              window.__wkdomainsAutoScrollTimers = [];

              const startX = before.x;
              const startY = before.y;
              const targetX = Math.min(Math.max(startX + deltaX, 0), before.maxX);
              const targetY = Math.min(Math.max(startY + deltaY, 0), before.maxY);
              const easeInOut = (value) => value < 0.5
                ? 2 * value * value
                : 1 - Math.pow(-2 * value + 2, 2) / 2;

              if (scrollStyle === "human" || scrollStyle === "natural") {
                const viewport = Math.max(480, window.innerHeight || 720);
                const directionSign = targetY < startY ? -1 : 1;
                const minGap = Math.round(viewport * 0.42);
                const maxGap = Math.round(viewport * 1.35);
                const stopSelectors = [
                  "main > section",
                  "main > article",
                  "main > div",
                  "section",
                  "article",
                  "[data-section]",
                  "[id]",
                  "h1",
                  "h2",
                  "h3"
                ].join(",");
                const headerOffset = Math.min(132, Math.max(76, Math.round(viewport * 0.14)));
                const stopCandidates = Array.from(document.querySelectorAll(stopSelectors))
                  .map((node) => {
                    if (!node || !node.getBoundingClientRect) return null;
                    const rect = node.getBoundingClientRect();
                    const style = getComputedStyle(node);
                    if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return null;
                    if (rect.width < Math.min(320, window.innerWidth * 0.28)) return null;
                    if (rect.height < 36) return null;
                    const tag = node.tagName.toLowerCase();
                    const textLength = String(node.innerText || node.textContent || "").replace(/\\s+/g, " ").trim().length;
                    const isHeading = /^h[1-3]$/.test(tag);
                    const isContainer = ["section", "article", "div", "main"].includes(tag);
                    if (isContainer && rect.height < viewport * 0.28 && textLength < 80) return null;
                    return {
                      y: Math.min(Math.max(Math.round(window.scrollY + rect.top - headerOffset), 0), before.maxY),
                      tag,
                      textLength,
                      height: Math.round(rect.height),
                      heading: isHeading,
                      score: (isHeading ? 80 : 0) + Math.min(120, Math.round(rect.height / 12)) + Math.min(80, Math.round(textLength / 28))
                    };
                  })
                  .filter(Boolean)
                  .filter((candidate) => directionSign > 0
                    ? candidate.y > startY + 24 && candidate.y < targetY - 24
                    : candidate.y < startY - 24 && candidate.y > targetY + 24)
                  .sort((left, right) => directionSign > 0 ? left.y - right.y : right.y - left.y);

                const curiosityScore = (candidate, index) => {
                  const textWeight = Math.min(1, (candidate.textLength || 0) / 900);
                  const heightWeight = Math.min(1, (candidate.height || 0) / (viewport * 1.4));
                  const rhythm = ((index * 37) % 100) / 100;
                  return (textWeight * 0.42) + (heightWeight * 0.38) + (rhythm * 0.2);
                };

                const semanticStops = [];
                stopCandidates.forEach((candidate, candidateIndex) => {
                  const previous = semanticStops[semanticStops.length - 1];
                  const previousWasHeading = previous?.heading === true;
                  const denseHeading = candidate.heading && previousWasHeading && Math.abs(candidate.y - previous.y) < viewport * 0.95;
                  if (denseHeading && curiosityScore(candidate, candidateIndex) < 0.72) return;

                  if (!previous) {
                    semanticStops.push(candidate);
                    return;
                  }

                  const gap = Math.abs(candidate.y - previous.y);
                  if (gap < minGap) {
                    if (candidate.score > previous.score) semanticStops[semanticStops.length - 1] = candidate;
                    return;
                  }

                  if (gap > maxGap * 1.7) {
                    const fillerCount = Math.floor(gap / maxGap);
                    for (let fillerIndex = 1; fillerIndex < fillerCount; fillerIndex += 1) {
                      semanticStops.push({
                        y: Math.round(previous.y + (directionSign * maxGap * fillerIndex)),
                        tag: "viewport",
                        textLength: 0,
                        height: viewport,
                        heading: false,
                        filler: true,
                        score: 0
                      });
                    }
                  }

                  semanticStops.push(candidate);
                });

                const stopYs = [startY, ...semanticStops.map((candidate) => candidate.y), targetY]
                  .filter((value, index, values) => index === 0 || Math.abs(value - values[index - 1]) > 12);
                const rawSegments = [];

                for (let index = 1; index < stopYs.length; index += 1) {
                  const fromY = stopYs[index - 1];
                  const toY = stopYs[index];
                  const distance = Math.abs(toY - fromY);
                  if (distance < 8) continue;
                  const stop = semanticStops[index - 1] || null;
                  const isLargeSkip = distance > viewport * 1.15;
                  const isHeadingStop = stop?.heading === true;
                  const isFiller = stop?.filler === true;
                  const stopKind = isFiller ? "filler" : isHeadingStop ? "heading" : isLargeSkip ? "section-skip" : "section";
                  const interest = stop ? curiosityScore(stop, index) : 0;
                  const curiosityPause = !isFiller && interest > 0.72;
                  rawSegments.push({
                    fromY,
                    toY,
                    moveMs: 420 + Math.round(Math.min(distance / viewport, 1.8) * 420),
                    pauseMs: isFiller
                      ? 180
                      : curiosityPause
                        ? 1350 + Math.min(900, Math.round((stop?.textLength || 260) / 5))
                        : isLargeSkip
                          ? 420
                          : isHeadingStop
                            ? 780
                            : 560 + Math.min(520, Math.round((stop?.textLength || 240) / 8)),
                    stopKind,
                    interest: Number(interest.toFixed(3)),
                    curiosityPause,
                    stop: stop ? {
                      tag: stop.tag,
                      y: stop.y,
                      height: stop.height,
                      heading: stop.heading,
                      filler: stop.filler === true
                    } : null
                  });
                }

                const rawTotalMs = rawSegments.reduce((sum, segment) => sum + segment.moveMs + segment.pauseMs, 0);
                const scale = rawTotalMs > 0 ? durationMs / rawTotalMs : 1;
                const moveScale = Math.min(1.18, Math.max(0.58, scale));
                const pauseScale = Math.min(1.12, Math.max(0.55, scale));
                const humanMoveMs = (segment) => Math.max(320, Math.round(segment.moveMs * moveScale));
                const humanPauseMs = (segment) => {
                  const minimum = segment.stopKind === "filler"
                    ? 120
                    : segment.curiosityPause
                      ? 920
                      : segment.stopKind === "heading"
                        ? 420
                        : segment.stopKind === "section-skip"
                          ? 280
                          : 360;
                  return Math.max(minimum, Math.round(segment.pauseMs * pauseScale));
                };
                let delayMs = 0;
                const trace = {
                  id: `scroll-${Date.now()}-${Math.random().toString(16).slice(2)}`,
                  status: "running",
                  style: "human",
                  url: location.href,
                  title: document.title,
                  startedAt: new Date().toISOString(),
                  startedAtPerformance: performance.now(),
                  requested: {
                    direction: direction || null,
                    durationMs,
                    startY: Math.round(startY),
                    targetY: Math.round(targetY)
                  },
                  plan: rawSegments.map((segment, segmentIndex) => ({
                    index: segmentIndex,
                    fromY: Math.round(segment.fromY),
                    toY: Math.round(segment.toY),
                    distance: Math.round(Math.abs(segment.toY - segment.fromY)),
                    moveMs: humanMoveMs(segment),
                    pauseMs: humanPauseMs(segment),
                    stopKind: segment.stopKind,
                    interest: segment.interest,
                    curiosityPause: segment.curiosityPause,
                    stop: segment.stop
                  })),
                  samples: [],
                  sampleCount: 0,
                  current: null
                };
                window.__wkdomainsScrollTrace = trace;
                recordScrollSample(trace, "start", { plannedStop: null });

                rawSegments.forEach((segment, segmentIndex) => {
                  const moveMs = humanMoveMs(segment);
                  const pauseMs = humanPauseMs(segment);
                  const timer = window.setTimeout(() => {
                    recordScrollSample(trace, "move-start", {
                      segmentIndex,
                      plannedStop: segment.stop,
                      plannedPauseMs: pauseMs,
                      interest: segment.interest,
                      curiosityPause: segment.curiosityPause
                    });
                    const segmentStartedAt = performance.now();
                    const animateSegment = (now) => {
                      const progress = Math.min(1, (now - segmentStartedAt) / moveMs);
                      const eased = easeInOut(progress);
                      window.scrollTo({
                        left: targetX,
                        top: segment.fromY + ((segment.toY - segment.fromY) * eased),
                        behavior: "instant"
                      });

                      if (progress < 1) {
                        window.__wkdomainsAutoScrollFrame = window.requestAnimationFrame(animateSegment);
                      } else {
                        recordScrollSample(trace, "pause-start", {
                          segmentIndex,
                          plannedStop: segment.stop,
                          plannedPauseMs: pauseMs,
                          moveMs,
                          interest: segment.interest,
                          curiosityPause: segment.curiosityPause
                        });
                        if (segmentIndex === rawSegments.length - 1) {
                          const doneTimer = window.setTimeout(() => {
                            trace.status = "completed";
                            trace.completedAt = new Date().toISOString();
                            trace.completedElapsedMs = Math.round(performance.now() - trace.startedAtPerformance);
                            recordScrollSample(trace, "completed", {
                              segmentIndex,
                              plannedStop: segment.stop
                            });
                            window.__wkdomainsAutoScrollFrame = null;
                            window.__wkdomainsAutoScrollTimers = [];
                          }, pauseMs);
                          window.__wkdomainsAutoScrollTimers.push(doneTimer);
                        }
                      }
                    };

                    window.__wkdomainsAutoScrollFrame = window.requestAnimationFrame(animateSegment);
                  }, delayMs);
                  window.__wkdomainsAutoScrollTimers.push(timer);
                  delayMs += moveMs + pauseMs;
                });

                return {
                  before,
                  after: before,
                  mode: "page",
                  status: "started",
                  style: "human",
                  durationMs,
                  segmentCount: rawSegments.length,
                  stopCount: semanticStops.length,
                  stops: rawSegments.slice(0, 24).map((segment) => segment.stop).filter(Boolean),
                  target: {
                    x: Math.round(targetX),
                    y: Math.round(targetY)
                  },
                  deltaX,
                  deltaY
                };
              }

              const startedAt = performance.now();

              const tick = (now) => {
                const progress = Math.min(1, (now - startedAt) / durationMs);
                const eased = easeInOut(progress);
                window.scrollTo({
                  left: startX + ((targetX - startX) * eased),
                  top: startY + ((targetY - startY) * eased),
                  behavior: "instant"
                });

                if (progress < 1) {
                  window.__wkdomainsAutoScrollFrame = window.requestAnimationFrame(tick);
                } else {
                  window.__wkdomainsAutoScrollFrame = null;
                }
              };

              window.__wkdomainsAutoScrollFrame = window.requestAnimationFrame(tick);
              return {
                before,
                after: before,
                mode: "page",
                status: "started",
                durationMs,
                target: {
                  x: Math.round(targetX),
                  y: Math.round(targetY)
                },
                deltaX,
                deltaY
              };
            }

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
