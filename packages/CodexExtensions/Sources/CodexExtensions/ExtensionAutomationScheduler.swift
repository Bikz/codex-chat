import Foundation

public actor ExtensionAutomationScheduler {
    public typealias Handler = @Sendable (_ automation: ExtensionAutomationDefinition) async -> Bool

    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private var tasks: [String: Task<Void, Never>] = [:]
    private var schedules: [String: CronSchedule] = [:]

    public init(timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = Date.init) {
        self.timeZone = timeZone
        self.now = now
    }

    public func replaceAutomations(_ automations: [ExtensionAutomationDefinition], handler: @escaping Handler) {
        let incomingIDs = Set(automations.map(\.id))

        for (id, task) in tasks where !incomingIDs.contains(id) {
            task.cancel()
            tasks[id] = nil
            schedules[id] = nil
        }

        for automation in automations {
            guard tasks[automation.id] == nil else { continue }

            do {
                let schedule = try CronSchedule(expression: automation.schedule)
                schedules[automation.id] = schedule
                tasks[automation.id] = Task {
                    await runLoop(automation: automation, schedule: schedule, handler: handler)
                }
            } catch {
                continue
            }
        }
    }

    public func stopAll() {
        for (_, task) in tasks {
            task.cancel()
        }
        tasks.removeAll()
        schedules.removeAll()
    }

    private func runLoop(
        automation: ExtensionAutomationDefinition,
        schedule: CronSchedule,
        handler: @escaping Handler
    ) async {
        var retryAttempts = 0

        while !Task.isCancelled {
            let referenceDate = now()
            guard let nextRun = schedule.nextRun(after: referenceDate, timeZone: timeZone) else {
                return
            }

            let delaySeconds = max(0, nextRun.timeIntervalSince(referenceDate))
            let delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)

            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            if Task.isCancelled {
                return
            }

            let ok = await handler(automation)
            if ok {
                retryAttempts = 0
                continue
            }

            retryAttempts += 1
            if retryAttempts > 3 {
                retryAttempts = 0
                continue
            }

            let backoffSeconds = min(300, Int(pow(2.0, Double(retryAttempts))) * 15)
            do {
                try await Task.sleep(nanoseconds: UInt64(backoffSeconds) * 1_000_000_000)
            } catch {
                return
            }

            let retryOK = await handler(automation)
            if retryOK {
                retryAttempts = 0
            }
        }
    }
}
