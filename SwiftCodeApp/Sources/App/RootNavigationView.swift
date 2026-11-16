import SwiftUI
import SwiftCodeCore

/// Primary three-column `NavigationSplitView` coordinating Sessions, Workspace, and Diff/Telemetry Inspector.
struct RootNavigationView: View {
    let container: SwiftCodeAppContainer
    @State private var sessionsVM: SessionsViewModel
    @State private var workspaceVM: WorkspaceViewModel
    @State private var inspectorVM: DiffInspectorViewModel
    @State private var settingsVM: DaemonSettingsViewModel
    @State private var showingSettings = false

    init(container: SwiftCodeAppContainer) {
        self.container = container
        self._sessionsVM = State(initialValue: SessionsViewModel(container: container))
        self._workspaceVM = State(initialValue: WorkspaceViewModel(container: container))
        self._inspectorVM = State(initialValue: DiffInspectorViewModel(container: container))
        self._settingsVM = State(initialValue: DaemonSettingsViewModel(container: container))
    }

    var body: some View {
        NavigationSplitView {
            SessionSidebarView(viewModel: sessionsVM)
                .navigationSplitViewColumnWidth(min: AppSizes.widthSidebarMin, ideal: AppSizes.widthStandard)
        } content: {
            WorkspaceDetailView(
                viewModel: workspaceVM,
                workspaceTitle: container.workspaceRoot.lastPathComponent
            )
            .navigationSplitViewColumnWidth(min: AppSizes.widthContentMin, ideal: AppSizes.widthContentIdeal)
        } detail: {
            DiffInspectorView(viewModel: inspectorVM, usage: workspaceVM.usage)
                .navigationSplitViewColumnWidth(min: AppSizes.widthLarge, ideal: AppSizes.widthLarge)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Vault & Daemon", systemImage: "slider.horizontal.3") {
                    showingSettings = true
                }
                .buttonStyle(.glass)
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                DaemonSettingsView(viewModel: settingsVM)
            }
        }
        .onChange(of: sessionsVM.selectedSessionID, initial: true) { _, newID in
            let item = sessionsVM.sessions.first { $0.id == newID }
            workspaceVM.loadSession(id: newID, mode: item?.mode ?? .plan)
        }
        .frame(minWidth: AppSizes.widthWindowMin, minHeight: AppSizes.heightWindowMin)
    }
}
