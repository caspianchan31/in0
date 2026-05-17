import Foundation
import Observation

enum TodoSource: String, Codable, CaseIterable {
    case manual
    case terminalSelection
    case agentStatus
    case gitHubScan
    case aiHistory
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id: UUID
    var workspaceId: UUID
    var title: String
    var note: String
    var source: TodoSource
    var isDone: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        workspaceId: UUID,
        title: String,
        note: String = "",
        source: TodoSource = .manual,
        isDone: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.note = note
        self.source = source
        self.isDone = isDone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
@Observable
final class TodoStore {
    private let fileURL: URL
    private(set) var items: [TodoItem]

    init(fileURL: URL = TodoStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.items = Self.load(from: fileURL)
    }

    func items(for workspaceId: UUID) -> [TodoItem] {
        items
            .filter { $0.workspaceId == workspaceId }
            .sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone }
                return lhs.createdAt < rhs.createdAt
            }
    }

    @discardableResult
    func add(title: String, workspaceId: UUID, source: TodoSource = .manual, note: String = "") -> TodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = TodoItem(workspaceId: workspaceId, title: trimmed, note: note, source: source)
        items.append(item)
        save()
        return item
    }

    func setDone(_ itemId: UUID, _ isDone: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].isDone = isDone
        items[idx].updatedAt = Date()
        save()
    }

    func delete(_ itemId: UUID) {
        items.removeAll { $0.id == itemId }
        save()
    }

    func clearDone(in workspaceId: UUID) {
        items.removeAll { $0.workspaceId == workspaceId && $0.isDone }
        save()
    }

    func removeWorkspace(_ workspaceId: UUID) {
        items.removeAll { $0.workspaceId == workspaceId }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("in0: failed to save todo items: \(error)")
        }
    }

    private static func load(from url: URL) -> [TodoItem] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            return []
        }
        return decoded
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("in0/plugins/todo/items.json", isDirectory: false)
    }
}
