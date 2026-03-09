import AppKit
import SwiftUI
@preconcurrency import Translation

private struct TranslationPreparationJob: Sendable {
    let candidate: TranslationCandidate
    let requestID: UUID
}

@MainActor
final class TranslationPreparationController {
    private let viewModel = TranslationPreparationViewModel()
    private var window: NSWindow?
    private var activeJob: TranslationPreparationJob?

    init() {
        viewModel.onComplete = { [weak self] result, job in
            self?.handleCompletion(result: result, job: job)
        }
    }

    func prepare(candidate: TranslationCandidate) {
        if
            activeJob?.candidate.sourceLanguage == candidate.sourceLanguage,
            activeJob?.candidate.targetLanguage == candidate.targetLanguage
        {
            return
        }

        let job = TranslationPreparationJob(candidate: candidate, requestID: UUID())
        activeJob = job
        viewModel.begin(job: job)

        let window = ensureWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DebugLog.write("prepare.show '\(candidate.normalizedText)'")
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "准备翻译语言包"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = NSHostingView(rootView: TranslationPreparationView(viewModel: viewModel))
        self.window = window
        return window
    }

    private func handleCompletion(
        result: Result<Void, Error>,
        job: TranslationPreparationJob
    ) {
        guard activeJob?.requestID == job.requestID else {
            return
        }

        switch result {
        case .success:
            DebugLog.write("prepare.finish '\(job.candidate.normalizedText)'")
            activeJob = nil

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.window?.orderOut(nil)
                self?.viewModel.reset()
            }

        case let .failure(error):
            DebugLog.write("prepare.fail '\(job.candidate.normalizedText)' error='\(error.localizedDescription)'")
            activeJob = nil
        }
    }
}

@MainActor
private final class TranslationPreparationViewModel: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    @Published private(set) var titleText = "正在准备翻译语言包"
    @Published private(set) var detailText = "系统可能会请求下载所需的翻译语言资源。"
    @Published private(set) var isLoading = false

    var onComplete: ((Result<Void, Error>, TranslationPreparationJob) -> Void)?

    private var activeJob: TranslationPreparationJob?

    func begin(job: TranslationPreparationJob) {
        activeJob = job
        titleText = "正在准备翻译语言包"
        detailText = "首次使用 \(job.candidate.normalizedText) 对应的翻译方向时，系统会请求下载语言资源。"
        isLoading = true
        configuration = TranslationSession.Configuration(
            source: job.candidate.sourceLanguage,
            target: job.candidate.targetLanguage
        )
    }

    func reset() {
        activeJob = nil
        configuration = nil
        titleText = "正在准备翻译语言包"
        detailText = "系统可能会请求下载所需的翻译语言资源。"
        isLoading = false
    }

    func currentJob() -> TranslationPreparationJob? {
        activeJob
    }

    func finishPreparation() {
        guard let job = activeJob else {
            return
        }

        configuration = nil
        isLoading = false
        titleText = "语言包已准备"
        detailText = "重新打开 Spotlight，再输入句子即可显示翻译。"
        onComplete?(.success(()), job)
    }

    func failPreparation(error: Error) {
        guard let job = activeJob else {
            return
        }

        configuration = nil
        isLoading = false
        titleText = "语言包准备失败"
        detailText = humanReadableMessage(for: error)
        onComplete?(.failure(error), job)
    }

    private func humanReadableMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

private struct TranslationPreparationView: View {
    @ObservedObject var viewModel: TranslationPreparationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.titleText)
                .font(.system(size: 22, weight: .semibold))

            Text(viewModel.detailText)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(viewModel.isLoading ? "系统窗口可能会弹出，请允许下载。" : "准备完成后可关闭此窗口。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 420, height: 210, alignment: .topLeading)
        .translationTask(viewModel.configuration) { session in
            guard viewModel.currentJob() != nil else {
                return
            }

            do {
                try await session.prepareTranslation()
                viewModel.finishPreparation()
            } catch is CancellationError {
                return
            } catch {
                viewModel.failPreparation(error: error)
            }
        }
    }
}
