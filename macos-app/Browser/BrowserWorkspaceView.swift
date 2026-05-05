//
//  BrowserWorkspaceView.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import SwiftUI
import WebKit

extension ContentView {
    var browserWorkspace: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                browserContent
                    .frame(width: isBotPanelVisible ? proxy.size.width * 0.75 : proxy.size.width)

                if isBotPanelVisible {
                    BotTerminalPanel(terminal: browser.botTerminal)
                        .frame(width: proxy.size.width * 0.25)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeInOut(duration: 0.18), value: isBotPanelVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var browserContent: some View {
        ZStack {
            Color(nsColor: browser.viewportMode == .desktop ? .textBackgroundColor : .windowBackgroundColor)

            ZStack {
                BrowserWebViewStack(
                    tabs: browser.tabStates,
                    activeTabID: browser.activeTabID,
                    blocksProgrammaticFocus: isAddressFocused
                )

                if !browser.hasAttemptedNavigation {
                    EmptyBrowserState()
                }

                if let errorMessage = browser.errorMessage {
                    BrowserErrorState(message: errorMessage) {
                        browser.reload()
                    }
                }
            }
            .frame(width: browser.viewportMode.width)
            .frame(
                maxWidth: browser.viewportMode == .desktop ? .infinity : nil,
                maxHeight: .infinity
            )
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var viewportControls: some View {
        HStack(spacing: 1) {
            ForEach(BrowserViewportMode.allCases) { mode in
                Button {
                    browser.setViewportMode(mode)
                } label: {
                    Image(systemName: mode.systemName)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(browser.viewportMode == mode ? Color.accentColor : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(browser.viewportMode == mode ? Color.accentColor.opacity(0.14) : Color.clear)
                )
                .accessibilityLabel(mode.accessibilityLabel)
                .help(mode.helpText)
            }
        }
    }

    var botControls: some View {
        HStack(spacing: 1) {
            Button {
                if isBotPanelVisible {
                    isBotPanelVisible = false
                    browser.closeBotTerminal()
                } else {
                    isBotPanelVisible = true
                    browser.requestLLMSSummary()
                }
            } label: {
                Image(systemName: "memorychip")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isBotPanelVisible ? Color.accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isBotPanelVisible ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .accessibilityLabel("Bot panel")
            .help("Bot panel")
        }
    }

    var progressBar: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 1)

            if browser.isLoading {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: max(24, proxy.size.width * browser.estimatedProgress), height: 2)
                        .animation(.easeOut(duration: 0.18), value: browser.estimatedProgress)
                }
                .frame(height: 2)
                .transition(.opacity)
            }
        }
        .frame(height: 2)
    }
}

struct BrowserToolbarButton: View {
    let systemName: String
    let accessibilityLabel: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? .tertiary : .primary)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
