import CodexKit
import Foundation

enum SkillReferenceParser {
    static func referencedTokens(in text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }

        let characters = Array(text)
        var tokens: [String] = []
        var seenKeys: Set<String> = []
        var index = 0

        while index < characters.count {
            let character = characters[index]
            guard character == "$" else {
                index += 1
                continue
            }

            let nextIndex = index + 1
            guard nextIndex < characters.count,
                  characters[nextIndex].isSkillReferenceTokenCharacter
            else {
                index += 1
                continue
            }

            if index > 0, characters[index - 1].isSkillReferenceTokenCharacter {
                index += 1
                continue
            }

            var endIndex = nextIndex
            while endIndex < characters.count, characters[endIndex].isSkillReferenceTokenCharacter {
                endIndex += 1
            }

            let token = String(characters[nextIndex ..< endIndex])
            let tokenKey = token.skillReferenceLookupKey
            if !tokenKey.isEmpty, seenKeys.insert(tokenKey).inserted {
                tokens.append(token)
            }
            index = endIndex
        }

        return tokens
    }
}

enum SkillReferenceResolver {
    static func runtimeSkillInputs(
        messageText: String,
        availableSkills: [AppModel.SkillListItem]
    ) -> [RuntimeSkillInput] {
        let tokens = SkillReferenceParser.referencedTokens(in: messageText)
        guard !tokens.isEmpty, !availableSkills.isEmpty else {
            return []
        }

        var skillsByLookupKey: [String: AppModel.SkillListItem] = [:]
        skillsByLookupKey.reserveCapacity(availableSkills.count * 2)
        for skillItem in availableSkills {
            for key in lookupKeys(forSkillName: skillItem.skill.name) {
                if skillsByLookupKey[key] == nil {
                    skillsByLookupKey[key] = skillItem
                }
            }
        }

        var inputs: [RuntimeSkillInput] = []
        var seenSkillIDs: Set<String> = []
        for token in tokens {
            let key = token.skillReferenceLookupKey
            guard let skillItem = skillsByLookupKey[key] else {
                continue
            }

            if seenSkillIDs.insert(skillItem.id).inserted {
                inputs.append(
                    RuntimeSkillInput(
                        name: skillItem.skill.name,
                        path: runtimePath(forSkillPath: skillItem.skill.skillPath)
                    )
                )
            }
        }

        return inputs
    }

    private static func lookupKeys(forSkillName name: String) -> Set<String> {
        let normalized = name.skillReferenceLookupKey
        guard !normalized.isEmpty else {
            return []
        }

        var keys: Set<String> = [normalized]
        if normalized.contains(" ") {
            let dashed = normalized.replacingOccurrences(
                of: #"\s+"#,
                with: "-",
                options: .regularExpression
            )
            if !dashed.isEmpty {
                keys.insert(dashed)
            }
        }
        return keys
    }

    private static func runtimePath(forSkillPath skillPath: String) -> String {
        URL(fileURLWithPath: skillPath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}

private extension Character {
    var isSkillReferenceTokenCharacter: Bool {
        isLetter || isNumber || self == "-" || self == "_"
    }
}

private extension String {
    var skillReferenceLookupKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
