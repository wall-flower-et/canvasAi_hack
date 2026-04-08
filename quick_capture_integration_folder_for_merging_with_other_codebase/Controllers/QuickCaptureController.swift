// =============================================================================
// INTEGRATION GUIDE — QuickCaptureController.swift
// STATUS: NEW FILE — does not exist in the other repo. Create it at:
//         <YourProject>/Controllers/QuickCaptureController.swift
//         and add it to the Xcode target.
//
// PURPOSE: Owns the floating NSPanel that appears on double-Control press.
//          Manages global/local NSEvent hotkey monitors, pasteboard polling,
//          and escape-key dismiss. Completely self-contained — no changes
//          needed to any view file to wire this up (wiring is in App entry point).
//
// DEPENDENCIES — adapt these names if your repo differs:
//   • CanvasViewModel          → your main @Observable view-model class
//   • CanvasViewModel.addNode(type:content:)
//                              → method that creates a canvas node and posts to backend
//   • PasteboardService.readPasteboard()
//                              → returns (type: ItemType, content: String)?
//   • CanvasItem.ItemType      → enum with cases: .text, .image, .link, .drawing
//   • Notification.Name.quickCaptureWillShow / .quickCaptureDidHide /
//     .quickCapturePasteboardCaptured
//                              → defined in App entry point (CanvasAiApp.swift)
//   • Color.terracotta         → brand accent colour (used only in QuickCaptureView)
//
// ENTITLEMENTS REQUIRED:
//   • com.apple.security.app-sandbox = false   (so file-URL screenshots can be read)
//   • No additional entitlements needed; Accessibility is a runtime TCC permission.
// =============================================================================

import AppKit
import SwiftUI

/// Owns the floating NSPanel and global double-Control hotkey detection.
/// Created once in CanvasAiApp and held for the app's lifetime.
@MainActor
final class QuickCaptureController {

    // MARK: - Properties

    private let viewModel: CanvasViewModel
    private var panel: NSPanel?
    private var globalMonitor: Any?          // .flagsChanged from any app (requires Accessibility)
    private var localMonitor: Any?           // .flagsChanged when CanvasAi is the focused app
    private var escapeMonitor: Any?          // Escape key only — no click-outside dismiss
    private var dismissTimer: Timer?
    private var pasteboardTimer: Timer?
    private var lastPasteboardChangeCount: Int = -1

    // Double-press detection state
    private var lastControlPressTime: Date = .distantPast
    private let doublePressInterval: TimeInterval = 0.35

    // MARK: - Init

    init(viewModel: CanvasViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Setup (called once after the app window appears)

    func setup() {
        requestAccessibilityPermission()
        buildPanel()
        startHotkeyMonitors()
    }

    // MARK: - Accessibility

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - NSPanel construction

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Exclude from ⌘⇧3/⌘⇧4 system screenshots — the panel won't appear
        // in any capture made via CGWindowListCreateImage.
        p.sharingType = .none

        let captureView = QuickCaptureView(
            onCapture: { [weak self] in self?.handleCaptureDone() },
            onDismiss:  { [weak self] in self?.hidePanel() }
        )
        .environment(viewModel)

        let hosted = NSHostingController(rootView: captureView)
        hosted.view.wantsLayer = true
        hosted.view.layer?.backgroundColor = NSColor.clear.cgColor
        p.contentViewController = hosted
        self.panel = p
    }

    // MARK: - Double-Control hotkey monitors

    private func startHotkeyMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.modifierFlags.contains(.control) else { return }
            let now = Date()
            let elapsed = now.timeIntervalSince(self?.lastControlPressTime ?? .distantPast)
            if elapsed < (self?.doublePressInterval ?? 0.35) {
                self?.lastControlPressTime = .distantPast
                DispatchQueue.main.async { self?.togglePanel() }
            } else {
                self?.lastControlPressTime = now
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { handler($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    // MARK: - Show / Hide

    private func togglePanel() {
        panel?.isVisible == true ? hidePanel() : showPanel()
    }

    func showPanel() {
        guard let panel else { return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel.setFrameOrigin(NSPoint(
            x: screen.frame.midX - 170,
            y: screen.frame.midY - 120
        ))

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        NotificationCenter.default.post(name: .quickCaptureWillShow, object: nil)
        startEscapeMonitor()
        startPasteboardMonitor()
    }

    func hidePanel() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            NotificationCenter.default.post(name: .quickCaptureDidHide, object: nil)
        })

        stopEscapeMonitor()
        stopPasteboardMonitor()
    }

    // MARK: - Auto-dismiss after successful capture

    private func handleCaptureDone() {
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.hidePanel() }
        }
    }

    // MARK: - Escape-only dismiss (no click-outside — lets user take screenshots freely)

    private func startEscapeMonitor() {
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }   // 53 = Escape
            DispatchQueue.main.async { self?.hidePanel() }
        }
    }

    private func stopEscapeMonitor() {
        if let m = escapeMonitor { NSEvent.removeMonitor(m); escapeMonitor = nil }
    }

    // MARK: - Pasteboard monitoring (captures clipboard changes while panel is open)
    // This handles: Cmd+C copied text, Cmd+Ctrl+Shift+4 screenshot-to-clipboard,
    // and any other content copied while the panel is visible.

    private func startPasteboardMonitor() {
        // Record current state so we don't capture stale clipboard on open.
        lastPasteboardChangeCount = NSPasteboard.general.changeCount

        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.checkPasteboardForChanges()
        }
    }

    private func stopPasteboardMonitor() {
        pasteboardTimer?.invalidate()
        pasteboardTimer = nil
    }

    private func checkPasteboardForChanges() {
        let current = NSPasteboard.general.changeCount
        guard current != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = current

        let pb = NSPasteboard.general

        // Try NSImage first — this resolves both raw image data (⌘⌃⇧4) AND file URLs
        // left by ⌘⇧4 screenshots. NSPasteboard handles the sandbox file-access grant
        // automatically when reading images this way.
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            let base64 = pngData.base64EncodedString()
            viewModel.addNode(type: .image, content: "data:image/png;base64,\(base64)")
            postCaptureSuccess(label: "Screenshot")
            return
        }

        // Fall back to text / links via PasteboardService.
        guard let result = PasteboardService.readPasteboard() else { return }

        // Feed into the existing pipeline.
        viewModel.addNode(type: result.type, content: result.content)

        // Build label for success animation.
        let label: String
        switch result.type {
        case .link:    label = result.content.count > 60 ? String(result.content.prefix(60)) + "…" : result.content
        case .image:   label = "Image"
        case .text:    label = String(result.content.prefix(60)) + (result.content.count > 60 ? "…" : "")
        case .drawing: label = "Drawing"
        }

        postCaptureSuccess(label: label)
    }

    private func postCaptureSuccess(label: String) {
        NotificationCenter.default.post(
            name: .quickCapturePasteboardCaptured,
            object: nil,
            userInfo: ["label": label]
        )
        handleCaptureDone()
    }

    // MARK: - Teardown

    deinit {
        [globalMonitor, localMonitor, escapeMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        dismissTimer?.invalidate()
        pasteboardTimer?.invalidate()
    }
}
