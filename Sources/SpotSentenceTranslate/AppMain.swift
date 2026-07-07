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
        // 作为菜单栏工具运行，不显示 Dock 图标。
        NSApp.setActivationPolicy(.accessory)
        appController = AppController()
        appController?.start()
    }
}

@MainActor
final class AppController {
    // 在这里集中装配依赖，避免状态分散在多个入口里。
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
        preparationController.onPrepared = { [weak self] candidate in
            self?.viewModel.markPreparationSucceeded(for: candidate)
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
