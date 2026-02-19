@testable import CodexComputerActions
import Foundation
import XCTest

final class CodexComputerActionsTests: XCTestCase {
    func testDesktopCleanupPreviewExecuteAndUndo() async throws {
        let root = try makeTempDirectory(prefix: "desktop-cleanup")
        let desktopURL = root.appendingPathComponent("Desktop", isDirectory: true)
        let undoURL = root.appendingPathComponent("undo", isDirectory: true)
        try FileManager.default.createDirectory(at: desktopURL, withIntermediateDirectories: true)

        let imageFile = desktopURL.appendingPathComponent("photo.png", isDirectory: false)
        let docFile = desktopURL.appendingPathComponent("notes.md", isDirectory: false)
        try Data("image".utf8).write(to: imageFile)
        try Data("doc".utf8).write(to: docFile)

        let action = DesktopCleanupAction()
        let request = ComputerActionRequest(
            runContextID: "run-1",
            arguments: [
                "desktopPath": desktopURL.path,
                "undoDirectoryPath": undoURL.path,
            ]
        )

        let preview = try await action.preview(request: request)
        XCTAssertEqual(preview.actionID, "desktop.cleanup")
        XCTAssertTrue(preview.summary.contains("Prepared"))

        let result = try await action.execute(request: request, preview: preview)
        XCTAssertTrue(result.summary.contains("Moved"))
        XCTAssertEqual(result.metadata["movedCount"], "2")

        XCTAssertFalse(FileManager.default.fileExists(atPath: imageFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: docFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: desktopURL.appendingPathComponent("Images/photo.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: desktopURL.appendingPathComponent("Documents/notes.md").path))

        let manifestPath = try XCTUnwrap(result.metadata["undoManifestPath"])
        let restored = try action.undoLastCleanup(manifestPath: manifestPath)
        XCTAssertEqual(restored, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: docFile.path))
    }

    func testCalendarTodayPreviewAndPermissionErrorMapping() async throws {
        let now = Date(timeIntervalSince1970: 1_735_660_800) // 2025-01-20 00:00:00 UTC
        let event = CalendarEvent(
            id: "evt_1",
            title: "Planning",
            calendarName: "Work",
            startAt: now.addingTimeInterval(3600),
            endAt: now.addingTimeInterval(7200),
            isAllDay: false
        )

        let source = MockCalendarSource(events: [event], error: nil)
        let action = CalendarTodayAction(eventSource: source, nowProvider: { now })
        let request = ComputerActionRequest(runContextID: "calendar-run", arguments: ["rangeHours": "24"])

        let preview = try await action.preview(request: request)
        XCTAssertEqual(preview.actionID, "calendar.today")
        XCTAssertTrue(preview.summary.contains("Found 1"))
        XCTAssertTrue(preview.detailsMarkdown.contains("Planning"))

        let execution = try await action.execute(request: request, preview: preview)
        XCTAssertTrue(execution.summary.contains("1 event"))

        let deniedAction = CalendarTodayAction(
            eventSource: MockCalendarSource(
                events: [],
                error: ComputerActionError.permissionDenied("Calendar access is denied.")
            ),
            nowProvider: { now }
        )

        do {
            _ = try await deniedAction.preview(request: request)
            XCTFail("Expected permission denied")
        } catch let error as ComputerActionError {
            guard case .permissionDenied = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testMessagesPreviewConfirmAndSend() async throws {
        let sender = MockMessagesSender()
        let action = MessagesSendAction(sender: sender)
        let request = ComputerActionRequest(
            runContextID: "msg-run",
            arguments: [
                "recipient": "+15551234567",
                "body": "Ship it",
            ]
        )

        let preview = try await action.preview(request: request)
        XCTAssertTrue(preview.summary.contains("Ready to send"))

        let sent = try await action.execute(request: request, preview: preview)
        XCTAssertEqual(sent.metadata["sent"], "true")

        let calls = await sender.calls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.recipient, "+15551234567")
        XCTAssertEqual(calls.first?.message, "Ship it")

        let changedRequest = ComputerActionRequest(
            runContextID: "msg-run",
            arguments: [
                "recipient": "+15551234567",
                "body": "Changed",
            ]
        )

        do {
            _ = try await action.execute(request: changedRequest, preview: preview)
            XCTFail("Expected changed message to require fresh preview")
        } catch let error as ComputerActionError {
            guard case .invalidArguments = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct MockCalendarSource: CalendarEventSource {
    let events: [CalendarEvent]
    let error: Error?

    func events(from _: Date, to _: Date) async throws -> [CalendarEvent] {
        if let error {
            throw error
        }
        return events
    }
}

private actor MockMessagesSender: MessagesSender {
    struct Call: Hashable {
        let message: String
        let recipient: String
    }

    private var sent: [Call] = []

    func send(message: String, to recipient: String) async throws {
        sent.append(Call(message: message, recipient: recipient))
    }

    func calls() -> [Call] {
        sent
    }
}
