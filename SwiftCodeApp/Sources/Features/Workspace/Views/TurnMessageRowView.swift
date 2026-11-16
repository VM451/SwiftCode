import SwiftUI

/// Renders a single conversation message bubble inside the workspace scroll stream.
struct TurnMessageRowView: View {
    let turn: WorkspaceTurnItem

    private var isUser: Bool { turn.role == "user" }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.stackSmall) {
            HStack(spacing: AppSpacing.small) {
                Label(
                    isUser ? "You" : "SwiftCode",
                    systemImage: isUser ? "person.circle" : "sparkles"
                )
                .font(.subheadline)
                .bold()
                .foregroundStyle(isUser ? Color.accentColor : Color.primary)
                Spacer()
                Text(turn.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let toolSummary = turn.toolSummary, !toolSummary.isEmpty {
                Text(toolSummary)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(AppSpacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: AppSizes.radiusSmall))
            }

            if !turn.content.isEmpty {
                Text(formattedMarkdown(turn.content))
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppSpacing.card)
        .background(
            isUser ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.regularMaterial),
            in: .rect(cornerRadius: AppSizes.radiusMedium)
        )
    }

    private func formattedMarkdown(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
    }
}

#Preview("Light & Dark") {
    VStack(spacing: AppSpacing.stackMedium) {
        TurnMessageRowView(turn: WorkspaceTurnItem(
            id: UUID(),
            role: "user",
            content: "Refactor ProviderRegistry for strict concurrency.",
            toolSummary: nil,
            createdAt: Date()
        ))
        .environment(\.colorScheme, .light)

        TurnMessageRowView(turn: WorkspaceTurnItem(
            id: UUID(),
            role: "assistant",
            content: "Inspected AST symbols and verified zero Sendable warnings.",
            toolSummary: "✓ astOutline (4ms)",
            createdAt: Date()
        ))
        .environment(\.colorScheme, .dark)
    }
    .padding(AppSpacing.screenHorizontal)
}
