//
//  BrowserDarkModeSiteFixesScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static func browserDarkModeSiteFixesScript(siteFixConfig: String) -> String {
        let siteFixConfigLiteral = javaScriptStringLiteral(siteFixConfig)

        return #"""
      const SITE_FIXES = [
        {
          url: ["mail.google.com"],
          invert: [
            ".asor_t0",
            ".asor_i1 > img",
            ".asor_i4",
            ".d-Na-Jo.d-Na-N-ax3",
            ".RK-QJ-Jk",
            ".RK-Mo.RK-Qq-LF",
            "#ita-st-id-cs",
            ".d-Na-N-M7-JX.d-Na-J3",
            ".ita-icon-0",
            ".ita-icon-1",
            "img[src$=\"profile_mask2.png\"]",
            ".rY>.sa",
            ".buh",
            ".asor",
            ".mixmax-flyout__wrapper",
            "div[aria-label=\"Hangouts\"] > div[role=\"tablist\"] > div[tabid=\"chat\"] > div",
            "form[method=\"POST\"] ~ table div[style] > div > :first-child button:not([string]):not([id])",
            "img[src^=\"//ssl.gstatic.com/ui/v1/icons/common/x\"]",
            "div[style$=\"gm_add_black_24dp.png)\"]",
            ".WR .z0>.L3::before",
            ".WR.anZ .z0>.L3::before",
            "form.bAs .J-Z-I:not(.T-I-atl):not(.n9pvd)",
            "form.bAs .J-JN-M-I:not(.T-I-atl):not(.n9pvd)",
            "form.bAs .T-I-ax7:not(.T-I-atl):not(.n9pvd)",
            "table:has(h2.a3E) [role=\"button\"]",
            ".aYF [role=\"button\"]"
          ],
          css: `
            @media (min-resolution: 144dpi), (-webkit-min-device-pixel-ratio: 1.5) {
              .buk {
                background-image: url(//ssl.gstatic.com/ui/v1/icons/mail/rfr/density_default_v1_2x.png) !important;
              }
              .bui {
                background-image: url(//ssl.gstatic.com/ui/v1/icons/mail/rfr/density_comfortable_v1_2x.png) !important;
              }
              .buj {
                background-image: url(//ssl.gstatic.com/ui/v1/icons/mail/rfr/density_compact_v1_2x.png) !important;
              }
            }
            .buk {
              background-image: url(//ssl.gstatic.com/ui/v1/icons/mail/rfr/density_default_v1_1x.png) !important;
            }
            .bui {
              background-image: url(//ssl.gstatic.com/ui/v1/icons/mail/rfr/density_comfortable_v1_1x.png) !important;
            }
            .buj {
              background-image: url(//ssl.gstatic.com/ui/v1/icons/mail/rfr/density_compact_v1_1x.png) !important;
            }
            div[class*="bym"][role="navigation"],
            .afC,
            .agJ {
              background-color: var(--darkreader-neutral-background) !important;
            }
            .agJ:hover,
            .ag5 {
              background-color: \${#E8E6E5} !important;
            }
            .agJ.bjE {
              background-color: \${#E3E1E0} !important;
            }
            .ain .TO,
            .TO.ol {
              background-color: rgba(255,255,255,0.05) !important;
            }
            .agh,
            .afV,
            .afA,
            .bbV {
              background-color: transparent !important;
            }
            .aRg,
            .aRj {
              color: \${white} !important;
            }
            .gb_3e {
              color: \${white} !important;
            }
            table {
              color: \${black} !important;
            }
            form.bAs input.aoT,
            form.bAs input[name="subjectbox"],
            form.bAs input[aria-label="Subject"],
            form.bAs input[placeholder="Subject"] {
              -webkit-appearance: none !important;
              appearance: none !important;
              background: var(--darkreader-neutral-background) !important;
              background-image: none !important;
              box-shadow: inset 0 0 0 9999px var(--darkreader-neutral-background) !important;
              color: var(--darkreader-neutral-text) !important;
              -webkit-text-fill-color: var(--darkreader-neutral-text) !important;
              caret-color: var(--darkreader-neutral-text) !important;
            }
            form.bAs input.aoT::placeholder,
            form.bAs input.aoT::-webkit-input-placeholder,
            form.bAs input[name="subjectbox"]::placeholder,
            form.bAs input[name="subjectbox"]::-webkit-input-placeholder {
              color: rgb(176, 170, 160) !important;
              -webkit-text-fill-color: rgb(176, 170, 160) !important;
              opacity: 1 !important;
            }
            form.bAs .J-Z-I,
            form.bAs .J-JN-M-I,
            form.bAs .T-I-ax7,
            table:has(h2.a3E) [role="button"],
            .aYF [role="button"] {
              color: var(--darkreader-neutral-text) !important;
              -webkit-text-fill-color: var(--darkreader-neutral-text) !important;
              opacity: 0.92 !important;
            }
            form.bAs .n9pvd {
              color: var(--darkreader-neutral-text) !important;
              -webkit-text-fill-color: var(--darkreader-neutral-text) !important;
            }
          `,
          ignoreInlineStyle: [
            ".at",
            ".au",
            ".av",
            ".qj",
            ".hU.hM",
            ".hV.hM",
            ".ajZ-Jt",
            ".aH5",
            ".JA-Kn-Jr-Kw-Jt"
          ],
          ignoreImageAnalysis: [
            ".WR .z0 > .L3::before",
            ".WR.anZ .z0>.L3::before",
            ".d-Na-J3",
            ".aBS .d-Na-JX-I .d-Na-J3"
          ]
        },
        {
          url: ["reddit.com", "new.reddit.com"],
          invert: [
            "video ~ div [style^=\"height\"]",
            ".snoo-cls-1",
            ".snoo-cls-2",
            ".snoo-cls-3",
            ".snoo-cls-8"
          ],
          css: `
            [style^="--background"] {
              --background: \${#FFFFFF} !important;
            }
            [style^="--canvas"] {
              --canvas: \${#DAE0E6} !important;
            }
            [style^="--pseudo-before-background"] {
              --pseudo-before-background: \${#DAE0E6} !important;
            }
            [style^="--comments-overlay-background"] {
              --comments-overlay-background: \${#DAE0E6} !important;
            }
            [style^="--commentswrapper-gradient-color"] {
              --comments-overlay-background: \${#DAE0E6} !important;
            }
            [style^="--fakelightbox-overlay-background"] {
              --fakelightbox-overlay-background: \${#DAE0E6} !important;
            }
            .button:hover {
              --button-color-background: var(--wkdomains-darkreader-bg-color-neutral-background-hover, var(--darkreader-neutral-background)) !important;
            }
            .hover\\:text-secondary:hover {
              color: var(--darkreader-neutral-text) !important;
            }
            .hover\\:bg-secondary-background-hover:hover {
              background-color: var(--wkdomains-darkreader-bg-color-neutral-background-hover, var(--darkreader-neutral-background)) !important;
            }
            .hover\\:border-secondary-background-hover:hover {
              border-color: var(--wkdomains-darkreader-border-color-neutral-border-medium, var(--darkreader-border)) !important;
            }
            .before\\:border-tone-4::before {
              border-color: var(--color-tone-4) !important;
            }
            .button-shell {
              color: var(--darkreader-neutral-text) !important;
            }
            .button-plain {
              --button-color-text-default: var(--darkreader-neutral-text) !important;
            }
            .button-secondary {
              --button-color-background-default: var(--wkdomains-darkreader-bg-color-neutral-background, var(--darkreader-neutral-background)) !important;
              --button-color-text-default: var(--wkdomains-darkreader-text-color-neutral-content-weak, var(--darkreader-neutral-text)) !important;
            }
            .internalBackButton,
            .internalForwardButton {
              background-image: linear-gradient(to right, var(--plain-background) 0, var(--wkdomains-darkreader-bg-color-secondary-background, var(--darkreader-neutral-background)) 30%) !important;
            }
            .label-container {
              background: var(--wkdomains-darkreader-bg-color-neutral-background, var(--darkreader-neutral-background)) !important;
            }
            .label-container:hover {
              background: var(--wkdomains-darkreader-bg-color-neutral-background-hover, var(--darkreader-neutral-background)) !important;
            }
            .md p>a[href="#s"]::after,
            a[href="#s"]::after {
              color: #000;
            }
            .text-neutral-content-strong {
              color: var(--wkdomains-darkreader-text-color-neutral-content-strong, var(--darkreader-neutral-text)) !important;
            }
            header a[aria-label="Home"] svg:last-child g,
            header > div > div + div a[href] *,
            header > div > div + div button[aria-label] * {
              fill: var(--darkreader-neutral-text) !important;
            }
            #comment-tree {
              background-color: var(--wkdomains-darkreader-bg-color-neutral-background, var(--darkreader-neutral-background)) !important;
            }
            #COIN_PURCHASE_DROPDOWN_ID > div {
              background: linear-gradient(180deg,hsla(0,0%,100%,.1) 45.96%,hsla(0,0%,100%,.57) 46%,hsla(0,0%,100%,0) 130%),\${gold} !important;
            }
            #COIN_PURCHASE_DROPDOWN_ID > div > span {
              color: \${white} !important;
            }
            #search-input-chip {
              background: var(--wkdomains-darkreader-bg-color-secondary-background-selected, var(--darkreader-neutral-background)) !important;
            }
            .md-spoiler-text:not([data-revealed])::selection {
              background-color: var(--wkdomains-darkreader-bg-newCommunityTheme-metaText, var(--darkreader-selection-background)) !important;
              color: transparent !important;
            }
            button[slot="forward-button"],
            button[slot="back-button"] {
              background-color: var(--wkdomains-darkreader-border-color-neutral, var(--darkreader-border)) !important;
            }
            div[slot="tabs"] {
              background: var(--wkdomains-darkreader-bg-color-neutral-background, var(--darkreader-neutral-background)) !important;
            }
            div[role="menu"][style^="position: fixed"] button button[role="switch"][aria-checked="false"] {
              background-color: \${gray} !important;
            }
            div[role="menu"][style^="position: fixed"] button button[role="switch"] > div {
              background-color: \${black} !important;
            }
            object[data="about:blank"] {
              display: none !important;
            }
            span[class="inline-block mr-[calc(var(--size-button-sm-h)-var(--rem10)-var(--button-border-width-default))] overflow-hidden text-ellipsis"] {
              color: var(--wkdomains-darkreader-text-color-neutral-content, var(--darkreader-neutral-text)) !important;
            }
            shreddit-comment-tree,
            .self-start,
            #comment-fold-button,
            button.w-lg,
            .bg-neutral-background {
              background-color: var(--wkdomains-darkreader-bg-shreddit-content-background, var(--darkreader-neutral-background)) !important;
            }
            .text-secondary {
              color: var(--wkdomains-darkreader-text-color-secondary, var(--darkreader-neutral-text)) !important;
            }
            faceplate-tracker > li > a:hover,
            faceplate-tracker > li > div:hover,
            div#RECENT > li > a:hover {
              background-color: var(--wkdomains-darkreader-bg-color-neutral-background-hover, var(--darkreader-neutral-background)) !important;
            }
            span.input-container.stateful-input input {
              color: var(--wkdomains-darkreader-text-color-tone-1, var(--darkreader-neutral-text)) !important;
            }
            .reddit-search-bar {
              background-color: var(--wkdomains-darkreader-bg-color-neutral-background, var(--darkreader-neutral-background)) !important;
            }
            .reddit-search-bar .text-neutral-content {
              color: var(--wkdomains-darkreader-text-color-tone-1, var(--darkreader-neutral-text)) !important;
            }
            faceplate-tracker > li[rpl-selected] > a {
              background-color: var(--wkdomains-darkreader-bg-color-tone-3, var(--darkreader-neutral-background)) !important;
            }
            faceplate-menu {
              background-color: var(--wkdomains-darkreader-bg-color-neutral-background-strong, var(--darkreader-neutral-background)) !important;
            }
            faceplate-tracker > button[rpl-selected] {
              background-color: var(--wkdomains-darkreader-bg-color-neutral-background-hover, var(--darkreader-neutral-background)) !important;
            }
            faceplate-tracker a[data-testid]:hover,
            faceplate-tracker[noun="trending"] div:hover {
              background-color: unset !important;
            }
            faceplate-hovercard > div > div > div,
            faceplate-hovercard > div > div > div:hover,
            #faceplate-tooltip {
              background-color: var(--wkdomains-darkreader-bg-color-neutral-background, var(--darkreader-neutral-background)) !important;
            }
            faceplate-hovercard p {
              color: var(--wkdomains-darkreader-text-color-neutral-content-strong, var(--darkreader-neutral-text)) !important;
            }
            .text-secondary-weak {
              color: var(--wkdomains-darkreader-text-color-secondary-weak, var(--darkreader-neutral-text)) !important;
            }
            button.button-plain:hover {
              color: var(--button-color-text-default) !important;
            }
            faceplate-menu > li > div {
              background-color: var(--wkdomains-darkreader-bg-color-neutral-background-hover, var(--darkreader-neutral-background)) !important;
            }
            .text-neutral-content-weak {
              color: var(--wkdomains-darkreader-text-color-neutral-content-weak, var(--darkreader-neutral-text));
            }
            :host > #content,
            .bg-neutral-background-weak {
              background: var(--darkreader-neutral-background) !important;
            }
          `
        }
      ];

      const SITE_FIX_CONFIG = \#(siteFixConfigLiteral);
      const SITE_FIX_SECTION_MAP = new Map([
        ["INVERT", "invert"],
        ["CSS", "css"],
        ["IGNORE INLINE STYLE", "ignoreInlineStyle"],
        ["IGNORE IMAGE ANALYSIS", "ignoreImageAnalysis"],
        ["IGNORE CSS", "ignoreCSS"],
        ["IGNORE CSS URL", "ignoreCSSUrl"],
        ["IGNORE CSS URLs", "ignoreCSSUrl"],
        ["DISABLE STYLESHEET PROXY", "disableStyleSheetsProxy"],
        ["DISABLE SHADOW ROOT PROXY", "disableShadowRootProxy"],
        ["DISABLE CUSTOM ELEMENT REGISTRY PROXY", "disableCustomElementRegistryProxy"],
        ["ENABLE CUSTOM ELEMENT REGISTRY PROXY", "enableCustomElementRegistryProxy"]
      ]);

      const isLikelySiteFixURLToken = (token) => {
        const value = String(token || "").trim().replace(/^https?:\/\//i, "");
        return value === "*"
          || /^(?:localhost(?::\d+)?|[*.a-z0-9-]+(?:\.[*a-z0-9-]+)+(?::\d+)?)(?:\/\S*)?$/i.test(value);
      };

      const isLikelySiteFixURLLine = (line) => {
        const tokens = String(line || "").trim().split(/\s+/).filter(Boolean);
        return tokens.length > 0 && tokens.every(isLikelySiteFixURLToken);
      };

      const makeEmptyParsedSiteFix = (urls) => ({
        url: urls,
        invert: [],
        css: "",
        ignoreInlineStyle: [],
        ignoreImageAnalysis: [],
        ignoreCSS: [],
        ignoreCSSUrl: [],
        disableStyleSheetsProxy: false,
        disableShadowRootProxy: false,
        disableCustomElementRegistryProxy: false,
        enableCustomElementRegistryProxy: false
      });

      const parseRelevantSiteFixConfig = (configText) => {
        const genericFixes = [];
        const bestSpecificFixes = [];
        let bestSpecificity = 0;
        let parsedFixCount = 0;
        let matchedFixCount = 0;
        let current = null;
        let section = null;
        let hadBlankLine = true;

        const commit = () => {
          if (current && current.url.length > 0) {
            parsedFixCount += 1;
            const isGeneric = current.url.includes("*");
            const specificity = siteFixSpecificity(current);
            if (isGeneric) {
              genericFixes.push(current);
              matchedFixCount += 1;
            } else if (specificity > 0) {
              matchedFixCount += 1;
              if (specificity > bestSpecificity) {
                bestSpecificity = specificity;
                bestSpecificFixes.splice(0, bestSpecificFixes.length, current);
              } else if (specificity === bestSpecificity) {
                bestSpecificFixes.push(current);
              }
            }
          }
          current = null;
          section = null;
        };

        for (const rawLine of String(configText || "").split(/\r?\n/)) {
          const line = rawLine.trimEnd();
          const trimmed = line.trim();
          if (!trimmed || trimmed.startsWith("#")) {
            hadBlankLine = true;
            continue;
          }

          const normalizedHeader = trimmed.toUpperCase();
          if (SITE_FIX_SECTION_MAP.has(normalizedHeader)) {
            section = SITE_FIX_SECTION_MAP.get(normalizedHeader);
            if (
              section === "disableStyleSheetsProxy"
              || section === "disableShadowRootProxy"
              || section === "disableCustomElementRegistryProxy"
              || section === "enableCustomElementRegistryProxy"
            ) {
              if (current) current[section] = true;
              section = null;
            }
            hadBlankLine = false;
            continue;
          }

          if ((hadBlankLine || !current) && isLikelySiteFixURLLine(trimmed)) {
            commit();
            current = makeEmptyParsedSiteFix(trimmed.split(/\s+/).filter(Boolean));
            hadBlankLine = false;
            continue;
          }

          if (!current || !section) {
            hadBlankLine = false;
            continue;
          }

          if (section === "css") {
            current.css += `${line}\n`;
          } else if (Array.isArray(current[section])) {
            current[section].push(trimmed);
          }
          hadBlankLine = false;
        }

        commit();
        return {
          fixes: [...genericFixes, ...bestSpecificFixes],
          parsedFixCount,
          matchedFixCount
        };
      };

      const siteFixPatternParts = (pattern) => {
        const normalized = String(pattern || "").toLowerCase().replace(/^[a-z][a-z0-9+.-]*:\/\//, "");
        const slashIndex = normalized.indexOf("/");
        return {
          host: slashIndex >= 0 ? normalized.slice(0, slashIndex) : normalized,
          path: slashIndex >= 0 ? normalized.slice(slashIndex) : ""
        };
      };

      const siteFixWildcardMatches = (value, pattern) => {
        if (!pattern || pattern === "*") return true;
        if (!pattern.includes("*")) return value === pattern;
        try {
          const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replaceAll("\\*", ".*");
          return new RegExp(`^${escaped}$`).test(value);
        } catch (_) {
          return value === pattern;
        }
      };

      const siteFixMatchesPattern = (pattern) => {
        const parts = siteFixPatternParts(pattern);
        const normalized = parts.host;
        const host = String(location.hostname || "").toLowerCase();
        if (!normalized || normalized === "*") return true;
        let hostMatches = false;
        if (normalized.startsWith("*.")) {
          const suffix = normalized.slice(1);
          hostMatches = host.endsWith(suffix);
        } else if (normalized.includes("*")) {
          hostMatches = siteFixWildcardMatches(host, normalized);
        } else {
          hostMatches = host === normalized || host.endsWith(`.${normalized}`);
        }
        return hostMatches && (!parts.path || siteFixWildcardMatches(location.pathname.toLowerCase(), parts.path));
      };

      const siteFixPatternSpecificity = (pattern) => {
        const parts = siteFixPatternParts(pattern);
        const normalized = parts.host;
        if (!normalized || normalized === "*") return 0;
        const wildcardPenalty = String(pattern || "").includes("*") ? 1000 : 0;
        const exactBonus = String(location.hostname || "").toLowerCase() === normalized ? 10000 : 0;
        return exactBonus + normalized.replaceAll("*", "").length + parts.path.replaceAll("*", "").length - wildcardPenalty;
      };

      const siteFixSpecificity = (fix) => {
        if (!fix || !Array.isArray(fix.url)) return 0;
        return fix.url
          .filter(siteFixMatchesPattern)
          .reduce((best, pattern) => Math.max(best, siteFixPatternSpecificity(pattern)), 0);
      };

      const combineSiteFixes = (fixes) => {
        if (!fixes.length) return null;
        const combined = {
          url: [],
          invert: [],
          css: "",
          ignoreInlineStyle: [],
          ignoreImageAnalysis: [],
          ignoreCSS: [],
          ignoreCSSUrl: [],
          disableStyleSheetsProxy: false,
          disableShadowRootProxy: false,
          disableCustomElementRegistryProxy: false,
          enableCustomElementRegistryProxy: false
        };

        for (const fix of fixes) {
          for (const key of ["url", "invert", "ignoreInlineStyle", "ignoreImageAnalysis", "ignoreCSS", "ignoreCSSUrl"]) {
            if (Array.isArray(fix[key])) {
              combined[key].push(...fix[key]);
            }
          }
          if (fix.css) {
            combined.css += `\n${fix.css}`;
          }
          combined.disableStyleSheetsProxy = combined.disableStyleSheetsProxy || fix.disableStyleSheetsProxy === true;
          combined.disableShadowRootProxy = combined.disableShadowRootProxy || fix.disableShadowRootProxy === true;
          combined.disableCustomElementRegistryProxy = combined.disableCustomElementRegistryProxy || fix.disableCustomElementRegistryProxy === true;
          combined.enableCustomElementRegistryProxy = combined.enableCustomElementRegistryProxy || fix.enableCustomElementRegistryProxy === true;
        }

        return combined;
      };

      const parsedSiteFixResult = parseRelevantSiteFixConfig(SITE_FIX_CONFIG);
      const parsedSiteFixes = parsedSiteFixResult.fixes;
      const allSiteFixes = SITE_FIXES.concat(parsedSiteFixes);
      const matchingSiteFixes = allSiteFixes.filter((fix) => Array.isArray(fix.url) && fix.url.some(siteFixMatchesPattern));
      const genericSiteFixes = matchingSiteFixes.filter((fix) => fix.url.includes("*"));
      const specificSiteFixes = matchingSiteFixes.filter((fix) => !fix.url.includes("*"));
      const bestSpecificity = specificSiteFixes.reduce((best, fix) => Math.max(best, siteFixSpecificity(fix)), 0);
      const mostSpecificSiteFixes = specificSiteFixes.filter((fix) => siteFixSpecificity(fix) === bestSpecificity && bestSpecificity > 0);
      const activeSiteFix = combineSiteFixes([
        ...genericSiteFixes,
        ...mostSpecificSiteFixes
      ].filter(Boolean));

      const activeSiteFixList = (key) => (
        activeSiteFix && Array.isArray(activeSiteFix[key])
          ? activeSiteFix[key].filter(Boolean)
          : []
      );

      const ignoredInlineSelectors = activeSiteFixList("ignoreInlineStyle");
      const ignoredImageAnalysisSelectors = activeSiteFixList("ignoreImageAnalysis");
      const ignoredCSSSelectors = activeSiteFixList("ignoreCSS");
      const ignoredCSSURLPatterns = activeSiteFixList("ignoreCSSUrl");
      const siteFixFlag = (key) => activeSiteFix && activeSiteFix[key] === true;
      const siteFixDebugStatus = () => ({
        configBytes: SITE_FIX_CONFIG.length,
        builtInFixes: SITE_FIXES.length,
        parsedFixes: parsedSiteFixResult.parsedFixCount,
        selectedParsedFixes: parsedSiteFixes.length,
        matchedParsedFixes: parsedSiteFixResult.matchedFixCount,
        matchingFixes: matchingSiteFixes.length,
        active: !!activeSiteFix,
        activeUrls: activeSiteFix ? activeSiteFix.url.slice(0, 12) : [],
        cssBytes: activeSiteFix ? String(activeSiteFix.css || "").length : 0,
        invertCount: activeSiteFixList("invert").length,
        ignoreInlineStyleCount: ignoredInlineSelectors.length,
        ignoreImageAnalysisCount: ignoredImageAnalysisSelectors.length,
        ignoreCSSCount: ignoredCSSSelectors.length,
        ignoreCSSUrlCount: ignoredCSSURLPatterns.length,
        disableStyleSheetsProxy: siteFixFlag("disableStyleSheetsProxy"),
        disableShadowRootProxy: siteFixFlag("disableShadowRootProxy"),
        disableCustomElementRegistryProxy: siteFixFlag("disableCustomElementRegistryProxy"),
        enableCustomElementRegistryProxy: siteFixFlag("enableCustomElementRegistryProxy")
      });

      const matchesAnySiteFixSelector = (element, selectors) => {
        if (!element || !element.matches || !selectors || selectors.length === 0) return false;
        for (const selector of selectors) {
          try {
            if (element.matches(selector)) return true;
          } catch (_) {}
        }
        return false;
      };

      const shouldIgnoreInlineStyle = (element) => matchesAnySiteFixSelector(element, ignoredInlineSelectors);
      const shouldIgnoreImageAnalysis = (element) => matchesAnySiteFixSelector(element, ignoredImageAnalysisSelectors);
      const shouldIgnoreCSSSelector = (selectorText) => {
        const text = String(selectorText || "");
        if (!text || ignoredCSSSelectors.length === 0) return false;
        return ignoredCSSSelectors.some((selector) => {
          const value = String(selector || "").trim();
          return value && (text === value || text.includes(value));
        });
      };

      const replaceSiteCSSTemplates = (cssText) => String(cssText || "").replace(/\$\{(.+?)\}/g, (match, token) => {
        const color = parseColor(token);
        if (!color) return match;
        return relativeLuminance(color) > 0.5
          ? (modifyBackgroundColor(color) || match)
          : (modifyForegroundColor(color) || match);
      });

      const siteFixRootSelector = (selector) => {
        const trimmed = String(selector || "").trim();
        return trimmed
          ? `:root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) ${trimmed}`
          : "";
      };

      const getSiteFixInvertStyle = () => {
        const selectors = activeSiteFixList("invert").map(siteFixRootSelector).filter(Boolean);
        return selectors.length > 0
          ? `${selectors.join(",\n")} {\n  filter: invert(100%) hue-rotate(180deg) !important;\n}`
          : "";
      };

      const getSiteFixStyle = () => activeSiteFix ? replaceSiteCSSTemplates(activeSiteFix.css || "") : "";
    """#
    }
}
