import Foundation
import Testing
@testable import SpotSentenceTranslate

@MainActor
struct TranslationViewModelTests {
    @Test
    func keepsOnlyLatestQueuedJobForSameLanguagePair() async {
        // 用户连续输入时只应该消费最后一个请求，避免旧句子排队翻译。
        let viewModel = TranslationViewModel()
        let sourceLanguage = Locale.Language(identifier: "en")
        let targetLanguage = Locale.Language(identifier: "zh-Hans")

        let firstCandidate = TranslationCandidate(
            originalText: "how are",
            normalizedText: "how are",
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
        let secondCandidate = TranslationCandidate(
            originalText: "how are you",
            normalizedText: "how are you",
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
        let thirdCandidate = TranslationCandidate(
            originalText: "how are you today",
            normalizedText: "how are you today",
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )

        viewModel.ensureTranslationQueue(for: firstCandidate)

        guard let stream = viewModel.translationJobStream() else {
            Issue.record("translation stream should exist after queue setup")
            return
        }

        let firstRequestID = UUID()
        let secondRequestID = UUID()
        let thirdRequestID = UUID()

        viewModel.submit(job: TranslationJob(candidate: firstCandidate, requestID: firstRequestID))
        viewModel.submit(job: TranslationJob(candidate: secondCandidate, requestID: secondRequestID))
        viewModel.submit(job: TranslationJob(candidate: thirdCandidate, requestID: thirdRequestID))

        var iterator = stream.makeAsyncIterator()
        let dequeuedJob = await iterator.next()

        #expect(dequeuedJob?.requestID == thirdRequestID)
        #expect(dequeuedJob?.candidate.normalizedText == "how are you today")
    }

    @Test
    func reconfiguresSessionWhenLanguagePairChanges() {
        let viewModel = TranslationViewModel()
        let englishCandidate = TranslationCandidate(
            originalText: "how are you",
            normalizedText: "how are you",
            sourceLanguage: Locale.Language(identifier: "en"),
            targetLanguage: Locale.Language(identifier: "zh-Hans")
        )
        let chineseCandidate = TranslationCandidate(
            originalText: "你好吗",
            normalizedText: "你好吗",
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: Locale.Language(identifier: "en")
        )

        viewModel.ensureTranslationQueue(for: englishCandidate)
        #expect(viewModel.configuration?.source?.maximalIdentifier.hasPrefix("en") == true)
        #expect(viewModel.configuration?.target?.maximalIdentifier.hasPrefix("zh-Hans") == true)

        viewModel.ensureTranslationQueue(for: chineseCandidate)
        #expect(viewModel.configuration?.source?.maximalIdentifier.hasPrefix("zh-Hans") == true)
        #expect(viewModel.configuration?.target?.maximalIdentifier.hasPrefix("en") == true)
    }

    @Test
    func resetClearsConfigurationAndQueueAndAllowsRebuild() async {
        let viewModel = TranslationViewModel()
        let candidate = TranslationCandidate(
            originalText: "how are you",
            normalizedText: "how are you",
            sourceLanguage: Locale.Language(identifier: "en"),
            targetLanguage: Locale.Language(identifier: "zh-Hans")
        )

        viewModel.ensureTranslationQueue(for: candidate)
        viewModel.reset()

        #expect(viewModel.configuration == nil)
        #expect(viewModel.translationJobStream() == nil)

        viewModel.ensureTranslationQueue(for: candidate)
        guard let stream = viewModel.translationJobStream() else {
            Issue.record("translation stream should be recreated after reset")
            return
        }
        #expect(viewModel.configuration?.source?.maximalIdentifier.hasPrefix("en") == true)
        #expect(viewModel.configuration?.target?.maximalIdentifier.hasPrefix("zh-Hans") == true)

        let requestID = UUID()
        viewModel.submit(job: TranslationJob(candidate: candidate, requestID: requestID))

        var iterator = stream.makeAsyncIterator()
        let dequeuedJob = await iterator.next()

        #expect(dequeuedJob?.requestID == requestID)
        #expect(dequeuedJob?.candidate.normalizedText == "how are you")
    }

    @Test
    func preparationSuccessSubmitsCandidateForTranslation() async {
        let viewModel = TranslationViewModel()
        let candidate = TranslationCandidate(
            originalText: "你还非得",
            normalizedText: "你还非得",
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: Locale.Language(identifier: "en")
        )

        viewModel.markPreparationSucceeded(for: candidate)

        guard let stream = viewModel.translationJobStream() else {
            Issue.record("translation stream should exist after preparation succeeds")
            return
        }

        var iterator = stream.makeAsyncIterator()
        let dequeuedJob = await iterator.next()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading)
        #expect(viewModel.resultText == "正在翻译…")
        #expect(dequeuedJob?.candidate.normalizedText == "你还非得")
    }
}
