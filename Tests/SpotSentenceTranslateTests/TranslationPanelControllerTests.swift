import AppKit
import Testing
@testable import SpotSentenceTranslate

@MainActor
struct TranslationPanelControllerTests {
    @Test
    func resizeKeepsExistingContentView() {
        // 回归保护：面板尺寸变化不能替换 HostingView，否则会把 translationTask 一起取消。
        let viewModel = TranslationViewModel()
        let controller = TranslationPanelController(viewModel: viewModel)

        let firstContext = FocusedTextContext(
            query: "how are you",
            queryFrame: CGRect(x: 840, y: 90, width: 420, height: 44),
            windowFrame: CGRect(x: 780, y: 56, width: 540, height: 120)
        )
        let secondContext = FocusedTextContext(
            query: "how are you today",
            queryFrame: CGRect(x: 820, y: 90, width: 480, height: 44),
            windowFrame: CGRect(x: 760, y: 56, width: 620, height: 120)
        )

        controller.show(context: firstContext)
        let initialContentViewIdentity = controller.debugContentViewIdentity

        controller.show(context: secondContext)
        let resizedContentViewIdentity = controller.debugContentViewIdentity

        #expect(initialContentViewIdentity != nil)
        #expect(initialContentViewIdentity == resizedContentViewIdentity)

        controller.hide()
    }

    @Test
    func hideAndReshowKeepsExistingContentView() {
        let viewModel = TranslationViewModel()
        let controller = TranslationPanelController(viewModel: viewModel)
        let context = FocusedTextContext(
            query: "how are you",
            queryFrame: CGRect(x: 840, y: 90, width: 420, height: 44),
            windowFrame: CGRect(x: 780, y: 56, width: 540, height: 120)
        )

        controller.show(context: context)
        let initialContentViewIdentity = controller.debugContentViewIdentity

        controller.hide()
        let hiddenContentViewIdentity = controller.debugContentViewIdentity

        controller.show(context: context)
        let reshownContentViewIdentity = controller.debugContentViewIdentity

        #expect(initialContentViewIdentity != nil)
        #expect(initialContentViewIdentity == hiddenContentViewIdentity)
        #expect(initialContentViewIdentity == reshownContentViewIdentity)

        controller.hide()
    }

    @Test
    func panelTopOverlapsSpotlightBottomCornerRadius() {
        guard let screen = NSScreen.main else {
            Issue.record("main screen should be available for geometry test")
            return
        }

        let viewModel = TranslationViewModel()
        let controller = TranslationPanelController(viewModel: viewModel)
        let windowFrame = CGRect(
            x: screen.frame.midX - 270,
            y: 56,
            width: 540,
            height: 120
        )
        let context = FocusedTextContext(
            query: "你还非得",
            queryFrame: CGRect(x: windowFrame.minX + 60, y: 90, width: 420, height: 44),
            windowFrame: windowFrame
        )

        let frame = controller.debugPreferredFrame(for: context)
        let spotlightBottomY = screen.frame.maxY - windowFrame.minY - windowFrame.height
        let overlap = frame.maxY - spotlightBottomY

        #expect(overlap == 25)
    }
}
