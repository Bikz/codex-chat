import Foundation
import os

enum RuntimeConcurrencySignpost {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.codexchat.app",
        category: "RuntimeConcurrency"
    )

    static func makeID() -> OSSignpostID {
        OSSignpostID(log: log)
    }

    static func begin(_ name: StaticString, id: OSSignpostID, detail: String) {
        os_signpost(.begin, log: log, name: name, signpostID: id, "%{public}s", detail)
    }

    static func end(_ name: StaticString, id: OSSignpostID, detail: String) {
        os_signpost(.end, log: log, name: name, signpostID: id, "%{public}s", detail)
    }
}
