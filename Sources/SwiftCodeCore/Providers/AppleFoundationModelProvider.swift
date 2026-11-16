import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Inspects live Apple Foundation Model availability and Private Cloud Compute quota state.
public protocol AppleFoundationModelInspector: Sendable {
    func localAvailability() -> (available: Bool, contextSize: Int, reason: String?)
    func pccQuotaState() async -> PCCQuotaState
    @MainActor func presentLimitIncreaseSuggestionIfAvailable() -> Bool
}

/// Default inspector backed by Apple's native `FoundationModels` framework on macOS 26/27+.
public struct LiveAppleFoundationModelInspector: AppleFoundationModelInspector, Sendable {
    public init() {}

    public func localAvailability() -> (available: Bool, contextSize: Int, reason: String?) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            let ctxSize: Int = if #available(macOS 26.4, *) {
                model.contextSize
            } else {
                AppleFoundationModelVariant.local.defaultContextWindowTokens
            }
            switch model.availability {
            case .available:
                return (true, ctxSize, nil)
            case .unavailable(let reason):
                let desc = switch reason {
                case .deviceNotEligible: "This Mac hardware is not eligible for Apple Intelligence."
                case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in System Settings."
                case .modelNotReady: "On-device Apple Foundation Model assets are still downloading."
                @unknown default: "On-device Apple Foundation Model is unavailable."
                }
                return (false, ctxSize, desc)
            }
        }
        #endif
        return (false, AppleFoundationModelVariant.local.defaultContextWindowTokens, "Requires macOS 26+ with Apple Intelligence enabled.")
    }

    public func pccQuotaState() async -> PCCQuotaState {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            let pcc = PrivateCloudComputeLanguageModel()
            let quota = pcc.quotaUsage
            let approaching: Bool
            let limitReached = quota.isLimitReached
            switch quota.status {
            case .belowLimit(let below):
                approaching = below.isApproachingLimit
            case .limitReached:
                approaching = false
            @unknown default:
                approaching = false
            }

            switch pcc.availability {
            case .available:
                return PCCQuotaState(
                    isAvailable: true,
                    isApproachingLimit: approaching,
                    isLimitReached: limitReached,
                    resetDate: quota.resetDate,
                    hasLimitIncreaseSuggestion: quota.limitIncreaseSuggestion != nil,
                    unavailableReason: nil
                )
            case .unavailable(let reason):
                let msg = switch reason {
                case .deviceNotEligible: "Mac hardware is not eligible for Apple Private Cloud Compute."
                case .systemNotReady: "Private Cloud Compute is not ready (verify Apple Intelligence and iCloud+ account status)."
                @unknown default: "Private Cloud Compute is unavailable."
                }
                return PCCQuotaState(
                    isAvailable: false,
                    isApproachingLimit: approaching,
                    isLimitReached: limitReached,
                    resetDate: quota.resetDate,
                    hasLimitIncreaseSuggestion: quota.limitIncreaseSuggestion != nil,
                    unavailableReason: msg
                )
            }
        }
        #endif
        return PCCQuotaState(
            isAvailable: false,
            unavailableReason: "Apple Private Cloud Compute requires macOS 27.0+ with Apple Intelligence & iCloud+ eligibility."
        )
    }

    @MainActor
    public func presentLimitIncreaseSuggestionIfAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            let pcc = PrivateCloudComputeLanguageModel()
            if let suggestion = pcc.quotaUsage.limitIncreaseSuggestion {
                suggestion.show()
                return true
            }
        }
        #endif
        return false
    }
}

/// Native `LLMProvider` wrapping Apple's on-device `SystemLanguageModel` and `PrivateCloudComputeLanguageModel`.
public struct AppleFoundationModelProvider: LLMProvider, Sendable {
    public let providerID: String
    public let variant: AppleFoundationModelVariant
    private let inspector: any AppleFoundationModelInspector

    public init(
        variant: AppleFoundationModelVariant = .local,
        inspector: any AppleFoundationModelInspector = LiveAppleFoundationModelInspector()
    ) {
        self.variant = variant
        self.providerID = variant.providerID
        self.inspector = inspector
    }

    public func streamCompletion(request: LLMRequest) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runGeneration(request: request, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runGeneration(
        request: LLMRequest,
        continuation: AsyncThrowingStream<LLMStreamChunk, Error>.Continuation
    ) async throws {
        #if canImport(FoundationModels)
        switch variant {
        case .local:
            let status = inspector.localAvailability()
            guard status.available else {
                throw AppleFoundationModelError.modelUnavailable(
                    variant: .local,
                    reason: status.reason ?? "Model unavailable"
                )
            }
            if #available(macOS 26.0, *) {
                let model = SystemLanguageModel.default
                let session = LanguageModelSession(model: model, instructions: request.systemPrompt)
                let prompt = formatPrompt(from: request.messages, maxChars: status.contextSize * 3)
                try await streamSession(session, prompt: prompt, request: request, contextLimit: status.contextSize, continuation: continuation)
                return
            }

        case .privateCloudCompute:
            let quotaState = await inspector.pccQuotaState()
            if quotaState.isLimitReached {
                throw AppleFoundationModelError.pccQuotaLimitReached(quotaState)
            }
            guard quotaState.isAvailable else {
                throw AppleFoundationModelError.modelUnavailable(
                    variant: .privateCloudCompute,
                    reason: quotaState.unavailableReason ?? "Private Cloud Compute unavailable"
                )
            }
            if #available(macOS 27.0, *) {
                let pcc = PrivateCloudComputeLanguageModel()
                let ctxSize = (try? await pcc.contextSize) ?? AppleFoundationModelVariant.privateCloudCompute.defaultContextWindowTokens
                let session = LanguageModelSession(model: pcc, instructions: request.systemPrompt)
                let prompt = formatPrompt(from: request.messages, maxChars: ctxSize * 3)
                do {
                    try await streamSession(session, prompt: prompt, request: request, contextLimit: ctxSize, continuation: continuation)
                    return
                } catch let pccError as PrivateCloudComputeLanguageModel.Error {
                    throw mapPCCError(pccError, fallbackQuota: quotaState)
                }
            }
        }
        #endif
        throw AppleFoundationModelError.platformUnsupported(
            "\(variant.displayName) requires Apple macOS 26/27+ with Apple FoundationModels."
        )
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func streamSession(
        _ session: LanguageModelSession,
        prompt: String,
        request: LLMRequest,
        contextLimit: Int,
        continuation: AsyncThrowingStream<LLMStreamChunk, Error>.Continuation
    ) async throws {
        let options = GenerationOptions(
            temperature: request.temperature,
            maximumResponseTokens: min(request.maxTokens, contextLimit / 2)
        )
        var emittedCount = 0
        do {
            for try await snapshot in session.streamResponse(to: prompt, options: options) {
                let current = snapshot.content
                if current.count > emittedCount {
                    let delta = String(current.dropFirst(emittedCount))
                    emittedCount = current.count
                    continuation.yield(.textDelta(delta))
                }
            }
            let inputEst = max(1, (request.systemPrompt.count + prompt.count) / 4)
            let outputEst = max(1, emittedCount / 4)
            continuation.yield(.usage(inputTokens: inputEst, outputTokens: outputEst, cachedTokens: 0))
            continuation.yield(.finished(stopReason: "stop"))
        } catch let genErr as LanguageModelSession.GenerationError {
            switch genErr {
            case .exceededContextWindowSize(let ctx):
                throw AppleFoundationModelError.exceededContextWindow(limitTokens: contextLimit, detail: ctx.debugDescription)
            case .rateLimited(let ctx):
                let currentQuota = await inspector.pccQuotaState()
                if variant == .privateCloudCompute {
                    throw AppleFoundationModelError.pccQuotaLimitReached(PCCQuotaState(
                        isAvailable: false,
                        isLimitReached: true,
                        resetDate: currentQuota.resetDate,
                        hasLimitIncreaseSuggestion: currentQuota.hasLimitIncreaseSuggestion,
                        unavailableReason: ctx.debugDescription
                    ))
                }
                throw AppleFoundationModelError.generationFailed(ctx.debugDescription)
            default:
                throw AppleFoundationModelError.generationFailed(genErr.localizedDescription)
            }
        }
    }

    @available(macOS 27.0, *)
    private func mapPCCError(
        _ error: PrivateCloudComputeLanguageModel.Error,
        fallbackQuota: PCCQuotaState
    ) -> AppleFoundationModelError {
        switch error {
        case .quotaLimitReached(let info):
            let state = PCCQuotaState(
                isAvailable: false,
                isApproachingLimit: false,
                isLimitReached: true,
                resetDate: info.resetDate ?? fallbackQuota.resetDate,
                hasLimitIncreaseSuggestion: info.limitIncreaseSuggestion != nil || fallbackQuota.hasLimitIncreaseSuggestion,
                unavailableReason: info.debugDescription
            )
            return .pccQuotaLimitReached(state)
        case .networkFailure(let info):
            return .modelUnavailable(variant: .privateCloudCompute, reason: "Network failure: \(info.debugDescription)")
        case .serviceUnavailable(let info):
            return .modelUnavailable(variant: .privateCloudCompute, reason: "Service unavailable: \(info.debugDescription)")
        @unknown default:
            return .generationFailed(error.localizedDescription)
        }
    }
    #endif

    private func formatPrompt(from messages: [ConversationMessage], maxChars: Int) -> String {
        let formatted = messages.map { msg in
            "[\(msg.role.rawValue.uppercased())]\n\(msg.content)"
        }.joined(separator: "\n\n")
        if formatted.count <= maxChars { return formatted }
        return String(formatted.suffix(maxChars))
    }
}
