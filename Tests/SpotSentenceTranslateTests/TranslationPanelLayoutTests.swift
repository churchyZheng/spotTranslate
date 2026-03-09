import Testing
@testable import SpotSentenceTranslate

struct TranslationPanelLayoutTests {
    @Test
    func longTextUsesMoreHeightThanShortText() {
        let shortHeight = TranslationPanelLayout.preferredHeight(
            panelWidth: 600,
            primaryText: "你好吗？",
            sourceText: "how are you",
            isError: false,
            visibleHeight: 900
        )
        let longHeight = TranslationPanelLayout.preferredHeight(
            panelWidth: 600,
            primaryText: "Screenity 是一个功能很强的屏幕录制和标注工具，可以用于工作、教育以及更多场景。你可以免费制作产品演示、教程、演讲内容，或者和团队共享反馈。",
            sourceText: "Screenity is a powerful screen recorder and annotation tool to make better videos for work, education, and more.",
            isError: false,
            visibleHeight: 900
        )

        #expect(longHeight > shortHeight)
    }

    @Test
    func heightIsCappedAtMaximumHeight() {
        let repeatedText = String(repeating: "这是一段很长的翻译内容。", count: 80)
        let height = TranslationPanelLayout.preferredHeight(
            panelWidth: 600,
            primaryText: repeatedText,
            sourceText: repeatedText,
            isError: false,
            visibleHeight: 1200
        )

        #expect(height == TranslationPanelLayout.maximumHeight)
    }
}
