import CodexChatCore

extension AppModel {
    func setComposerMemoryMode(_ mode: ComposerMemoryMode) {
        composerMemoryMode = mode
    }

    func effectiveComposerMemoryWriteMode(for project: ProjectRecord?) -> ProjectMemoryWriteMode {
        switch composerMemoryMode {
        case .projectDefault:
            project?.memoryWriteMode ?? .off
        case .off:
            .off
        case .summariesOnly:
            .summariesOnly
        case .summariesAndKeyFacts:
            .summariesAndKeyFacts
        }
    }

    var composerMemoryDisplayLabel: String {
        switch composerMemoryMode {
        case .projectDefault:
            "Default"
        case .off:
            "Off"
        case .summariesOnly:
            "Summary"
        case .summariesAndKeyFacts:
            "Key facts"
        }
    }

    func memoryWriteModeTitle(_ mode: ProjectMemoryWriteMode) -> String {
        switch mode {
        case .off:
            "Off"
        case .summariesOnly:
            "Summary"
        case .summariesAndKeyFacts:
            "Key facts"
        }
    }

    var composerMemoryStatusLine: String? {
        guard let project = selectedProject else {
            return nil
        }

        if composerMemoryMode == .projectDefault {
            return nil
        }

        let effective = effectiveComposerMemoryWriteMode(for: project)
        return "Memory override is active: \(memoryWriteModeTitle(effective))."
    }
}
