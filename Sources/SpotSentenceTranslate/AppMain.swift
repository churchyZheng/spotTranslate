import AppKit
import SwiftUI

@main
struct SpotSentenceTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appController = AppController()
        appController?.start()
    }
}

@MainActor
final class AppController {
    private let preparationController = TranslationPreparationController()
    private lazy var viewModel = TranslationViewModel()
    private lazy var panelController = TranslationPanelController(viewModel: viewModel)
    private lazy var monitor = SpotlightMonitor(panelController: panelController, viewModel: viewModel)
    private lazy var statusItemController = StatusItemController()

    func start() {
        DebugLog.reset()
        DebugLog.write("AppController.start")
        DebugLog.write("AppController.configure closures")
        statusItemController.onRequestAccessibility = { [weak self] in
            self?.monitor.requestAccessibilityPermission()
        }
        viewModel.onNeedsPreparation = { [weak self] candidate in
            self?.preparationController.prepare(candidate: candidate)
        }
        statusItemController.onQuit = {
            NSApp.terminate(nil)
        }
        monitor.onAccessibilityChanged = { [weak self] granted in
            self?.statusItemController.updateAccessibilityState(granted: granted)
        }

        DebugLog.write("AppController.install status item")
        statusItemController.install()
        DebugLog.write("AppController.start monitor")
        monitor.start()
        DebugLog.write("AppController.start done")
    }
}
