import Foundation

@MainActor
@Observable
final class TerminalSearchStore {
    private(set) var isPresented = false
    private(set) var terminalId: UUID?
    var query = ""
    private(set) var total: Int?
    private(set) var selected: Int?

    func open(for terminalId: UUID?, initialQuery: String? = nil) {
        self.terminalId = terminalId
        if let initialQuery {
            query = initialQuery
        }
        isPresented = true
        total = nil
        selected = nil
        if let terminalId {
            GhosttyTerminalView.performSearch(query, terminalId: terminalId)
        }
    }

    func close() {
        if let terminalId {
            GhosttyTerminalView.endSearch(terminalId: terminalId)
        }
        isPresented = false
        terminalId = nil
        query = ""
        total = nil
        selected = nil
    }

    func setFocusedTerminal(_ id: UUID?) {
        terminalId = id
        guard isPresented, let id else { return }
        GhosttyTerminalView.performSearch(query, terminalId: id)
    }

    func updateQuery(_ newValue: String) {
        query = newValue
        total = nil
        selected = nil
        guard isPresented, let terminalId else { return }
        GhosttyTerminalView.performSearch(newValue, terminalId: terminalId)
    }

    func next() {
        guard isPresented, let terminalId else { return }
        GhosttyTerminalView.navigateSearch(.next, terminalId: terminalId)
    }

    func previous() {
        guard isPresented, let terminalId else { return }
        GhosttyTerminalView.navigateSearch(.previous, terminalId: terminalId)
    }

    func applyStartSearch(terminalId: UUID, needle: String?) {
        open(for: terminalId, initialQuery: needle ?? query)
    }

    func applyEndSearch(terminalId: UUID) {
        guard self.terminalId == terminalId else { return }
        isPresented = false
        self.terminalId = nil
        query = ""
        total = nil
        selected = nil
    }

    func applyTotal(_ total: Int, terminalId: UUID) {
        guard self.terminalId == terminalId else { return }
        self.total = max(total, 0)
    }

    func applySelected(_ selected: Int, terminalId: UUID) {
        guard self.terminalId == terminalId else { return }
        self.selected = selected >= 0 ? selected + 1 : nil
    }
}
