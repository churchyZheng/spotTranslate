import Testing
@testable import SpotSentenceTranslate

struct QueryClassifierTests {
    @Test
    func rejectsSingleWordEnglish() {
        #expect(QueryClassifier.translationCandidate(for: "hello") == nil)
    }

    @Test
    func acceptsMultiWordEnglishSentence() {
        let candidate = QueryClassifier.translationCandidate(for: "  how   are you ")
        #expect(candidate?.normalizedText == "how are you")
        #expect(candidate?.sourceLanguage.maximalIdentifier.hasPrefix("en") == true)
        #expect(candidate?.targetLanguage.maximalIdentifier.hasPrefix("zh-Hans") == true)
    }

    @Test
    func acceptsChinesePhraseAndTargetsEnglish() {
        let candidate = QueryClassifier.translationCandidate(for: "今天天气不错")
        #expect(candidate?.sourceLanguage.maximalIdentifier.hasPrefix("zh-Hans") == true)
        #expect(candidate?.targetLanguage.maximalIdentifier.hasPrefix("en") == true)
    }

    @Test
    func rejectsURL() {
        #expect(QueryClassifier.translationCandidate(for: "https://apple.com") == nil)
    }
}
