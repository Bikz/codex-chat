import Foundation

struct PerformanceSample: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let durationMS: Double
    let timestamp: Date
    let status: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        name: String,
        durationMS: Double,
        timestamp: Date = Date(),
        status: String = "ok",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.durationMS = durationMS
        self.timestamp = timestamp
        self.status = status
        self.metadata = metadata
    }
}

struct PerformanceOperationStats: Hashable, Sendable {
    let name: String
    let count: Int
    let p50MS: Double
    let p95MS: Double
    let maxMS: Double
    let lastMS: Double
    let lastAt: Date
}

struct PerformanceSnapshot: Hashable, Sendable {
    let generatedAt: Date
    let operations: [PerformanceOperationStats]
    let recent: [PerformanceSample]
}

struct PerformanceSpan: Hashable, Sendable {
    let name: String
    let startedAt: ContinuousClock.Instant
    let metadata: [String: String]
}

actor PerformanceTracer {
    static let shared = PerformanceTracer()

    private var durationsByName: [String: [Double]] = [:]
    private var lastByName: [String: (duration: Double, at: Date)] = [:]
    private var recentSamples: [PerformanceSample] = []
    private let historyLimitPerOperation = 300
    private let recentLimit = 500
    private let clock = ContinuousClock()

    func begin(name: String, metadata: [String: String] = [:]) -> PerformanceSpan {
        PerformanceSpan(name: name, startedAt: clock.now, metadata: metadata)
    }

    func end(_ span: PerformanceSpan, status: String = "ok", extraMetadata: [String: String] = [:]) {
        let duration = clock.now - span.startedAt
        let durationMS = duration.seconds * 1000
        var metadata = span.metadata
        for (key, value) in extraMetadata {
            metadata[key] = value
        }
        record(
            name: span.name,
            durationMS: durationMS,
            status: status,
            metadata: metadata
        )
    }

    @discardableResult
    nonisolated func measure<T>(
        name: String,
        metadata: [String: String] = [:],
        operation: () async throws -> T
    ) async rethrows -> T {
        let span = await begin(name: name, metadata: metadata)
        do {
            let value = try await operation()
            await end(span)
            return value
        } catch {
            await end(span, status: "error", extraMetadata: ["error": String(describing: error)])
            throw error
        }
    }

    func record(
        name: String,
        durationMS: Double,
        status: String = "ok",
        metadata: [String: String] = [:]
    ) {
        var durations = durationsByName[name, default: []]
        durations.append(durationMS)
        if durations.count > historyLimitPerOperation {
            durations.removeFirst(durations.count - historyLimitPerOperation)
        }
        durationsByName[name] = durations

        let timestamp = Date()
        lastByName[name] = (duration: durationMS, at: timestamp)
        recentSamples.append(
            PerformanceSample(
                name: name,
                durationMS: durationMS,
                timestamp: timestamp,
                status: status,
                metadata: metadata
            )
        )
        if recentSamples.count > recentLimit {
            recentSamples.removeFirst(recentSamples.count - recentLimit)
        }
    }

    func snapshot(maxRecent: Int = 80) -> PerformanceSnapshot {
        let operations: [PerformanceOperationStats] = durationsByName.compactMap { key, durations in
            guard !durations.isEmpty,
                  let last = lastByName[key]
            else {
                return nil
            }

            let sorted = durations.sorted()
            return PerformanceOperationStats(
                name: key,
                count: durations.count,
                p50MS: percentile(0.50, sortedValues: sorted),
                p95MS: percentile(0.95, sortedValues: sorted),
                maxMS: sorted.last ?? 0,
                lastMS: last.duration,
                lastAt: last.at
            )
        }
        .sorted {
            if $0.p95MS != $1.p95MS {
                return $0.p95MS > $1.p95MS
            }
            return $0.name < $1.name
        }

        let recent = Array(recentSamples.suffix(maxRecent)).reversed()
        return PerformanceSnapshot(
            generatedAt: Date(),
            operations: operations,
            recent: Array(recent)
        )
    }

    func reset() {
        durationsByName = [:]
        lastByName = [:]
        recentSamples = []
    }

    private func percentile(_ quantile: Double, sortedValues: [Double]) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let bounded = min(max(quantile, 0), 1)
        let index = Int((Double(sortedValues.count - 1) * bounded).rounded())
        return sortedValues[index]
    }
}

private extension Duration {
    var seconds: Double {
        let components = components
        return Double(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
