//
//  BotTerminalPanel.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import SwiftUI

struct BotTerminalPanel: View {
    @ObservedObject var terminal: BotTerminalModel
    @State private var promptText = ""
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 0) {
                ScrollViewReader { reader in
                    ScrollView {
                        Text(terminal.message)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.44, green: 1.0, blue: 0.52))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(16)
                            .id("terminal-end")
                    }
                    .onChange(of: terminal.message) { _, _ in
                        withAnimation(.easeOut(duration: 0.12)) {
                            reader.scrollTo("terminal-end", anchor: .bottom)
                        }
                    }
                }

                if terminal.isInputReady {
                    HStack(spacing: 8) {
                        Text(">")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.44, green: 1.0, blue: 0.52))

                        TextField("Ask about this page", text: $promptText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.44, green: 1.0, blue: 0.52))
                            .focused($isPromptFocused)
                            .onSubmit {
                                submitPrompt()
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color(red: 0.44, green: 1.0, blue: 0.52).opacity(0.25))
                            .frame(height: 1)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onChange(of: terminal.isInputReady) { _, isReady in
            guard isReady else { return }

            DispatchQueue.main.async {
                isPromptFocused = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(terminal.message)
    }

    private func submitPrompt() {
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        terminal.submitHumanMessage(trimmedPrompt)
        promptText = ""
        isPromptFocused = true
    }
}
