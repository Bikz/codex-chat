@testable import CodexChatShared
import XCTest

final class ScheduleQueryParserTests: XCTestCase {
    func testParsesCalendarHoursQuery() {
        let result = ScheduleQueryParser.parse(
            text: "show my calendar for the next 8 hours"
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.domain, .calendar)
        XCTAssertEqual(result?.rangeHours, 8)
        XCTAssertEqual(result?.dayOffset, 0)
        XCTAssertEqual(result?.anchor, .now)
    }

    func testUsesPreferredDomainForTemporalFollowUp() {
        let result = ScheduleQueryParser.parse(
            text: "tomorrow?",
            preferredDomain: .calendar
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.domain, .calendar)
        XCTAssertEqual(result?.rangeHours, 24)
        XCTAssertEqual(result?.dayOffset, 1)
        XCTAssertEqual(result?.anchor, .dayStart)
    }

    func testUsesPreferredDomainForRangeFollowUp() {
        let result = ScheduleQueryParser.parse(
            text: "in 3 hours",
            preferredDomain: .reminders
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.domain, .reminders)
        XCTAssertEqual(result?.rangeHours, 3)
        XCTAssertEqual(result?.dayOffset, 0)
        XCTAssertEqual(result?.anchor, .now)
    }

    func testActionArgumentsIncludeTrimmedQueryText() {
        let result = ScheduleQueryParser.parse(
            text: "tomorrow?",
            preferredDomain: .calendar
        )

        guard let result else {
            XCTFail("Expected schedule parse result")
            return
        }

        let arguments = result.actionArguments(queryText: "  tomorrow?  ")

        XCTAssertEqual(arguments["rangeHours"], "24")
        XCTAssertEqual(arguments["dayOffset"], "1")
        XCTAssertEqual(arguments["anchor"], "dayStart")
        XCTAssertEqual(arguments["queryText"], "tomorrow?")
    }

    func testRejectsConversationalCalendarMentionsWithoutExplicitRequest() {
        XCTAssertNil(
            ScheduleQueryParser.parse(text: "my calendar tomorrow is packed")
        )
        XCTAssertNil(
            ScheduleQueryParser.parse(text: "calendar? i'm not ready")
        )
    }

    func testParsesExplicitCalendarRequestWithTemporalContext() {
        let result = ScheduleQueryParser.parse(
            text: "check my calendar tomorrow"
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.domain, .calendar)
        XCTAssertEqual(result?.dayOffset, 1)
        XCTAssertEqual(result?.rangeHours, 24)
    }
}
