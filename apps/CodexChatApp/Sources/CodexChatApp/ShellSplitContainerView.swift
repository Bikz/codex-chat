import SwiftUI

struct ShellSplitContainerView: View {
    @ObservedObject var model: AppModel
    let projectID: UUID
    let session: ShellSessionState

    var body: some View {
        splitNodeView(sessionID: session.id, node: session.rootNode)
            .padding(8)
    }

    private func splitNodeView(sessionID: UUID, node: ShellSplitNode) -> AnyView {
        switch node {
        case let .leaf(pane):
            AnyView(
                ShellPaneChromeView(
                    pane: pane,
                    isActive: session.activePaneID == pane.id,
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
            )

        case let .split(_, axis, _, first, second):
            switch axis {
            case .horizontal:
                AnyView(
                    HSplitView {
                        splitNodeView(sessionID: sessionID, node: first)
                        splitNodeView(sessionID: sessionID, node: second)
                    }
                )
            case .vertical:
                AnyView(
                    VSplitView {
                        splitNodeView(sessionID: sessionID, node: first)
                        splitNodeView(sessionID: sessionID, node: second)
                    }
                )
            }
        }
    }
}
