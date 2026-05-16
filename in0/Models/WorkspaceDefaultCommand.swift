import Foundation

/// Tiny pure helper for the workspace default-command "spawn this in a
/// new surface" path. Keeps trimming + trailing-newline rules in one
/// place so `StartupCommandResolver` and any future direct call site
/// agree on what counts as an empty command.
enum WorkspaceDefaultCommand {

    /// Returns the string to type into a fresh shell on behalf of the
    /// user, or `nil` when there's nothing to send.
    ///
    /// - Trims surrounding whitespace.
    /// - Returns `nil` for nil input or for purely-whitespace input — the
    ///   surface stays at the shell's bare prompt.
    /// - Otherwise appends `\n` so the shell actually executes it instead
    ///   of leaving it on the input line.
    static func startupInput(for command: String?) -> String? {
        guard let command else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed + "\n"
    }
}
