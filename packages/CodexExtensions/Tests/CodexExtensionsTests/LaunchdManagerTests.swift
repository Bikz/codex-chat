@testable import CodexExtensions
import Foundation
import XCTest

final class LaunchdManagerTests: XCTestCase {
    func testPlistDataClampsStartIntervalAndIncludesOptionalFields() throws {
        let manager = LaunchdManager(commandRunner: { _ in "" })
        let spec = LaunchdJobSpec(
            label: "com.codexchat.test",
            programArguments: ["/usr/bin/env", "echo", "hello"],
            workingDirectory: "/tmp/project",
            standardOutPath: "/tmp/out.log",
            standardErrorPath: "/tmp/err.log",
            schedule: .interval(seconds: 5)
        )

        let data = try manager.plistData(for: spec)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dictionary = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(dictionary["Label"] as? String, "com.codexchat.test")
        XCTAssertEqual(dictionary["StartInterval"] as? Int, 60)
        XCTAssertEqual(dictionary["WorkingDirectory"] as? String, "/tmp/project")
        XCTAssertEqual(dictionary["StandardOutPath"] as? String, "/tmp/out.log")
        XCTAssertEqual(dictionary["StandardErrorPath"] as? String, "/tmp/err.log")
    }

    func testWritePlistPersistsXMLPlist() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexextensions-launchd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = LaunchdManager(commandRunner: { _ in "" })
        let spec = LaunchdJobSpec(
            label: "com.codexchat.persist",
            programArguments: ["/usr/bin/true"],
            schedule: .interval(seconds: 120)
        )
        let plistURL = try manager.writePlist(spec: spec, directoryURL: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))

        let data = try Data(contentsOf: plistURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dictionary = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(dictionary["Label"] as? String, "com.codexchat.persist")
    }

    func testBootstrapAndBootoutDelegateToCommandRunner() throws {
        final class InvocationLog: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var invocations: [[String]] = []

            func append(_ invocation: [String]) {
                lock.lock()
                invocations.append(invocation)
                lock.unlock()
            }
        }

        let log = InvocationLog()
        let manager = LaunchdManager(commandRunner: { arguments in
            log.append(arguments)
            return ""
        })

        try manager.bootstrap(plistURL: URL(fileURLWithPath: "/tmp/test.plist"), uid: 501)
        try manager.bootout(label: "com.codexchat.test", uid: 501)

        XCTAssertEqual(log.invocations.count, 2)
        XCTAssertEqual(log.invocations[0], ["bootstrap", "gui/501", "/tmp/test.plist"])
        XCTAssertEqual(log.invocations[1], ["bootout", "gui/501/com.codexchat.test"])
    }

    func testBootstrapPropagatesLaunchctlFailure() {
        let manager = LaunchdManager(commandRunner: { arguments in
            throw LaunchdManagerError.commandFailed("launchctl \(arguments.joined(separator: " ")) failed")
        })

        XCTAssertThrowsError(
            try manager.bootstrap(plistURL: URL(fileURLWithPath: "/tmp/fail.plist"), uid: 501)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("launchctl bootstrap"))
        }
    }

    func testPlistDataEncodesCalendarScheduleAsStartCalendarInterval() throws {
        let manager = LaunchdManager(commandRunner: { _ in "" })
        let spec = LaunchdJobSpec(
            label: "com.codexchat.calendar",
            programArguments: ["/usr/bin/true"],
            schedule: .calendar([
                LaunchdCalendarInterval(minute: 30, hour: 9, weekday: 1),
                LaunchdCalendarInterval(minute: 30, hour: 9, weekday: 3),
            ])
        )

        let data = try manager.plistData(for: spec)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dictionary = try XCTUnwrap(object as? [String: Any])
        let calendarIntervals = try XCTUnwrap(dictionary["StartCalendarInterval"] as? [[String: Int]])

        XCTAssertNil(dictionary["StartInterval"])
        XCTAssertEqual(
            calendarIntervals,
            [
                ["Minute": 30, "Hour": 9, "Weekday": 1],
                ["Minute": 30, "Hour": 9, "Weekday": 3],
            ]
        )
    }

    func testCronScheduleBuildsCalendarIntervalsForWeekdaySchedules() throws {
        let schedule = try CronSchedule(expression: "30 9 * * 1,3,5")

        XCTAssertNil(schedule.fixedLaunchdIntervalSeconds())
        XCTAssertEqual(
            schedule.launchdCalendarIntervals(),
            [
                LaunchdCalendarInterval(minute: 30, hour: 9, weekday: 1),
                LaunchdCalendarInterval(minute: 30, hour: 9, weekday: 3),
                LaunchdCalendarInterval(minute: 30, hour: 9, weekday: 5),
            ]
        )
    }
}
