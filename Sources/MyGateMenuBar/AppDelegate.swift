import AppKit
import Combine
import SwiftUI

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var demoCapturePath: String?
    private let model = MGModel()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var pendingPanel: NSPanel?
    private var pendingAutoClose: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var globalClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MGDiagnostics.hardenExistingLogs()
        let me = ProcessInfo.processInfo.processIdentifier
        if AppDelegate.demoCapturePath == nil {
            let bundleId = Bundle.main.bundleIdentifier ?? "com.secureu.mygate"
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .filter { $0.processIdentifier != me }
            if !others.isEmpty {
                MGDiagnostics.append("duplicate launch pid=\(me) already=\(others.map(\.processIdentifier))")
                NSApp.terminate(nil)
                return
            }
        }
        MGDiagnostics.append("launch pid=\(me)")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = menuIcon() ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "MyGate")
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
            button.toolTip = "MyGate"
        }

        popover = NSPopover()
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))

        model.onPending = { [weak self] pending in
            guard let self else { return }
            self.flashBell()
            self.showPendingPanel(pending)
        }
        model.onPendingCleared = { [weak self] in self?.closePendingPanel() }

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusItem() } }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.closePopoverIfShown() }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.closePendingPanel() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.model.restartPolling()
                await self?.model.checkPending()
            }
        }

        updateStatusItem()
        model.start()
        Task { await model.checkPending() }

        if let demoPath = AppDelegate.demoCapturePath {
            let sample = MGPending(validationId: "demo", title: "Swiggy Delivery",
                                   subtitle: "Delivery executive", body: "At the main gate",
                                   category: "Delivery", time: "7:05 PM", flat: "T1 101",
                                   gate: "Main gate", photoURL: nil)
            showPendingPanel(sample)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, let view = self.pendingPanel?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    print("DEMO_CAPTURE_FAILED"); exit(1)
                }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: demoPath))
                    print("DEMO_CAPTURE \(demoPath) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
                    exit(0)
                }
                print("DEMO_CAPTURE_FAILED"); exit(1)
            }
        }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        installGlobalClickMonitor()
        Task { await model.checkPending() }
    }

    private func closePopoverIfShown() { if popover.isShown { popover.performClose(nil) } }

    private func installGlobalClickMonitor() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePopoverIfShown() }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor); globalClickMonitor = nil }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if model.pending == nil {
            button.image = menuIcon() ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "MyGate")
        } else {
            button.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Visitor")
        }
        button.title = ""
        var tip = "MyGate"
        if model.phase == .loggedIn {
            tip += " · \(model.config.buildingName) \(model.config.flatName)"
            if let pending = model.pending { tip += " · \(pending.title) at gate" }
        }
        button.toolTip = tip
    }

    private func menuIcon() -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("MenuIcon.png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    private func flashBell() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Visitor")
        }
    }

    private func showPendingPanel(_ pending: MGPending, error: String? = nil) {
        MGDiagnostics.append("pending panel shown id=\(pending.validationId) error=\(error ?? "none")")
        closePendingPanel()
        let card = PendingPanelView(
            pending: pending,
            errorText: error,
            onApprove: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    await self.model.approve(pending)
                    if self.model.pending == nil {
                        self.closePendingPanel()
                    } else {
                        self.showPendingPanel(pending, error: self.model.message)
                    }
                }
            },
            onDeny: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    await self.model.reject(pending)
                    if self.model.pending == nil {
                        self.closePendingPanel()
                    } else {
                        self.showPendingPanel(pending, error: self.model.message)
                    }
                }
            },
            onClose: { [weak self] in
                self?.closePendingPanel()
            }
        )
        let hosting = NSHostingView(rootView: card)
        hosting.sizingOptions = []
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 360)
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let size = NSSize(width: 400, height: min(max(fitting.height, 190), 520))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        let panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.minSize = size
        panel.maxSize = size
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - size.width - 14
            let y = screen.visibleFrame.maxY - size.height - 10
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pendingPanel = panel
        schedulePendingAutoClose(panel)
    }

    private func schedulePendingAutoClose(_ panel: KeyablePanel) {
        pendingAutoClose?.cancel()
        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel, self.pendingPanel === panel else { return }
            MGDiagnostics.append("pending panel auto-closed after 5 minutes")
            self.closePendingPanel()
        }
        pendingAutoClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: work)
    }

    private func closePendingPanel() {
        pendingAutoClose?.cancel()
        pendingAutoClose = nil
        pendingPanel?.orderOut(nil)
        pendingPanel = nil
    }
}
