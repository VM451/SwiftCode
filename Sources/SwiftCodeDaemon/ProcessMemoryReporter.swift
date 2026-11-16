import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Measures current process resident set size (RSS) in megabytes for NFR-2 telemetry.
public enum ProcessMemoryReporter {
    public static func currentRSSMegabytes() -> Double {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024.0 * 1024.0)
        #else
        guard let statm = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8),
              let rssPages = statm.split(separator: " ").dropFirst().first,
              let pages = Double(rssPages) else { return 0 }
        return (pages * 4096.0) / (1024.0 * 1024.0)
        #endif
    }
}
