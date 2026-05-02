//
//  ContentView.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var browser: BrowserModel
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar
            progressBar

            ZStack {
                BrowserWebView(webView: browser.webView)
                    .opacity(browser.hasAttemptedNavigation ? 1 : 0)

                if !browser.hasAttemptedNavigation {
                    EmptyBrowserState()
                }

                if let errorMessage = browser.errorMessage {
                    BrowserErrorState(message: errorMessage) {
                        browser.reload()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            isAddressFocused = true
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
            BrowserToolbarButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                isDisabled: !browser.canGoBack
            ) {
                browser.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)

            BrowserToolbarButton(
                systemName: "chevron.right",
                accessibilityLabel: "Forward",
                isDisabled: !browser.canGoForward
            ) {
                browser.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)

            BrowserToolbarButton(
                systemName: browser.isLoading ? "xmark" : "arrow.clockwise",
                accessibilityLabel: browser.isLoading ? "Stop loading" : "Reload",
                isDisabled: !browser.hasAttemptedNavigation && !browser.isLoading
            ) {
                browser.isLoading ? browser.stopLoading() : browser.reload()
            }
            .keyboardShortcut("r", modifiers: .command)

            HStack(spacing: 8) {
                Image(systemName: browser.isSecurePage ? "lock.fill" : "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(browser.isSecurePage ? .green : .secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                TextField("Enter a website", text: $browser.addressText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .disableAutocorrection(true)
                    .focused($isAddressFocused)
                    .onSubmit {
                        browser.loadCurrentAddress()
                    }
                    .accessibilityLabel("Website address")

                if !browser.addressText.isEmpty {
                    Button {
                        browser.addressText = ""
                        isAddressFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear address")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isAddressFocused ? Color.accentColor.opacity(0.75) : Color(nsColor: .separatorColor).opacity(0.55),
                        lineWidth: isAddressFocused ? 1.5 : 1
                    )
            )

            Button {
                browser.loadCurrentAddress()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(browser.addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Go")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var progressBar: some View {
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

private struct BrowserToolbarButton: View {
    let systemName: String
    let accessibilityLabel: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? .tertiary : .primary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isDisabled ? 0.45 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    ContentView(browser: BrowserModel())
}
