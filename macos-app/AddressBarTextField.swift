//
//  AddressBarTextField.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import AppKit
import SwiftUI

struct AddressBarTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var selectAllOnFocus: Bool

    let placeholder: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onMoveSelection: (Int) -> Bool
    let onAcceptCompletion: () -> Bool
    let shouldPreserveFocus: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> BrowserAddressNSTextField {
        let textField = BrowserAddressNSTextField()
        textField.delegate = context.coordinator
        textField.onKeyDown = { event in
            context.coordinator.handleKeyDown(event)
        }
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.sendsActionOnEndEditing = false

        return textField
    }

    func updateNSView(_ nsView: BrowserAddressNSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.placeholderString = placeholder

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        guard isFocused else { return }

        DispatchQueue.main.async {
            guard nsView.window != nil,
                  nsView.window?.firstResponder !== nsView.currentEditor()
            else {
                context.coordinator.selectAllIfNeeded(in: nsView)
                return
            }

            nsView.window?.makeFirstResponder(nsView)
            context.coordinator.selectAllIfNeeded(in: nsView)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressBarTextField

        init(_ parent: AddressBarTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.selectAllOnFocus = true
            }

            parent.isFocused = true

            if let textField = notification.object as? BrowserAddressNSTextField {
                DispatchQueue.main.async {
                    self.selectAllIfNeeded(in: textField)
                }
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }

            parent.selectAllOnFocus = false
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.shouldPreserveFocus(),
               let textField = notification.object as? BrowserAddressNSTextField
            {
                parent.isFocused = true

                DispatchQueue.main.async {
                    guard self.parent.shouldPreserveFocus() else {
                        self.parent.isFocused = false
                        return
                    }

                    textField.window?.makeFirstResponder(textField)
                }
                return
            }

            parent.isFocused = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.moveDown(_:)):
                return parent.onMoveSelection(1)
            case #selector(NSResponder.moveUp(_:)):
                return parent.onMoveSelection(-1)
            case #selector(NSResponder.moveRight(_:)),
                 #selector(NSResponder.insertTab(_:)):
                return parent.onAcceptCompletion()
            default:
                return false
            }
        }

        func selectAllIfNeeded(in textField: BrowserAddressNSTextField) {
            guard parent.selectAllOnFocus,
                  let editor = textField.currentEditor()
            else {
                return
            }

            parent.selectAllOnFocus = false
            editor.selectAll(nil)
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifierFlags.contains(.command) || modifierFlags.contains(.control) || modifierFlags.contains(.option) {
                return false
            }

            switch event.keyCode {
            case 36, 76:
                parent.onSubmit()
                return true
            case 48:
                if !modifierFlags.contains(.shift), parent.onAcceptCompletion() {
                    return true
                }

                return false
            case 53:
                parent.onCancel()
                return true
            case 124:
                return parent.onAcceptCompletion()
            case 125:
                return parent.onMoveSelection(1)
            case 126:
                return parent.onMoveSelection(-1)
            default:
                return false
            }
        }
    }
}

final class BrowserAddressNSTextField: NSTextField {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}
