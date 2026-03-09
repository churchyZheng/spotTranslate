import AppKit

@MainActor
final class StatusItemController: NSObject {
    var onRequestAccessibility: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLabelItem = NSMenuItem(title: "辅助功能权限：检查中", action: nil, keyEquivalent: "")

    func install() {
        updateAccessibilityState(granted: false)
        statusItem.button?.font = .systemFont(ofSize: 14, weight: .semibold)

        let menu = NSMenu()
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)
        menu.addItem(
            withTitle: "打开辅助功能授权",
            action: #selector(requestAccessibility),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    func updateAccessibilityState(granted: Bool) {
        // 菜单栏标题直接反映权限状态，方便快速定位“没翻译”是否是授权问题。
        statusLabelItem.title = granted ? "辅助功能权限：已授予" : "辅助功能权限：未授予"
        statusItem.button?.title = granted ? "译" : "译!"
    }

    @objc private func requestAccessibility() {
        onRequestAccessibility?()
    }

    @objc private func quitApp() {
        onQuit?()
    }
}
