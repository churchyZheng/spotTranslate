import AppKit
import SwiftUI

@MainActor
final class TranslationPanelController {
    private struct PanelGeometry {
        let origin: CGPoint
        let size: NSSize
    }

    private let defaultPanelSize = NSSize(
        width: TranslationPanelLayout.defaultWidth,
        height: TranslationPanelLayout.minimumHeight
    )
    private let attachedTopOverlap: CGFloat = 34
    private let minimumBottomMargin: CGFloat = 36
    private let sideMargin: CGFloat = 24
    private let viewModel: TranslationViewModel
    private var panel: NSPanel?
    private var hostingView: NSHostingView<TranslationPanelView>?

    init(viewModel: TranslationViewModel) {
        self.viewModel = viewModel
    }

    func show(context: FocusedTextContext) {
        let geometry = preferredGeometry(for: context)
        let panel = ensurePanel(size: geometry.size)
        updatePanelIfNeeded(panel, size: geometry.size)
        DebugLog.write("panel.show at \(Int(geometry.origin.x)),\(Int(geometry.origin.y)) size \(Int(geometry.size.width))x\(Int(geometry.size.height))")
        panel.setFrame(NSRect(origin: geometry.origin, size: geometry.size), display: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        guard let panel, panel.isVisible else {
            return
        }
        DebugLog.write("panel.hide")
        panel.orderOut(nil)
        panel.contentView = nil
        hostingView = nil
        self.panel = nil
        DebugLog.write("panel.destroyed")
    }

    private func ensurePanel(size: NSSize) -> NSPanel {
        if let panel {
            return panel
        }

        DebugLog.write("panel.ensure begin")
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        DebugLog.write("panel.ensure created NSPanel")
        DebugLog.write("panel.ensure set isFloatingPanel")
        panel.isFloatingPanel = true
        DebugLog.write("panel.ensure set level")
        panel.level = .statusBar
        DebugLog.write("panel.ensure set collectionBehavior")
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        DebugLog.write("panel.ensure set hidesOnDeactivate")
        panel.hidesOnDeactivate = false
        DebugLog.write("panel.ensure set isOpaque")
        panel.isOpaque = false
        DebugLog.write("panel.ensure set backgroundColor")
        panel.backgroundColor = .clear
        DebugLog.write("panel.ensure set hasShadow")
        panel.hasShadow = false
        DebugLog.write("panel.ensure set ignoresMouseEvents")
        panel.ignoresMouseEvents = true
        DebugLog.write("panel.ensure set animationBehavior")
        panel.animationBehavior = .utilityWindow
        DebugLog.write("panel.ensure before hosting view")
        // HostingView 只创建一次，避免尺寸变化时重建 SwiftUI 树把 translationTask 一起取消。
        let hostingView = NSHostingView(rootView: TranslationPanelView(viewModel: viewModel))
        panel.contentView = hostingView
        self.hostingView = hostingView
        DebugLog.write("panel.ensure after hosting view")
        panel.setContentSize(size)
        self.panel = panel
        DebugLog.write("panel.created")
        return panel
    }

    private func updatePanelIfNeeded(_ panel: NSPanel, size: NSSize) {
        let currentSize = panel.frame.size
        let needsResize =
            abs(currentSize.width - size.width) > 0.5
            || abs(currentSize.height - size.height) > 0.5

        if panel.contentView == nil {
            // 极少数情况下 contentView 会被系统释放，这里只补建视图，不主动替换已有实例。
            let hostingView = NSHostingView(rootView: TranslationPanelView(viewModel: viewModel))
            panel.contentView = hostingView
            self.hostingView = hostingView
        }

        guard needsResize else {
            return
        }

        panel.setContentSize(size)
        DebugLog.write("panel.resized to \(Int(size.width))x\(Int(size.height))")
    }

#if DEBUG
    var debugContentViewIdentity: ObjectIdentifier? {
        panel?.contentView.map(ObjectIdentifier.init)
    }
#endif

    private func preferredGeometry(for context: FocusedTextContext) -> PanelGeometry {
        let anchorFrame = context.windowFrame ?? context.queryFrame
        let screen = preferredScreen(for: anchorFrame) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return PanelGeometry(origin: .zero, size: defaultPanelSize)
        }

        let size = preferredSize(for: context.windowFrame, screen: screen)
        let origin = preferredOrigin(
            windowFrame: context.windowFrame,
            queryFrame: context.queryFrame,
            panelSize: size,
            screen: screen
        )
        return PanelGeometry(origin: origin, size: size)
    }

    private func preferredSize(for windowFrame: CGRect?, screen: NSScreen) -> NSSize {
        let width: CGFloat
        if let windowFrame {
            width = min(windowFrame.width, screen.frame.width)
        } else {
            let maxWidth = screen.visibleFrame.width - sideMargin * 2
            width = min(defaultPanelSize.width, maxWidth)
        }

        let resolvedWidth = round(width)
        // 高度根据当前翻译结果实时计算，但要限制在可视区域内，避免长文本把 Spotlight 顶走。
        let resolvedHeight = TranslationPanelLayout.preferredHeight(
            panelWidth: resolvedWidth,
            primaryText: viewModel.errorMessage ?? viewModel.resultText,
            sourceText: viewModel.sourceText,
            isError: viewModel.errorMessage != nil,
            visibleHeight: screen.visibleFrame.height
        )
        return NSSize(width: resolvedWidth, height: resolvedHeight)
    }

    private func preferredOrigin(
        windowFrame: CGRect?,
        queryFrame: CGRect?,
        panelSize: NSSize,
        screen: NSScreen
    ) -> CGPoint {
        let minX = screen.visibleFrame.minX + sideMargin
        let maxX = screen.visibleFrame.maxX - panelSize.width - sideMargin
        let x: CGFloat

        if let windowFrame {
            x = round(windowFrame.minX)
        } else {
            let desiredMidX = queryFrame?.midX ?? screen.frame.midX
            let unclampedX = desiredMidX - panelSize.width / 2
            x = round(min(max(unclampedX, minX), maxX))
        }

        let fallbackY = screen.visibleFrame.maxY - panelSize.height - 220
        let panelY: CGFloat

        if let windowFrame {
            // Accessibility API 返回的坐标以左上角为原点，而 AppKit 面板坐标以左下角为原点，需要手动换算。
            let spotlightBottomY = screen.frame.maxY - windowFrame.minY - windowFrame.height
            panelY = spotlightBottomY - panelSize.height + attachedTopOverlap
        } else if let queryFrame {
            let searchFieldBottomY = screen.frame.maxY - queryFrame.minY - queryFrame.height
            panelY = searchFieldBottomY - panelSize.height - 388
        } else {
            panelY = fallbackY
        }

        let minY = screen.visibleFrame.minY + minimumBottomMargin
        let maxY = screen.visibleFrame.maxY - panelSize.height - sideMargin
        let y = round(min(max(panelY, minY), maxY))
        return CGPoint(x: x, y: y)
    }

    private func preferredScreen(for anchorFrame: CGRect?) -> NSScreen? {
        guard let anchorFrame else {
            return NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        }

        let midX = anchorFrame.midX
        return NSScreen.screens.first(where: { screen in
            screen.frame.minX <= midX && midX <= screen.frame.maxX
        })
    }
}
