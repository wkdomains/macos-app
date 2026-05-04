//
//  BrowserLoginScripts.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static func loginCaptureScript(targetsJSON: String) -> String {
        """
        (() => {
          const targets = \(targetsJSON);
          window.__wkdomainsLoginCapture = targets;

          const escapeCSS = (value) => {
            if (window.CSS && CSS.escape) return CSS.escape(value);
            return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\\\$&");
          };

          const controlsIn = (root) => Array.from((root || document).querySelectorAll("input, textarea, select"));
          const fieldMatches = (field, target) => {
            if (!field || !target) return false;
            const tag = field.tagName ? field.tagName.toLowerCase() : null;
            const type = field.getAttribute ? field.getAttribute("type") : null;
            const name = field.getAttribute ? field.getAttribute("name") : null;
            if (target.tag && tag !== target.tag) return false;
            if (target.name && name !== target.name) return false;
            if (target.type && type !== target.type) return false;
            return true;
          };

          const findBySelector = (target) => {
            if (!target.cssPath) return null;
            try {
              const field = document.querySelector(target.cssPath);
              return fieldMatches(field, target) ? field : null;
            } catch (_) {
              return null;
            }
          };

          const findByID = (target) => {
            if (!target.id) return null;
            const matches = document.querySelectorAll(`#${escapeCSS(target.id)}`);
            if (matches.length !== 1) return null;
            return fieldMatches(matches[0], target) ? matches[0] : null;
          };

          const findByFormPosition = (target) => {
            if (target.formIndex === null || target.formIndex === undefined) return null;
            if (target.fieldIndex === null || target.fieldIndex === undefined) return null;
            const form = document.querySelectorAll("form")[target.formIndex];
            if (!form) return null;
            const field = controlsIn(form)[target.fieldIndex];
            return fieldMatches(field, target) ? field : null;
          };

          const findByName = (target) => {
            if (!target.name) return null;
            const selector = `[name="${escapeCSS(target.name)}"]`;
            const root = target.formIndex === null || target.formIndex === undefined
              ? document
              : document.querySelectorAll("form")[target.formIndex] || document;
            const matches = Array.from(root.querySelectorAll(selector));
            return matches.find((field) => fieldMatches(field, target)) || null;
          };

          const findByGlobalPosition = (target) => {
            if (target.fieldIndex === null || target.fieldIndex === undefined) return null;
            const field = controlsIn(document)[target.fieldIndex];
            return fieldMatches(field, target) ? field : null;
          };

          const findField = (target) => (
            findBySelector(target)
              || findByID(target)
              || findByFormPosition(target)
              || findByName(target)
              || findByGlobalPosition(target)
          );

          const capture = () => {
            const currentTargets = window.__wkdomainsLoginCapture;
            if (!currentTargets) return;

            const usernameField = findField(currentTargets.usernameTarget);
            const passwordField = findField(currentTargets.passwordTarget);
            const username = usernameField ? usernameField.value || "" : "";
            const password = passwordField ? passwordField.value || "" : "";
            if (!username.trim() || !password) return;

            window.webkit.messageHandlers.wkdomainsLogin.postMessage({
              pageURL: location.href,
              username,
              password
            });
          };

          if (!window.__wkdomainsLoginCaptureInstalled) {
            window.__wkdomainsLoginCaptureInstalled = true;
            document.addEventListener("submit", capture, true);
            document.addEventListener("click", (event) => {
              const element = event.target && event.target.closest
                ? event.target.closest("button, input[type='submit'], input[type='button']")
                : null;
              if (element) capture();
            }, true);
            document.addEventListener("keydown", (event) => {
              if (event.key === "Enter") capture();
            }, true);
            window.addEventListener("beforeunload", capture);
          }

          capture();
          return true;
        })()
        """
    }

    static func loginFillScript(entryJSON: String) -> String {
        """
        (() => {
          const entry = \(entryJSON);
          const escapeCSS = (value) => {
            if (window.CSS && CSS.escape) return CSS.escape(value);
            return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\\\$&");
          };

          const controlsIn = (root) => Array.from((root || document).querySelectorAll("input, textarea, select"));
          const fieldMatches = (field, target) => {
            if (!field || !target) return false;
            const tag = field.tagName ? field.tagName.toLowerCase() : null;
            const type = field.getAttribute ? field.getAttribute("type") : null;
            const name = field.getAttribute ? field.getAttribute("name") : null;
            if (target.tag && tag !== target.tag) return false;
            if (target.name && name !== target.name) return false;
            if (target.type && type !== target.type) return false;
            return true;
          };

          const findBySelector = (target) => {
            if (!target.cssPath) return null;
            try {
              const field = document.querySelector(target.cssPath);
              return fieldMatches(field, target) ? field : null;
            } catch (_) {
              return null;
            }
          };

          const findByID = (target) => {
            if (!target.id) return null;
            const matches = document.querySelectorAll(`#${escapeCSS(target.id)}`);
            if (matches.length !== 1) return null;
            return fieldMatches(matches[0], target) ? matches[0] : null;
          };

          const findByFormPosition = (target) => {
            if (target.formIndex === null || target.formIndex === undefined) return null;
            if (target.fieldIndex === null || target.fieldIndex === undefined) return null;
            const form = document.querySelectorAll("form")[target.formIndex];
            if (!form) return null;
            const field = controlsIn(form)[target.fieldIndex];
            return fieldMatches(field, target) ? field : null;
          };

          const findByName = (target) => {
            if (!target.name) return null;
            const selector = `[name="${escapeCSS(target.name)}"]`;
            const root = target.formIndex === null || target.formIndex === undefined
              ? document
              : document.querySelectorAll("form")[target.formIndex] || document;
            const matches = Array.from(root.querySelectorAll(selector));
            return matches.find((field) => fieldMatches(field, target)) || null;
          };

          const findByGlobalPosition = (target) => {
            if (target.fieldIndex === null || target.fieldIndex === undefined) return null;
            const field = controlsIn(document)[target.fieldIndex];
            return fieldMatches(field, target) ? field : null;
          };

          const findField = (target) => (
            findBySelector(target)
              || findByID(target)
              || findByFormPosition(target)
              || findByName(target)
              || findByGlobalPosition(target)
          );

          const setValue = (field, value) => {
            if (!field) return false;
            field.focus({ preventScroll: true });

            const prototype = field instanceof HTMLInputElement
              ? HTMLInputElement.prototype
              : field instanceof HTMLTextAreaElement
                ? HTMLTextAreaElement.prototype
                : field instanceof HTMLSelectElement
                  ? HTMLSelectElement.prototype
                  : null;
            const valueSetter = prototype
              ? Object.getOwnPropertyDescriptor(prototype, "value")?.set
              : null;

            if (valueSetter) {
              valueSetter.call(field, value);
            } else {
              field.value = value;
            }

            field.dispatchEvent(new InputEvent("input", {
              bubbles: true,
              inputType: "insertReplacementText",
              data: value
            }));
            field.dispatchEvent(new Event("change", { bubbles: true }));
            return true;
          };

          const usernameField = findField(entry.usernameTarget);
          const passwordField = findField(entry.passwordTarget);
          let filled = 0;
          if (setValue(usernameField, entry.username)) filled += 1;
          if (setValue(passwordField, entry.password)) filled += 1;
          return filled;
        })()
        """
    }
}
