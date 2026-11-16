import SwiftUI
import SwiftCodeCore

/// Native macOS menu bar popover providing quick daemon health & one-click toggles.
struct MenuBarDaemonView: View {
    @Bindable var settingsVM: DaemonSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.stackMedium) {
            Label(
                settingsVM.daemonStatus?.running == true ? "Daemon Running" : "Daemon Idle",
                systemImage: settingsVM.daemonStatus?.running == true ? "checkmark.circle.fill" : "pause.circle"
            )
            .font(.headline)

            if let snap = settingsVM.daemonStatus {
                Text("Tasks: \(snap.processedTasks) • RSS: \(String(format: "%.1f", snap.residentMemoryMB)) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(settingsVM.daemonStatus?.running == true ? "Pause Daemon" : "Start Daemon") {
                settingsVM.toggleDaemon()
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .frame(maxWidth: .infinity, minHeight: AppSizes.heightStandard)
        }
        .padding(AppSpacing.card)
        .frame(width: AppSizes.widthStandard)
    }
}
