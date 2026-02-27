import Darwin
import Foundation

enum RuntimeConcurrencyHeuristics {
    private enum Constants {
        static let minimumWorkerCount = 2
        static let maximumDefaultWorkerCount = 12
        static let maximumFallbackWorkerCount = 8
        static let minimumPerWorkerTurnLimit = 2
        static let maximumPerWorkerTurnLimit = 8
    }

    static func detectedPerformanceCoreCount() -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.perflevel0.physicalcpu", &value, &size, nil, 0)
        guard result == 0 else {
            return 0
        }
        return max(0, Int(value))
    }

    static func recommendedRuntimePoolSize(
        performanceCoreCount: Int = detectedPerformanceCoreCount(),
        logicalCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> Int {
        let normalizedPerformanceCores = max(0, performanceCoreCount)
        if normalizedPerformanceCores > 0 {
            // Use all performance cores up to 8, then leave 1 P-core for UI responsiveness.
            let preferred = normalizedPerformanceCores <= 8
                ? normalizedPerformanceCores
                : normalizedPerformanceCores - 1
            return clamp(
                preferred,
                min: Constants.minimumWorkerCount,
                max: Constants.maximumDefaultWorkerCount
            )
        }

        let fallback = max(Constants.minimumWorkerCount, max(1, logicalCoreCount) / 2)
        return clamp(
            fallback,
            min: Constants.minimumWorkerCount,
            max: Constants.maximumFallbackWorkerCount
        )
    }

    static func recommendedPerWorkerTurnLimit(
        performanceCoreCount: Int = detectedPerformanceCoreCount(),
        logicalCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> Int {
        let normalizedPerformanceCores = max(0, performanceCoreCount)
        let normalizedLogicalCores = max(1, logicalCoreCount)

        let recommended = if normalizedPerformanceCores >= 10 || normalizedLogicalCores >= 16 {
            5
        } else if normalizedPerformanceCores >= 8 || normalizedLogicalCores >= 10 {
            4
        } else if normalizedPerformanceCores >= 4 || normalizedLogicalCores >= 6 {
            3
        } else {
            2
        }

        return clamp(
            recommended,
            min: Constants.minimumPerWorkerTurnLimit,
            max: Constants.maximumPerWorkerTurnLimit
        )
    }

    static func recommendedAdaptiveBasePerWorker(
        performanceCoreCount: Int = detectedPerformanceCoreCount(),
        logicalCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> Int {
        let normalizedPerformanceCores = max(0, performanceCoreCount)
        let normalizedLogicalCores = max(1, logicalCoreCount)

        if normalizedPerformanceCores >= 10 || normalizedLogicalCores >= 16 {
            return 5
        }
        if normalizedPerformanceCores >= 8 || normalizedLogicalCores >= 10 {
            return 4
        }
        return 3
    }

    private static func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}
