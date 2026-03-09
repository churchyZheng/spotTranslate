import Foundation

@MainActor
final class SpotlightMonitor {
    var onAccessibilityChanged: ((Bool) -> Void)?

    private let panelController: TranslationPanelController
    private let viewModel: TranslationViewModel
    private var timer: Timer?
    private var lastAccessibilityState = false
    private var lastPollSummary: String?
    private var invalidPollCount = 0

    init(panelController: TranslationPanelController, viewModel: TranslationViewModel) {
        self.panelController = panelController
        self.viewModel = viewModel
    }

    func start() {
        DebugLog.write("monitor.start enter")
        refreshAccessibility(prompt: true)
        poll()

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        DebugLog.write("monitor.start timer scheduled")
    }

    func requestAccessibilityPermission() {
        refreshAccessibility(prompt: true)
        if !lastAccessibilityState {
            AccessibilityBridge.openAccessibilitySettings()
        }
    }

    private func poll() {
        refreshAccessibility(prompt: false)
        if lastAccessibilityState == false {
            reportPoll("poll: trusted flag false, probing spotlight anyway")
        }

        guard let context = AccessibilityBridge.focusedSpotlightTextContext() else {
            reportPoll("poll: no spotlight context")
            registerInvalidPoll()
            return
        }

        guard let candidate = QueryClassifier.translationCandidate(for: context.query) else {
            reportPoll("poll: query rejected '\(context.query)'")
            registerInvalidPoll()
            return
        }

        invalidPollCount = 0
        reportPoll("poll: show for '\(candidate.normalizedText)'")
        viewModel.enqueue(candidate: candidate)
        panelController.show(context: context)
    }

    private func refreshAccessibility(prompt: Bool) {
        let granted = AccessibilityBridge.isTrusted(prompt: prompt)
        guard granted != lastAccessibilityState else {
            return
        }

        lastAccessibilityState = granted
        DebugLog.write("accessibility changed: \(granted)")
        onAccessibilityChanged?(granted)
    }

    private func hidePanel() {
        viewModel.reset()
        panelController.hide()
    }

    private func registerInvalidPoll() {
        invalidPollCount += 1
        guard invalidPollCount >= 3 else {
            return
        }

        hidePanel()
    }

    private func reportPoll(_ summary: String) {
        guard summary != lastPollSummary else {
            return
        }

        lastPollSummary = summary
        DebugLog.write(summary)
    }
}
