//
//  BrowserDarkModeStaticStyleScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStaticStyleScript = #"""
      const createOrUpdateStyle = (className, root = document.head || document.documentElement || document) => {
        const ownerRoot = root || document;
        if (!staticStyleMap.has(ownerRoot)) {
          staticStyleMap.set(ownerRoot, new Map());
        }

        const classMap = staticStyleMap.get(ownerRoot);
        let element = null;
        try {
          element = ownerRoot.querySelector ? ownerRoot.querySelector(`style.${className}`) : null;
        } catch (_) {}

        if (element) {
          classMap.set(className, element);
        } else if (classMap.has(className)) {
          element = classMap.get(className);
        } else {
          element = document.createElement("style");
          element.classList.add(INLINE_CLASS, "darkreader", className);
          element.media = "screen";
          element.textContent = "";
          classMap.set(className, element);
        }

        return element;
      };

      const findStaticStyle = (className, root = document) => {
        try {
          const cached = staticStyleMap.get(root)?.get(className);
          if (cached) return cached;
          return root.querySelector ? root.querySelector(`style.${className}`) : null;
        } catch (_) {
          return null;
        }
      };

      const injectStyleNextTo = (style, root, previous = null) => {
        const target = root === document ? (document.head || document.documentElement) : root;
        if (!target) return;
        try {
          const reference = previous && previous.parentNode === target
            ? previous.nextSibling
            : (previous ? null : target.firstChild);
          if (reference === style) return;
          if (style.parentNode !== target || style.nextSibling !== reference) {
            target.insertBefore(style, reference);
          }
        } catch (_) {
          try { target.appendChild(style); } catch (_) {}
        }
      };

      const injectStyleAtEnd = (style, root = document) => {
        const target = root === document ? (document.documentElement || document.head) : root;
        if (!target) return;
        try {
          if (style.parentNode !== target || style.nextSibling) {
            target.appendChild(style);
          }
        } catch (_) {
          target.appendChild(style);
        }
      };

      const setupNodePositionWatcher = (node, alias, callback) => {
        const previous = nodePositionWatchers.get(alias);
        if (previous) previous.disconnect();
        if (!window.MutationObserver) return;

        const target = document.head || document.documentElement;
        if (!target) return;

        let scheduledRestore = false;
        const observer = new MutationObserver(() => {
          if (scheduledRestore) return;
          scheduledRestore = true;
          queueMicrotask(() => {
            scheduledRestore = false;
            if (!node.isConnected || node.parentNode !== (document.head || document.documentElement)) {
              callback?.();
            }
          });
        });

        observer.observe(target, { childList: true });
        nodePositionWatchers.set(alias, observer);
      };

      const stopStylePositionWatchers = () => {
        for (const observer of nodePositionWatchers.values()) {
          observer.disconnect();
        }
        nodePositionWatchers.clear();
      };

      const injectStaticStyle = (style, previous, alias, callback) => {
        injectStyleNextTo(style, document, previous);
        setupNodePositionWatcher(style, alias, callback || restoreStaticStyleOrder);
      };

      const getInlineOverrideStyle = () => {
        const inlineOverrides = [
          [COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", "color"],
          [BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", "background-color"],
          [BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", "background-image"],
          [FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", "fill"],
          [STROKE_ATTRIBUTE, "--wkdomains-forced-dark-stroke", "stroke"],
          [BOX_SHADOW_ATTRIBUTE, "--wkdomains-forced-dark-box-shadow", "box-shadow"],
          ...BORDER_OVERRIDES.map((override) => [override.attr, override.prop, override.css]),
          ...SHORTHAND_OVERRIDES.map((override) => [override.attr, override.prop, override.css])
        ];

        return inlineOverrides.map(([attribute, property, cssProperty]) => [
          `:root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [${attribute}] {`,
          `  ${cssProperty}: var(${property}) !important;`,
          "}"
        ].join("\n")).join("\n");
      };

      const getVariablesStyle = () => `
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) {
          --darkreader-neutral-background: ${toThemeRGBA(themeBackgroundColor())};
          --darkreader-neutral-text: ${toThemeRGBA(themeTextColor())};
          --darkreader-border: ${toThemeRGBA(themeBorderColor())};
          --darkreader-selection-background: ${toThemeRGBA(themeSelectionBackgroundColor())};
          --darkreader-selection-text: ${toThemeRGBA(themeSelectionTextColor())};
          ${registeredColorDeclarations().join("\n")}
        }
      `;

      const getFallbackStyle = () => `
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) {
          color-scheme: dark !important;
          --darkreader-neutral-background: ${toThemeRGBA(themeBackgroundColor())};
          --darkreader-neutral-text: ${toThemeRGBA(themeTextColor())};
          --darkreader-border: ${toThemeRGBA(themeBorderColor())};
          --darkreader-selection-background: ${toThemeRGBA(themeSelectionBackgroundColor())};
          --darkreader-selection-text: ${toThemeRGBA(themeSelectionTextColor())};
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]),
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) body {
          background: var(--darkreader-neutral-background) !important;
          color: var(--darkreader-neutral-text) !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) body * {
          transition-property: color, background-color, border-color, outline-color, box-shadow, fill, stroke !important;
          transition-duration: 0s !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) ::selection {
          background: var(--darkreader-selection-background) !important;
          color: var(--darkreader-selection-text) !important;
        }
      `;

      const getUserAgentStyle = () => `
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) textarea,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) select,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) button,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) dialog,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [popover],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [aria-modal="true"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="dialog"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="button"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="combobox"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="searchbox"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="textbox"] {
          color-scheme: dark !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) textarea,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) select {
          background-color: ${toThemeRGBA(mix(themeBackgroundColor(), themeTextColor(), 0.04))} !important;
          color: var(--darkreader-neutral-text) !important;
          border-color: var(--darkreader-border) !important;
          caret-color: var(--darkreader-neutral-text) !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input:not([type]),
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input[type="text"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input[type="search"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input[type="email"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input[type="password"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input[type="url"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input[type="tel"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input[type="number"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) textarea {
          -webkit-appearance: none !important;
          appearance: none !important;
          background-color: var(--darkreader-neutral-background) !important;
          background-image: none !important;
          color: var(--darkreader-neutral-text) !important;
          -webkit-text-fill-color: var(--darkreader-neutral-text) !important;
          caret-color: var(--darkreader-neutral-text) !important;
          box-shadow: inset 0 0 0 9999px var(--darkreader-neutral-background) !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input::placeholder,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) textarea::placeholder {
          color: rgb(176, 170, 160) !important;
          opacity: 1 !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [contenteditable="true"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="textbox"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .editable[contenteditable] {
          color: var(--darkreader-neutral-text) !important;
          caret-color: var(--darkreader-neutral-text) !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) dialog,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [popover],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [aria-modal="true"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="dialog"] {
          background-color: var(--darkreader-neutral-background) !important;
          color: var(--darkreader-neutral-text) !important;
          border-color: var(--darkreader-border) !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="region"][aria-label]:has(input, textarea, [contenteditable="true"]),
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="form"]:has(input, textarea, [contenteditable="true"]),
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) form:has(input, textarea, [contenteditable="true"]) {
          color-scheme: dark !important;
          background-color: var(--darkreader-neutral-background) !important;
          color: var(--darkreader-neutral-text) !important;
          border-color: var(--darkreader-border) !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="region"][aria-label]:has(input, textarea, [contenteditable="true"]) :not(img):not(picture):not(video):not(canvas):not(svg):not(path):not(iframe),
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="form"]:has(input, textarea, [contenteditable="true"]) :not(img):not(picture):not(video):not(canvas):not(svg):not(path):not(iframe),
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) form:has(input, textarea, [contenteditable="true"]) :not(img):not(picture):not(video):not(canvas):not(svg):not(path):not(iframe) {
          border-color: var(--darkreader-border) !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="region"][aria-label]:has(input, textarea, [contenteditable="true"]) :not(img):not(picture):not(video):not(canvas):not(svg):not(path):not(iframe):not([${BACKGROUND_ATTRIBUTE}]),
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="form"]:has(input, textarea, [contenteditable="true"]) :not(img):not(picture):not(video):not(canvas):not(svg):not(path):not(iframe):not([${BACKGROUND_ATTRIBUTE}]),
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) form:has(input, textarea, [contenteditable="true"]) :not(img):not(picture):not(video):not(canvas):not(svg):not(path):not(iframe):not([${BACKGROUND_ATTRIBUTE}]) {
          background-color: transparent !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="region"][aria-label]:has(input, textarea, [contenteditable="true"]) input,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="form"]:has(input, textarea, [contenteditable="true"]) input,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) form:has(input, textarea, [contenteditable="true"]) input,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="region"][aria-label]:has(input, textarea, [contenteditable="true"]) textarea,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="form"]:has(input, textarea, [contenteditable="true"]) textarea,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) form:has(input, textarea, [contenteditable="true"]) textarea,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="region"][aria-label]:has(input, textarea, [contenteditable="true"]) [contenteditable="true"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="form"]:has(input, textarea, [contenteditable="true"]) [contenteditable="true"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) form:has(input, textarea, [contenteditable="true"]) [contenteditable="true"] {
          background-color: transparent !important;
          color: var(--darkreader-neutral-text) !important;
          -webkit-text-fill-color: var(--darkreader-neutral-text) !important;
          caret-color: var(--darkreader-neutral-text) !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="region"][aria-label]:has(input, textarea, [contenteditable="true"]) [role="button"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="form"]:has(input, textarea, [contenteditable="true"]) [role="button"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) form:has(input, textarea, [contenteditable="true"]) [role="button"] {
          color: var(--darkreader-neutral-text) !important;
          -webkit-text-fill-color: var(--darkreader-neutral-text) !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [bgcolor] :not(iframe):not(img):not(picture):not(video):not(canvas):not(svg):not(path):not([${BACKGROUND_ATTRIBUTE}]) {
          background-color: transparent !important;
        }
      `;

      const getStructuralStyle = () => `
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) #site-header,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) header.header-bg,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) header.header-bg-solid,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) header.has-sub-nav,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .header-bg,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .header-bg-solid,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .nav-dropdown,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .navigation-dropdown-bg-solid,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .main_sub-navigation,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) nav[aria-label],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="navigation"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="site-header" i],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="main-nav" i]:not(a):not(button):not(li):not(span),
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="sub-navigation" i],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [class*="navigation" i]:not(a):not(button):not(li):not(span) {
          background-color: var(--darkreader-neutral-background) !important;
        }
      `;

      const restoreStaticStyleOrder = () => {
        const root = document.head || document.documentElement;
        if (!root) return;

        let previous = null;
        for (const className of STATIC_STYLE_CLASSES) {
          const style = findStaticStyle(className, document);
          if (!style || !style.textContent && className === "wkdomains-darkreader--pdf") continue;
          injectStyleNextTo(style, document, previous);
          previous = style;
        }
      };

      const ensureSiteFixStyle = () => {
        const siteFixStyle = createOrUpdateStyle("wkdomains-darkreader--site-fixes", document);
        siteFixStyle.textContent = getSiteFixStyle();
        const structuralStyle = findStaticStyle("wkdomains-darkreader--structural", document);
        injectStaticStyle(siteFixStyle, structuralStyle || document.head?.lastChild || null, "site-fixes");
      };

      const ensureBaseStyle = () => {
        if (!document.documentElement) return;
        document.documentElement.setAttribute(ROOT_ATTRIBUTE, "true");
        document.documentElement.setAttribute(DARKREADER_MODE_ATTRIBUTE, "dynamic");
        document.documentElement.setAttribute(DARKREADER_SCHEME_ATTRIBUTE, "dark");

        const fallbackStyle = createOrUpdateStyle("wkdomains-darkreader--fallback", document);
        fallbackStyle.id = STYLE_ID;
        if (!fallbackWasCleared || loadingStyles.size > 0) {
          fallbackStyle.textContent = getFallbackStyle();
        }
        injectStaticStyle(fallbackStyle, null, "fallback");

        const userAgentStyle = createOrUpdateStyle("wkdomains-darkreader--user-agent", document);
        userAgentStyle.textContent = getUserAgentStyle();
        injectStaticStyle(userAgentStyle, fallbackStyle, "user-agent");

        const invertStyle = createOrUpdateStyle("wkdomains-darkreader--invert", document);
        invertStyle.textContent = getSiteFixInvertStyle();
        injectStaticStyle(invertStyle, userAgentStyle, "invert");

        const inlineStyle = createOrUpdateStyle("wkdomains-darkreader--inline", document);
        inlineStyle.textContent = getInlineOverrideStyle();
        injectStaticStyle(inlineStyle, invertStyle, "inline");

        const variablesStyle = createOrUpdateStyle("wkdomains-darkreader--variables", document);
        variablesStyle.textContent = getVariablesStyle();
        injectStaticStyle(variablesStyle, inlineStyle, "variables");

        const rootVarsStyle = createOrUpdateStyle("wkdomains-darkreader--root-vars", document);
        rootVarsStyle.textContent = "";
        injectStaticStyle(rootVarsStyle, variablesStyle, "root-vars");

        const structuralStyle = createOrUpdateStyle("wkdomains-darkreader--structural", document);
        structuralStyle.textContent = getStructuralStyle();
        injectStaticStyle(structuralStyle, rootVarsStyle, "structural");

        ensureSiteFixStyle();
        restoreStaticStyleOrder();
      };

      const toShadowScopedStyle = (css) => String(css || "").replaceAll(
        `:root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}])`,
        `:host-context([${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]))`
      );

      const createShadowStaticStyleOverridesInner = (root) => {
        if (!root || !root.querySelector) return;
        const style = createOrUpdateStyle(SHADOW_STYLE_CLASS, root);
        style.textContent = [
          toShadowScopedStyle(getInlineOverrideStyle()),
          toShadowScopedStyle(getUserAgentStyle()),
          toShadowScopedStyle(getSiteFixInvertStyle()),
          getSiteFixStyle()
        ].join("\n");
        if (style.parentNode !== root) {
          try {
            root.insertBefore(style, root.firstChild);
          } catch (_) {
            root.appendChild(style);
          }
        }
        shadowRootsWithOverrides.add(root);
      };

      const delayedCreateShadowStaticStyleOverrides = (root) => {
        if (!window.MutationObserver) return;
        const observer = new MutationObserver((mutations, activeObserver) => {
          activeObserver.disconnect();
          for (const mutation of mutations) {
            if (mutation.type !== "childList") continue;
            for (const node of mutation.removedNodes) {
              if (
                node.nodeType === Node.ELEMENT_NODE
                && node.tagName === "STYLE"
                && node.classList
                && (node.classList.contains(SHADOW_STYLE_CLASS) || node.classList.contains(INLINE_CLASS))
              ) {
                createShadowStaticStyleOverridesInner(root);
                return;
              }
            }
          }
        });
        observer.observe(root, { childList: true });
        cleanupTasks.push(() => observer.disconnect());
      };

      const createShadowStaticStyleOverrides = (root) => {
        if (!root) return;
        const delayed = root.firstChild === null;
        createShadowStaticStyleOverridesInner(root);
        if (delayed) {
          delayedCreateShadowStaticStyleOverrides(root);
        }
      };

      const changeMetaThemeColorWhenAvailable = () => {
        const apply = () => {
          if (!document.head) return;
          for (const meta of document.head.querySelectorAll('meta[name="theme-color"]')) {
            if (!originalMetaThemeColors.has(meta)) {
              originalMetaThemeColors.set(meta, {
                hadContent: meta.hasAttribute("content"),
                content: meta.getAttribute("content")
              });
            }
            const nextColor = toThemeRGBA(themeBackgroundColor());
            if (meta.getAttribute("content") !== nextColor) {
              meta.setAttribute("content", nextColor);
            }
          }
        };

        apply();
        if (!window.MutationObserver || themeColorObserver || !document.head) return;
        themeColorObserver = new MutationObserver(apply);
        themeColorObserver.observe(document.head, {
          attributes: true,
          attributeFilter: ["content"],
          childList: true,
          subtree: true
        });
      };

      const restoreMetaThemeColor = () => {
        if (themeColorObserver) {
          themeColorObserver.disconnect();
          themeColorObserver = null;
        }
        if (!document.head) return;
        for (const meta of document.head.querySelectorAll('meta[name="theme-color"]')) {
          const original = originalMetaThemeColors.get(meta);
          if (!original) continue;
          if (original.hadContent) {
            meta.setAttribute("content", original.content || "");
          } else {
            meta.removeAttribute("content");
          }
        }
      };

      const tryInvertPDF = () => {
        let hasPDF = false;
        try {
          hasPDF = document.contentType === "application/pdf"
            || !!document.querySelector('embed[type="application/pdf"], object[type="application/pdf"], iframe[src$=".pdf"]');
        } catch (_) {}
        if (!hasPDF) return;

        const pdfStyle = createOrUpdateStyle("wkdomains-darkreader--pdf", document);
        pdfStyle.textContent = `
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) embed[type="application/pdf"],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) object[type="application/pdf"],
          :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) iframe[src$=".pdf"] {
            filter: invert(1) contrast(0.9) hue-rotate(180deg) !important;
          }
        `;
        injectStaticStyle(pdfStyle, findStaticStyle("wkdomains-darkreader--site-fixes", document) || null, "pdf");
      };

      const removeBaseStyle = () => {
        if (!document.documentElement) return;
        document.documentElement.removeAttribute(ROOT_ATTRIBUTE);
        document.documentElement.removeAttribute(READY_ATTRIBUTE);
        document.documentElement.removeAttribute(SAMPLING_ATTRIBUTE);
        document.documentElement.removeAttribute(DARKREADER_MODE_ATTRIBUTE);
        document.documentElement.removeAttribute(DARKREADER_SCHEME_ATTRIBUTE);
        restoreMetaThemeColor();
        for (const style of document.querySelectorAll(`style.${INLINE_CLASS}`)) {
          style.remove();
        }
        for (const root of shadowRootsWithOverrides) {
          try {
            for (const style of root.querySelectorAll(`style.${INLINE_CLASS}`)) {
              style.remove();
            }
          } catch (_) {}
        }
        shadowRootsWithOverrides.clear();
        stopStylePositionWatchers();
        staticStyleMap = new WeakMap();
      };
    """#
}
