import AppKit
import SwiftUI

private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class StatusPanelController: NSObject {
    private let statusItem: NSStatusItem
    private let model: StatusControlCenterModel
    private let panel: StatusPanel
    private var pendingCompactResize: DispatchWorkItem?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    var onWillShow: (() -> Void)?

    init(statusItem: NSStatusItem, model: StatusControlCenterModel) {
        self.statusItem = statusItem
        self.model = model
        panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: model.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentViewController = NSHostingController(rootView: StatusControlCenterView(model: model))
        model.requestIslandToggle = { [weak self] island in
            self?.toggleIsland(island)
        }
    }

    func toggle() {
        panel.isVisible ? requestClose() : show(animated: true)
    }

    func show(animated: Bool) {
        onWillShow?()
        setPanelHeight(height(for: model.expandedIsland))
        positionPanel()
        installEventMonitors()
        panel.alphaValue = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 1
        panel.orderFrontRegardless()
        panel.makeKey()

        if panel.alphaValue == 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide(animated: Bool) {
        removeEventMonitors()
        pendingCompactResize?.cancel()
        pendingCompactResize = nil
        model.expandedIsland = nil

        guard animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        })
    }

    func requestClose() {
        if #available(macOS 27.0, *), let session = statusItem.expandedInterfaceSession {
            session.cancel()
        } else {
            hide(animated: true)
        }
    }

    private func toggleIsland(_ island: StatusIsland) {
        guard island != .battery else { return }
        pendingCompactResize?.cancel()
        pendingCompactResize = nil

        if model.expandedIsland == island {
            setExpandedIsland(nil)
            scheduleCompactResize()
            return
        }

        // Give SwiftUI the final canvas before the glass changes identity. This
        // mirrors Apple's examples: only the glass participates in the visible
        // transition, rather than competing with an AppKit window animation.
        setPanelHeight(height(for: island))
        panel.contentView?.layoutSubtreeIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.setExpandedIsland(island)
        }
    }

    private func setExpandedIsland(_ island: StatusIsland?) {
        let animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil
            : StatusMotion.expansion
        withAnimation(animation) {
            model.expandedIsland = island
        }
    }

    private func scheduleCompactResize() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setPanelHeight(height(for: nil))
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.expandedIsland == nil else { return }
            self.setPanelHeight(self.height(for: nil))
            self.pendingCompactResize = nil
        }
        pendingCompactResize = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + StatusMotion.expansionDuration,
            execute: work
        )
    }

    private func height(for expandedIsland: StatusIsland?) -> CGFloat {
        switch expandedIsland {
        case .battery: return 286
        case .connectivity: return 620
        case .inputSource: return 560
        case nil: return 286
        }
    }

    private func setPanelHeight(_ height: CGFloat) {
        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size = NSSize(width: 360, height: height)
        frame.origin.y = top - frame.height
        panel.setFrame(frame, display: true)
    }

    private func positionPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        var origin = NSPoint(
            x: buttonRect.midX - panel.frame.width / 2,
            y: buttonRect.minY - panel.frame.height - 6
        )
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        origin.y = max(origin.y, visible.minY + 8)
        panel.setFrameOrigin(origin)
    }

    private func installEventMonitors() {
        removeEventMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 {
                self.requestClose()
                return nil
            }
            if let eventWindow = event.window, eventWindow !== self.panel {
                self.requestClose()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.requestClose()
        }
    }

    private func removeEventMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    deinit {
        pendingCompactResize?.cancel()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
}

@available(macOS 27.0, *)
@MainActor
final class StatusExpandedInterfaceDelegate: NSObject, @preconcurrency NSStatusItemExpandedInterfaceDelegate {
    weak var panelController: StatusPanelController?

    init(panelController: StatusPanelController) {
        self.panelController = panelController
    }

    func statusItem(
        _ statusItem: NSStatusItem,
        didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession
    ) {
        panelController?.show(animated: true)
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        panelController?.hide(animated: animated)
    }
}
