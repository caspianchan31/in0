@preconcurrency import AppKit

/// AppKit container that hosts the tab bar + the active tab's split pane
/// for a single workspace. Owned by TabBridge.
@MainActor
final class TabContentView: NSView {
    var theme: AppTheme {
        didSet {
            needsDisplay = true
            tabBar.theme = theme
        }
    }

    private let tabBar: TabBarView
    private let paneContainer = NSView()
    private let cache = SurfaceCache()

    private var workspace: Workspace?
    private var windowObserver: NSObjectProtocol?

    /// Active tab → SplitPaneView. Kept across switches so divider drag state
    /// (and the underlying ghostty surfaces, via the shared cache) survive.
    private var paneCache: [UUID: SplitPaneView] = [:]

    var onAddTab: (() -> Void)?
    var onSplitVertical: (() -> Void)?
    var onSplitHorizontal: (() -> Void)?
    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onCloseOtherTabs: ((UUID) -> Void)?
    var onCloseTabsToRight: ((UUID) -> Void)?
    var onRatioChange: ((_ tabId: UUID, _ splitId: UUID, _ ratio: Double) -> Void)?
    var onFocusTerminal: ((_ tabId: UUID, _ terminalId: UUID) -> Void)?
    var onRenameTab: ((_ tabId: UUID, _ newTitle: String) -> Void)?
    var onReorderTabs: ((_ from: Int, _ to: Int) -> Void)?
    var onQuickAction: ((QuickActionId) -> Void)?

    func applyQuickActions(_ descriptors: [QuickActionDescriptor]) {
        tabBar.applyQuickActions(descriptors)
    }
    var onTabDropOnPane: ((_ droppedTabId: UUID, _ ontoTabId: UUID, _ ontoTerminalId: UUID, _ edge: NSRectEdge) -> Void)?

    init(theme: AppTheme) {
        self.theme = theme
        self.tabBar = TabBarView(theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        setup()
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }
        guard let window else { return }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.focusCurrentTerminal()
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.focusCurrentTerminal()
        }
    }

    private func setup() {
        addSubview(tabBar)
        addSubview(paneContainer)
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.wantsLayer = true

        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: topAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: DesignTokens.Layout.tabBarHeight),

            paneContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            paneContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            paneContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            paneContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        tabBar.onAdd = { [weak self] in self?.onAddTab?() }
        tabBar.onSplitVertical = { [weak self] in self?.onSplitVertical?() }
        tabBar.onSplitHorizontal = { [weak self] in self?.onSplitHorizontal?() }
        tabBar.onSelect = { [weak self] id in self?.onSelectTab?(id) }
        tabBar.onClose = { [weak self] id in self?.onCloseTab?(id) }
        tabBar.onCloseOthers = { [weak self] id in self?.onCloseOtherTabs?(id) }
        tabBar.onCloseToRight = { [weak self] id in self?.onCloseTabsToRight?(id) }
        tabBar.onRename = { [weak self] id, name in self?.onRenameTab?(id, name) }
        tabBar.onReorder = { [weak self] from, to in self?.onReorderTabs?(from, to) }
        tabBar.onQuickAction = { [weak self] action in self?.onQuickAction?(action) }
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.canvasNS.setFill()
        bounds.fill()
    }

    /// Render `workspace`. Reuses cached pane views per tab id; reaps any
    /// surfaces that no longer appear in the workspace's full layout set.
    func apply(workspace: Workspace) {
        self.workspace = workspace
        tabBar.apply(tabs: workspace.tabs, selected: workspace.selectedTabId)

        // Reap surfaces & pane views for tabs no longer present.
        let liveTabIds = Set(workspace.tabs.map { $0.id })
        for tabId in paneCache.keys where !liveTabIds.contains(tabId) {
            paneCache[tabId]?.removeFromSuperview()
            paneCache.removeValue(forKey: tabId)
        }
        let allLeafIds = Set(workspace.tabs.flatMap { $0.layout.allTerminalIds() })
        cache.reapMissing(aliveIds: allLeafIds)

        // Mount the selected tab.
        guard let selId = workspace.selectedTabId,
              let tab = workspace.tabs.first(where: { $0.id == selId }) else {
            paneContainer.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        let pane: SplitPaneView
        if let existing = paneCache[selId] {
            pane = existing
        } else {
            pane = SplitPaneView(
                tabId: selId,
                cache: cache,
                onRatioChange: { [weak self] sid, ratio in
                    self?.onRatioChange?(selId, sid, ratio)
                },
                onPaneFocus: { [weak self] termId in
                    self?.onFocusTerminal?(selId, termId)
                }
            )
            pane.onTabDropOnPane = { [weak self] droppedTabId, ontoTermId, edge in
                self?.onTabDropOnPane?(droppedTabId, selId, ontoTermId, edge)
            }
            paneCache[selId] = pane
        }
        pane.apply(layout: tab.layout)

        // Swap the visible child.
        for sub in paneContainer.subviews where sub !== pane {
            sub.removeFromSuperview()
        }
        if pane.superview !== paneContainer {
            paneContainer.subviews.forEach { $0.removeFromSuperview() }
            paneContainer.addSubview(pane)
            pane.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
                pane.topAnchor.constraint(equalTo: paneContainer.topAnchor),
                pane.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor),
            ])
        }

        DispatchQueue.main.async {
            self.focusCurrentTerminal()
        }
    }

    func clearWorkspace() {
        workspace = nil
        tabBar.apply(tabs: [], selected: nil)
        paneContainer.subviews.forEach { $0.removeFromSuperview() }
        paneCache.removeAll()
        cache.reapMissing(aliveIds: [])
    }

    private func focusCurrentTerminal() {
        guard let workspace,
              let selectedTabId = workspace.selectedTabId,
              let tab = workspace.tabs.first(where: { $0.id == selectedTabId }),
              let pane = paneCache[selectedTabId] else { return }
        pane.focusTerminal(tab.focusedTerminalId)
    }
}
