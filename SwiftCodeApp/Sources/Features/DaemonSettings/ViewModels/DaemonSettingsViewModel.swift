import Foundation
import SwiftCodeCore
import SwiftCodeDaemon

/// `@MainActor @Observable` ViewModel managing Keychain API keys and Daemon lifecycle.
@MainActor
@Observable
final class DaemonSettingsViewModel {
    private let container: SwiftCodeAppContainer
    var selectedKey: SecretKey = .anthropicAPIKey
    var keyDraft: String = ""
    var storedKeys: [String] = []
    var daemonStatus: DaemonStatusSnapshot?
    var statusBanner: String?

    init(container: SwiftCodeAppContainer) {
        self.container = container
        Task { await refresh() }
    }

    func refresh() async {
        storedKeys = (try? await container.secretStore.listKeys()) ?? []
        daemonStatus = await container.daemonService.statusSnapshot()
    }

    func saveKey() {
        let value = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let targetKey = selectedKey.rawValue
        keyDraft = ""
        Task {
            do {
                try await container.secretStore.setSecret(value, forKey: targetKey)
                statusBanner = "Saved \(targetKey) to Keychain."
                await refresh()
            } catch {
                statusBanner = error.localizedDescription
            }
        }
    }

    func deleteKey(_ key: String) {
        Task {
            try? await container.secretStore.deleteSecret(forKey: key)
            statusBanner = "Removed \(key)."
            await refresh()
        }
    }

    func toggleDaemon() {
        Task {
            if daemonStatus?.running == true {
                await container.daemonService.stop()
                statusBanner = "Daemon stopped."
            } else {
                do {
                    try await container.daemonService.start()
                    statusBanner = "Daemon started."
                } catch {
                    statusBanner = error.localizedDescription
                }
            }
            await refresh()
        }
    }
}
