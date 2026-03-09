import AppKit
import Testing
@testable import SpotSentenceTranslate

@MainActor
struct TranslationPanelControllerTests {
    @Test
    func resizeKeepsExistingContentView() {
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
}
