//
//  BrowserDarkModeStaticStyleScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStaticStyleScript = #"""
      const createOrUpdateStyle = (className, root = document.head || document.documentElement || document) => {
        let element = root.querySelector ? root.querySelector(`style.${className}`) : null;
        if (!element) {
          element = document.createElement("style");
          element.classList.add(INLINE_CLASS, className);
          element.media = "screen";
        }
        return element;
      };

      const injectStyleNextTo = (style, root, previous = null) => {
        const target = root === document ? (document.head || document.documentElement) : root;
        if (!target) return;
        try {
          if (previous) {
            if (style.parentNode !== target || previous.nextSibling !== style) {
              target.insertBefore(style, previous.nextSibling);
            }
          } else if (style.parentNode !== target || style.nextSibling) {
            target.appendChild(style);
          }
        } catch (_) {
          target.appendChild(style);
        }
      };

      const getInlineOverrideStyle = () => {
        const inlineOverrides = [
          [COLOR_ATTRIBUTE, "--wkdomains-forced-dark-color", "color"],
          [BACKGROUND_ATTRIBUTE, "--wkdomains-forced-dark-bg", "background-color"],
          [BACKGROUND_IMAGE_ATTRIBUTE, "--wkdomains-forced-dark-bg-image", "background-image"],
          [FILL_ATTRIBUTE, "--wkdomains-forced-dark-fill", "fill"],
          [STROKE_ATTRIBUTE, "--wkdomains-forced-dark-stroke", "stroke"],
          [BOX_SHADOW_ATTRIBUTE, "--wkdomains-forced-dark-box-shadow", "box-shadow"],
          ...BORDER_OVERRIDES.map((override) => [override.attr, override.prop, override.css])
        ];

        return inlineOverrides.map(([attribute, property, cssProperty]) => [
          `:root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [${attribute}] {`,
          `  ${cssProperty}: var(${property}) !important;`,
          "}"
        ].join("\n")).join("\n");
      };

      const getFallbackStyle = () => `
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) {
          color-scheme: dark !important;
          --darkreader-neutral-background: ${toRGBA(DEFAULT_BACKGROUND)};
          --darkreader-neutral-text: ${toRGBA(DEFAULT_TEXT)};
          --darkreader-border: ${toRGBA(DEFAULT_BORDER)};
          --darkreader-selection-background: rgb(67, 91, 122);
          --darkreader-selection-text: rgb(246, 248, 250);
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
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) button {
          color-scheme: dark !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) textarea,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) select {
          background-color: rgb(31, 33, 34) !important;
          color: var(--darkreader-neutral-text) !important;
          border-color: var(--darkreader-border) !important;
          caret-color: var(--darkreader-neutral-text) !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input::placeholder,
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) textarea::placeholder {
          color: rgb(176, 170, 160) !important;
          opacity: 1 !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input[name="subjectbox"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input[aria-label="Subject"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input[placeholder="Subject"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) input.aoT {
          background: rgb(24, 26, 27) !important;
          color: var(--darkreader-neutral-text) !important;
          -webkit-text-fill-color: var(--darkreader-neutral-text) !important;
          box-shadow: none !important;
        }
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [contenteditable="true"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) [role="textbox"],
        :root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) .editable[contenteditable] {
          color: var(--darkreader-neutral-text) !important;
          caret-color: var(--darkreader-neutral-text) !important;
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

      const ensureBaseStyle = () => {
        if (!document.documentElement) return;
        document.documentElement.setAttribute(ROOT_ATTRIBUTE, "true");

        const fallbackStyle = createOrUpdateStyle("wkdomains-darkreader--fallback", document);
        fallbackStyle.id = STYLE_ID;
        fallbackStyle.textContent = getFallbackStyle();
        injectStyleNextTo(fallbackStyle, document, null);

        const userAgentStyle = createOrUpdateStyle("wkdomains-darkreader--user-agent", document);
        userAgentStyle.textContent = getUserAgentStyle();
        injectStyleNextTo(userAgentStyle, document, fallbackStyle);

        const inlineStyle = createOrUpdateStyle("wkdomains-darkreader--inline", document);
        inlineStyle.textContent = getInlineOverrideStyle();
        injectStyleNextTo(inlineStyle, document, userAgentStyle);

        const structuralStyle = createOrUpdateStyle("wkdomains-darkreader--structural", document);
        structuralStyle.textContent = getStructuralStyle();
        injectStyleNextTo(structuralStyle, document, inlineStyle);
      };

      const createShadowStaticStyleOverrides = (root) => {
        if (!root || !root.querySelector) return;
        const style = createOrUpdateStyle(SHADOW_STYLE_CLASS, root);
        style.textContent = `${getInlineOverrideStyle()}\n${getUserAgentStyle()}`;
        if (style.parentNode !== root) {
          try {
            root.insertBefore(style, root.firstChild);
          } catch (_) {
            root.appendChild(style);
          }
        }
      };

      const removeBaseStyle = () => {
        if (!document.documentElement) return;
        document.documentElement.removeAttribute(ROOT_ATTRIBUTE);
        document.documentElement.removeAttribute(READY_ATTRIBUTE);
        document.documentElement.removeAttribute(SAMPLING_ATTRIBUTE);
        for (const style of document.querySelectorAll(`style.${INLINE_CLASS}`)) {
          style.remove();
        }
      };
    """#
}
