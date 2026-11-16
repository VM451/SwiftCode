import Foundation
import Testing
@testable import SwiftCodeApp
import SwiftCodeCore

@MainActor
struct DiffInspectorViewModelTests {
    @Test func buildsTelemetryChartPointsFromUsage() {
        let container = SwiftCodeAppContainer(inMemory: true)
        let vm = DiffInspectorViewModel(container: container)
        let points = vm.chartPoints(usage: TokenUsage(inputTokens: 2000, outputTokens: 500, cachedTokens: 800))
        #expect(points.count == 3)
        #expect(points.first { $0.label == "Input" }?.count == 2000)
    }
}
