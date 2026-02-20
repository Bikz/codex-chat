import CodexChatUI
import SwiftUI

struct ShellSplitContainerView: View {
    @ObservedObject var model: AppModel
    let projectID: UUID
    let session: ShellSessionState

    var body: some View {
        ShellSplitNodeView(
            model: model,
            projectID: projectID,
            sessionID: session.id,
            activePaneID: session.activePaneID,
            node: session.rootNode
        )
        .padding(2)
    }
}

private struct ShellSplitNodeView: View {
    @ObservedObject var model: AppModel
    let projectID: UUID
    let sessionID: UUID
    let activePaneID: UUID?
    let node: ShellSplitNode

    var body: some View {
        switch node {
        case let .leaf(pane):
            ShellPaneChromeView(
                pane: pane,
                isActive: activePaneID == pane.id,
                onFocus: {
                    model.focusShellPane(sessionID: sessionID, paneID: pane.id)
                },
                onSplitHorizontal: {
                    model.splitShellPane(sessionID: sessionID, paneID: pane.id, axis: .horizontal)
                },
                onSplitVertical: {
                    model.splitShellPane(sessionID: sessionID, paneID: pane.id, axis: .vertical)
                },
                onRestart: {
                    model.restartShellPane(sessionID: sessionID, paneID: pane.id)
                },
                onClose: {
                    model.closeShellPane(sessionID: sessionID, paneID: pane.id)
                },
                content: {
                    ShellTerminalPaneView(
                        projectID: projectID,
                        sessionID: sessionID,
                        pane: pane,
                        onTitleChanged: model.updateShellPaneTitle,
                        onCWDChanged: model.updateShellPaneCWD,
                        onProcessTerminated: model.markShellPaneProcessTerminated
                    )
                    .id("\(pane.id.uuidString)-\(pane.launchGeneration)")
                }
            )
            .frame(minWidth: 140, minHeight: 120)

        case let .split(_, axis, _, first, second):
            switch axis {
            case .horizontal:
                HSplitView {
                    ShellSplitNodeView(
                        model: model,
                        projectID: projectID,
                        sessionID: sessionID,
                        activePaneID: activePaneID,
                        node: first
                    )
                    ShellSplitNodeView(
                        model: model,
                        projectID: projectID,
                        sessionID: sessionID,
                        activePaneID: activePaneID,
                        node: second
                    )
                }
            case .vertical:
                VSplitView {
                    ShellSplitNodeView(
                        model: model,
                        projectID: projectID,
                        sessionID: sessionID,
                        activePaneID: activePaneID,
                        node: first
                    )
                    ShellSplitNodeView(
                        model: model,
                        projectID: projectID,
                        sessionID: sessionID,
                        activePaneID: activePaneID,
                        node: second
                    )
                }
            }
        }
    }
}
