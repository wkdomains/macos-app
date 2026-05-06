//
//  BrowserDarkModeSiteFixesScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeSiteFixesScript = #"""
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
        }
      ];

      const siteFixMatchesPattern = (pattern) => {
        const normalized = String(pattern || "").toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, "");
        const host = String(location.hostname || "").toLowerCase();
        if (!normalized || normalized === "*") return true;
        if (normalized.startsWith("*.")) {
          const suffix = normalized.slice(1);
          return host.endsWith(suffix);
        }
        return host === normalized || host.endsWith(`.${normalized}`);
      };

      const combineSiteFixes = (fixes) => {
        if (!fixes.length) return null;
        const combined = {
          url: [],
          invert: [],
          css: "",
          ignoreInlineStyle: [],
          ignoreImageAnalysis: [],
          ignoreCSSUrl: [],
          disableStyleSheetsProxy: false,
          disableCustomElementRegistryProxy: false
        };

        for (const fix of fixes) {
          for (const key of ["url", "invert", "ignoreInlineStyle", "ignoreImageAnalysis", "ignoreCSSUrl"]) {
            if (Array.isArray(fix[key])) {
              combined[key].push(...fix[key]);
            }
          }
          if (fix.css) {
            combined.css += `\n${fix.css}`;
          }
          combined.disableStyleSheetsProxy = combined.disableStyleSheetsProxy || fix.disableStyleSheetsProxy === true;
          combined.disableCustomElementRegistryProxy = combined.disableCustomElementRegistryProxy || fix.disableCustomElementRegistryProxy === true;
        }

        return combined;
      };

      const matchingSiteFixes = SITE_FIXES.filter((fix) => Array.isArray(fix.url) && fix.url.some(siteFixMatchesPattern));
      const genericSiteFixes = matchingSiteFixes.filter((fix) => fix.url.includes("*"));
      const specificSiteFixes = matchingSiteFixes.filter((fix) => !fix.url.includes("*"));
      const activeSiteFix = combineSiteFixes([...genericSiteFixes, ...specificSiteFixes]);

      const activeSiteFixList = (key) => (
        activeSiteFix && Array.isArray(activeSiteFix[key])
          ? activeSiteFix[key].filter(Boolean)
          : []
      );

      const ignoredInlineSelectors = activeSiteFixList("ignoreInlineStyle");
      const ignoredImageAnalysisSelectors = activeSiteFixList("ignoreImageAnalysis");
      const ignoredCSSURLPatterns = activeSiteFixList("ignoreCSSUrl");
      const siteFixFlag = (key) => activeSiteFix && activeSiteFix[key] === true;

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
