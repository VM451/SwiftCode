# UI Rule

- Do:
  - Target macOS 27.0+ with 2026 Liquid Glass (`.buttonStyle(.glass)`, `.glassEffect(..., in:)`, `GlassEffectContainer` + `glassEffectUnion`, `ConcentricRectangle`).
  - Use strict MVVM folder-by-feature (`Features/<Feature>/{Views,ViewModels,Models,Tests}`).
  - Host titles and actions in native `.toolbar` (`ToolbarItem`, `ToolbarItemGroup`, `.navigationTitle`).
  - Use `LiquidGlassSegmentedPicker` (`NSSegmentedControl` with `role = .tabs`, `borderShape = .capsule`, `.controlSize(.extraLarge)`) for Plan/Build and inspector mode switchers; ensure `LC_BUILD_VERSION` `sdk >= 26.0`.
  - Support both Light and Dark mode using dynamic semantic colors and `Assets.xcassets/AccentColor`.
- Don't:
  - Never use 2013 blur (`UIVisualEffectView`, `.blur()`, `.fill(.ultraThinMaterial)` as fake glass).
  - Never nest glass inside glass.
  - Never use numeric `.frame(...)`, `.padding(...)`, or `cornerRadius:` literals; use `AppSpacing` and `AppSizes` tokens only.
  - Never create custom `HStack` top navigation headers or custom `Capsule()` segmented switchers.
