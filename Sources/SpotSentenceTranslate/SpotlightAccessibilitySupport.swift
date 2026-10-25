import CoreGraphics
import Foundation

// 把容易受系统界面层级影响的判断集中到纯函数中，便于覆盖新旧 Spotlight 回归测试。
enum SpotlightAccessibilitySupport {
    // Campo 是 macOS 27 起的新 Spotlight/Siri 宿主，旧系统仍使用 Spotlight 进程。
    static let hostBundleIdentifiers = [
        "com.apple.campo",
        "com.apple.Spotlight",
    ]

    static let searchFieldIdentifier = "SpotlightSearchField"
    static let searchFieldSubrole = "AXSearchField"
    static let spotlightDialogSubrole = "AXSystemDialog"

    private static let editableRoles: Set<String> = [
        "AXSearchField",
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
    ]

    static func isQueryField(
        role: String?,
        subrole: String?,
        identifier: String?,
        value: String?,
        requiresSearchSemantics: Bool = false
    ) -> Bool {
        guard let role else {
            return false
        }

        let hasSearchSemantics = editableRoles.contains(role) || subrole == searchFieldSubrole
        guard hasSearchSemantics else {
            return false
        }

        let hasSpotlightSemantics = identifier == searchFieldIdentifier || subrole == searchFieldSubrole
        guard requiresSearchSemantics == false || hasSpotlightSemantics else {
            return false
        }

        // Campo 工具栏也有“AXButton + AXSearchField”，但该按钮没有输入值。
        // 只接受带非空值的输入控件，可排除这个按钮和 Siri 聊天窗口中的普通控件。
        guard value?.isEmpty == false else {
            return false
        }

        return identifier == searchFieldIdentifier || hasSearchSemantics
    }

    static func isSpotlightDialog(role: String?, subrole: String?) -> Bool {
        role == "AXWindow" && subrole == spotlightDialogSubrole
    }

    // 屏幕级透明层也会出现在窗口列表中，不能把它的尺寸当成 Spotlight 浮窗尺寸。
    static func isPlausibleSpotlightPopupFrame(_ frame: CGRect, displayBounds: CGRect) -> Bool {
        guard frame.width >= 240, frame.height >= 30 else {
            return false
        }
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            return true
        }

        return frame.width < displayBounds.width - 2
            && frame.height < displayBounds.height - 2
    }
}
