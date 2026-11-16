import Foundation
import Testing
@testable import SwiftCodeApp
import SwiftCodeCore

@MainActor
struct SessionsViewModelTests {
    @Test func createsAndFiltersSessionsInMemory() {
        let container = SwiftCodeAppContainer(inMemory: true)
        let vm = SessionsViewModel(container: container)
        #expect(vm.sessions.isEmpty)

        vm.startNewSession(mode: .plan)
        #expect(vm.sessions.count == 1)
        #expect(vm.selectedSessionID == vm.sessions.first?.id)

        vm.searchText = "NonExistent"
        #expect(vm.filteredSessions.isEmpty)

        vm.searchText = "Session"
        #expect(vm.filteredSessions.count == 1)
    }
}
