import AppKit
import SwiftUI

/// Segment option descriptor for `LiquidGlassSegmentedPicker`.
struct SegmentedOption<Value: Hashable>: Equatable {
    let value: Value
    let title: String
    let systemImage: String?
}

/// Native macOS 27 Liquid Glass segmented control backed by `NSSegmentedControl` (`role = .tabs`, `.capsule`, `.extraLarge`).
struct LiquidGlassSegmentedPicker<Value: Hashable>: NSViewRepresentable {
    let options: [SegmentedOption<Value>]
    @Binding var selection: Value

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, options: options)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.role = .tabs
        control.borderShape = .capsule
        control.controlSize = .extraLarge
        control.trackingMode = .selectOne
        control.segmentDistribution = .fit
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectionChanged(_:))
        configureSegments(on: control, coordinator: context.coordinator)
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        nsView.controlSize = .extraLarge
        nsView.role = .tabs
        nsView.borderShape = .capsule
        if context.coordinator.options != options {
            context.coordinator.options = options
            configureSegments(on: nsView, coordinator: context.coordinator)
        }
        if let targetIdx = options.firstIndex(where: { $0.value == selection }),
           nsView.selectedSegment != targetIdx {
            nsView.selectedSegment = targetIdx
        }
    }

    private func configureSegments(on control: NSSegmentedControl, coordinator: Coordinator) {
        control.segmentCount = options.count
        for (idx, option) in options.enumerated() {
            control.setLabel(option.title, forSegment: idx)
            if let symbol = option.systemImage,
               let image = NSImage(systemSymbolName: symbol, accessibilityDescription: option.title) {
                control.setImage(image, forSegment: idx)
                control.setImageScaling(.scaleProportionallyDown, forSegment: idx)
            }
        }
        if let idx = options.firstIndex(where: { $0.value == selection }) {
            control.selectedSegment = idx
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var options: [SegmentedOption<Value>]

        init(selection: Binding<Value>, options: [SegmentedOption<Value>]) {
            self.selection = selection
            self.options = options
        }

        @MainActor @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let idx = sender.selectedSegment
            guard options.indices.contains(idx) else { return }
            selection.wrappedValue = options[idx].value
        }
    }
}
