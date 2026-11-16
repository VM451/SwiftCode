import Foundation

/// Token accounting and estimated cost for an LLM turn or session.
public struct TokenUsage: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int
    public var estimatedCostUSD: Double

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        estimatedCostUSD: Double = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.estimatedCostUSD = estimatedCostUSD
    }

    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    public mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cachedTokens += other.cachedTokens
        estimatedCostUSD += other.estimatedCostUSD
    }

    /// Estimates cost in USD using conservative per-million token defaults.
    public static func estimateCost(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int
    ) -> Double {
        let lower = model.lowercased()
        let (inRate, outRate): (Double, Double) = if lower.contains("opus") {
            (15.0, 75.0)
        } else if lower.contains("haiku") || lower.contains("mini") || lower.contains("flash") {
            (0.25, 1.25)
        } else if lower.contains("mlx") || lower.contains("ollama") || lower.contains("local") {
            (0.0, 0.0)
        } else {
            (3.0, 15.0)
        }
        let billableInput = max(0, inputTokens - cachedTokens)
        let cachedRate = inRate * 0.1
        return (Double(billableInput) * inRate + Double(cachedTokens) * cachedRate + Double(outputTokens) * outRate) / 1_000_000.0
    }
}
