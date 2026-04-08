// =============================================================================
// INTEGRATION GUIDE — CanvasAiApp.swift  (App entry point)
// STATUS: MODIFIED — merge these changes into your existing App entry point.
//
// CHANGES MADE (2 additions):
//
// 1. LIFT CanvasViewModel to App scope (was in ContentView before):
//      @State private var viewModel = CanvasViewModel()
//    Remove the equivalent @State from ContentView and change its signature to:
//      struct ContentView: View { var viewModel: CanvasViewModel ... }
//    Then pass it in the WindowGroup: ContentView(viewModel: viewModel)
//    Reason: QuickCaptureController needs the SAME instance as ContentView.
//
// 2. ADD QuickCaptureController wiring in .onAppear:
//      @State private var captureController: QuickCaptureController?
//      // in .onAppear: create controller, call .setup()
//    Reason: controller must be created after the window exists (NSPanel setup).
//
// 3. ADD three Notification.Name entries to your existing extension:
//      .quickCaptureWillShow, .quickCaptureDidHide, .quickCapturePasteboardCaptured
//    If your repo already has a Notification.Name extension elsewhere, add these there.
//
// DEPENDENCIES:
//   • CanvasViewModel  → your @Observable view-model class name
//   • ContentView      → your root SwiftUI view (must accept viewModel as a parameter)
//   • QuickCaptureController → new file (QuickCaptureController.swift)
// =============================================================================

import SwiftUI

@main
struct CanvasAiApp: App {
    // Single CanvasViewModel instance for the entire app lifetime.
    // Lifted here from ContentView so QuickCaptureController can share the same object.
    @State private var viewModel = CanvasViewModel()
    @State private var captureController: QuickCaptureController?

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    // Wire up the floating capture panel once the window is ready.
                    if captureController == nil {
                        captureController = QuickCaptureController(viewModel: viewModel)
                        captureController?.setup()
                    }
                }
        }
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentSize)
        .commands {
            // Zoom commands
            CommandMenu("Canvas") {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .canvasZoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .canvasZoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Zoom") {
                    NotificationCenter.default.post(name: .canvasZoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Ask CanvasAi") {
                    NotificationCenter.default.post(name: .canvasSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let canvasZoomIn     = Notification.Name("canvasZoomIn")
    static let canvasZoomOut    = Notification.Name("canvasZoomOut")
    static let canvasZoomReset  = Notification.Name("canvasZoomReset")
    static let canvasSearch     = Notification.Name("canvasSearch")
    // Quick Capture panel lifecycle
    static let quickCaptureWillShow          = Notification.Name("quickCaptureWillShow")
    static let quickCaptureDidHide           = Notification.Name("quickCaptureDidHide")
    static let quickCapturePasteboardCaptured = Notification.Name("quickCapturePasteboardCaptured")
}
