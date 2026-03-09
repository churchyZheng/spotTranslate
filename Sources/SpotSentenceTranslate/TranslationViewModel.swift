import Foundation
@preconcurrency import Translation

struct TranslationJob: Sendable {
    let candidate: TranslationCandidate
    let requestID: UUID
}

struct TranslationLanguagePair: Equatable, Sendable {
    let source: Locale.Language
    let target: Locale.Language
}

private struct TranslationJobQueue {
    let languagePair: TranslationLanguagePair
    let stream: AsyncStream<TranslationJob>
    let continuation: AsyncStream<TranslationJob>.Continuation
}

private enum TranslationPreparationError: LocalizedError {
    case unsupportedLanguagePairing
    case languagePackNotInstalled

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguagePairing:
            return "当前系统不支持这个翻译方向。"
        case .languagePackNotInstalled:
            return "首次使用需要下载翻译语言包，系统准备窗口已经打开。"
        }
    }
}

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    @Published private(set) var sourceText = ""
    @Published private(set) var resultText = "正在翻译…"
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var targetLabel = "目标语言：简体中文"

    var onNeedsPreparation: ((TranslationCandidate) -> Void)?

    private var activeCandidate: TranslationCandidate?
    private var pendingCandidate: TranslationCandidate?
    private var activeRequestID = UUID()
    private var debounceTask: Task<Void, Never>?
    private var availabilityTask: Task<Void, Never>?
    private var translationQueue: TranslationJobQueue?

    func enqueue(candidate: TranslationCandidate) {
        guard activeCandidate != candidate, pendingCandidate != candidate else {
            return
        }

        DebugLog.write("viewModel.enqueue '\(candidate.normalizedText)'")
        debounceTask?.cancel()
        availabilityTask?.cancel()
        pendingCandidate = candidate
        activeCandidate = nil
        activeRequestID = UUID()
        sourceText = candidate.normalizedText
        resultText = "正在检查翻译资源…"
        errorMessage = nil
        isLoading = true
        targetLabel = candidate.targetLanguage.maximalIdentifier.hasPrefix("en") ? "目标语言：English" : "目标语言：简体中文"

        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            await self?.activate(candidate: candidate)
        }
    }

    func reset() {
        debounceTask?.cancel()
        availabilityTask?.cancel()
        debounceTask = nil
        availabilityTask = nil
        activeCandidate = nil
        pendingCandidate = nil
        activeRequestID = UUID()
        translationQueue?.continuation.finish()
        translationQueue = nil
        configuration = nil
        sourceText = ""
        resultText = "正在翻译…"
        errorMessage = nil
        isLoading = false
        targetLabel = "目标语言：简体中文"
        DebugLog.write("viewModel.reset clear configuration")
    }

    private func activate(candidate: TranslationCandidate) async {
        guard pendingCandidate == candidate else {
            return
        }

        pendingCandidate = nil
        activeCandidate = candidate
        activeRequestID = UUID()
        let requestID = activeRequestID

        availabilityTask?.cancel()
        availabilityTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let availability = LanguageAvailability()
            let status = await availability.status(
                from: candidate.sourceLanguage,
                to: candidate.targetLanguage
            )

            guard
                self.activeRequestID == requestID,
                self.activeCandidate == candidate
            else {
                return
            }

            switch status {
            case .installed:
                DebugLog.write("translation.status '\(candidate.normalizedText)' installed")
                self.resultText = "正在翻译…"
                self.startTranslation(candidate: candidate)

            case .supported:
                DebugLog.write("translation.status '\(candidate.normalizedText)' supported")
                self.isLoading = false
                self.errorMessage = TranslationPreparationError.languagePackNotInstalled.errorDescription
                DebugLog.write("translation.prepare needed '\(candidate.normalizedText)'")
                self.onNeedsPreparation?(candidate)

            case .unsupported:
                DebugLog.write("translation.status '\(candidate.normalizedText)' unsupported")
                self.fail(
                    error: TranslationPreparationError.unsupportedLanguagePairing,
                    for: TranslationJob(candidate: candidate, requestID: requestID)
                )

            @unknown default:
                DebugLog.write("translation.status '\(candidate.normalizedText)' unknown")
                self.fail(
                    error: TranslationPreparationError.unsupportedLanguagePairing,
                    for: TranslationJob(candidate: candidate, requestID: requestID)
                )
            }
        }
    }

    private func startTranslation(candidate: TranslationCandidate) {
        let requestID = activeRequestID
        let job = TranslationJob(candidate: candidate, requestID: requestID)
        ensureTranslationQueue(for: candidate)
        submit(job: job)
    }

    func translationJobStream() -> AsyncStream<TranslationJob>? {
        translationQueue?.stream
    }

    func ensureTranslationQueue(for candidate: TranslationCandidate) {
        let languagePair = TranslationLanguagePair(
            source: candidate.sourceLanguage,
            target: candidate.targetLanguage
        )

        if translationQueue?.languagePair == languagePair {
            if configuration == nil {
                configuration = TranslationSession.Configuration(
                    source: languagePair.source,
                    target: languagePair.target
                )
                DebugLog.write("translation.session rearm same pair")
            }
            return
        }

        translationQueue?.continuation.finish()

        var continuation: AsyncStream<TranslationJob>.Continuation?
        let stream = AsyncStream<TranslationJob>(bufferingPolicy: .bufferingNewest(1)) { streamContinuation in
            continuation = streamContinuation
        }

        guard let continuation else {
            return
        }

        translationQueue = TranslationJobQueue(
            languagePair: languagePair,
            stream: stream,
            continuation: continuation
        )
        configuration = TranslationSession.Configuration(
            source: languagePair.source,
            target: languagePair.target
        )
    }

    func submit(job: TranslationJob) {
        translationQueue?.continuation.yield(job)
    }

    func finish(response: TranslationSession.Response, for job: TranslationJob) {
        guard job.requestID == activeRequestID, activeCandidate == job.candidate else {
            return
        }

        DebugLog.write("translation.finish '\(job.candidate.normalizedText)' -> '\(response.targetText)'")
        resultText = response.targetText
        errorMessage = nil
        isLoading = false
        pendingCandidate = nil
    }

    func fail(error: Error, for job: TranslationJob) {
        guard job.requestID == activeRequestID else {
            return
        }

        DebugLog.write("translation.fail '\(job.candidate.normalizedText)' error='\(error.localizedDescription)'")
        errorMessage = humanReadableMessage(for: error)
        isLoading = false
        pendingCandidate = nil
    }

    private func humanReadableMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }

        return "翻译失败，请稍后重试。"
    }
}
