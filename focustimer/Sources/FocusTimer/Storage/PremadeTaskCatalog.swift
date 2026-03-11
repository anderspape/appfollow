import Foundation

final class PremadeTaskCatalog {
    private let resourceName = "PremadeTasks"
    private let resourceExtension = "json"
    private let subdirectory = "Library"

    func load() -> [TaskTemplate] {
        let bundle = Bundle.module
        let url = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: subdirectory
        ) ?? bundle.url(forResource: resourceName, withExtension: resourceExtension)

        guard let url else {
            return []
        }

        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TaskTemplate].self, from: data)
        else {
            return []
        }

        return normalize(decoded)
    }

    private func normalize(_ templates: [TaskTemplate]) -> [TaskTemplate] {
        var usedPremadeIDs = Set<String>()

        return templates.enumerated().compactMap { index, template in
            guard let categoryName = template.resolvedCategoryName else { return nil }

            let candidateID = sanitizedPremadeID(template.premadeTemplateID)
                ?? "premade-\(slug(categoryName))-\(index + 1)"
            let premadeID = makeUnique(candidateID, usedIDs: &usedPremadeIDs)

            return TaskTemplate(
                id: template.id,
                title: template.title,
                emoji: template.emoji,
                accentHex: template.accentHex,
                focusMinutes: template.focusMinutes,
                subTasks: template.subTasks.map { task in
                    FocusTask(
                        id: task.id,
                        emoji: task.emoji,
                        title: task.title,
                        durationMinutes: task.durationMinutes,
                        accentHex: task.accentHex,
                        isDone: false
                    )
                },
                subTaskTimersEnabled: template.subTaskTimersEnabled,
                categoryName: categoryName,
                source: .premade,
                premadeTemplateID: premadeID,
                createdAt: template.createdAt,
                updatedAt: template.updatedAt
            )
        }
    }

    private func sanitizedPremadeID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: " ", with: "-")
    }

    private func makeUnique(_ candidate: String, usedIDs: inout Set<String>) -> String {
        var unique = candidate
        var suffix = 2
        while usedIDs.contains(unique) {
            unique = "\(candidate)-\(suffix)"
            suffix += 1
        }
        usedIDs.insert(unique)
        return unique
    }

    private func slug(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}
