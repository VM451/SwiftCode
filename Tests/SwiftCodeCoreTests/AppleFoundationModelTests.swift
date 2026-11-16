import Foundation
import Testing
@testable import SwiftCodeCore

private struct MockAppleInspector: AppleFoundationModelInspector {
    let localStatus: (available: Bool, contextSize: Int, reason: String?)
    let pccState: PCCQuotaState

    func localAvailability() -> (available: Bool, contextSize: Int, reason: String?) {
        localStatus
    }

    func pccQuotaState() async -> PCCQuotaState {
        pccState
    }

    @MainActor
    func presentLimitIncreaseSuggestionIfAvailable() -> Bool {
        pccState.hasLimitIncreaseSuggestion
    }
}

struct AppleFoundationModelTests {
    @Test func configurationDefaultsToLocalWithSmallerContextWindow() {
        let config = SwiftCodeConfiguration()
        #expect(config.defaultAppleModel == .local)
        #expect(config.contextWindowLimit == 4_096)
        #expect(config.models.architect.provider == "apple-local")
        #expect(config.models.architect.model == AppleFoundationModelVariant.local.rawValue)
        #expect(config.models.coder.provider == "apple-local")
        #expect(config.effectiveContextWindowLimit(for: .architect) == 4_096)
        #expect(config.effectiveContextWindowLimit(for: .coder) == 4_096)

        var pccConfig = config
        pccConfig.applyDefaultAppleModel(.privateCloudCompute)
        #expect(pccConfig.defaultAppleModel == .privateCloudCompute)
        #expect(pccConfig.contextWindowLimit == 32_768)
        #expect(pccConfig.models.architect.provider == "apple-pcc")
        #expect(pccConfig.effectiveContextWindowLimit(for: .architect) == 32_768)
        #expect(pccConfig.effectiveContextWindowLimit(for: .utility) == 4_096)
    }

    @Test func variantResolutionHandlesLocalAndPCCAliases() {
        #expect(AppleFoundationModelVariant.parseUserSelection("local") == .local)
        #expect(AppleFoundationModelVariant.parseUserSelection("pcc") == .privateCloudCompute)
        #expect(AppleFoundationModelVariant.parseUserSelection("private-cloud-compute") == .privateCloudCompute)
        #expect(AppleFoundationModelVariant.from(providerID: "apple-pcc", model: "anything") == .privateCloudCompute)
        #expect(AppleFoundationModelVariant.from(providerID: "apple-local", model: "anything") == .local)
        #expect(AppleFoundationModelVariant.from(providerID: "anthropic", model: "claude") == nil)
    }

    @Test func pccQuotaStateComputesWaitDaysAndICloudPlusGuidance() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let threeDaysLater = now.addingTimeInterval(2.4 * 86_400)
        let state = PCCQuotaState(
            isAvailable: true,
            isApproachingLimit: false,
            isLimitReached: true,
            resetDate: threeDaysLater,
            hasLimitIncreaseSuggestion: true
        )

        #expect(state.daysUntilReset(from: now) == 3)
        let guidance = state.formattedGuidance(referenceDate: now)
        #expect(guidance.contains("Wait 3 days"))
        #expect(guidance.contains("iCloud+"))
        #expect(guidance.contains("Local"))
    }

    @Test func pccProviderRejectsRequestWithQuotaErrorWhenLimitReached() async throws {
        let reset = Date().addingTimeInterval(4 * 86_400)
        let state = PCCQuotaState(
            isAvailable: true,
            isLimitReached: true,
            resetDate: reset,
            hasLimitIncreaseSuggestion: true
        )
        let inspector = MockAppleInspector(
            localStatus: (true, 4_096, nil),
            pccState: state
        )
        let provider = AppleFoundationModelProvider(variant: .privateCloudCompute, inspector: inspector)
        let request = LLMRequest(
            model: AppleFoundationModelVariant.privateCloudCompute.rawValue,
            systemPrompt: "System",
            messages: [ConversationMessage(role: .user, content: "Hello")]
        )

        var caughtError: AppleFoundationModelError?
        do {
            for try await _ in provider.streamCompletion(request: request) {}
        } catch let error as AppleFoundationModelError {
            caughtError = error
        }

        if case .pccQuotaLimitReached(let capturedState) = caughtError {
            #expect(capturedState.isLimitReached)
            #expect(capturedState.resetDate == reset)
        } else {
            Issue.record("Expected pccQuotaLimitReached, got \(String(describing: caughtError))")
        }
    }

    @Test func orchestratorEmitsPCCQuotaNoticeWhenApproachingOrLimitReached() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sh-apple-pcc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let reset = Date().addingTimeInterval(2 * 86_400)
        let inspector = MockAppleInspector(
            localStatus: (true, 4_096, nil),
            pccState: PCCQuotaState(
                isAvailable: true,
                isApproachingLimit: false,
                isLimitReached: true,
                resetDate: reset,
                hasLimitIncreaseSuggestion: true
            )
        )
        let mockProvider = MockScriptedProvider(providerID: "mock-pcc") { _ in
            [.textDelta("Fallback reply"), .finished(stopReason: "end_turn")]
        }

        var config = SwiftCodeConfiguration()
        config.applyDefaultAppleModel(.privateCloudCompute)
        config.verificationCommands = []

        let orchestrator = OrchestratorActor(
            workspaceRoot: tempDir,
            configuration: config,
            overrideProvider: mockProvider,
            appleInspector: inspector,
            memoryStore: nil
        )
        let reply = try await orchestrator.runTurn(userPrompt: "Plan something big")
        #expect(reply == "Fallback reply")

        let events = await orchestrator.eventHistory()
        let notices = events.compactMap { event -> PCCQuotaNotice? in
            if case .pccQuotaNotice(let notice) = event.kind { return notice }
            return nil
        }
        #expect(notices.count == 1)
        #expect(notices.first?.state.isLimitReached == true)
        #expect(notices.first?.message.contains("iCloud+") == true)
    }

    @Test func tokenUsageReportsZeroCostForAppleFoundationModels() {
        let cost = TokenUsage.estimateCost(
            model: AppleFoundationModelVariant.local.rawValue,
            inputTokens: 100_000,
            outputTokens: 20_000,
            cachedTokens: 0
        )
        #expect(cost == 0)
    }

    @Test func contextCompactorHonors4KLocalOverrideVersus32KPCCOverride() async {
        let compactor = ContextCompactor(maxTokens: 200_000, thresholdRatio: 0.80, keepRecentTurns: 2)
        let messages = (0..<8).map { idx in
            ConversationMessage(role: .user, content: "Turn \(idx) " + String(repeating: "a", count: 2_500))
        }
        let localOutcome = await compactor.compactIfNeeded(
            systemPrompt: "System",
            messages: messages,
            maxTokensOverride: AppleFoundationModelVariant.local.defaultContextWindowTokens
        )
        #expect(localOutcome.didCompact)

        let pccOutcome = await compactor.compactIfNeeded(
            systemPrompt: "System",
            messages: messages,
            maxTokensOverride: AppleFoundationModelVariant.privateCloudCompute.defaultContextWindowTokens
        )
        #expect(pccOutcome.didCompact == false)
    }
}
