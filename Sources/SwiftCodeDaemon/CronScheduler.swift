import Foundation

/// Standard 5-field cron expression parser (`minute hour day month weekday`) (FR-8.1).
public struct CronExpression: Sendable, Equatable {
    public let rawValue: String
    private let minutes: Set<Int>
    private let hours: Set<Int>
    private let days: Set<Int>
    private let months: Set<Int>
    private let weekdays: Set<Int>

    public init?(_ expression: String) {
        let fields = expression.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 5,
              let minSet = Self.parseField(fields[0], range: 0...59),
              let hrSet = Self.parseField(fields[1], range: 0...23),
              let daySet = Self.parseField(fields[2], range: 1...31),
              let monSet = Self.parseField(fields[3], range: 1...12),
              let dowSet = Self.parseField(fields[4], range: 0...6) else {
            return nil
        }
        self.rawValue = expression
        self.minutes = minSet
        self.hours = hrSet
        self.days = daySet
        self.months = monSet
        self.weekdays = dowSet
    }

    public func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
        let comps = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        guard let minute = comps.minute,
              let hour = comps.hour,
              let day = comps.day,
              let month = comps.month,
              let weekday = comps.weekday else { return false }
        let cronWeekday = weekday - 1 // Calendar Sunday=1..Saturday=7 -> Cron 0..6
        return minutes.contains(minute)
            && hours.contains(hour)
            && days.contains(day)
            && months.contains(month)
            && weekdays.contains(cronWeekday)
    }

    private static func parseField(_ token: String, range: ClosedRange<Int>) -> Set<Int>? {
        var result: Set<Int> = []
        for part in token.split(separator: ",") {
            let s = String(part)
            if s == "*" {
                result.formUnion(range)
            } else if s.hasPrefix("*/"), let step = Int(s.dropFirst(2)), step > 0 {
                var val = range.lowerBound
                while val <= range.upperBound {
                    result.insert(val)
                    val += step
                }
            } else if s.contains("-") {
                let bounds = s.split(separator: "-").compactMap { Int($0) }
                guard bounds.count == 2, bounds[0] <= bounds[1],
                      range.contains(bounds[0]), range.contains(bounds[1]) else { return nil }
                result.formUnion(bounds[0]...bounds[1])
            } else if let exact = Int(s), range.contains(exact) {
                result.insert(exact)
            } else {
                return nil
            }
        }
        return result.isEmpty ? nil : result
    }
}

/// Scheduled autonomous background job definition.
public struct CronJob: Sendable, Identifiable {
    public let id: String
    public let schedule: CronExpression
    public let task: InboundAgentTask

    public init(id: String, schedule: CronExpression, task: InboundAgentTask) {
        self.id = id
        self.schedule = schedule
        self.task = task
    }
}

/// Runs scheduled cron tasks cooperatively inside `SwiftCodeDaemon`.
public actor CronScheduler {
    private var jobs: [CronJob] = []
    private var lastMinuteKey: String = ""
    private var runnerTask: Task<Void, Never>?

    public init(jobs: [CronJob] = []) {
        self.jobs = jobs
    }

    public func register(_ job: CronJob) {
        jobs.append(job)
    }

    public func evaluate(at date: Date, dispatcher: DaemonTaskDispatcher) async -> [String] {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let key = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)-\(comps.hour ?? 0)-\(comps.minute ?? 0)"
        guard key != lastMinuteKey else { return [] }
        lastMinuteKey = key

        var triggered: [String] = []
        for job in jobs where job.schedule.matches(date) {
            triggered.append(job.id)
            _ = await dispatcher(job.task)
        }
        return triggered
    }

    public func start(dispatcher: @escaping DaemonTaskDispatcher) {
        guard runnerTask == nil else { return }
        runnerTask = Task {
            while !Task.isCancelled {
                _ = await self.evaluate(at: Date(), dispatcher: dispatcher)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    public func stop() {
        runnerTask?.cancel()
        runnerTask = nil
    }
}
