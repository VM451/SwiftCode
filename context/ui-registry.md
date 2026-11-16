# UI Registry

## LiquidGlassSegmentedPicker
- Where: `SwiftCodeApp/Sources/Design/LiquidGlassSegmentedPicker.swift`
- Pattern: `NSViewRepresentable` wrapping `NSSegmentedControl` (`role = .tabs`, `borderShape = .capsule`, `.controlSize(.extraLarge)`). Used for Plan/Build switcher and Inspector tabs.

## NativeDiffTextView
- Where: `SwiftCodeApp/Sources/Features/DiffInspector/Views/NativeDiffTextView.swift`
- Pattern: `NSViewRepresentable` wrapping scrollable `NSTextView` with monospaced font and dynamic green/red diff line attribution for Light + Dark modes.
