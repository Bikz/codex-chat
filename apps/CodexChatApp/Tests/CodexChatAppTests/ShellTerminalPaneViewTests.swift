import AppKit
@testable import CodexChatShared
import SwiftTerm
import XCTest

@MainActor
final class ShellTerminalPaneViewTests: XCTestCase {
    private final class AsyncTitleInvoker: NSObject {
        let coordinator: ShellTerminalPaneView.Coordinator
        let source: LocalProcessTerminalView
        let signal: DispatchSemaphore

        init(
            coordinator: ShellTerminalPaneView.Coordinator,
            source: LocalProcessTerminalView,
            signal: DispatchSemaphore
        ) {
            self.coordinator = coordinator
            self.source = source
            self.signal = signal
        }

        @objc
        func invoke() {
            coordinator.setTerminalTitle(source: source, title: "Old Pane Title")
            signal.signal()
        }
    }

    func testCoordinatorDeduplicatesTitleAndDirectoryUpdates() {
        let projectID = UUID()
        let sessionID = UUID()
        let paneID = UUID()
        var titles: [String] = []
        var directories: [String] = []

        let coordinator = ShellTerminalPaneView.Coordinator(
            projectID: projectID,
            sessionID: sessionID,
            paneID: paneID,
            onTitleChanged: { _, _, _, title in
                titles.append(title)
            },
            onCWDChanged: { _, _, _, directory in
                directories.append(directory)
            },
            onProcessTerminated: { _, _, _, _ in }
        )

        let source = LocalProcessTerminalView(frame: .zero)
        coordinator.setTerminalTitle(source: source, title: "Shell")
        coordinator.setTerminalTitle(source: source, title: "Shell")
        coordinator.setTerminalTitle(source: source, title: "Build")

        coordinator.hostCurrentDirectoryUpdate(source: source, directory: "file:///tmp/workspace")
        coordinator.hostCurrentDirectoryUpdate(source: source, directory: "file:///tmp/workspace")
        coordinator.hostCurrentDirectoryUpdate(source: source, directory: "/tmp/other")

        XCTAssertEqual(titles, ["Shell", "Build"])
        XCTAssertEqual(directories, ["/tmp/workspace", "/tmp/other"])
    }

    func testCoordinatorDeduplicatesDuplicateTerminationEvents() {
        let projectID = UUID()
        let sessionID = UUID()
        let paneID = UUID()
        var exitCodes: [Int32?] = []

        let coordinator = ShellTerminalPaneView.Coordinator(
            projectID: projectID,
            sessionID: sessionID,
            paneID: paneID,
            onTitleChanged: { _, _, _, _ in },
            onCWDChanged: { _, _, _, _ in },
            onProcessTerminated: { _, _, _, exitCode in
                exitCodes.append(exitCode)
            }
        )

        let source = LocalProcessTerminalView(frame: .zero)
        coordinator.processTerminated(source: source, exitCode: 1)
        coordinator.processTerminated(source: source, exitCode: 1)
        coordinator.processTerminated(source: source, exitCode: nil)

        XCTAssertEqual(exitCodes.count, 2)
        XCTAssertEqual(exitCodes[0], 1)
        XCTAssertNil(exitCodes[1])
    }

    func testCoordinatorDropsStaleAsyncTitleUpdateAfterPaneIDChanges() {
        let projectID = UUID()
        let sessionID = UUID()
        let paneID = UUID()
        var deliveredTitles: [String] = []

        let coordinator = ShellTerminalPaneView.Coordinator(
            projectID: projectID,
            sessionID: sessionID,
            paneID: paneID,
            onTitleChanged: { _, _, _, title in
                deliveredTitles.append(title)
            },
            onCWDChanged: { _, _, _, _ in },
            onProcessTerminated: { _, _, _, _ in }
        )

        let source = LocalProcessTerminalView(frame: .zero)
        let scheduled = DispatchSemaphore(value: 0)
        let invoker = AsyncTitleInvoker(
            coordinator: coordinator,
            source: source,
            signal: scheduled
        )
        invoker.performSelector(inBackground: #selector(AsyncTitleInvoker.invoke), with: nil)

        XCTAssertEqual(scheduled.wait(timeout: .now() + 1), .success)
        coordinator.paneID = UUID()

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(deliveredTitles.isEmpty)
    }
}
