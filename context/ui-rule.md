# UI Rule (Terminal ANSI TUI Only)

- SwiftCode is distributed strictly as a pure-Swift CLI & raw-`termios` ANSI TUI (`swiftcode`). No GUI `.app`, SwiftUI window, or web views exist in this repository.
- Do:
  - Keep terminal output crisp, monochrome/ANSI-accessible, and dynamically sized to terminal columns via `TerminalRawMode.terminalWidth()`.
  - Stream tokens directly with `fflush(stdout)` and show live context utilization % relative to the active model window (`4K` Local vs `32K` PCC).
  - Emit clear ANSI warnings and macOS Notification Center alerts (`PCCDesktopNotifier`) when Private Cloud Compute hits quota limits, stating remaining wait days, iCloud+ dependency, and `/model local` fallback.
- Don't:
  - Never depend on HTML, CSS, JavaScript, WebViews, or a GUI companion app.
