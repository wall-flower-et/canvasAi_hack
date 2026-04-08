// =============================================================================
// INTEGRATION GUIDE — QuickCaptureView.swift
// STATUS: NEW FILE — does not exist in the other repo. Create it at:
//         <YourProject>/Views/QuickCaptureView.swift
//         and add it to the Xcode target.
//
// PURPOSE: The SwiftUI view rendered inside the floating NSPanel.
//          Animates from a small terracotta dot → full glass card (bloom effect).
//          Accepts drag-and-drop AND auto-captures clipboard changes detected
//          by QuickCaptureController. Does NOT duplicate any parsing logic —
//          it delegates entirely to PasteboardService and ViewModel.addNode().
//
// DEPENDENCIES — adapt these names if your repo differs:
//   • CanvasViewModel          → injected via .environment(CanvasViewModel.self)
//                                Must be @Observable for this to work.
//   • CanvasViewModel.addNode(type:content:)
//   • PasteboardService.processDropProviders(_ providers: [NSItemProvider]) async
//                              → returns [(type: ItemType, content: String)]
//   • CanvasItem.ItemType      → enum cases: .text, .image, .link, .drawing
//   • Color.terracotta         → brand accent (define as Color extension if missing)
//   • Notification.Name.quickCaptureWillShow / .quickCaptureDidHide /
//     .quickCapturePasteboardCaptured
//                              → defined in App entry point
//
// ANIMATION: 4-phase state machine driven by scaleEffect (not frame changes).
//   dormant → blooming → ready → success(label:)
//   Panel stays 340×240 throughout; visual bloom is a scale from ~0.13→1.0.
// =============================================================================

import SwiftUI
import UniformTypeIdentifiers

/// Floating drop-zone that blooms open when the user double-presses Control.
/// Accepts links, images, and text — funnels them into the existing
/// PasteboardService + CanvasViewModel.addNode() pipeline without duplication.
struct QuickCaptureView: View {

    let onCapture: () -> Void   // tell controller to start 1.5s auto-dismiss timer
    let onDismiss:  () -> Void   // tell controller to hide immediately

    @Environment(CanvasViewModel.self) private var viewModel
    @State private var phase: Phase = .dormant
    @State private var isTargeted = false   // drag is hovering over the drop zone

    // MARK: - Animation state machine

    enum Phase: Equatable {
        case dormant                   // panel not yet visible — tiny seed
        case blooming                  // spring-expanding from dot to card
        case ready                     // fully open, accepting drops
        case success(label: String)    // capture confirmed — show checkmark
    }

    // scaleEffect drives the bloom while the panel stays at its full 340×240 size.
    // The drop target therefore registers immediately (no layout changes mid-animation).
    private var targetScale: CGFloat {
        switch phase {
        case .dormant: return 44.0 / 340.0   // starts as a ~44pt terracotta dot
        default:       return 1.0
        }
    }

    private var targetOpacity: Double {
        phase == .dormant ? 0 : 1
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            glassBacking

            switch phase {
            case .dormant:
                EmptyView()

            case .blooming:
                // Terracotta pulse while the spring unwinds
                Circle()
                    .fill(Color.terracotta.opacity(0.55))
                    .frame(width: 44, height: 44)

            case .ready:
                dropZoneContent
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))

            case .success(let label):
                successContent(label: label)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .frame(width: 340, height: 240)
        .scaleEffect(targetScale)
        .opacity(targetOpacity)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: targetScale)
        .animation(.easeInOut(duration: 0.18), value: targetOpacity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.terracotta.opacity(0.25), radius: 24, y: 8)
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        .onReceive(NotificationCenter.default.publisher(for: .quickCaptureWillShow)) { _ in
            startBloom()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickCaptureDidHide)) { _ in
            phase = .dormant
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickCapturePasteboardCaptured)) { note in
            let label = note.userInfo?["label"] as? String ?? "Captured"
            withAnimation(.easeInOut(duration: 0.2)) {
                phase = .success(label: label)
            }
        }
    }

    // MARK: - Glass backing (matches AnimatedPromptBarView / GlassMorphism aesthetic)

    private var glassBacking: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 20)
                .fill(Color.terracotta.opacity(isTargeted ? 0.18 : 0.10))
                .animation(.easeInOut(duration: 0.15), value: isTargeted)

            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isTargeted ? 0.50 : 0.28),
                            Color.terracotta.opacity(isTargeted ? 0.40 : 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isTargeted ? 1.5 : 1.0
                )
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
        }
    }

    // MARK: - Drop zone content

    private var dropZoneContent: some View {
        VStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.terracotta.opacity(0.12))
                    .frame(width: 56, height: 56)

                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.terracotta)
                    .scaleEffect(isTargeted ? 1.15 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
            }

            VStack(spacing: 4) {
                Text("Drop anything here")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))

                Text("links · images · text")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.65))
            }

            Text("Drop here, or copy anything while open")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.40))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Reuse PasteboardService.processDropProviders — no logic duplicated here.
        .onDrop(of: [.image, .url, .plainText], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Success content

    private func successContent(label: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 56, height: 56)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
            }

            Text("Added to canvas")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary.opacity(0.70))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Bloom animation

    private func startBloom() {
        // Phase 1: spring expand from dot (scaleEffect drives this)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            phase = .blooming
        }
        // Phase 2: reveal drop zone after spring settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.2)) {
                phase = .ready
            }
        }
    }

    // MARK: - Drop handler

    private func handleDrop(providers: [NSItemProvider]) {
        guard case .ready = phase else { return }

        Task {
            // Delegate parsing entirely to the existing PasteboardService.
            let results = await PasteboardService.processDropProviders(providers)
            guard !results.isEmpty else { return }

            // Build a short label for the success state.
            let label: String
            if let first = results.first {
                switch first.type {
                case .link:    label = first.content.count > 60 ? String(first.content.prefix(60)) + "…" : first.content
                case .image:   label = results.count > 1 ? "\(results.count) images" : "Image"
                case .text:    label = String(first.content.prefix(60)) + (first.content.count > 60 ? "…" : "")
                case .drawing: label = "Drawing"
                }
            } else {
                label = "Item"
            }

            await MainActor.run {
                // Feed into the existing pipeline — same call as InfiniteCanvasView's onDrop.
                for result in results {
                    viewModel.addNode(type: result.type, content: result.content)
                }

                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = .success(label: label)
                }

                // Signal controller to start the 1.5s auto-dismiss timer.
                onCapture()
            }
        }
    }
}
