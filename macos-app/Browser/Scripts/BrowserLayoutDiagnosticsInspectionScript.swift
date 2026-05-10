//
//  BrowserLayoutDiagnosticsInspectionScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let layoutDiagnosticsInspectionScript = """
    (() => {
      const MAX_ITEMS = 80;
      const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
      const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
      const doc = document.documentElement;
      const body = document.body;

      const truncate = (value, limit = 160) => {
        const text = String(value || "").replace(/\\s+/g, " ").trim();
        return text.length > limit ? `${text.slice(0, limit)}...` : text;
      };

      const rectFor = (element) => {
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

      const isVisible = (element) => {
        if (!element || !element.getBoundingClientRect) return false;
        const style = getComputedStyle(element);
        if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
        const rect = element.getBoundingClientRect();
        if (rect.width < 1 || rect.height < 1) return false;
        return rect.bottom >= 0 && rect.right >= 0 && rect.top <= viewportHeight && rect.left <= viewportWidth;
      };

      const labelFor = (element) => truncate(
        element.getAttribute("aria-label")
          || element.innerText
          || element.textContent
          || element.getAttribute("title")
          || element.getAttribute("placeholder")
          || element.tagName.toLowerCase(),
        100
      );

      const selectorHintFor = (element) => {
        if (element.id) return `#${element.id}`;
        const testID = element.getAttribute("data-testid") || element.getAttribute("data-test") || element.getAttribute("data-cy");
        if (testID) return `[data-testid="${testID}"]`;
        const name = element.getAttribute("name");
        if (name) return `${element.tagName.toLowerCase()}[name="${name}"]`;
        return element.tagName.toLowerCase();
      };

      const summaryFor = (element, extra = {}) => ({
        tag: element.tagName.toLowerCase(),
        role: element.getAttribute("role") || null,
        label: labelFor(element),
        selectorHint: selectorHintFor(element),
        rect: rectFor(element),
        ...extra
      });

      const all = Array.from(document.querySelectorAll("body *")).filter(isVisible);
      const interactiveSelector = [
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
        "[role='searchbox']",
        "[role='slider']"
      ].join(",");
      const interactive = Array.from(document.querySelectorAll(interactiveSelector)).filter(isVisible);

      const outsideViewport = all
        .filter((element) => {
          const rect = element.getBoundingClientRect();
          return rect.left < -1 || rect.right > viewportWidth + 1 || rect.top < -1 || rect.bottom > viewportHeight + 1;
        })
        .slice(0, MAX_ITEMS)
        .map((element) => summaryFor(element));

      const clipped = all
        .filter((element) => {
          const style = getComputedStyle(element);
          const clipsX = ["hidden", "clip", "auto", "scroll"].includes(style.overflowX);
          const clipsY = ["hidden", "clip", "auto", "scroll"].includes(style.overflowY);
          return (clipsX && element.scrollWidth > element.clientWidth + 1)
            || (clipsY && element.scrollHeight > element.clientHeight + 1);
        })
        .slice(0, MAX_ITEMS)
        .map((element) => summaryFor(element, {
          scrollWidth: element.scrollWidth,
          clientWidth: element.clientWidth,
          scrollHeight: element.scrollHeight,
          clientHeight: element.clientHeight,
          overflowX: getComputedStyle(element).overflowX,
          overflowY: getComputedStyle(element).overflowY
        }));

      const smallTapTargets = interactive
        .filter((element) => {
          const rect = element.getBoundingClientRect();
          return rect.width < 44 || rect.height < 44;
        })
        .slice(0, MAX_ITEMS)
        .map((element) => summaryFor(element));

      const fixedOrSticky = all
        .filter((element) => {
          const position = getComputedStyle(element).position;
          return position === "fixed" || position === "sticky";
        })
        .slice(0, 40);

      const intersections = [];
      for (let i = 0; i < fixedOrSticky.length; i += 1) {
        for (let j = i + 1; j < fixedOrSticky.length; j += 1) {
          const a = fixedOrSticky[i].getBoundingClientRect();
          const b = fixedOrSticky[j].getBoundingClientRect();
          const width = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left));
          const height = Math.max(0, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top));
          const area = width * height;
          if (area >= 64) {
            intersections.push({
              area: Math.round(area),
              first: summaryFor(fixedOrSticky[i], { position: getComputedStyle(fixedOrSticky[i]).position }),
              second: summaryFor(fixedOrSticky[j], { position: getComputedStyle(fixedOrSticky[j]).position })
            });
          }
        }
      }

      return JSON.stringify({
        url: location.href,
        title: document.title || null,
        generatedAt: new Date().toISOString(),
        viewport: {
          width: Math.round(viewportWidth),
          height: Math.round(viewportHeight),
          scrollX: Math.round(window.scrollX || 0),
          scrollY: Math.round(window.scrollY || 0),
          devicePixelRatio: window.devicePixelRatio || 1
        },
        document: {
          scrollWidth: doc ? doc.scrollWidth : null,
          clientWidth: doc ? doc.clientWidth : null,
          scrollHeight: doc ? doc.scrollHeight : null,
          clientHeight: doc ? doc.clientHeight : null,
          bodyScrollWidth: body ? body.scrollWidth : null,
          bodyClientWidth: body ? body.clientWidth : null,
          hasHorizontalOverflow: !!doc && doc.scrollWidth > doc.clientWidth + 1
        },
        counts: {
          visibleElements: all.length,
          interactiveElements: interactive.length,
          outsideViewport: outsideViewport.length,
          clipped: clipped.length,
          smallTapTargets: smallTapTargets.length,
          fixedOrSticky: fixedOrSticky.length,
          fixedOrStickyOverlaps: intersections.length
        },
        outsideViewport,
        clipped,
        smallTapTargets,
        fixedOrStickyOverlaps: intersections.slice(0, 30)
      });
    })();
    """
}
