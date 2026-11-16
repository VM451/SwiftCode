import SwiftUI
import SwiftCodeCore

/// Settings sheet / window for Keychain API keys and background daemon controls.
struct DaemonSettingsView: View {
    @Bindable var viewModel: DaemonSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("macOS Keychain API Vault") {
                Picker("Credential", selection: $viewModel.selectedKey) {
                    ForEach(SecretKey.allCases, id: \.self) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                LabeledContent("Secret") {
                    SecureField("Paste API key or bot token", text: $viewModel.keyDraft)
                }
                Button("Save to Keychain", systemImage: "key.fill") {
                    viewModel.saveKey()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .frame(minHeight: AppSizes.heightStandard)

                if !viewModel.storedKeys.isEmpty {
                    ForEach(viewModel.storedKeys, id: \.self) { key in
                        LabeledContent(key) {
                            Button("Delete", role: .destructive) {
                                viewModel.deleteKey(key)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                        }
                    }
                }
            }

            Section("Always-On SwiftNIO Daemon") {
                if let snap = viewModel.daemonStatus {
                    LabeledContent("State", value: snap.running ? "Running" : "Idle")
                    LabeledContent("Memory RSS", value: String(format: "%.1f MB", snap.residentMemoryMB))
                    LabeledContent("Processed Tasks", value: "\(snap.processedTasks)")
                }
                Button(viewModel.daemonStatus?.running == true ? "Stop Daemon" : "Start Daemon", systemImage: "bolt.horizontal.circle") {
                    viewModel.toggleDaemon()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .frame(minHeight: AppSizes.heightStandard)
            }

            if let banner = viewModel.statusBanner {
                Section {
                    Text(banner)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(AppSpacing.screenHorizontal)
        .navigationTitle("Daemon & Vault")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .buttonStyle(.glass)
            }
        }
        .frame(minWidth: AppSizes.widthLarge, minHeight: AppSizes.heightInspectorPanel)
    }
}
