import AppKit
import ApplicationServices
import Foundation

struct FocusedTextContext {
    let query: String
    let queryFrame: CGRect?
    let windowFrame: CGRect?
}

enum AccessibilityBridge {
    nonisolated(unsafe) private static var lastProbeSummary: String?

    static func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func focusedSpotlightTextContext() -> FocusedTextContext? {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight")
        guard let application = applications.first else {
            reportProbe("spotlight app not running")
            return nil
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let windowsResult = copyElementsAttributeResult(kAXWindowsAttribute as CFString, from: appElement)

        guard let windows = windowsResult.elements else {
            reportProbe("spotlight pid \(application.processIdentifier) windows read failed: \(windowsResult.error.rawValue)")
            return nil
        }

        guard windows.isEmpty == false else {
            reportProbe("spotlight pid \(application.processIdentifier) has 0 windows")
            return nil
        }

        let windowTitles = windows.map { copyStringAttribute(kAXTitleAttribute as CFString, from: $0) ?? "<untitled>" }
        guard let spotlightWindow = copySpotlightWindow(from: windows) else {
            reportProbe("spotlight windows present but no matching window: \(windowTitles.joined(separator: ", "))")
            return nil
        }

        let windowTitle = copyStringAttribute(kAXTitleAttribute as CFString, from: spotlightWindow) ?? "<untitled>"
        guard let queryField = copyQueryField(from: spotlightWindow) else {
            let childRoles = copyElementsAttribute(kAXChildrenAttribute as CFString, from: spotlightWindow)
                .compactMap { copyStringAttribute(kAXRoleAttribute as CFString, from: $0) }
            reportProbe("spotlight window '\(windowTitle)' has no query field; child roles: \(childRoles.joined(separator: ", "))")
            return nil
        }

        guard let role = copyStringAttribute(kAXRoleAttribute as CFString, from: queryField) else {
            reportProbe("spotlight window '\(windowTitle)' query field missing role")
            return nil
        }

        guard ["AXSearchField", "AXTextField", "AXTextArea", "AXComboBox"].contains(role) else {
            reportProbe("spotlight window '\(windowTitle)' unsupported query field role: \(role)")
            return nil
        }

        guard let value = copyStringAttribute(kAXValueAttribute as CFString, from: queryField) else {
            let placeholder = copyStringAttribute(kAXPlaceholderValueAttribute as CFString, from: queryField) ?? "<nil>"
            reportProbe("spotlight window '\(windowTitle)' query field missing value; placeholder: \(placeholder)")
            return nil
        }

        reportProbe("spotlight window '\(windowTitle)' ready with role \(role)")
        return FocusedTextContext(
            query: value,
            queryFrame: copyFrame(from: queryField),
            windowFrame: copyFrame(from: spotlightWindow)
        )
    }

    private static func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        guard let value = copyAttribute(attribute, from: element) else {
            return nil
        }
        return value as? String
    }

    private static func copyElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(attribute, from: element) else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func copyElementsAttribute(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
        copyElementsAttributeResult(attribute, from: element).elements ?? []
    }

    private static func copyElementsAttributeResult(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> (elements: [AXUIElement]?, error: AXError) {
        guard let value = copyAttribute(attribute, from: element) else {
            let error = copyAttributeError(attribute, from: element)
            return (nil, error)
        }

        let elements = (value as? [AnyObject])?.map { candidate in
            unsafeDowncast(candidate, to: AXUIElement.self)
        } ?? []
        return (elements, .success)
    }

    private static func copyAttribute(_ attribute: CFString, from element: AXUIElement) -> AnyObject? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &rawValue)
        guard result == .success, let rawValue else {
            return nil
        }
        return rawValue
    }

    private static func copyAttributeError(_ attribute: CFString, from element: AXUIElement) -> AXError {
        var rawValue: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute, &rawValue)
    }

    private static func copyFrame(from element: AXUIElement) -> CGRect? {
        guard
            let positionValue = copyAXValueAttribute(kAXPositionAttribute as CFString, from: element),
            let sizeValue = copyAXValueAttribute(kAXSizeAttribute as CFString, from: element)
        else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetType(positionValue) == .cgPoint,
            AXValueGetValue(positionValue, .cgPoint, &origin),
            AXValueGetType(sizeValue) == .cgSize,
            AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    private static func copyAXValueAttribute(_ attribute: CFString, from element: AXUIElement) -> AXValue? {
        guard let value = copyAttribute(attribute, from: element) else {
            return nil
        }
        return unsafeDowncast(value, to: AXValue.self)
    }

    private static func copySpotlightWindow(from windows: [AXUIElement]) -> AXUIElement? {
        return windows.first { window in
            guard let title = copyStringAttribute(kAXTitleAttribute as CFString, from: window) else {
                return false
            }

            return title == "聚焦" || title.localizedCaseInsensitiveContains("spotlight")
        } ?? windows.first
    }

    private static func copyQueryField(from window: AXUIElement) -> AXUIElement? {
        let directChildren = copyElementsAttribute(kAXChildrenAttribute as CFString, from: window)
        if let directField = directChildren.first(where: isQueryField) {
            return directField
        }

        return firstDescendant(in: window, matching: isQueryField)
    }

    private static func firstDescendant(
        in element: AXUIElement,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        for child in copyElementsAttribute(kAXChildrenAttribute as CFString, from: element) {
            if predicate(child) {
                return child
            }

            if let nestedMatch = firstDescendant(in: child, matching: predicate) {
                return nestedMatch
            }
        }

        return nil
    }

    private static func isQueryField(_ element: AXUIElement) -> Bool {
        guard let role = copyStringAttribute(kAXRoleAttribute as CFString, from: element) else {
            return false
        }

        guard ["AXSearchField", "AXTextField", "AXTextArea", "AXComboBox"].contains(role) else {
            return false
        }

        let directValue = copyStringAttribute(kAXValueAttribute as CFString, from: element)
        let placeholder = copyStringAttribute(kAXPlaceholderValueAttribute as CFString, from: element)
        let description = copyStringAttribute(kAXDescriptionAttribute as CFString, from: element)
        let title = copyStringAttribute(kAXTitleAttribute as CFString, from: element)

        return directValue != nil
            || placeholder == "聚焦搜索"
            || description == "聚焦搜索"
            || title == "聚焦搜索"
    }

    private static func reportProbe(_ message: String) {
        guard message != lastProbeSummary else {
            return
        }

        lastProbeSummary = message
        DebugLog.write("ax: \(message)")
    }
}
