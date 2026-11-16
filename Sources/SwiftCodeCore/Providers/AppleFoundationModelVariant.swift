import Foundation

/// Selectable Apple Foundation Model execution tier.
public enum AppleFoundationModelVariant: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Local on-device Apple Foundation Model (`SystemLanguageModel.default`): unlimited usage, ~4K context window.
    case local = "apple-foundation-local"
    /// Apple Private Cloud Compute (`PrivateCloudComputeLanguageModel`): ~32K context window, iCloud+-dependent quota.
    case privateCloudCompute = "apple-foundation-pcc"

    public var id: String { rawValue }

    public var providerID: String {
        switch self {
        case .local: "apple-local"
        case .privateCloudCompute: "apple-pcc"
        }
    }

    public var displayName: String {
        switch self {
        case .local: "Apple Foundation (Local)"
        case .privateCloudCompute: "Apple Private Cloud Compute"
        }
    }

    public var shortLabel: String {
        switch self {
        case .local: "Local (4K)"
        case .privateCloudCompute: "PCC (32K)"
        }
    }

    /// Default conservative context window size in tokens before runtime query.
    public var defaultContextWindowTokens: Int {
        switch self {
        case .local: 4_096
        case .privateCloudCompute: 32_768
        }
    }

    public var requiresICloudPlusCheck: Bool {
        self == .privateCloudCompute
    }

    public static func from(providerID: String, model: String) -> AppleFoundationModelVariant? {
        if model == Self.local.rawValue || providerID == "apple-local" {
            return .local
        }
        if model == Self.privateCloudCompute.rawValue || providerID == "apple-pcc" {
            return .privateCloudCompute
        }
        return nil
    }

    /// Parses CLI/TUI aliases such as `local`, `pcc`, or full identifiers.
    public static func parseUserSelection(_ raw: String) -> AppleFoundationModelVariant? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "local", "apple-local", Self.local.rawValue:
            return .local
        case "pcc", "apple-pcc", "private-cloud-compute", "privatecloudcompute", Self.privateCloudCompute.rawValue:
            return .privateCloudCompute
        default:
            return nil
        }
    }
}

/// Snapshot of Apple Private Cloud Compute availability, usage limit, reset wait time, and iCloud+ dependency.
public struct PCCQuotaState: Codable, Sendable, Equatable {
    public let isAvailable: Bool
    public let isApproachingLimit: Bool
    public let isLimitReached: Bool
    public let resetDate: Date?
    public let hasLimitIncreaseSuggestion: Bool
    public let unavailableReason: String?
    public let checkedAt: Date

    public init(
        isAvailable: Bool,
        isApproachingLimit: Bool = false,
        isLimitReached: Bool = false,
        resetDate: Date? = nil,
        hasLimitIncreaseSuggestion: Bool = false,
        unavailableReason: String? = nil,
        checkedAt: Date = Date()
    ) {
        self.isAvailable = isAvailable
        self.isApproachingLimit = isApproachingLimit
        self.isLimitReached = isLimitReached
        self.resetDate = resetDate
        self.hasLimitIncreaseSuggestion = hasLimitIncreaseSuggestion
        self.unavailableReason = unavailableReason
        self.checkedAt = checkedAt
    }

    /// Whole days remaining until Apple Private Cloud Compute resets (at least 1 day when resetDate is in the future).
    public func daysUntilReset(from referenceDate: Date = Date()) -> Int? {
        guard let resetDate else { return nil }
        let seconds = resetDate.timeIntervalSince(referenceDate)
        guard seconds > 0 else { return 0 }
        return max(1, Int(ceil(seconds / 86_400.0)))
    }

    /// Human-readable guidance covering wait days, iCloud+ dependency, and local fallback.
    public func formattedGuidance(referenceDate: Date = Date()) -> String {
        if isLimitReached {
            let waitPart: String = if let days = daysUntilReset(from: referenceDate), days > 0 {
                "Wait \(days) \(days == 1 ? "day" : "days")"
            } else {
                "Wait until your quota resets"
            }
            let datePart: String = if let resetDate {
                " (resets \(resetDate.formatted(date: .abbreviated, time: .shortened)))"
            } else {
                ""
            }
            return "Apple Private Cloud Compute hit its usage limit. \(waitPart)\(datePart) to continue using Private Cloud Compute, or check your Apple iCloud+ subscription (PCC capacity depends on your iCloud+ plan). You can switch to Apple Foundation (Local) immediately for unlimited on-device use."
        }
        if isApproachingLimit {
            return "Approaching your Apple Private Cloud Compute usage limit. Capacity depends on your Apple iCloud+ subscription; Apple Foundation (Local) remains unlimited."
        }
        if !isAvailable {
            return unavailableReason ?? "Apple Private Cloud Compute is currently unavailable on this Mac. Capacity also depends on Apple Intelligence & iCloud+ eligibility; switch to Apple Foundation (Local) to continue."
        }
        return "Apple Private Cloud Compute ready (~32K context window; quota governed by your Apple iCloud+ subscription)."
    }
}

/// Notification event emitted when Apple Private Cloud Compute approaches or hits its quota limit.
public struct PCCQuotaNotice: Codable, Sendable, Equatable {
    public let state: PCCQuotaState
    public let message: String

    public init(state: PCCQuotaState, message: String? = nil) {
        self.state = state
        self.message = message ?? state.formattedGuidance()
    }
}

/// Errors emitted by `AppleFoundationModelProvider`.
public enum AppleFoundationModelError: Error, LocalizedError, Sendable, Equatable {
    case platformUnsupported(String)
    case modelUnavailable(variant: AppleFoundationModelVariant, reason: String)
    case pccQuotaLimitReached(PCCQuotaState)
    case exceededContextWindow(limitTokens: Int, detail: String)
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .platformUnsupported(let msg):
            msg
        case .modelUnavailable(let variant, let reason):
            "\(variant.displayName) unavailable: \(reason)"
        case .pccQuotaLimitReached(let state):
            state.formattedGuidance()
        case .exceededContextWindow(let limit, let detail):
            "Exceeded Apple Foundation Model context window (\(limit) tokens): \(detail)"
        case .generationFailed(let detail):
            "Apple Foundation Model error: \(detail)"
        }
    }
}
