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

    func hasSameDisplayContent(as other: WorkspaceMetadataSnapshot) -> Bool {
        gitBranch == other.gitBranch
            && pwd == other.pwd
            && openPRCount == other.openPRCount
            && unreadNotifications == other.unreadNotifications
            && prStatus == other.prStatus
    }
}

@MainActor
@Observable
final class WorkspaceMetadataStore {
    private(set) var snapshots: [UUID: WorkspaceMetadataSnapshot] = [:]

    func snapshot(for workspaceId: UUID) -> WorkspaceMetadataSnapshot? {
        snapshots[workspaceId]
    }

    func set(_ snapshot: WorkspaceMetadataSnapshot, for workspaceId: UUID) {
        if let current = snapshots[workspaceId],
           snapshot.hasSameDisplayContent(as: current) {
            return
        }
        snapshots[workspaceId] = snapshot
    }

    func set(_ nextSnapshots: [UUID: WorkspaceMetadataSnapshot]) {
        var next = snapshots
        var changed = false

        for (workspaceId, snapshot) in nextSnapshots {
            if let current = next[workspaceId],
               snapshot.hasSameDisplayContent(as: current) {
                continue
            }
            next[workspaceId] = snapshot
            changed = true
        }

        if changed {
            snapshots = next
        }
    }
}
