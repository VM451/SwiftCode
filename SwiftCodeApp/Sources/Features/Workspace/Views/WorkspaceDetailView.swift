import SwiftUI
import SwiftCodeCore

/// Center workspace column with native toolbar, Plan/Build Liquid Glass segmented control, and turn stream.
struct WorkspaceDetailView: View {
    @Bindable var viewModel: WorkspaceViewModel
    let workspaceTitle: String
    @Namespace private var composerGlassNamespace

    private var modeOptions: [SegmentedOption<AgentMode>] {
        [
            SegmentedOption(value: .plan, title: "Plan", systemImage: "map"),
            SegmentedOption(value: .build, title: "Build", systemImage: "hammer"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: AppSpacing.stackMedium) {
                    if viewModel.turns.isEmpty {
                        ContentUnavailableView(
                            "Start an Agent Session",
                            systemImage: "terminal",
                            description: Text("Plan safely in read-only mode or switch to Build to mutate files with automatic Shadow-Git checkpoints.")
                        )
                        .padding(AppSpacing.hero)
                    } else {
                        ForEach(viewModel.turns) { turn in
                            TurnMessageRowView(turn: turn)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.screenVertical)
            }

            if let pending = viewModel.pendingApproval {
                ApprovalRequestBannerView(request: pending) { resolution in
                    viewModel.resolveApproval(resolution)
                }
                .padding(.bottom, AppSpacing.small)
            }

            composerBar
        }
        .navigationTitle(workspaceTitle == "/" ? "Workspace" : workspaceTitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                LiquidGlassSegmentedPicker(
                    options: modeOptions,
                    selection: Binding(
                        get: { viewModel.selectedMode },
                        set: { viewModel.switchMode(to: $0) }
                    )
                )
            }
            ToolbarItem(placement: .status) {
                Text("\(viewModel.usage.totalTokens) tok")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.small)
            }
        }
    }

    private var composerBar: some View {
        HStack(spacing: AppSpacing.stackMedium) {
            TextField(
                viewModel.selectedMode == .plan ? "Plan architecture or inspect AST (@file:, @symbol:)..." : "Build, edit, or run swift test...",
                text: $viewModel.promptDraft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)
            .background(.regularMaterial, in: .rect(cornerRadius: AppSizes.radiusMedium))
            .onSubmit { viewModel.sendPrompt() }

            GlassEffectContainer {
                Button(action: { viewModel.sendPrompt() }) {
                    Label(viewModel.isRunning ? "Running" : "Send", systemImage: viewModel.isRunning ? "hourglass" : "arrow.up")
                        .padding(.horizontal, AppSpacing.large)
                        .frame(minHeight: AppSizes.heightStandard)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(viewModel.isRunning)
                .glassEffectUnion(id: "send", namespace: composerGlassNamespace)
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.medium)
    }
}
