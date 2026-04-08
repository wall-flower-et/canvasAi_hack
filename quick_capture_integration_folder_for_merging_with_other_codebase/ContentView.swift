// =============================================================================
// INTEGRATION GUIDE — ContentView.swift
// STATUS: MODIFIED — one line changed, nothing else.
//
// CHANGE: The CanvasViewModel is no longer created here. It is injected by
//         the App entry point (CanvasAiApp) so that QuickCaptureController
//         can share the same instance.
//
// BEFORE (remove this line):
//   @State private var viewModel = CanvasViewModel()
//
// AFTER (replace with):
//   var viewModel: CanvasViewModel   // injected by CanvasAiApp
//
// Everything else in this file is UNCHANGED.
// If your repo uses a different name for the view-model type, use that name.
// =============================================================================

import SwiftUI

/// Root composition — ZStack layering all canvas elements
struct ContentView: View {
    var viewModel: CanvasViewModel   // owned and injected by CanvasAiApp
    @State private var promptExpanded = false

    var body: some View {
        ZStack {
            // Layer 1: Warm beige background
            Color.canvasBackground
                .ignoresSafeArea()

            // Layer 2: Warped perspective grid
            WarpedGridView()
                .ignoresSafeArea()

            // Layer 3: Infinite canvas (pan/zoom/drag + all canvas content)
            InfiniteCanvasView(viewModel: viewModel)

            // Layer 4: Ambient label (bottom center overlay)
            VStack {
                Spacer()
                AmbientLabelView(text: viewModel.ambientText)
                    .padding(.bottom, 60)
            }
            .allowsHitTesting(false)

            // Layer 5: Undo toast (when undo available)
            if let snapshot = viewModel.undoSnapshot {
                VStack {
                    Spacer()
                    UndoToastView(
                        reason: snapshot.reason,
                        onUndo: { viewModel.undoRearrange() }
                    )
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Layer 6: Card prompt (when card selected)
            if let prompt = viewModel.activeCardPrompt {
                GeometryReader { geo in
                    CardPromptView(
                        nodeId: prompt.nodeId,
                        position: prompt.position,
                        canvasCenter: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2),
                        scale: 1.0,
                        offset: .zero,
                        onSubmit: { nodeId, question in
                            await viewModel.handleCardPrompt(nodeId: nodeId, question: question)
                        },
                        onDismiss: { viewModel.activeCardPrompt = nil }
                    )
                }
            }

            // Layer 7: Empty state glass card
            if viewModel.items.isEmpty {
                GlassCardView()
            }

            // Layer 8: Output card (when AI overview has data)
            if viewModel.overview.hasContent && !promptExpanded {
                VStack {
                    HStack {
                        Spacer()
                        OutputCardView(
                            overview: viewModel.overview,
                            onSuggestionTap: { suggestion in
                                Task {
                                    do { try await viewModel.api.infer(input: suggestion) }
                                    catch { print("[api] OutputCard suggestion error: \(error.localizedDescription)") }
                                }
                            }
                        )
                        .padding(.trailing, 24)
                    }
                    Spacer()
                }
                .padding(.top, 24)
                .zIndex(5)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            // Layer 9: Animated prompt bar (mouse-following circle → text input)
            AnimatedPromptBarView(
                onSubmit: { text in
                    Task {
                        do { try await viewModel.api.infer(input: text) }
                        catch { print("[api] Prompt bar infer error: \(error.localizedDescription)") }
                    }
                },
                isExpanded: $promptExpanded
            )
            .zIndex(20)
        }
        .animation(.easeInOut(duration: 0.3), value: promptExpanded)
        .animation(.easeInOut(duration: 0.3), value: viewModel.undoSnapshot != nil)
        .animation(.easeInOut(duration: 0.5), value: viewModel.items.isEmpty)
        .animation(.easeInOut(duration: 0.5), value: viewModel.overview.hasContent)
        .onAppear {
            viewModel.start()
        }
    }
}
