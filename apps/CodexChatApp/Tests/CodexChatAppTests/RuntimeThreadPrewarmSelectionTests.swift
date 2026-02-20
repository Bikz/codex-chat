import CodexChatCore
@testable import CodexChatShared
import Foundation
import XCTest

@MainActor
final class RuntimeThreadPrewarmSelectionTests: XCTestCase {
    func testTargetSelectionLimitsToFourAndKeepsPrimaryFirst() {
        let project = ProjectRecord(name: "Project", path: "/tmp/project", trustState: .trusted)
        let primary = ThreadRecord(projectId: project.id, title: "Primary")
        let siblingOne = ThreadRecord(projectId: project.id, title: "Sibling One")
        let siblingTwo = ThreadRecord(projectId: project.id, title: "Sibling Two")
        let siblingThree = ThreadRecord(projectId: project.id, title: "Sibling Three")
        let siblingFour = ThreadRecord(projectId: project.id, title: "Sibling Four")

        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id
        model.selectedThreadID = primary.id
        model.threadsState = .loaded([siblingOne, primary, siblingTwo, siblingThree, siblingFour])

        let targets = model.runtimeThreadPrewarmTargetThreadIDs(primaryThreadID: primary.id)
        XCTAssertEqual(targets.count, 4)
        XCTAssertEqual(targets.first, primary.id)
        XCTAssertEqual(Set(targets).count, 4)
    }

    func testTargetSelectionKeepsArchivedPrimaryButSkipsArchivedSiblings() {
        let project = ProjectRecord(name: "Project", path: "/tmp/project", trustState: .trusted)
        let archivedPrimary = ThreadRecord(
            projectId: project.id,
            title: "Archived Primary",
            archivedAt: Date()
        )
        let archivedSibling = ThreadRecord(
            projectId: project.id,
            title: "Archived Sibling",
            archivedAt: Date()
        )
        let activeSiblingOne = ThreadRecord(projectId: project.id, title: "Active One")
        let activeSiblingTwo = ThreadRecord(projectId: project.id, title: "Active Two")

        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id
        model.selectedThreadID = archivedPrimary.id
        model.threadsState = .loaded([archivedSibling, activeSiblingOne, activeSiblingTwo])

        let targets = model.runtimeThreadPrewarmTargetThreadIDs(primaryThreadID: archivedPrimary.id)
        XCTAssertTrue(targets.contains(archivedPrimary.id))
        XCTAssertFalse(targets.contains(archivedSibling.id))
        XCTAssertEqual(targets.count, 3)
    }

    func testTargetSelectionUsesGeneralThreadSourceForGeneralProject() {
        let generalProject = ProjectRecord(
            name: "General",
            path: "/tmp/general",
            isGeneralProject: true,
            trustState: .trusted
        )
        let namedProject = ProjectRecord(name: "Named", path: "/tmp/named", trustState: .trusted)
        let generalPrimary = ThreadRecord(projectId: generalProject.id, title: "General Primary")
        let generalSibling = ThreadRecord(projectId: generalProject.id, title: "General Sibling")
        let namedSibling = ThreadRecord(projectId: namedProject.id, title: "Named Sibling")

        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.projectsState = .loaded([generalProject, namedProject])
        model.selectedProjectID = generalProject.id
        model.selectedThreadID = generalPrimary.id
        model.generalThreadsState = .loaded([generalPrimary, generalSibling])
        model.threadsState = .loaded([namedSibling])

        let targets = model.runtimeThreadPrewarmTargetThreadIDs(primaryThreadID: generalPrimary.id)
        XCTAssertEqual(targets.first, generalPrimary.id)
        XCTAssertTrue(targets.contains(generalSibling.id))
        XCTAssertFalse(targets.contains(namedSibling.id))
    }
}
