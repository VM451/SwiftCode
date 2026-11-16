import SwiftUI
import SwiftCodeCore

/// Trailing inspector column displaying Shadow-Git diffs, Swift Charts telemetry, and MCP/VM health.
struct DiffInspectorView: View {
    @Bindable var viewModel: DiffInspectorViewModel
    let usage: TokenUsage

    private var tabOptions: [SegmentedOption<InspectorTab>] {
        [
            SegmentedOption(value: .diff, title: "Diff", systemImage: "doc.text.magnifyingglass"),
            SegmentedOption(value: .telemetry, title: "Metrics", systemImage: "chart.bar"),
            SegmentedOption(value: .mcp, title: "Sandbox", systemImage: "cpu"),
        ]
    }

    var body: some View {
        VStack(spacing: AppSpacing.stackMedium) {
            LiquidGlassSegmentedPicker(options: tabOptions, selection: $viewModel.selectedTab)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.medium)

            switch viewModel.selectedTab {
            case .diff:
                diffTabContent
            case .telemetry:
                TelemetryChartView(points: viewModel.chartPoints(usage: usage), totalCostUSD: usage.estimatedCostUSD)
                Spacer()
            case .mcp:
                sandboxAndMCPTabContent
            }
        }
        .frame(minWidth: AppSizes.widthLarge)
        .padding(.bottom, AppSpacing.screenVertical)
    }

    private var diffTabContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.stackSmall) {
            HStack(spacing: AppSpacing.small) {
                Text("Checkpoints")
                    .font(.headline)
                Spacer()
                Button("Rollback", systemImage: "arrow.uturn.backward") {
                    viewModel.rollbackToSelected()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .frame(minHeight: AppSizes.heightStandard)
                .disabled(viewModel.selectedCheckpointID == nil)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)

            if viewModel.checkpoints.isEmpty {
                Text("No Shadow-Git snapshots in this workspace yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
            } else {
                List(viewModel.checkpoints, selection: $viewModel.selectedCheckpointID) { cp in
                    VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                        Text(cp.label).font(.subheadline).lineLimit(1)
                        Text(cp.shortHash).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .tag(cp.commitHash)
                }
                .frame(maxHeight: AppSizes.heightInspectorPanel)
                .onChange(of: viewModel.selectedCheckpointID) { _, newValue in
                    if let newValue { viewModel.selectCheckpoint(newValue) }
                }
            }

            NativeDiffTextView(diffText: viewModel.diffText)
                .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: AppSizes.radiusMedium))
                .padding(.horizontal, AppSpacing.screenHorizontal)
        }
    }

    private var sandboxAndMCPTabContent: some View {
        List {
            Section("Apple Virtualization.framework") {
                if let vm = viewModel.vmReport {
                    LabeledContent("Supported", value: vm.virtualizationSupported ? "Yes" : "Unavailable")
                    LabeledContent("Kernel", value: vm.kernelFound ? "Ready" : "Missing vmlinuz")
                }
            }
            Section("Configured MCP Servers") {
                if viewModel.mcpServers.isEmpty {
                    Text("No external MCP servers configured in config.json")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.mcpServers) { srv in
                        LabeledContent(srv.name, value: srv.transport)
                    }
                }
            }
        }
    }
}
