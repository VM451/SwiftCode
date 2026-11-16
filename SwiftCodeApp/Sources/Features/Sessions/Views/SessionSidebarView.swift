import SwiftUI

/// Sidebar listing saved sessions with native `.searchable()` and `ContentUnavailableView`.
struct SessionSidebarView: View {
    @Bindable var viewModel: SessionsViewModel

    var body: some View {
        List(selection: $viewModel.selectedSessionID) {
            if viewModel.filteredSessions.isEmpty {
                ContentUnavailableView.search
            } else {
                ForEach(viewModel.filteredSessions) { item in
                    SessionRowView(item: item)
                        .tag(item.id)
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search sessions")
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Session", systemImage: "plus", action: {
                    viewModel.startNewSession()
                })
                .buttonStyle(.glass)
            }
        }
    }
}
