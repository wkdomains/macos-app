//
//  BrowserDarkModeSiteFixesScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static func browserDarkModeSiteFixesScript(siteFixConfig: String) -> String {
        let siteFixConfigLiteral = javaScriptStringLiteral(siteFixConfig)

        return #"""
      const SITE_FIXES = [];

      const SITE_FIX_CONFIG = \#(siteFixConfigLiteral);
      const SITE_FIX_SECTION_MAP = new Map([
        ["INVERT", "invert"],
        ["CSS", "css"],
        ["IGNORE INLINE STYLE", "ignoreInlineStyle"],
        ["IGNORE INLINE STYLES", "ignoreInlineStyle"],
        ["IGNORE IMAGE ANALYSIS", "ignoreImageAnalysis"],
        ["IGNORE CSS", "ignoreCSS"],
        ["IGNORE CSS URL", "ignoreCSSUrl"],
        ["IGNORE CSS URLs", "ignoreCSSUrl"],
        ["DISABLE STYLESHEET PROXY", "disableStyleSheetsProxy"],
        ["DISABLE STYLE SHEETS PROXY", "disableStyleSheetsProxy"],
        ["DISABLE SHADOW ROOT PROXY", "disableShadowRootProxy"],
        ["DISABLE CUSTOM ELEMENT REGISTRY PROXY", "disableCustomElementRegistryProxy"],
        ["ENABLE CUSTOM ELEMENT REGISTRY PROXY", "enableCustomElementRegistryProxy"]
      ]);
      const UNKNOWN_SITE_FIX_SECTION = "__unknown";

      const normalizeSiteFixSectionHeader = (line) => String(line || "").trim().toUpperCase().replace(/\s+/g, " ");

      const isLikelyUnknownSiteFixSectionHeader = (line) => {
        const value = normalizeSiteFixSectionHeader(line);
        if (!value || SITE_FIX_SECTION_MAP.has(value) || isLikelySiteFixURLLine(value)) return false;
        if (value.length > 72) return false;
        if (!/^(IGNORE|DISABLE|ENABLE|INVERT|CSS|NO|ONLY)\b/.test(value)) return false;
        return /^[A-Z][A-Z0-9 _-]*$/.test(value);
      };

      const isLikelySiteFixURLToken = (token) => {
        const value = String(token || "").trim().replace(/^https?:\/\//i, "");
        return value === "*"
          || /^(?:localhost(?::\d+)?|[*.a-z0-9-]+(?:\.[*a-z0-9-]+)+(?::\d+)?)(?:\/\S*)?$/i.test(value);
      };

      const isLikelySiteFixURLLine = (line) => {
        const tokens = String(line || "").trim().split(/\s+/).filter(Boolean);
        return tokens.length > 0 && tokens.every(isLikelySiteFixURLToken);
      };

      const isSiteFixSeparatorLine = (line) => /^={3,}$/.test(String(line || "").trim());

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
        let unknownSectionCount = 0;
        let skippedUnknownSectionLines = 0;
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

          if (isSiteFixSeparatorLine(trimmed)) {
            commit();
            hadBlankLine = true;
            continue;
          }

          const normalizedHeader = normalizeSiteFixSectionHeader(trimmed);
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

          if (current && isLikelyUnknownSiteFixSectionHeader(trimmed)) {
            section = UNKNOWN_SITE_FIX_SECTION;
            unknownSectionCount += 1;
            hadBlankLine = false;
            continue;
          }

          if ((!current || (!section && hadBlankLine)) && isLikelySiteFixURLLine(trimmed)) {
            commit();
            current = makeEmptyParsedSiteFix(trimmed.split(/\s+/).filter(Boolean));
            hadBlankLine = false;
            continue;
          }

          if (current && !section && isLikelySiteFixURLLine(trimmed)) {
            current.url.push(...trimmed.split(/\s+/).filter(Boolean));
            hadBlankLine = false;
            continue;
          }

          if (!current || !section) {
            hadBlankLine = false;
            continue;
          }

          if (section === UNKNOWN_SITE_FIX_SECTION) {
            skippedUnknownSectionLines += 1;
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
          matchedFixCount,
          unknownSectionCount,
          skippedUnknownSectionLines
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
      const builtInSiteFixesActive = SITE_FIX_CONFIG.length === 0;
      const allSiteFixes = (builtInSiteFixesActive ? SITE_FIXES : []).concat(parsedSiteFixes);
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
        builtInFixes: builtInSiteFixesActive ? SITE_FIXES.length : 0,
        fallbackBuiltInFixes: SITE_FIXES.length,
        parsedFixes: parsedSiteFixResult.parsedFixCount,
        selectedParsedFixes: parsedSiteFixes.length,
        matchedParsedFixes: parsedSiteFixResult.matchedFixCount,
        unknownSections: parsedSiteFixResult.unknownSectionCount,
        skippedUnknownSectionLines: parsedSiteFixResult.skippedUnknownSectionLines,
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

      const parseSiteFixTemplateColor = (token) => {
        const text = String(token || "").trim();
        if (/^[0-9a-f]{3,4}$/i.test(text) || /^[0-9a-f]{6,8}$/i.test(text)) {
          return parseColor(`#${text}`);
        }
        return parseColor(text);
      };

      const siteFixDeclarationNameBefore = (cssText, offset) => {
        const text = String(cssText || "");
        const semicolon = text.lastIndexOf(";", offset);
        const openBrace = text.lastIndexOf("{", offset);
        const closeBrace = text.lastIndexOf("}", offset);
        const start = Math.max(semicolon, openBrace, closeBrace);
        const colon = text.lastIndexOf(":", offset);
        if (colon <= start) return "";
        return text.slice(start + 1, colon).trim().toLowerCase();
      };

      const siteFixTemplateTransformer = (property, color) => {
        const name = String(property || "").toLowerCase();
        if (
          name.includes("background")
          || name.includes("--darkreader-bg")
          || name.includes("-bg")
          || name.includes("surface")
          || name.includes("canvas")
          || name.includes("container")
        ) {
          return modifyBackgroundColor;
        }
        if (
          name.includes("border")
          || name.includes("outline")
          || name.includes("column-rule")
          || name.includes("decoration")
          || name.includes("--darkreader-border")
        ) {
          return modifyBorderColor;
        }
        if (
          name.includes("shadow")
          || name.includes("overlay")
          || name.includes("scrim")
        ) {
          return modifyBackgroundColor;
        }
        if (
          name.includes("color")
          || name.includes("text")
          || name.includes("foreground")
          || name.includes("content")
          || name.includes("fill")
          || name.includes("stroke")
          || name.includes("--darkreader-text")
        ) {
          return modifyForegroundColor;
        }
        return relativeLuminance(color) > 0.5 ? modifyBackgroundColor : modifyForegroundColor;
      };

      const replaceSiteCSSTemplates = (cssText) => String(cssText || "").replace(/\$\{(.+?)\}/g, (match, token, offset, source) => {
        const color = parseSiteFixTemplateColor(token);
        if (!color) return match;
        const property = siteFixDeclarationNameBefore(source, offset);
        return siteFixTemplateTransformer(property, color)(color) || match;
      });

      const siteFixRootSelector = (selector) => {
        const trimmed = String(selector || "").trim();
        return trimmed
          ? `:root[${ROOT_ATTRIBUTE}]:not([${SAMPLING_ATTRIBUTE}]) ${trimmed}`
          : "";
      };

      const getSiteFixInvertStyle = () => {
        const selectors = activeSiteFixList("invert").map(siteFixRootSelector).filter(Boolean);
        const filterValue = themeInversionFilterValue(-10, 100) || "invert(100%) hue-rotate(180deg)";
        return selectors.length > 0
          ? `${selectors.join(",\n")} {\n  -webkit-filter: ${filterValue} !important;\n  filter: ${filterValue} !important;\n}`
          : "";
      };

      const getSiteFixStyle = () => activeSiteFix ? replaceSiteCSSTemplates(activeSiteFix.css || "") : "";
    """#
    }
}
