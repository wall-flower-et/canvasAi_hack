import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var images: [NSImage] = []
    @State private var promptExpanded: Bool = false

    var body: some View {
        ZStack {
            Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255)
                .ignoresSafeArea()

            WarpedGridView()
                .ignoresSafeArea()

            if images.isEmpty {
                GlassCard()
            }

            if images.count >= 2 {
                OutputCard()
                    .zIndex(1)
            }

            ImageCards(images: images)
                .zIndex(2)
                .allowsHitTesting(images.count > 0)

            // Add button — bottom center
            if !promptExpanded {
                VStack {
                    Spacer()
                    PhotosPicker(selection: $selectedItems, matching: .images) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color(red: 222/255, green: 115/255, blue: 86/255))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 30)
                }
                .zIndex(10)
                .transition(.scale.combined(with: .opacity))
            }

            // Floating prompt circle / bar — follows mouse, full screen overlay
            AnimatedPromptBar(isExpanded: $promptExpanded)
                .zIndex(20)
        }
        .onChange(of: selectedItems) {
            Task { await loadImages() }
        }
    }

    private func loadImages() async {
        var newImages: [NSImage] = []
        for item in selectedItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let nsImage = NSImage(data: data) {
                newImages.append(nsImage)
            }
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            images = newImages
        }
    }
}

// MARK: - Warped Grid

struct WarpedGridView: View {
    private let lineColor = Color(red: 222 / 255, green: 115 / 255, blue: 86 / 255).opacity(0.7)
    private let bgColor = Color(red: 245 / 255, green: 242 / 255, blue: 236 / 255)

    private let lineCount: Int = 5
    private let lineWidth: CGFloat = 0.5
    private let margin: CGFloat = 0.3
    private let warpStrength: CGFloat = 0.8
    private let segments: Int = 120

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let halfW = w / 2
            let halfH = h / 2
            let k = warpStrength

            context.fill(Path(CGRect(origin: .zero, size: CGSize(width: w, height: h))), with: .color(bgColor))

            func warp(_ p: CGPoint) -> CGPoint {
                let nx = (p.x - cx) / halfW
                let ny = (p.y - cy) / halfH
                let fx = 1.0 + k * ny * ny
                let fy = 1.0 + k * nx * nx
                return CGPoint(x: cx + nx * fx * halfW, y: cy + ny * fy * halfH)
            }

            let gridHalf = cy * (1 - margin)
            let spacing = gridHalf / CGFloat(lineCount)
            let vLineCount = Int(cx / spacing)

            for i in -lineCount...lineCount {
                let y = cy + CGFloat(i) * spacing
                var path = Path()
                for s in 0...segments {
                    let u = CGFloat(s) / CGFloat(segments)
                    let x = u * w
                    let wp = warp(CGPoint(x: x, y: y))
                    if s == 0 { path.move(to: wp) } else { path.addLine(to: wp) }
                }
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
            }

            let topY = cy - gridHalf
            let bottomY = cy + gridHalf

            for i in -vLineCount...vLineCount {
                let x = cx + CGFloat(i) * spacing
                var path = Path()
                for s in 0...segments {
                    let u = CGFloat(s) / CGFloat(segments)
                    let y = topY + u * (bottomY - topY)
                    let wp = warp(CGPoint(x: x, y: y))
                    if s == 0 { path.move(to: wp) } else { path.addLine(to: wp) }
                }
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
            }
        }
        .clipped()
        .drawingGroup()
    }
}

// MARK: - Connection Lines

struct ConnectionLine {
    let fromId: Int
    let toId: Int
    let label: String
    let color: Color
}

// MARK: - Image Cards

struct ImageCards: View {
    let images: [NSImage]
    private let spreadRadius: CGFloat = 280
    private let accentColor = Color(red: 222/255, green: 115/255, blue: 86/255)

    // Orbit center offset from screen center
    private let orbitOffsetX: CGFloat = -80
    private let orbitOffsetY: CGFloat = -30

    @State private var selectedId: Int? = nil
    @State private var savedOffsets: [Int: CGSize] = [:]   // persisted position
    @State private var activeDrag: [Int: CGSize] = [:]     // live drag delta

    // Auto-generate connections: consecutive + one cross
    private var connections: [ConnectionLine] {
        let n = images.count
        guard n >= 2 else { return [] }
        var lines: [ConnectionLine] = []
        for i in 0..<(n - 1) {
            lines.append(ConnectionLine(fromId: i, toId: i + 1, label: "link", color: accentColor))
        }
        if n >= 3 {
            lines.append(ConnectionLine(fromId: 0, toId: n - 1, label: "cross", color: accentColor))
        }
        return lines
    }

    // Fibonacci sphere → 2D projection
    // Golden angle distributes N points evenly on a sphere,
    // then we project (x, y) to get a naturally-spaced 2D layout
    private func cardPosition(_ i: Int, cx: CGFloat, cy: CGFloat) -> CGPoint {
        let n = images.count
        let goldenAngle = CGFloat.pi * (3.0 - sqrt(5.0)) // ~2.3999 rad
        let ringCx = cx + orbitOffsetX
        let ringCy = cy + orbitOffsetY

        // Fibonacci sphere: y goes from -1 to 1, golden angle increments azimuth
        let t = n <= 1 ? 0.0 : CGFloat(i) / CGFloat(n - 1)
        let phi = CGFloat(i) * goldenAngle
        let cosTheta = 1.0 - 2.0 * t          // ranges from 1 to -1
        let sinTheta = sqrt(1.0 - cosTheta * cosTheta)

        // Project sphere (x, y) → screen (x, y), z becomes depth/scale
        let sx = sinTheta * cos(phi)
        let sy = sinTheta * sin(phi)

        let saved = savedOffsets[i] ?? .zero
        let drag = activeDrag[i] ?? .zero
        return CGPoint(
            x: ringCx + sx * spreadRadius + saved.width + drag.width,
            y: ringCy + sy * spreadRadius + saved.height + drag.height
        )
    }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let n = images.count

            ZStack {
                // Connection lines (behind cards)
                Canvas { context, _ in
                    for conn in connections {
                        let from = cardPosition(conn.fromId, cx: cx, cy: cy)
                        let to = cardPosition(conn.toId, cx: cx, cy: cy)

                        // Line
                        var linePath = Path()
                        linePath.move(to: from)
                        linePath.addLine(to: to)
                        context.stroke(linePath, with: .color(conn.color.opacity(0.25)), lineWidth: 1)

                        // Diamond at midpoint
                        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                        let d: CGFloat = 5
                        var diamond = Path()
                        diamond.move(to: CGPoint(x: mid.x, y: mid.y - d))
                        diamond.addLine(to: CGPoint(x: mid.x + d, y: mid.y))
                        diamond.addLine(to: CGPoint(x: mid.x, y: mid.y + d))
                        diamond.addLine(to: CGPoint(x: mid.x - d, y: mid.y))
                        diamond.closeSubpath()
                        context.fill(diamond, with: .color(conn.color.opacity(0.35)))
                    }
                }

                // Cards
                ForEach(0..<n, id: \.self) { i in
                    let pos = cardPosition(i, cx: cx, cy: cy)
                    let isSelected = selectedId == i
                    let hasFocus = selectedId != nil

                    ImageCard(image: images[i])
                        .scaleEffect(isSelected ? 1.15 : (hasFocus ? 0.9 : 1.0))
                        .opacity(isSelected ? 1.0 : (hasFocus ? 0.3 : 1.0))
                        .shadow(color: isSelected ? .black.opacity(0.2) : .clear, radius: 20, y: 10)
                        .zIndex(isSelected ? 10 : 0)
                        .position(x: pos.x, y: pos.y)
                        .transition(.scale.combined(with: .opacity))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    selectedId = i
                                    activeDrag[i] = value.translation
                                }
                                .onEnded { value in
                                    // Accumulate into saved offset
                                    let prev = savedOffsets[i] ?? .zero
                                    savedOffsets[i] = CGSize(
                                        width: prev.width + value.translation.width,
                                        height: prev.height + value.translation.height
                                    )
                                    activeDrag[i] = .zero
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedId = nil
                                    }
                                }
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35)) {
                                selectedId = selectedId == i ? nil : i
                            }
                        }
                        .animation(.spring(response: 0.35), value: selectedId)
                }
            }
        }
    }
}

struct ImageCard: View {
    let image: NSImage

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 90, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Image")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 110, height: 130)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
    }
}

// MARK: - Output Card

struct OutputCard: View {
    private let cardWidth: CGFloat = 260
    private let cornerRadius: CGFloat = 16
    private let accentColor = Color(red: 222/255, green: 115/255, blue: 86/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("travel")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.2))
                    )

                Text("Here's what I see in your photos")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .overlay(.white.opacity(0.15))
                .padding(.horizontal, 16)

            // Body
            VStack(alignment: .leading, spacing: 14) {
                Text("Weekend Getaway")
                    .font(.custom("DM Serif Display", size: 20))
                    .foregroundStyle(.white)

                OutputSection(heading: "Places", items: ["Coastal cliffs at sunset", "Old town market square"])
                OutputSection(heading: "Mood", items: ["Warm golden light", "Relaxed, candid moments"])
                OutputSection(heading: "Story", items: ["A weekend road-trip south along the coast"])
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)

            // Footer
            Text("Want me to turn this into a travel log?")
                .font(.system(size: 12, weight: .regular))
                .italic()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 0,
                            bottomLeading: cornerRadius,
                            bottomTrailing: cornerRadius,
                            topTrailing: 0
                        )
                    )
                    .fill(.white.opacity(0.15))
                )
        }
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(accentColor)
                .shadow(color: accentColor.opacity(0.35), radius: 16, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .transition(
            .scale(scale: 0.9)
            .combined(with: .opacity)
        )
    }
}

struct OutputSection: View {
    let heading: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.8)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 4, height: 4)
                        .padding(.top, 5)

                    Text(item)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }
}

// MARK: - Animated Prompt Bar

struct AnimatedPromptBar: View {
    @Binding var isExpanded: Bool
    @State private var phase: PromptPhase = .circle
    @State private var mousePos: CGPoint = .zero
    @State private var rollOffset: CGFloat = 0
    @State private var rollRotation: Double = 0
    @State private var barWidth: CGFloat = 44
    @State private var promptText: String = ""
    @FocusState private var isFocused: Bool

    private let circleSize: CGFloat = 44
    private let expandedWidth: CGFloat = 400
    private let accentColor = Color(red: 222/255, green: 115/255, blue: 86/255)

    enum PromptPhase {
        case circle
        case rolling
        case expanding
        case expanded
    }

    var body: some View {
        GeometryReader { geo in
            let screenCx = geo.size.width / 2
            let anchorY = geo.size.height - 50

            // Where the shape should be
            let posX: CGFloat = phase == .circle ? mousePos.x : screenCx + rollOffset
            let posY: CGFloat = phase == .circle ? mousePos.y : anchorY

            ZStack {
                HStack(spacing: 0) {
                    if phase == .expanded {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))

                            TextField("Ask CanvasAi anything…", text: $promptText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .focused($isFocused)

                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity.animation(.easeIn(duration: 0.2)))
                    }
                }
                .frame(width: barWidth, height: circleSize)
                .background(
                    Capsule()
                        .fill(accentColor)
                        .shadow(color: accentColor.opacity(0.3), radius: 12, y: 4)
                )
                .clipShape(Capsule())
                .rotationEffect(.degrees(rollRotation))
                .position(x: posX, y: posY)
                .animation(phase == .circle ? .smooth(duration: 0.15) : nil, value: mousePos)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { hoverPhase in
                if phase == .circle {
                    switch hoverPhase {
                    case .active(let location):
                        mousePos = location
                    case .ended:
                        break
                    }
                }
            }
            .onTapGesture(count: 2) {
                if phase == .expanded || phase == .expanding {
                    collapseAnimation(screenCx: screenCx, anchorY: anchorY)
                }
            }
            .onTapGesture(count: 1) {
                if phase == .circle {
                    expandAnimation(screenCx: screenCx, anchorY: anchorY)
                }
            }
        }
    }

    private func expandAnimation(screenCx: CGFloat, anchorY: CGFloat) {
        // Snap to bottom center to start rolling
        withAnimation(.easeOut(duration: 0.25)) {
            mousePos = CGPoint(x: screenCx - 160, y: anchorY)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isExpanded = true
            phase = .rolling

            // Phase 1: Roll to the right
            withAnimation(.easeIn(duration: 0.45)) {
                rollOffset = 160
                rollRotation = 360
            }

            // Phase 2: Stop rolling, expand width
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                phase = .expanding
                rollRotation = 0
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    rollOffset = 0
                    barWidth = expandedWidth
                }
            }

            // Phase 3: Show text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                phase = .expanded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isFocused = true
                }
            }
        }
    }

    private func collapseAnimation(screenCx: CGFloat, anchorY: CGFloat) {
        isFocused = false
        promptText = ""

        // Shrink bar back to circle
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            barWidth = circleSize
            phase = .circle
            isExpanded = false
        }

        // Reset position to center so it picks up mouse again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            rollOffset = 0
            rollRotation = 0
            mousePos = CGPoint(x: screenCx, y: anchorY)
        }
    }
}

// MARK: - Glass Card

struct GlassCard: View {
    private let cardWidth: CGFloat = 340
    private let cardHeight: CGFloat = 400
    private let cornerRadius: CGFloat = 20
    private let thickness: CGFloat = 6
    private let accentColor = Color(red: 222/255, green: 115/255, blue: 86/255)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(accentColor.opacity(0.15))
                .frame(width: cardWidth, height: cardHeight)
                .offset(y: thickness)

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(accentColor.opacity(0.85))

                Text("CanvasAi")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)

                Text("Drop an image to begin")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(accentColor.opacity(0.6))
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(red: 204/255, green: 85/255, blue: 0/255).opacity(0.6))
            )
            .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        }
        //.shadow(color: accentColor.opacity(0.35), radius: 16, y: 8)
        .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    ContentView()
        .frame(width: 1280, height: 800)
}
