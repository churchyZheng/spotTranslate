import CoreGraphics
import Testing
@testable import SpotSentenceTranslate

struct SpotlightAccessibilitySupportTests {
    @Test
    func hostOrderPrefersCampoAndKeepsLegacySpotlight() {
        #expect(SpotlightAccessibilitySupport.hostBundleIdentifiers == [
            "com.apple.campo",
            "com.apple.Spotlight",
        ])
    }

    @Test
    func acceptsCampoSpotlightSearchField() {
        #expect(SpotlightAccessibilitySupport.isQueryField(
            role: "AXTextField",
            subrole: "AXSearchField",
            identifier: "SpotlightSearchField",
            value: "how are you"
        ))
    }

    @Test
    func rejectsSiriToolbarSearchButtonWithoutValue() {
        #expect(SpotlightAccessibilitySupport.isQueryField(
            role: "AXButton",
            subrole: "AXSearchField",
            identifier: nil,
            value: nil
        ) == false)
    }

    @Test
    func acceptsLegacySpotlightTextFieldWithValue() {
        #expect(SpotlightAccessibilitySupport.isQueryField(
            role: "AXTextField",
            subrole: nil,
            identifier: nil,
            value: "今天天气不错"
        ))
    }

    @Test
    func rejectsGenericCampoTextAreaDuringSpotlightTransition() {
        #expect(SpotlightAccessibilitySupport.isQueryField(
            role: "AXTextArea",
            subrole: nil,
            identifier: nil,
            value: "how are you today",
            requiresSearchSemantics: true
        ) == false)
    }

    @Test
    func rejectsEmptyQueryField() {
        #expect(SpotlightAccessibilitySupport.isQueryField(
            role: "AXTextField",
            subrole: "AXSearchField",
            identifier: "SpotlightSearchField",
            value: ""
        ) == false)
    }

    @Test
    func rejectsScreenSizedTransientWindow() {
        let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let transient = CGRect(x: 0, y: 0, width: 1470, height: 144)
        let spotlight = CGRect(x: 830, y: 33, width: 640, height: 245)

        #expect(SpotlightAccessibilitySupport.isPlausibleSpotlightPopupFrame(
            transient,
            displayBounds: display
        ) == false)
        #expect(SpotlightAccessibilitySupport.isPlausibleSpotlightPopupFrame(
            spotlight,
            displayBounds: display
        ))
    }

    @Test
    func recognizesCampoSpotlightDialog() {
        #expect(SpotlightAccessibilitySupport.isSpotlightDialog(
            role: "AXWindow",
            subrole: "AXSystemDialog"
        ))
        #expect(SpotlightAccessibilitySupport.isSpotlightDialog(
            role: "AXWindow",
            subrole: "AXStandardWindow"
        ) == false)
    }
}
