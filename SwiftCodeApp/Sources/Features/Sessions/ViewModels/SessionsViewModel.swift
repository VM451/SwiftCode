import Foundation
import SwiftCodeCore

/// `@MainActor @Observable` ViewModel owning the sidebar session list.
@MainActor
@Observable
final class SessionsViewModel {
    private let container: SwiftCodeAppContainer
    var sessions: [AgentSessionItem] = []
    var selectedSessionID: UUID?
    var searchText: String = ""

    init(container: SwiftCodeAppContainer) {
        self.container = container
        reload()
    }

    var filteredSessions: [AgentSessionItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.localizedStandardContains(q) || $0.workspacePath.localizedStandardContains(q)
        }
    }

    func reload() {
        sessions = container.fetchSessionSummaries()
        if selectedSessionID == nil {
            selectedSessionID = sessions.first?.id
        }
    }

    func startNewSession(mode: AgentMode = .plan) {
        let created = container.createSession(title: "Session \(sessions.count + 1)", mode: mode)
        reload()
        selectedSessionID = created.id
    }
}
