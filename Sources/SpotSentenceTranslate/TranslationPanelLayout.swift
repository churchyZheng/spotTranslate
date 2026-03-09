import AppKit
import Foundation

enum TranslationPanelLayout {
    static let defaultWidth: CGFloat = 540
    static let minimumHeight: CGFloat = 144
    static let maximumHeight: CGFloat = 320
    static let primaryFontSize: CGFloat = 19
    static let errorFontSize: CGFloat = 16
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 22
    static let bottomPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let contentSpacing: CGFloat = 9
    static let headerHeight: CGFloat = 30
    static let dividerHeight: CGFloat = 1
    static let sourceIconSpacing: CGFloat = 18
    static let sourceRowMinimumHeight: CGFloat = 16

    static func preferredHeight(
        panelWidth: CGFloat,
        primaryText: String,
        sourceText: String,
        isError: Bool,
        visibleHeight: CGFloat
    ) -> CGFloat {
        let contentWidth = max(panelWidth - horizontalPadding * 2, 240)
        let primaryHeight = textHeight(
            primaryText,
            font: primaryFont(isError: isError),
            width: contentWidth
        )
        let sourceHeight = max(
            textHeight(
                sourceText,
                font: NSFont.systemFont(ofSize: 13),
                width: max(contentWidth - sourceIconSpacing, 180)
            ),
            sourceRowMinimumHeight
        )

        let rawHeight =
            topPadding
            + headerHeight
            + sectionSpacing
            + primaryHeight
            + contentSpacing
            + dividerHeight
            + contentSpacing
            + sourceHeight
            + bottomPadding

        // 最低保证卡片观感稳定，最高则限制在屏幕可视区域，长文本通过滚动承载。
        let maxHeight = max(
            minimumHeight,
            min(maximumHeight, visibleHeight - 64)
        )
        return ceil(min(max(rawHeight, minimumHeight), maxHeight))
    }

    static func primaryFont(isError: Bool) -> NSFont {
        if isError {
            return NSFont.systemFont(ofSize: errorFontSize, weight: .medium)
        }

        return NSFont.systemFont(ofSize: primaryFontSize, weight: .medium)
    }

    private static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard text.isEmpty == false else {
            return font.pointSize * 1.3
        }

        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(max(rect.height, font.pointSize * 1.3))
    }
}
