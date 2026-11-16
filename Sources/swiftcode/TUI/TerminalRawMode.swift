import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// POSIX raw-mode `termios` controller with terminal size lookup (`TIOCGWINSZ`) (TUI §5.1).
public final class TerminalRawMode {
    private var originalTermios = termios()
    private var isRaw = false

    public init() {}

    public func enableRawModeIfTTY() {
        guard isatty(STDIN_FILENO) != 0, !isRaw else { return }
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~UInt(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        isRaw = true
    }

    public func disableRawMode() {
        guard isRaw else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
        isRaw = false
    }

    deinit {
        disableRawMode()
    }

    /// Reads one raw character cleanly when prompting for single-key HITL approvals.
    public static func readSingleKey() -> Character? {
        guard isatty(STDIN_FILENO) != 0 else {
            return readLine()?.first
        }
        var old = termios()
        tcgetattr(STDIN_FILENO, &old)
        var raw = old
        raw.c_lflag &= ~UInt(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        defer { tcsetattr(STDIN_FILENO, TCSANOW, &old) }
        var byte: UInt8 = 0
        let count = read(STDIN_FILENO, &byte, 1)
        guard count == 1 else { return nil }
        return Character(UnicodeScalar(byte))
    }

    /// Queries terminal column/row dimensions without external curses libraries.
    public static func terminalWidth() -> Int {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0 {
            return Int(ws.ws_col)
        }
        return 100
    }
}
