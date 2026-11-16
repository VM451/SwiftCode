import SwiftUI
import SwiftCodeCore

/// Single session row in the sidebar using `AppSpacing` and `AppSizes` tokens exclusively.
struct SessionRowView: View {
    let item: AgentSessionItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: item.mode == .plan ? "map" : "hammer")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: AppSizes.iconMedium, height: AppSizes.iconMedium)
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            HStack(spacing: AppSpacing.small) {
                Text(item.mode.rawValue.uppercased())
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(item.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppSpacing.rowVertical)
        .padding(.horizontal, AppSpacing.small)
        .frame(minHeight: AppSizes.heightStandard, alignment: .leading)
    }
}

#Preview("Light & Dark") {
    VStack(spacing: AppSpacing.stackMedium) {
        SessionRowView(item: AgentSessionItem(
            id: UUID(),
            title: "Refactor AuthActor",
            workspacePath: "/Repos/App",
            mode: .build,
            updatedAt: Date(),
            totalTokens: 1240,
            estimatedCostUSD: 0.02
        ))
        .environment(\.colorScheme, .light)

        SessionRowView(item: AgentSessionItem(
            id: UUID(),
            title: "Audit Seatbelt Profile",
            workspacePath: "/Repos/Core",
            mode: .plan,
            updatedAt: Date(),
            totalTokens: 540,
            estimatedCostUSD: 0.01
        ))
        .environment(\.colorScheme, .dark)
    }
    .padding(AppSpacing.card)
}
