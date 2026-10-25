import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// 聚合 Spotlight 输入框文本和几何信息，供浮层定位与翻译触发复用。
struct FocusedTextContext {
    let query: String
    let queryFrame: CGRect?
    let windowFrame: CGRect?
}

enum AccessibilityBridge {
    private struct SpotlightHost {
        let application: NSRunningApplication
        let bundleIdentifier: String
    }

    // 只记录探测结果的变化，避免轮询日志刷屏。
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
        let hosts = runningSpotlightHosts()
        guard hosts.isEmpty == false else {
            reportProbe("no running Spotlight host; candidates: \(SpotlightAccessibilitySupport.hostBundleIdentifiers.joined(separator: ", "))")
            return nil
        }

        for host in hosts {
            if let context = focusedTextContext(for: host) {
                return context
            }
        }

        let hostDescriptions = hosts.map { "\($0.bundleIdentifier) pid \($0.application.processIdentifier)" }
        reportProbe("Spotlight host present but no active query field: \(hostDescriptions.joined(separator: ", "))")
        return nil
    }

    private static func runningSpotlightHosts() -> [SpotlightHost] {
        SpotlightAccessibilitySupport.hostBundleIdentifiers.flatMap { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map {
                SpotlightHost(application: $0, bundleIdentifier: bundleIdentifier)
            }
        }
    }

    private static func focusedTextContext(for host: SpotlightHost) -> FocusedTextContext? {
        let appElement = AXUIElementCreateApplication(host.application.processIdentifier)
        let isCampo = host.bundleIdentifier == "com.apple.campo"

        for root in candidateRoots(appElement: appElement, isCampo: isCampo) {
            if let context = textContext(from: root, host: host) {
                return context
            }
        }

        // 某些系统版本不把浮窗放进 AXWindows，但命中测试仍可取得浮窗内的元素。
        for root in popupHitTestRoots(processIdentifier: host.application.processIdentifier, isCampo: isCampo) {
            if let context = textContext(from: root, host: host) {
                return context
            }
        }

        return nil
    }

    private static func candidateRoots(appElement: AXUIElement, isCampo: Bool) -> [AXUIElement] {
        var roots: [AXUIElement] = []

        if let focusedElement = copyElementAttribute(kAXFocusedUIElementAttribute as CFString, from: appElement) {
            roots.append(focusedElement)
        }
        if let focusedWindow = copyElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement) {
            roots.append(focusedWindow)
        }
        roots.append(contentsOf: copyElementsAttribute(kAXWindowsAttribute as CFString, from: appElement))

        if isCampo {
            // Campo 的标准窗口是 Siri 聊天窗口。只允许浮窗及其搜索框进入候选集，避免误翻译聊天内容。
            roots = roots.filter { isCampoSpotlightRoot($0) }
        }

        return roots
    }

    private static func visiblePopupWindowFrames(processIdentifier: pid_t) -> [CGRect] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { window in
            guard
                (window[kCGWindowOwnerPID as String] as? Int) == Int(processIdentifier),
                (window[kCGWindowLayer as String] as? Int) ?? 0 > 0,
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let x = bounds["X"] as? CGFloat,
                let y = bounds["Y"] as? CGFloat,
                let width = bounds["Width"] as? CGFloat,
                let height = bounds["Height"] as? CGFloat
            else {
                return nil
            }

            let frame = CGRect(x: x, y: y, width: width, height: height)
            guard let displayBounds = displayBounds(containing: frame),
                  SpotlightAccessibilitySupport.isPlausibleSpotlightPopupFrame(frame, displayBounds: displayBounds)
            else {
                return nil
            }
            return frame
        }
    }

    private static func displayBounds(containing frame: CGRect) -> CGRect? {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return nil
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return nil
        }

        let bounds = displays.prefix(Int(displayCount)).map(CGDisplayBounds)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return bounds.first(where: { $0.contains(center) })
            ?? bounds.first(where: { $0.intersects(frame) })
    }

    private static func bestPopupWindowFrame(processIdentifier: pid_t, relativeTo queryFrame: CGRect?) -> CGRect? {
        let frames = visiblePopupWindowFrames(processIdentifier: processIdentifier)
        guard let queryFrame else {
            return frames.first
        }

        let queryCenter = CGPoint(x: queryFrame.midX, y: queryFrame.midY)
        return frames.first(where: { $0.contains(queryCenter) })
    }

    private static func popupHitTestRoots(processIdentifier: pid_t, isCampo: Bool) -> [AXUIElement] {
        let popupFrames = visiblePopupWindowFrames(processIdentifier: processIdentifier)
        let systemElement = AXUIElementCreateSystemWide()
        var roots: [AXUIElement] = []

        for frame in popupFrames {
            let probePoints = [
                CGPoint(x: frame.minX + 24, y: frame.minY + min(20, frame.height / 2)),
                CGPoint(x: frame.midX, y: frame.minY + min(20, frame.height / 2)),
                CGPoint(x: frame.maxX - 24, y: frame.minY + min(20, frame.height / 2)),
            ]

            for point in probePoints {
                var hitElement: AXUIElement?
                guard AXUIElementCopyElementAtPosition(systemElement, Float(point.x), Float(point.y), &hitElement) == .success,
                      let hitElement else {
                    continue
                }

                var pid: pid_t = 0
                guard AXUIElementGetPid(hitElement, &pid) == .success, pid == processIdentifier else {
                    continue
                }

                if let window = enclosingWindow(of: hitElement) {
                    if isCampo, isCampoSpotlightRoot(window) == false {
                        continue
                    }
                    roots.append(window)
                } else if isCampo == false {
                    roots.append(hitElement)
                }
            }
        }

        return roots
    }

    private static func textContext(from root: AXUIElement, host: SpotlightHost) -> FocusedTextContext? {
        let isCampo = host.bundleIdentifier == "com.apple.campo"
        guard let queryField = copyQueryField(from: root, requiresSearchSemantics: isCampo) else {
            return nil
        }

        let fieldRole = copyStringAttribute(kAXRoleAttribute as CFString, from: queryField) ?? "<nil>"
        let fieldIdentifier = copyStringAttribute(kAXIdentifierAttribute as CFString, from: queryField) ?? "<nil>"
        guard let value = copyStringAttribute(kAXValueAttribute as CFString, from: queryField) else {
            return nil
        }

        let fieldWindow = copyElementAttribute(kAXWindowAttribute as CFString, from: queryField)
            ?? enclosingWindow(of: queryField)
        let queryFrame = copyFrame(from: queryField)
        // SwiftUI 刷新搜索结果时可能短暂丢失 AXFrame，此时只接受包含输入框的可信浮窗。
        let axWindowFrame = fieldWindow
            .flatMap(copyFrame)
            .flatMap { frame -> CGRect? in
                guard let currentDisplayBounds = displayBounds(containing: frame),
                      SpotlightAccessibilitySupport.isPlausibleSpotlightPopupFrame(frame, displayBounds: currentDisplayBounds)
                else {
                    return nil
                }
                return frame
            }
        let windowFrame = axWindowFrame
            ?? bestPopupWindowFrame(processIdentifier: host.application.processIdentifier, relativeTo: queryFrame)
        guard queryFrame != nil || windowFrame != nil else {
            return nil
        }
        let windowTitle = fieldWindow.flatMap { copyStringAttribute(kAXTitleAttribute as CFString, from: $0) } ?? "<untitled>"

        reportProbe("\(host.bundleIdentifier) pid \(host.application.processIdentifier) ready; window '\(windowTitle)' role \(fieldRole) id \(fieldIdentifier)")
        return FocusedTextContext(
            query: value,
            queryFrame: queryFrame,
            windowFrame: windowFrame
        )
    }

    private static func isCampoSpotlightRoot(_ element: AXUIElement) -> Bool {
        if SpotlightAccessibilitySupport.isSpotlightDialog(
            role: copyStringAttribute(kAXRoleAttribute as CFString, from: element),
            subrole: copyStringAttribute(kAXSubroleAttribute as CFString, from: element)
        ) {
            return true
        }

        guard let window = enclosingWindow(of: element) else {
            return false
        }
        return SpotlightAccessibilitySupport.isSpotlightDialog(
            role: copyStringAttribute(kAXRoleAttribute as CFString, from: window),
            subrole: copyStringAttribute(kAXSubroleAttribute as CFString, from: window)
        )
    }

    private static func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        guard let value = copyAttribute(attribute, from: element) else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }
        return nil
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

    private static func copyQueryField(from root: AXUIElement, requiresSearchSemantics: Bool) -> AXUIElement? {
        firstDescendant(in: root, depth: 0) { element in
            isQueryField(element, requiresSearchSemantics: requiresSearchSemantics)
        }
    }

    private static func firstDescendant(
        in element: AXUIElement,
        depth: Int,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        guard depth <= 12 else {
            return nil
        }

        if predicate(element) {
            return element
        }

        // 部分 SwiftUI 窗口只把输入控件放进导航顺序，不放进 AXChildren。
        let childAttributes = [
            kAXChildrenAttribute as CFString,
            "AXChildrenInNavigationOrder" as CFString,
            "AXContents" as CFString,
            "AXFunctionRowTopLevelElements" as CFString,
        ]
        for attribute in childAttributes {
            for child in copyElementsAttribute(attribute, from: element) {
                if let nestedMatch = firstDescendant(in: child, depth: depth + 1, matching: predicate) {
                    return nestedMatch
                }
            }
        }

        return nil
    }

    private static func isQueryField(_ element: AXUIElement, requiresSearchSemantics: Bool) -> Bool {
        SpotlightAccessibilitySupport.isQueryField(
            role: copyStringAttribute(kAXRoleAttribute as CFString, from: element),
            subrole: copyStringAttribute(kAXSubroleAttribute as CFString, from: element),
            identifier: copyStringAttribute(kAXIdentifierAttribute as CFString, from: element),
            value: copyStringAttribute(kAXValueAttribute as CFString, from: element),
            requiresSearchSemantics: requiresSearchSemantics
        )
    }

    private static func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<16 {
            guard let candidate = current else {
                return nil
            }

            if copyStringAttribute(kAXRoleAttribute as CFString, from: candidate) == "AXWindow" {
                return candidate
            }
            current = copyElementAttribute(kAXParentAttribute as CFString, from: candidate)
        }

        return nil
    }

    private static func reportProbe(_ message: String) {
        guard message != lastProbeSummary else {
            return
        }

        lastProbeSummary = message
        DebugLog.write("ax: \(message)")
    }
}
