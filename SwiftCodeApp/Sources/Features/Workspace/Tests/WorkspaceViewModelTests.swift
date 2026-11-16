import Foundation
import Testing
@testable import SwiftCodeApp
import SwiftCodeCore

@MainActor
struct WorkspaceViewModelTests {
    @Test func switchesModesAndLoadsTurns() {
        let container = SwiftCodeAppContainer(inMemory: true)
        let session = container.createSession(title: "Test Session", mode: .plan)
        container.appendTurn(sessionID: session.id, role: "user", content: "Hello")

        let vm = WorkspaceViewModel(container: container)
        vm.loadSession(id: session.id, mode: .plan)
        #expect(vm.turns.count == 1)
        #expect(vm.selectedMode == .plan)

        vm.switchMode(to: .build)
        #expect(vm.selectedMode == .build)
    }
}
