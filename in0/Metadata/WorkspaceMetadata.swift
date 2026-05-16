import Foundation
import Observation

/// Per-workspace derived metadata that the sidebar shows. Refreshed every
/// 5 seconds by `MetadataRefresher`. Not persisted — recomputed on launch.
struct WorkspaceMetadataSnapshot: Equatable {
    var gitBranch: String?
    var pwd: String?
    var openPRCount: Int?
    var unreadNotifications: Int?
    /// Short PR status badge text ("3 PR", "open", etc.) computed from
    /// `openPRCount`. Lives on the snapshot so views don't have to
    /// reformat the number every render.
    var prStatus: String?
    var updatedAt: Date
}

@MainActor
@Observable
final class WorkspaceMetadataStore {
    private(set) var snapshots: [UUID: WorkspaceMetadataSnapshot] = [:]

    func snapshot(for workspaceId: UUID) -> WorkspaceMetadataSnapshot? {
        snapshots[workspaceId]
    }

    func set(_ snapshot: WorkspaceMetadataSnapshot, for workspaceId: UUID) {
        snapshots[workspaceId] = snapshot
    }
}
