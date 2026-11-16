import SwiftUI
import SwiftCodeCore

/// Floating Liquid Glass HITL approval prompt for mutating tool calls.
struct ApprovalRequestBannerView: View {
    let request: PendingApprovalItem
    let onResolve: (ApprovalResolution) -> Void
    @Namespace private var glassNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.stackMedium) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Approval Required: \(request.summary)")
                        .font(.headline)
                    Text("Risk tier: \(request.riskTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(request.diffPreview ?? request.argumentsPreview)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(6)
                .padding(AppSpacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.opacity(0.65), in: .rect(cornerRadius: AppSizes.radiusSmall))

            GlassEffectContainer {
                HStack(spacing: AppSpacing.stackSmall) {
                    Button("Allow Once") { onResolve(.allowOnce) }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .frame(minHeight: AppSizes.heightStandard)
                        .glassEffectUnion(id: "approval", namespace: glassNamespace)

                    Button("Allow Session") { onResolve(.allowForSession) }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .frame(minHeight: AppSizes.heightStandard)
                        .glassEffectUnion(id: "approval", namespace: glassNamespace)

                    Button("Deny") { onResolve(.deny("Denied in SwiftCodeApp")) }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .frame(minHeight: AppSizes.heightStandard)
                        .glassEffectUnion(id: "approval", namespace: glassNamespace)
                }
            }
        }
        .padding(AppSpacing.card)
        .glassEffect(.regular, in: .rect(cornerRadius: AppSizes.radiusLarge))
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }
}
