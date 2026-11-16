import SwiftData
import SwiftUI

@main
struct SwiftCodeAppMain: App {
    @State private var container = SwiftCodeAppContainer()
    @State private var menuSettingsVM: DaemonSettingsViewModel

    init() {
        let shared = SwiftCodeAppContainer()
        self._container = State(initialValue: shared)
        self._menuSettingsVM = State(initialValue: DaemonSettingsViewModel(container: shared))
    }

    var body: some Scene {
        WindowGroup("SwiftCode") {
            RootNavigationView(container: container)
                .modelContainer(container.modelContainer)
        }

        MenuBarExtra("SwiftCode", systemImage: "terminal") {
            MenuBarDaemonView(settingsVM: menuSettingsVM)
        }
        .menuBarExtraStyle(.window)
    }
}
