//
//  BrowserXRayOverlay.swift
//  macos-app
//

import Combine
import AppKit
import Foundation
import SwiftUI
import WebKit

private enum XRayTheme {
    static let ink = Color(red: 0.93, green: 0.98, blue: 0.98)
    static let muted = Color(red: 0.58, green: 0.69, blue: 0.70)
    static let faint = Color(red: 0.34, green: 0.45, blue: 0.46)
    static let panel = Color(red: 0.035, green: 0.047, blue: 0.050)
    static let panelRaised = Color(red: 0.055, green: 0.074, blue: 0.078)
    static let grid = Color(red: 0.35, green: 0.77, blue: 0.78)
    static let accent = Color(red: 0.48, green: 0.98, blue: 0.90)
    static let warm = Color(red: 1.0, green: 0.62, blue: 0.32)
    static let bad = Color(red: 1.0, green: 0.33, blue: 0.38)
}

struct BrowserXRayWorkspace<Content: View>: View {
    @ObservedObject var browser: BrowserModel
    let isVisible: Bool
    let content: () -> Content

    @StateObject private var model = BrowserXRayOverlayModel()

    init(browser: BrowserModel, isVisible: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.browser = browser
        self.isVisible = isVisible
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let leftGutter: CGFloat = 320
            let preferredRightGutter = min(max(proxy.size.width * 0.26, 280), 380)
            let rightGutter = isVisible ? max(240, min(preferredRightGutter, proxy.size.width - leftGutter - 420)) : 0
            let recentXHR = currentPageXHR.prefix(6)
            let warnings = browser.consoleRecords
                .filter { ["error", "warn", "warning"].contains($0.level.lowercased()) }
                .suffix(4)

            HStack(spacing: 0) {
                XRayDOMTreeRail(telemetry: model.telemetry)
                    .frame(width: isVisible ? leftGutter : 0)
                    .opacity(isVisible ? 1 : 0)
                    .clipped()

                ZStack(alignment: .topLeading) {
                    content()
                        .frame(width: isVisible ? nil : browser.viewportMode.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .frame(
                    maxWidth: isVisible || browser.viewportMode == .desktop ? .infinity : nil,
                    maxHeight: .infinity
                )

                XRayStatsRail(
                    telemetry: model.telemetry,
                    title: browser.webView.title ?? "Untitled",
                    url: browser.webView.url,
                    requests: Array(recentXHR),
                    warnings: Array(warnings)
                )
                .frame(width: rightGutter)
                .opacity(isVisible ? 1 : 0)
                .clipped()
            }
            .clipShape(Rectangle())
            .onAppear {
                if isVisible {
                    model.start(browser: browser)
                }
            }
            .onDisappear {
                model.stop()
            }
            .onChange(of: isVisible) { _, visible in
                if visible {
                    model.start(browser: browser)
                } else {
                    model.stop()
                }
            }
            .onChange(of: browser.activeTabID) { _, _ in
                if isVisible {
                    model.start(browser: browser)
                }
            }
            .onChange(of: browser.isLoading) { _, _ in
                if isVisible {
                    model.refreshSoon(browser: browser)
                }
            }
        }
    }

    private var currentPageXHR: [XHRRequestRecord] {
        guard let host = browser.webView.url?.host else {
            return Array(browser.xhrRecords.suffix(8).reversed())
        }

        return browser.xhrRequests(for: host)
            .sorted { $0.startedAt > $1.startedAt }
    }
}

private struct XRayCenterInstrumentation: View {
    let telemetry: BrowserXRayTelemetry
    let host: String
    let hoverPath: [BrowserXRayHoverNode]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                XRayCenterSurface()

                XRayGrid(spacing: 28)
                    .stroke(XRayTheme.grid.opacity(0.10), lineWidth: 1)

                if let node = hoverPath.last {
                    let rect = scaledRect(node.rect, viewport: telemetry.viewport, canvas: proxy.size)

                    if rect.width > 5, rect.height > 5 {
                        XRayHoverPathFrame(node: node)
                            .frame(width: max(8, rect.width), height: max(8, rect.height))
                            .position(x: rect.midX, y: rect.midY)
                    }
                }

                XRayPlainPageHeader(host: host, hoverPath: hoverPath)
                    .frame(width: min(max(proxy.size.width - 28, 220), 620), alignment: .leading)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    private func scaledRect(_ rect: CGRect, viewport: CGSize, canvas: CGSize) -> CGRect {
        guard viewport.width > 0, viewport.height > 0 else { return .zero }

        let xScale = canvas.width / viewport.width
        let yScale = canvas.height / viewport.height
        return CGRect(
            x: rect.minX * xScale,
            y: rect.minY * yScale,
            width: rect.width * xScale,
            height: rect.height * yScale
        )
    }
}

@MainActor
private final class BrowserXRayOverlayModel: ObservableObject {
    @Published var telemetry = BrowserXRayTelemetry.empty

    private var browser: BrowserModel?
    private var refreshTask: Task<Void, Never>?
    private var mouseMonitor: Any?
    private var mousePoint: CGPoint?
    private var isRefreshing = false
    private var lastMouseRefresh = Date.distantPast

    func start(browser: BrowserModel) {
        stop()
        self.browser = browser
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self, weak browser] event in
            guard let self, let browser else { return event }
            self.updateMousePoint(from: event, browser: browser)
            return event
        }
        refresh(browser: browser)
        refreshTask = Task { @MainActor [weak self, weak browser] in
            while !Task.isCancelled {
                guard let self, let browser else { return }
                self.refresh(browser: browser, renderView: false)
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        if let browser {
            removeAgentView(from: browser)
        }
        mouseMonitor = nil
        browser = nil
        mousePoint = nil
        isRefreshing = false
    }

    func refreshSoon(browser: BrowserModel) {
        Task { @MainActor [weak self, weak browser] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard let self, let browser else { return }
            self.refresh(browser: browser)
        }
    }

    private func refresh(browser: BrowserModel, renderView: Bool = true) {
        guard !isRefreshing else { return }
        isRefreshing = true

        browser.webView.evaluateJavaScript(Self.telemetryScript(mousePoint: mousePoint, renderView: renderView)) { [weak self] value, _ in
            let json = value as? String

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRefreshing = false

                guard let json,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let payload = object as? [String: Any]
                else {
                    return
                }

                self.telemetry = BrowserXRayTelemetry(payload: payload)
            }
        }
    }

    private func refreshHover(browser: BrowserModel) {
        browser.webView.evaluateJavaScript(Self.telemetryScript(mousePoint: mousePoint, renderView: false)) { [weak self] value, _ in
            let json = value as? String

            Task { @MainActor [weak self] in
                guard let self,
                      let json,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let payload = object as? [String: Any]
                else {
                    return
                }

                self.telemetry = BrowserXRayTelemetry(payload: payload)
            }
        }
    }

    private func updateMousePoint(from event: NSEvent, browser: BrowserModel) {
        let viewPoint = browser.webView.convert(event.locationInWindow, from: nil)
        guard browser.webView.bounds.contains(viewPoint) else {
            mousePoint = nil
            return
        }

        mousePoint = CGPoint(
            x: max(0, viewPoint.x),
            y: max(0, browser.webView.bounds.height - viewPoint.y)
        )

        guard Date().timeIntervalSince(lastMouseRefresh) > 0.12 else { return }
        lastMouseRefresh = Date()
        refreshHover(browser: browser)
    }

    private func removeAgentView(from browser: BrowserModel) {
        browser.restoreOriginalPageViewAfterXRay()
    }

    private static func telemetryScript(mousePoint: CGPoint?, renderView: Bool) -> String {
        let mouseX = mousePoint.map { String(format: "%.1f", Double($0.x)) } ?? "null"
        let mouseY = mousePoint.map { String(format: "%.1f", Double($0.y)) } ?? "null"
        let shouldRender = renderView ? "true" : "false"

        return """
    (() => {
      const renderView = \(shouldRender);
      const rootID = "__wkdomainsAgentTextView";
      const styleID = "__wkdomainsAgentViewStyle";
      const mousePoint = { x: \(mouseX), y: \(mouseY) };
      const hiddenTags = new Set(["script", "style", "link", "meta", "noscript", "template"]);
      const sourceSelector = "body *";

      const css = `
        html.__wkdomains_agent_view,
        html.__wkdomains_agent_view body {
          background: #111313 !important;
          color: #d7ddda !important;
          color-scheme: dark !important;
          margin: 0 !important;
          padding: 0 !important;
        }

        html.__wkdomains_agent_view body > :not(#__wkdomainsAgentTextView):not(#__wkdomainsAgentViewStyle) {
          display: none !important;
        }

        #__wkdomainsAgentTextView,
        #__wkdomainsAgentTextView * {
          animation: none !important;
          background-image: none !important;
          box-sizing: border-box !important;
          box-shadow: none !important;
          font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif !important;
          letter-spacing: 0 !important;
          text-shadow: none !important;
          transition: none !important;
        }

        #__wkdomainsAgentTextView {
          background: #111313 !important;
          color: #d7ddda !important;
          display: block !important;
          font-size: 16px !important;
          line-height: 1.55 !important;
          margin: 0 auto !important;
          max-width: 880px !important;
          min-height: 100vh !important;
          padding: 24px 28px 96px !important;
        }

        #__wkdomainsAgentTextView .wkx-document-header {
          border-bottom: 1px solid rgba(215, 221, 218, 0.16) !important;
          color: #899695 !important;
          display: block !important;
          font-size: 12px !important;
          font-weight: 700 !important;
          margin: 0 0 18px !important;
          padding: 0 0 10px !important;
        }

        #__wkdomainsAgentTextView .wkx-line {
          border-bottom: 1px solid rgba(215, 221, 218, 0.08) !important;
          color: #d7ddda !important;
          cursor: default !important;
          display: block !important;
          margin: 0 !important;
          padding: 8px 0 !important;
          text-align: left !important;
          white-space: normal !important;
          width: 100% !important;
        }

        #__wkdomainsAgentTextView .wkx-line[data-wkx-kind="heading"] {
          border-bottom-color: rgba(215, 221, 218, 0.18) !important;
          color: #f4f7f5 !important;
          font-size: 22px !important;
          font-weight: 760 !important;
          line-height: 1.25 !important;
          margin-top: 10px !important;
          padding-top: 14px !important;
        }

        #__wkdomainsAgentTextView .wkx-line[data-wkx-kind="link"] {
          color: #8ecfff !important;
          cursor: pointer !important;
        }

        #__wkdomainsAgentTextView .wkx-line[data-wkx-kind="button"] {
          color: #f1d18a !important;
          cursor: pointer !important;
          font-weight: 680 !important;
        }

        #__wkdomainsAgentTextView .wkx-line[data-wkx-kind="field"] {
          color: #bfe7d8 !important;
          cursor: text !important;
        }

        #__wkdomainsAgentTextView .wkx-line[data-wkx-kind="media"] {
          color: #899695 !important;
          font-size: 13px !important;
        }

        #__wkdomainsAgentTextView .wkx-kind {
          color: #6f7c7a !important;
          display: inline-block !important;
          font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace !important;
          font-size: 11px !important;
          font-weight: 800 !important;
          margin-right: 10px !important;
          min-width: 54px !important;
          text-transform: uppercase !important;
        }

      `;

      const text = (element) => {
        const direct = Array.from(element.childNodes || [])
          .filter((node) => node.nodeType === Node.TEXT_NODE)
          .map((node) => node.textContent || "")
          .join(" ");
        const raw = element.getAttribute("aria-label")
          || element.getAttribute("placeholder")
          || element.getAttribute("alt")
          || element.getAttribute("title")
          || direct
          || (["input", "textarea", "select"].includes(element.tagName.toLowerCase()) ? element.value : "")
          || "";
        return String(raw).replace(/\\s+/g, " ").trim();
      };

      const role = (element) => {
        if (!element || element.nodeType !== 1) return "";
        const explicit = element.getAttribute("role");
        if (explicit) return explicit;
        const tag = element.tagName.toLowerCase();
        if (tag === "a") return "link";
        if (tag === "button") return "button";
        if (["input", "select", "textarea"].includes(tag)) return "field";
        if (/^h[1-6]$/.test(tag)) return "heading";
        return tag;
      };

      const kind = (element) => {
        const tag = element.tagName.toLowerCase();
        const elementRole = role(element);
        if (/^h[1-6]$/.test(tag) || elementRole === "heading") return "heading";
        if (tag === "a" || elementRole === "link") return "link";
        if (tag === "button" || elementRole === "button" || element.onclick) return "button";
        if (["input", "select", "textarea"].includes(tag) || elementRole === "textbox") return "field";
        if (["img", "video", "canvas", "svg"].includes(tag)) return "media";
        return "text";
      };

      const tone = (element) => {
        const itemKind = kind(element);
        if (["link", "button", "field"].includes(itemKind)) return "action";
        if (itemKind === "heading") return "semantic";
        if (element.getAttribute("aria-label") || element.getAttribute("data-testid")) return "signal";
        return "structure";
      };

      const shortSelector = (element) => {
        if (!element || element.nodeType !== 1) return "";
        const tag = element.tagName.toLowerCase();
        const id = element.id ? `#${String(element.id).replace(/\\s+/g, "")}` : "";
        if (id) return `${tag}${id}`;
        const testId = element.getAttribute("data-testid");
        if (testId) return `${tag}[data-testid="${String(testId).slice(0, 34)}"]`;
        const className = String(element.className || "").split(/\\s+/).filter(Boolean).slice(0, 2).join(".");
        return className ? `${tag}.${className}` : tag;
      };

      const install = () => {
        document.documentElement.classList.add("__wkdomains_agent_view");
        let style = document.getElementById(styleID);
        if (!style) {
          style = document.createElement("style");
          style.id = styleID;
          (document.head || document.documentElement).appendChild(style);
        }
        if (style.textContent !== css) style.textContent = css;
      };

      const shouldInclude = (element) => {
        if (!element || element.nodeType !== 1) return false;
        if (element.closest(`#${rootID}`)) return false;
        const tag = element.tagName.toLowerCase();
        if (hiddenTags.has(tag)) return false;
        const itemKind = kind(element);
        const label = text(element);
        if (itemKind === "media") return label.length > 0;
        if (["link", "button", "field", "heading"].includes(itemKind)) return label.length > 0 || tag !== "a";
        if (label.length < 2) return false;
        if (element.children.length > 4 && label.length > 120) return false;
        return Array.from(element.childNodes || []).some((node) => node.nodeType === Node.TEXT_NODE && String(node.textContent || "").trim().length > 0);
      };

      const collectSources = () => {
        const seen = new Set();
        const sources = [];
        Array.from(document.querySelectorAll(sourceSelector)).forEach((element) => {
          if (!shouldInclude(element)) return;
          const label = text(element);
          const itemKind = kind(element);
          const key = `${itemKind}:${label.toLowerCase()}`;
          if (label.length > 14 && seen.has(key)) return;
          seen.add(key);
          sources.push(element);
        });
        return sources.slice(0, 500);
      };

      const render = () => {
        install();
        const sources = collectSources();
        window.__wkdomainsAgentSources = sources;

        let root = document.getElementById(rootID);
        if (!root) {
          root = document.createElement("main");
          root.id = rootID;
          document.body.prepend(root);
        }

        root.textContent = "";
        const header = document.createElement("div");
        header.className = "wkx-document-header";
        header.textContent = `${document.title || location.hostname} / ${location.hostname}`;
        root.appendChild(header);

        sources.forEach((source, index) => {
          const itemKind = kind(source);
          const line = document.createElement("button");
          line.type = "button";
          line.className = "wkx-line";
          line.dataset.wkxSourceIndex = String(index);
          line.dataset.wkxKind = itemKind;

          const marker = document.createElement("span");
          marker.className = "wkx-kind";
          marker.textContent = itemKind;

          const content = document.createElement("span");
          content.textContent = text(source) || shortSelector(source);

          line.append(marker, content);
          root.appendChild(line);
        });

        if (!root.dataset.wired) {
          root.dataset.wired = "true";
          root.addEventListener("click", (event) => {
            const line = event.target && event.target.closest("[data-wkx-source-index]");
            if (!line) return;
            const source = window.__wkdomainsAgentSources?.[Number(line.dataset.wkxSourceIndex)];
            if (!source) return;
            if (["INPUT", "TEXTAREA", "SELECT"].includes(source.tagName)) {
              source.focus();
            } else {
              source.click();
            }
          });
        }
      };

      if (renderView || !document.getElementById(rootID)) render();

      const sources = window.__wkdomainsAgentSources || [];
      const sourceFromPoint = () => {
        if (mousePoint.x == null || mousePoint.y == null) return null;
        const target = document.elementFromPoint(mousePoint.x, mousePoint.y);
        const line = target && target.closest ? target.closest("[data-wkx-source-index]") : null;
        if (!line) return null;
        const source = sources[Number(line.dataset.wkxSourceIndex)];
        return source || null;
      };

      const hoverPath = (() => {
        const source = sourceFromPoint();
        if (!source) return [];
        const path = [];
        let current = source;
        while (current && current.nodeType === 1 && path.length < 9) {
          path.unshift({
            id: `@h${path.length + 1}`,
            tag: current.tagName.toLowerCase(),
            role: role(current),
            label: text(current).slice(0, 100),
            selector: shortSelector(current),
            rect: { x: 0, y: 0, width: 0, height: 0 }
          });
          current = current.parentElement;
        }
        return path;
      })();

      const nodes = sources.slice(0, 90).map((element, index) => ({
        id: `@e${index + 1}`,
        tag: element.tagName.toLowerCase(),
        role: role(element),
        label: text(element).slice(0, 100),
        tone: tone(element),
        rect: { x: 0, y: 0, width: 0, height: 0 }
      }));

      const originalRoot = document.body;
      const all = Array.from(originalRoot.querySelectorAll(sourceSelector)).filter((element) => !element.closest(`#${rootID}`));
      const clickable = all.filter((element) => ["link", "button", "field"].includes(kind(element))).length;
      const forms = all.filter((element) => ["input", "select", "textarea", "form"].includes(element.tagName.toLowerCase())).length;
      const headings = all.filter((element) => kind(element) === "heading").length;
      const links = all.filter((element) => element.tagName?.toLowerCase() === "a").length;
      const depth = (() => {
        let max = 0;
        const walk = (node, level) => {
          if (!node || node.id === rootID) return;
          max = Math.max(max, level);
          Array.from(node.children || []).slice(0, 18).forEach((child) => walk(child, level + 1));
        };
        walk(document.body, 1);
        return max;
      })();

      return JSON.stringify({
        nodes,
        hoverPath,
        elementCount: all.length,
        clickableCount: clickable,
        formControlCount: forms,
        headingCount: headings,
        linkCount: links,
        domDepth: depth,
        scrollY: Math.round(window.scrollY || 0),
        docHeight: Math.round(document.documentElement.scrollHeight || document.body?.scrollHeight || 0),
        viewport: { width: window.innerWidth || 1, height: window.innerHeight || 1 }
      });
    })();
    """
    }

}

extension BrowserModel {
    func restoreOriginalPageViewAfterXRay() {
        for tab in tabStates {
            tab.webView.evaluateJavaScript(BrowserXRayPageScripts.removeAgentView)
        }
    }
}

private enum BrowserXRayPageScripts {
    static let removeAgentView = """
    (() => {
      document.documentElement.classList.remove("__wkdomains_agent_view");
      document.getElementById("__wkdomainsAgentViewStyle")?.remove();
      document.getElementById("__wkdomainsAgentTextView")?.remove();
      window.__wkdomainsAgentSources = [];
      document.querySelectorAll("[data-wkx-node],[data-wkx-hover],[data-wkx-source-index],[data-wkx-kind]").forEach((element) => {
        element.removeAttribute("data-wkx-node");
        element.removeAttribute("data-wkx-hover");
        element.removeAttribute("data-wkx-ref");
        element.removeAttribute("data-wkx-tag");
        element.removeAttribute("data-wkx-role");
        element.removeAttribute("data-wkx-source-index");
        element.removeAttribute("data-wkx-kind");
      });
      return true;
    })();
    """
}

nonisolated private struct BrowserXRayTelemetry {
    var nodes: [BrowserXRayNode]
    var hoverPath: [BrowserXRayHoverNode]
    var elementCount: Int
    var clickableCount: Int
    var formControlCount: Int
    var headingCount: Int
    var linkCount: Int
    var domDepth: Int
    var scrollY: Int
    var docHeight: Int
    var viewport: CGSize

    static let empty = BrowserXRayTelemetry(
        nodes: [],
        hoverPath: [],
        elementCount: 0,
        clickableCount: 0,
        formControlCount: 0,
        headingCount: 0,
        linkCount: 0,
        domDepth: 0,
        scrollY: 0,
        docHeight: 0,
        viewport: CGSize(width: 1, height: 1)
    )

    init(
        nodes: [BrowserXRayNode],
        hoverPath: [BrowserXRayHoverNode],
        elementCount: Int,
        clickableCount: Int,
        formControlCount: Int,
        headingCount: Int,
        linkCount: Int,
        domDepth: Int,
        scrollY: Int,
        docHeight: Int,
        viewport: CGSize
    ) {
        self.nodes = nodes
        self.hoverPath = hoverPath
        self.elementCount = elementCount
        self.clickableCount = clickableCount
        self.formControlCount = formControlCount
        self.headingCount = headingCount
        self.linkCount = linkCount
        self.domDepth = domDepth
        self.scrollY = scrollY
        self.docHeight = docHeight
        self.viewport = viewport
    }

    init(payload: [String: Any]) {
        let viewportPayload = payload["viewport"] as? [String: Any]
        viewport = CGSize(
            width: Self.number(viewportPayload?["width"]) ?? 1,
            height: Self.number(viewportPayload?["height"]) ?? 1
        )
        elementCount = Int(Self.number(payload["elementCount"]) ?? 0)
        clickableCount = Int(Self.number(payload["clickableCount"]) ?? 0)
        formControlCount = Int(Self.number(payload["formControlCount"]) ?? 0)
        headingCount = Int(Self.number(payload["headingCount"]) ?? 0)
        linkCount = Int(Self.number(payload["linkCount"]) ?? 0)
        domDepth = Int(Self.number(payload["domDepth"]) ?? 0)
        scrollY = Int(Self.number(payload["scrollY"]) ?? 0)
        docHeight = Int(Self.number(payload["docHeight"]) ?? 0)

        nodes = (payload["nodes"] as? [[String: Any]] ?? []).compactMap(BrowserXRayNode.init(payload:))
        hoverPath = (payload["hoverPath"] as? [[String: Any]] ?? []).compactMap(BrowserXRayHoverNode.init(payload:))
    }

    private static func number(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return nil
    }
}

nonisolated private struct BrowserXRayHoverNode: Identifiable {
    let id: String
    let tag: String
    let role: String
    let label: String
    let selector: String
    let rect: CGRect

    init?(payload: [String: Any]) {
        guard let id = payload["id"] as? String,
              let rectPayload = payload["rect"] as? [String: Any]
        else {
            return nil
        }

        self.id = id
        tag = payload["tag"] as? String ?? "node"
        role = payload["role"] as? String ?? tag
        label = payload["label"] as? String ?? tag
        selector = payload["selector"] as? String ?? tag
        rect = CGRect(
            x: Self.number(rectPayload["x"]) ?? 0,
            y: Self.number(rectPayload["y"]) ?? 0,
            width: Self.number(rectPayload["width"]) ?? 0,
            height: Self.number(rectPayload["height"]) ?? 0
        )
    }

    private static func number(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return nil
    }
}

nonisolated private struct BrowserXRayNode: Identifiable {
    let id: String
    let tag: String
    let role: String
    let label: String
    let tone: String
    let rect: CGRect

    init?(payload: [String: Any]) {
        guard let id = payload["id"] as? String,
              let rectPayload = payload["rect"] as? [String: Any]
        else {
            return nil
        }

        self.id = id
        tag = payload["tag"] as? String ?? "node"
        role = payload["role"] as? String ?? tag
        label = payload["label"] as? String ?? tag
        tone = payload["tone"] as? String ?? "structure"
        rect = CGRect(
            x: Self.number(rectPayload["x"]) ?? 0,
            y: Self.number(rectPayload["y"]) ?? 0,
            width: Self.number(rectPayload["width"]) ?? 0,
            height: Self.number(rectPayload["height"]) ?? 0
        )
    }

    private static func number(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return nil
    }
}

private struct XRayDOMTreeRail: View {
    let telemetry: BrowserXRayTelemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DOM TREE")
                    .font(.system(size: 19, weight: .black, design: .monospaced))
                    .foregroundStyle(XRayTheme.ink)
                Text("hover expands the branch under the pointer")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(XRayTheme.muted)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 0) {
                if telemetry.hoverPath.isEmpty {
                    treeLine(depth: 0, text: "<html>", isActive: false)
                    treeLine(depth: 1, text: "<body>", isActive: false)
                    treeLine(depth: 2, text: "<move cursor over page>", isActive: true)
                } else {
                    ForEach(Array(telemetry.hoverPath.enumerated()), id: \.element.id) { index, node in
                        treeNode(node, depth: index, isLeaf: index == telemetry.hoverPath.count - 1)
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("VISIBLE NODES")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(XRayTheme.faint)

                ForEach(telemetry.nodes.prefix(12)) { node in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(nodeColor(node.tone))
                            .frame(width: 5, height: 5)
                        Text("<\(node.tag)>")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(XRayTheme.ink.opacity(0.86))
                            .frame(width: 68, alignment: .leading)
                        Text(node.label)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(XRayTheme.muted)
                            .lineLimit(1)
                    }
                    .frame(height: 18)
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity)
        .background(XRayDarkGridBackground())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(XRayTheme.grid.opacity(0.24))
                .frame(width: 1)
        }
    }

    private func treeNode(_ node: BrowserXRayHoverNode, depth: Int, isLeaf: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            treeLine(depth: min(depth, 7), text: "<\(node.tag)> \(wrappableSelector(node.selector))", isActive: isLeaf)
            if isLeaf {
                Text(node.label.isEmpty ? node.role : node.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(XRayTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, CGFloat(min(depth, 7)) * 14 + 14)
                    .padding(.bottom, 5)
            }
        }
    }

    private func treeLine(depth: Int, text: String, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Color.clear
                .frame(width: CGFloat(depth) * 13, height: 1)
            Text(isActive ? ">" : "|")
                .frame(width: 8, alignment: .center)
            Text(text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: isActive ? .black : .semibold, design: .monospaced))
        .foregroundStyle(isActive ? XRayTheme.accent : XRayTheme.muted)
        .padding(.vertical, 3)
        .padding(.horizontal, isActive ? 7 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Rectangle()
                .fill(isActive ? XRayTheme.accent.opacity(0.10) : Color.clear)
        )
    }

    private func nodeColor(_ tone: String) -> Color {
        switch tone {
        case "action":
            return XRayTheme.accent
        case "semantic":
            return XRayTheme.warm
        case "signal":
            return Color(red: 0.56, green: 0.90, blue: 0.52)
        default:
            return XRayTheme.faint
        }
    }

    private func wrappableSelector(_ selector: String) -> String {
        selector
            .replacingOccurrences(of: "#", with: " #")
            .replacingOccurrences(of: ".", with: ". ")
            .replacingOccurrences(of: "[", with: " [")
            .replacingOccurrences(of: "]", with: "] ")
    }
}

private struct XRayStatsRail: View {
    let telemetry: BrowserXRayTelemetry
    let title: String
    let url: URL?
    let requests: [XHRRequestRecord]
    let warnings: [ConsoleMessageRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PAGE SIGNALS")
                    .font(.system(size: 19, weight: .black, design: .monospaced))
                    .foregroundStyle(XRayTheme.ink)

                Text(url?.host ?? "NO PAGE LOCK")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(XRayTheme.accent.opacity(0.82))
                    .lineLimit(1)

                Text(title.isEmpty ? "Waiting for document signal" : title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(XRayTheme.muted)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                XRayStat(value: telemetry.elementCount, label: "DOM")
                XRayStat(value: telemetry.clickableCount, label: "ACTIONS")
                XRayStat(value: telemetry.domDepth, label: "DEPTH")
            }

            VStack(alignment: .leading, spacing: 9) {
                XRaySignalBar(label: "interactive", value: telemetry.clickableCount, maxValue: max(telemetry.elementCount, 1))
                XRaySignalBar(label: "forms", value: telemetry.formControlCount, maxValue: max(telemetry.clickableCount, 1))
                XRaySignalBar(label: "links", value: telemetry.linkCount, maxValue: max(telemetry.clickableCount, 1))
                XRaySignalBar(label: "headings", value: telemetry.headingCount, maxValue: max(telemetry.elementCount / 8, 1))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("XHR REQUESTS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(XRayTheme.faint)

                if requests.isEmpty {
                    Text("no fetch/xhr captured")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(XRayTheme.muted)
                } else {
                    ForEach(requests, id: \.id) { request in
                        XRayRequestRow(request: request)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("CONSOLE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(XRayTheme.faint)

                if warnings.isEmpty {
                    Text("no warnings")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(XRayTheme.muted)
                } else {
                    ForEach(warnings, id: \.id) { warning in
                        Text("\(warning.level.uppercased()) \(warning.message)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(XRayTheme.warm.opacity(0.92))
                            .lineLimit(2)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxHeight: .infinity)
        .background(XRayDarkGridBackground())
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(XRayTheme.grid.opacity(0.24))
                .frame(width: 1)
        }
    }
}

private struct XRayPlainPageHeader: View {
    let host: String
    let hoverPath: [BrowserXRayHoverNode]

    var body: some View {
        HStack(spacing: 10) {
            Text("HTML")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Rectangle().fill(XRayTheme.accent))

            Text(host)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(XRayTheme.ink.opacity(0.78))
                .lineLimit(1)

            Spacer()

            Text(hoverPath.last.map { "<\($0.tag)> \($0.selector)" } ?? "hover page")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(XRayTheme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(XRayTheme.panel.opacity(0.86))
        .overlay(Rectangle().stroke(XRayTheme.grid.opacity(0.22), lineWidth: 1))
    }
}

private struct XRaySignalRail: View {
    let requests: [XHRRequestRecord]
    let warnings: [ConsoleMessageRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("NETWORK WAKE")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.green)
                Spacer()
                Text("\(requests.count) LIVE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.64))
            }

            VStack(alignment: .leading, spacing: 9) {
                if requests.isEmpty {
                    Text("No XHR/fetch signals captured on this page yet.")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.58))
                } else {
                    ForEach(requests, id: \.id) { request in
                        XRayRequestRow(request: request)
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.16))

            HStack {
                Text("CONSOLE HEAT")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.orange)
                Spacer()
                Text("\(warnings.count) FLAGS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.64))
            }

            if warnings.isEmpty {
                Text("No warnings or errors in the current capture window.")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                ForEach(warnings, id: \.id) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Text(warning.level.uppercased())
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(warning.level.lowercased() == "error" ? Color.red : Color.orange)
                            .frame(width: 44, alignment: .leading)
                        Text(warning.message)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(14)
        .background(XRayPanelBackground())
    }
}

private struct XRayCausalTrace: View {
    let requests: [XHRRequestRecord]

    var body: some View {
        HStack(spacing: 12) {
            traceStep("01", "OBSERVE", "viewport mapped", .cyan)
            traceStep("02", "RESOLVE", "refs classified", .pink)
            traceStep("03", "ACT", "click path armed", .green)
            traceStep("04", "XHR", latestRequestTitle, .orange)
            traceStep("05", "DIFF", "visual delta pending", .white)
        }
        .padding(12)
        .background(XRayPanelBackground())
    }

    private var latestRequestTitle: String {
        guard let request = requests.first else { return "no network pulse" }
        let path = URL(string: request.url)?.path ?? request.url
        return path.isEmpty ? request.method : "\(request.method) \(path)"
    }

    private func traceStep(_ number: String, _ title: String, _ detail: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(Circle().fill(color.opacity(0.88)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct XRayRequestRow: View {
    let request: XHRRequestRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(request.method)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(Rectangle().fill(statusColor.opacity(0.92)))

                Text(path)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(XRayTheme.ink.opacity(0.84))
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(statusText)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 8) {
                Text(byteText)
                Text(request.jsonShape ?? request.jsonType ?? "opaque response")
                    .lineLimit(1)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(XRayTheme.muted)
        }
    }

    private var path: String {
        let url = URL(string: request.url)
        let path = url?.path ?? request.url
        let query = url?.query.map { "?\($0)" } ?? ""
        let value = "\(path)\(query)"
        return value.isEmpty ? request.url : value
    }

    private var statusText: String {
        request.status.map(String.init) ?? "OPEN"
    }

    private var statusColor: Color {
        guard let status = request.status else { return XRayTheme.grid }
        if status >= 500 { return XRayTheme.bad }
        if status >= 400 { return XRayTheme.warm }
        if status >= 300 { return Color(red: 0.82, green: 0.66, blue: 1.0) }
        return XRayTheme.accent
    }

    private var byteText: String {
        guard let bytes = request.responseBytes else { return "streaming" }
        if bytes > 999_999 {
            return String(format: "%.1fMB", Double(bytes) / 1_000_000)
        }
        if bytes > 999 {
            return String(format: "%.1fKB", Double(bytes) / 1_000)
        }
        return "\(bytes)B"
    }
}

private struct XRayNodeFrame: View {
    let node: BrowserXRayNode
    let showLabel: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color.opacity(node.tone == "action" ? 0.045 : 0.018))
                .overlay(
                    Rectangle()
                        .stroke(color.opacity(node.tone == "action" ? 0.54 : 0.28), lineWidth: node.tone == "action" ? 1 : 0.6)
                )

            Rectangle()
                .fill(color)
                .frame(width: 14, height: 1)

            Rectangle()
                .fill(color)
                .frame(width: 1, height: 14)

            if showLabel {
                Text("\(node.id) \(node.role) \"\(node.label)\"")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(XRayTheme.accent.opacity(0.94))
                    .offset(x: 0, y: -18)
            }
        }
    }

    private var color: Color {
        switch node.tone {
        case "action":
            return XRayTheme.accent.opacity(0.76)
        case "semantic":
            return XRayTheme.warm.opacity(0.60)
        case "signal":
            return Color(red: 0.72, green: 0.96, blue: 0.66).opacity(0.58)
        default:
            return XRayTheme.grid.opacity(0.38)
        }
    }
}

private struct XRayHoverPathFrame: View {
    let node: BrowserXRayHoverNode

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .background(XRayTheme.accent.opacity(0.045))
            .overlay(Rectangle().stroke(XRayTheme.accent.opacity(0.92), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
            .overlay(alignment: .topLeading) {
                Text("<\(node.tag)>")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(XRayTheme.accent)
                    .offset(y: -18)
            }
    }
}

private struct XRayStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundStyle(XRayTheme.ink)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(XRayTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct XRaySignalBar: View {
    let label: String
    let value: Int
    let maxValue: Int
    let color: Color

    init(label: String, value: Int, maxValue: Int, color: Color = XRayTheme.accent) {
        self.label = label
        self.value = value
        self.maxValue = maxValue
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label.uppercased())
                Spacer()
                Text("\(value)")
            }
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundStyle(XRayTheme.muted)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                    Rectangle()
                        .fill(color.opacity(0.72))
                        .frame(width: proxy.size.width * min(CGFloat(value) / CGFloat(max(maxValue, 1)), 1))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct XRayPanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(XRayTheme.panel.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [XRayTheme.grid.opacity(0.55), .white.opacity(0.10), XRayTheme.accent.opacity(0.32)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.30), radius: 16, y: 10)
    }
}

private struct XRayCenterSurface: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.065)
            LinearGradient(
                colors: [
                    XRayTheme.panel.opacity(0.08),
                    Color.clear,
                    XRayTheme.panel.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct XRayDarkGridBackground: View {
    var body: some View {
        ZStack {
            XRayTheme.panel
            LinearGradient(
                colors: [
                    XRayTheme.panelRaised.opacity(0.92),
                    XRayTheme.panel.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            XRayGrid(spacing: 28)
                .stroke(XRayTheme.grid.opacity(0.09), lineWidth: 1)
        }
    }
}

private struct XRayGrid: Shape {
    let spacing: CGFloat

    init(spacing: CGFloat = 36) {
        self.spacing = spacing
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }

        return path
    }
}

private struct XRaySweep: View {
    let offset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .cyan.opacity(0.0), .cyan.opacity(0.36), .white.opacity(0.16), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 120)
                .offset(y: proxy.size.height * offset)
        }
    }
}
