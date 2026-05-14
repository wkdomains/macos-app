//
//  BrowserTabStripItemView.swift
//  macos-app
//

import AppKit
import SwiftUI

struct BrowserTabStripItemView: View {
    let item: BrowserTabItem
    let favicon: NSImage?
    let width: CGFloat
    let height: CGFloat
    let close: () -> Void

    @State private var isHovering = false
    @State private var isCloseHovering = false

    var body: some View {
        ZStack {
            tabBackground

            if item.isPinned {
                faviconView
            } else {
                HStack(spacing: 9) {
                    faviconView

                    Text(title)
                        .font(.system(size: 13, weight: item.isActive ? .semibold : .medium))
                        .foregroundStyle(item.isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    closeButton
                }
                .padding(.leading, 13)
                .padding(.trailing, 9)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var title: String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        return item.url?.host ?? "New Tab"
    }

    private var tabBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(item.isActive ? selectedTabBackground : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(item.isActive ? Color.white.opacity(0.04) : Color.clear, lineWidth: 1)
            }
    }

    private var selectedTabBackground: Color {
        Color(
            red: 91 / 255,
            green: 89 / 255,
            blue: 102 / 255
        )
    }

    private var faviconView: some View {
        Group {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else if item.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.64)
            } else if let image = NSImage(named: NSImage.Name("AppIcon")) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(closeButtonForeground)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(item.isActive || isHovering ? 1 : 0.64)
        .background(
            Circle()
                .fill(isCloseHovering ? Color.white.opacity(0.10) : Color.clear)
        )
        .onHover { isCloseHovering = $0 }
        .accessibilityLabel("Close tab")
        .help("Close Tab")
    }

    private var closeButtonForeground: Color {
        item.isActive || isHovering ? .primary : .secondary
    }
}
