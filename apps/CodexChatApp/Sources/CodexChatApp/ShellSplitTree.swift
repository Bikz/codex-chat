import Foundation

enum ShellSplitTree {
    static func findLeaf(in root: ShellSplitNode, paneID: UUID) -> ShellPaneState? {
        switch root {
        case let .leaf(pane):
            pane.id == paneID ? pane : nil
        case let .split(_, _, _, first, second):
            findLeaf(in: first, paneID: paneID) ?? findLeaf(in: second, paneID: paneID)
        }
    }

    static func replaceLeaf(in root: inout ShellSplitNode, pane: ShellPaneState) -> Bool {
        switch root {
        case let .leaf(existing):
            guard existing.id == pane.id else {
                return false
            }
            root = .leaf(pane)
            return true

        case let .split(id, axis, ratio, first, second):
            var mutableFirst = first
            if replaceLeaf(in: &mutableFirst, pane: pane) {
                root = .split(id: id, axis: axis, ratio: ratio, first: mutableFirst, second: second)
                return true
            }

            var mutableSecond = second
            if replaceLeaf(in: &mutableSecond, pane: pane) {
                root = .split(id: id, axis: axis, ratio: ratio, first: first, second: mutableSecond)
                return true
            }

            return false
        }
    }

    static func updateLeaf(
        in root: inout ShellSplitNode,
        paneID: UUID,
        mutate: (inout ShellPaneState) -> Void
    ) -> Bool {
        guard var pane = findLeaf(in: root, paneID: paneID) else {
            return false
        }
        mutate(&pane)
        return replaceLeaf(in: &root, pane: pane)
    }

    static func splitLeaf(
        in root: inout ShellSplitNode,
        paneID: UUID,
        axis: ShellSplitAxis,
        newPane: ShellPaneState
    ) -> Bool {
        switch root {
        case let .leaf(existing):
            guard existing.id == paneID else {
                return false
            }
            root = .split(
                id: UUID(),
                axis: axis,
                ratio: 0.5,
                first: .leaf(existing),
                second: .leaf(newPane)
            )
            return true

        case let .split(id, currentAxis, ratio, first, second):
            var mutableFirst = first
            if splitLeaf(in: &mutableFirst, paneID: paneID, axis: axis, newPane: newPane) {
                root = .split(id: id, axis: currentAxis, ratio: ratio, first: mutableFirst, second: second)
                return true
            }

            var mutableSecond = second
            if splitLeaf(in: &mutableSecond, paneID: paneID, axis: axis, newPane: newPane) {
                root = .split(id: id, axis: currentAxis, ratio: ratio, first: first, second: mutableSecond)
                return true
            }

            return false
        }
    }

    static func closeLeaf(in root: ShellSplitNode, paneID: UUID) -> (root: ShellSplitNode?, didClose: Bool) {
        close(node: root, paneID: paneID)
    }

    private static func close(node: ShellSplitNode, paneID: UUID) -> (root: ShellSplitNode?, didClose: Bool) {
        switch node {
        case let .leaf(pane):
            if pane.id == paneID {
                return (nil, true)
            }
            return (node, false)

        case let .split(id, axis, ratio, first, second):
            let firstResult = close(node: first, paneID: paneID)
            if firstResult.didClose {
                guard let nextFirst = firstResult.root else {
                    return (second, true)
                }
                return (.split(id: id, axis: axis, ratio: ratio, first: nextFirst, second: second), true)
            }

            let secondResult = close(node: second, paneID: paneID)
            if secondResult.didClose {
                guard let nextSecond = secondResult.root else {
                    return (first, true)
                }
                return (.split(id: id, axis: axis, ratio: ratio, first: first, second: nextSecond), true)
            }

            return (node, false)
        }
    }
}
